import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cleanup_scanner.dart';
import '../background/scan_runtime.dart';

/// Lives above the library tabs: switching views does not stop the scan.
class CleanupController extends ChangeNotifier {
  final CleanupScanner _scanner = CleanupScanner();
  final ScanRuntime performance = ScanRuntime();
  static const _autoKey = 'cleanup_auto_scan_v02';

  CleanupScanResult? result;
  bool autoScan = true;
  bool analyzingPeople = false;
  bool running = false;
  bool paused = false;
  bool completed = false;
  int? year;
  String? error;
  DateTime? _startedAt;
  Duration? _eta;
  bool _cancel = false;
  int _scanGeneration = 0;
  int get scanRevision => _scanGeneration;
  bool _disposed = false;
  bool _settingsLoaded = false;
  Set<String> _protected = {};
  final Set<String> _excluded = {};
  final Set<String> _dismissedExact = {};
  final Set<String> _dismissedSimilar = {};

  int get visited => result?.visited ?? 0;
  int get total => result?.total ?? 0;
  double get fraction => total == 0 ? 0 : (visited / total).clamp(0.0, 1.0);
  Duration? get eta => _eta;
  int get exactCount =>
      exact.fold(0, (n, group) => n + (group.length - 1));
  int get similarCount =>
      similar.fold(0, (n, group) => n + (group.length - 1));

  List<List<String>> get exact =>
      _filteredGroups(result?.groups.exact ?? [], _dismissedExact);
  List<List<String>> get similar =>
      _filteredGroups(result?.groups.similar ?? [], _dismissedSimilar);
  List<String> get blurry => (result?.groups.blurry ?? [])
      .where((id) => !_excluded.contains(id)).toList();
  List<String> get noPeople => (result?.groups.noPeople ?? [])
      .where((id) => !_excluded.contains(id)).toList();

  List<List<String>> _filteredGroups(
    List<List<String>> source, Set<String> dismissed,
  ) => [
    for (final group in source)
      if (!group.any(dismissed.contains) &&
          group.where((id) => !_excluded.contains(id)).length > 1)
        group.where((id) => !_excluded.contains(id)).toList(),
  ];

  void _notify() {
    if (_disposed) return;
    notifyListeners();
    performance.sendStatus();
  }

  Future<void> initialize() async {
    if (_settingsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    await performance.initialize();
    if (_disposed) return;
    autoScan = prefs.getBool(_autoKey) ?? true;
    _settingsLoaded = true;
    _notify();
  }

  Future<void> setAutoScan(bool enabled) async {
    autoScan = enabled;
    _notify();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoKey, enabled);
    // Disabling automatic starts doesn't interrupt an active manual scan.
  }

  Future<void> startIfEnabled(Set<String> protectedIds) async {
    _protected = Set<String>.of(protectedIds);
    await initialize();
    if (autoScan && !running && !completed && !_cancel) {
      start();
    }
  }

  Future<void> start({int? scopeYear, bool? people}) async {
    if (running) return;
    final generation = ++_scanGeneration;
    _cancel = false;
    year = scopeYear;
    analyzingPeople = people ?? analyzingPeople;
    running = true;
    paused = false;
    completed = false;
    error = null;
    result = null;
    _excluded.clear();
    _dismissedExact.clear();
    _dismissedSimilar.clear();
    _startedAt = DateTime.now();
    _eta = null;
    _notify();
    try {
      final finalResult = await _scanner.scan(
        cancelled: () => _cancel || _disposed || generation != _scanGeneration,
        waitIfPaused: () async {
          while (paused && !_cancel && !_disposed && generation == _scanGeneration) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        },
        performance: performance,
        protectedIds: Set<String>.of(_protected),
        year: year,
        analyzePeople: analyzingPeople,
        onProgress: (snapshot) {
          if (_disposed || _cancel || generation != _scanGeneration) return;
          result = snapshot;
          final elapsed = DateTime.now().difference(_startedAt!);
          // Show a measured ETA only after a meaningful sample. No fake ETA.
          if (snapshot.visited >= 40 && elapsed.inSeconds >= 2 &&
              snapshot.total > snapshot.visited) {
            final remainingSeconds = elapsed.inMilliseconds /
                snapshot.visited * (snapshot.total - snapshot.visited) / 1000;
            _eta = Duration(seconds: remainingSeconds.round());
          }
          _notify();
        },
      );
      if (!_disposed && !_cancel && generation == _scanGeneration) {
        result = finalResult;
        completed = true;
        _eta = null;
      }
    } catch (e) {
      if (!_disposed && generation == _scanGeneration && !_cancel) {
        error = '$e';
      }
    } finally {
      if (!_disposed && generation == _scanGeneration) {
        running = false;
        paused = false;
        _notify();
      }
    }
  }

  void pauseOrResume() {
    if (!running) return;
    paused = !paused;
    _notify();
  }

  void stop() {
    _cancel = true;
    paused = false;
    _notify();
  }

  /// Dismiss this recommendation while leaving every Photos asset untouched.
  /// Suppression survives progressive updates within this scan, but a new
  /// explicit scan starts fresh.
  void dismissGroup(Iterable<String> ids, {required bool similar}) {
    (similar ? _dismissedSimilar : _dismissedExact).addAll(ids);
    _notify();
  }

  /// Stop work and forget ALL suggestions (including partial results). An
  /// in-flight older scan cannot restore its results after being discarded.
  void discardScan() {
    _scanGeneration++;
    _cancel = true;
    running = false;
    paused = false;
    completed = false;
    result = null;
    error = null;
    _eta = null;
    _startedAt = null;
    _excluded.clear();
    _dismissedExact.clear();
    _dismissedSimilar.clear();
    _notify();
  }

  void exclude(Iterable<String> ids) {
    _excluded.addAll(ids);
    _notify();
  }

  @override
  void dispose() {
    _cancel = true;
    _scanGeneration++;
    _disposed = true;
    performance.dispose();
    super.dispose();
  }
}