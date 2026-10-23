import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cleanup_scanner.dart';
import 'scan_checkpoint.dart';
import 'scan_result_archive.dart';
import 'photo_analysis.dart';
import '../background/scan_runtime.dart';

/// Lives above the library tabs: switching views does not stop the scan.
class CleanupController extends ChangeNotifier {
  CleanupController() {
    performance.addListener(_notify);
  }
  final CleanupScanner _scanner = CleanupScanner();
  final ScanRuntime performance = ScanRuntime();
  ScanCheckpointStore? checkpointStore;
  ScanResultArchive? get archive => checkpointStore == null
      ? null : ScanResultArchive(checkpointStore!.folder);
  bool showHistory = false;
  String? resumeStatus;
  Future<void>? _initializing;
  int get analyzedCount {
    final current = result?.photos.length ?? 0;
    final saved = checkpointStore?.current?.analyzed ?? 0;
    return current > saved ? current : saved;
  }
  int _baselineVisited = 0;
  Future<void> _discardPending = Future<void>.value();
  Completer<void>? _scanFinished;
  Future<void>? _preparingQuit;
  Completer<void>? _resumeSignal;
  String scanPhase = 'Idle';
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

  // Keep the recovered count visible while the scanner is rebuilding result
  // groups. A new session must not display zero after restoring its journal.
  int get visited {
    final saved = checkpointStore?.current?.visited ?? 0;
    final shown = result?.visited ?? 0;
    return shown > saved ? shown : saved;
  }
  int get total => result?.total ?? checkpointStore?.current?.total ?? 0;
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

  Future<void> initialize() => _initializing ??= _initializeOnce();

  Future<void> _initializeOnce() async {
    if (_settingsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    await performance.initialize();
    checkpointStore ??= await ScanCheckpointStore.open();
    final prior = await checkpointStore!.load();
    if (_disposed) return;
    if (checkpointStore!.recoveryIssue != null) {
      error = checkpointStore!.recoveryIssue;
    }
    if (prior != null) {
      resumeStatus = 'Restored ${prior.visited} previously scanned photos '
          'from the local checkpoint.';
      year = prior.year;
      analyzingPeople = prior.people;
      completed = prior.complete;
      _baselineVisited = prior.visited;
      result = CleanupScanResult(
        photos: const {}, groups: const CleanupGroups(
          exact: [], similar: [], blurry: [], noPeople: []),
        total: prior.total, visited: prior.visited,
        skipped: prior.skipped, peopleDetectionAvailable: prior.people,
        years: const {},
      );
    }
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
    if (autoScan && !running && !_cancel &&
        checkpointStore?.recoveryIssue == null) {
      // Restore thumbnails and resume unfinished work without re-decoding
      // every photo previously analyzed. Completed scans hydrate the gallery.
      start(scopeYear: checkpointStore?.current?.year,
        people: checkpointStore?.current?.people);
    }
  }

  Future<void> start({int? scopeYear, bool? people}) async {
    if (running) return;
    final generation = ++_scanGeneration;
    _cancel = false;
    await _discardPending;
    await initialize();
    if (_disposed || generation != _scanGeneration) return;
    if (checkpointStore?.recoveryIssue != null) {
      error = checkpointStore!.recoveryIssue;
      _notify();
      return;
    }
    year = scopeYear;
    analyzingPeople = people ?? analyzingPeople;
    _baselineVisited = checkpointStore?.current?.year == year &&
            checkpointStore?.current?.people == analyzingPeople
        ? checkpointStore?.current?.visited ?? 0 : 0;
    running = true;
    _scanFinished = Completer<void>();
    paused = false;
    scanPhase = _baselineVisited > 0 ? 'Restoring saved scan' : 'Preparing scan';
    completed = false;
    error = null;
    if (_baselineVisited == 0) {
      result = null;
      resumeStatus = null;
    } else {
      resumeStatus = 'Resuming $_baselineVisited previously scanned photos.';
    }
    _excluded.clear();
    _dismissedExact.clear();
    _dismissedSimilar.clear();
    _startedAt = DateTime.now();
    _eta = null;
    _notify();
    try {
      final finalResult = await _scanner.scan(
        cancelled: () => _cancel || _disposed || generation != _scanGeneration,
        waitIfPaused: waitWhilePaused,
        onPhase: (phase) {
          if (!_disposed && !_cancel && generation == _scanGeneration &&
              scanPhase != phase) {
            scanPhase = phase;
            _notify();
          }
        },
        performance: performance,
        checkpointStore: checkpointStore!,
        protectedIds: Set<String>.of(_protected),
        year: year,
        analyzePeople: analyzingPeople,
        onProgress: (snapshot) {
          if (_disposed || _cancel || generation != _scanGeneration) return;
          result = snapshot;
          if (snapshot.restoring) {
            resumeStatus = 'Restoring saved analysis: '
                '${snapshot.restoredIndexed} / ${snapshot.restoredTotal} '
                'photos located. No thumbnails reanalyzed.';
          } else if (snapshot.restoredTotal > 0) {
            resumeStatus = null;
          }
          final elapsed = DateTime.now().difference(_startedAt!);
          // Show a measured ETA only after a meaningful sample. No fake ETA.
          final added = snapshot.visited - _baselineVisited;
          if (added >= 40 && elapsed.inSeconds >= 2 &&
              snapshot.total > snapshot.visited) {
            final remainingSeconds = elapsed.inMilliseconds /
                added * (snapshot.total - snapshot.visited) / 1000;
            _eta = Duration(seconds: remainingSeconds.round());
          }
          _notify();
        },
      );
      if (!_disposed && !_cancel && generation == _scanGeneration) {
        result = finalResult;
        completed = true;
        _eta = null;
        final scan = checkpointStore?.current;
        if (scan != null) {
          await archive?.save(
            started: scan.started,
            total: scan.total,
            analyzed: scan.analyzed,
            groups: finalResult.groups,
            peopleAnalyzed: scan.people &&
                finalResult.peopleDetectionAvailable,
          );
        }
        await checkpointStore?.finish('complete');
      }
    } catch (e) {
      if (!_disposed && generation == _scanGeneration && !_cancel) {
        error = '$e';
      }
    } finally {
      if (!_disposed && generation == _scanGeneration) {
        running = false;
        paused = false;
        scanPhase = error == null
            ? (completed ? 'Completed' : 'Stopped, checkpoint saved')
            : 'Scan interrupted: $error';
        _releasePausedWorker();
        _notify();
      }
      final completion = _scanFinished;
      _scanFinished = null;
      if (completion != null && !completion.isCompleted) {
        completion.complete();
      }
    }
  }

  /// Stop new work, finish the current in-flight batch, and safely flush its
  /// checkpoint. Called by the macOS menu bar before explicit full quit.
  /// Native macOS has its own 20-second deadline and forced-exit fallback.
  Future<void> pauseAndSaveForQuit() =>
      _preparingQuit ??= _pauseAndSaveForQuit();

  Future<void> _pauseAndSaveForQuit() async {
    await initialize();
    _cancel = true;
    paused = false;
    _releasePausedWorker();
    scanPhase = 'Saving checkpoint before quit';
    resumeStatus = 'Stopping scan and saving checkpoint before quit…';
    _notify();
    await _scanFinished?.future;
    await _discardPending;
    await checkpointStore?.flush();
    if (checkpointStore?.current != null) {
      await checkpointStore!.finish('paused');
    }
  }

  /// Pause at the next safe scanner boundary, then unblock immediately on
  /// Resume. A completer prevents repeated 200ms polling and missed toggles.
  Future<void> waitWhilePaused() async {
    while (paused && !_cancel && !_disposed) {
      _resumeSignal ??= Completer<void>();
      await _resumeSignal!.future;
    }
  }

  void _releasePausedWorker() {
    final waiting = _resumeSignal;
    _resumeSignal = null;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete();
    }
  }

  void pauseOrResume() {
    if (!running) return;
    paused = !paused;
    if (paused) {
      _resumeSignal ??= Completer<void>();
      scanPhase = 'Pausing after current photo operation';
    } else {
      _releasePausedWorker();
      scanPhase = 'Resuming scan';
    }
    _notify();
  }

  void stop() {
    _cancel = true;
    paused = false;
    _releasePausedWorker();
    scanPhase = 'Stopping';
    checkpointStore?.finish('stopped');
    _notify();
  }

  void toggleHistory() {
    showHistory = !showHistory;
    _notify();
  }

  void openHistory() {
    showHistory = true;
    _notify();
  }

  /// These options affect the next scan, not an already-running worker.
  void setNextScanOptions({int? scopeYear, required bool people}) {
    if (running) { return; }
    year = scopeYear;
    analyzingPeople = people;
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
    _releasePausedWorker();
    scanPhase = 'Scan results discarded';
    completed = false;
    result = null;
    error = null;
    _eta = null;
    _startedAt = null;
    resumeStatus = null;
    _excluded.clear();
    _dismissedExact.clear();
    _dismissedSimilar.clear();
    _discardPending = checkpointStore?.discard() ?? Future<void>.value();
    _notify();
  }

  void exclude(Iterable<String> ids) {
    _excluded.addAll(ids);
    _notify();
  }

  @override
  void dispose() {
    _cancel = true;
    _releasePausedWorker();
    _scanGeneration++;
    _disposed = true;
    performance.removeListener(_notify);
    performance.dispose();
    super.dispose();
  }
}