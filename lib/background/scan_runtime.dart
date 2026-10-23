import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ScanMode { minimal, eco, balanced, turbo }

extension ScanModeDetails on ScanMode {
  String get title => switch (this) {
        ScanMode.minimal => 'Minimal',
        ScanMode.eco => 'Eco',
        ScanMode.balanced => 'Balanced',
        ScanMode.turbo => 'Turbo',
      };

  double get targetCpu => switch (this) {
        ScanMode.minimal => 2,
        ScanMode.eco => 8,
        ScanMode.balanced => 30,
        ScanMode.turbo => 300,
      };

  int get concurrency => switch (this) {
        ScanMode.minimal || ScanMode.eco => 1,
        ScanMode.balanced => 2,
        ScanMode.turbo => 4,
      };

  Duration get minimumPacing => switch (this) {
        ScanMode.minimal => const Duration(milliseconds: 1100),
        ScanMode.eco => const Duration(milliseconds: 170),
        ScanMode.balanced => const Duration(milliseconds: 35),
        ScanMode.turbo => Duration.zero,
      };
}

class ScanProgress {
  const ScanProgress({
    required this.visited,
    required this.total,
    required this.analyzed,
    required this.running,
    required this.paused,
    required this.complete,
    this.eta,
    this.elapsedMs = 0,
    this.photosPerMinute = 0,
  });
  final int visited;
  final int total;
  final int analyzed;
  final bool running;
  final bool paused;
  final bool complete;
  final Duration? eta;
  final int elapsedMs;
  final double photosPerMinute;
}

/// Platform feedback for responsible scanning, not an OS-enforced CPU quota.
/// A native macOS status item owns menu clicks and hover information.
class ScanRuntime extends ChangeNotifier {
  static const MethodChannel _menu = MethodChannel('siftidy/menu_bar');
  static const String _modeKey = 'scan_base_mode_v02';
  static const String _idleKey = 'scan_auto_turbo_idle_v02';
  static const String _turboUntilKey = 'scan_manual_turbo_until_v02';

  ScanMode baseMode = ScanMode.eco;
  ScanMode activeMode = ScanMode.eco;
  Duration? get manualTurboRemaining {
    final deadline = _manualTurboUntil;
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    return remaining > Duration.zero ? remaining : null;
  }
  bool autoTurboOnIdle = false;
  double processCpu = 0;
  double ramMb = 0;
  bool onAcPower = false;
  bool thermalLimited = false;
  double idleSeconds = 0;
  bool supported = false;
  Future<void>? _initialization;
  Future<void> _turboWrites = Future<void>.value();
  bool _attached = false;
  bool _closed = false;
  DateTime? _manualTurboUntil;
  bool _manualTurboSawIdle = false;
  Timer? _poller;
  ScanProgress Function()? progress;
  void Function(String action)? handleAction;

  Future<void> initialize() => _initialization ??= _initializeOnce();

  Future<void> _initializeOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (_closed) return;
    baseMode = ScanMode.values.firstWhere(
      (item) => item.name == prefs.getString(_modeKey),
      orElse: () => ScanMode.eco,
    );
    if (baseMode == ScanMode.turbo) baseMode = ScanMode.eco;
    autoTurboOnIdle = prefs.getBool(_idleKey) ?? false;
    final deadline = prefs.getInt(_turboUntilKey);
    if (deadline != null) {
      final restored = DateTime.fromMillisecondsSinceEpoch(deadline);
      if (restored.isAfter(DateTime.now())) {
        _manualTurboUntil = restored;
        // Relaunching must not count as "returning from lunch". A fresh
        // idle-to-input transition will still cancel manual Turbo.
        _manualTurboSawIdle = false;
      }
    }
    _reconcile();
    notifyListeners();
  }

  Future<void> _saveTurboDeadline(DateTime? deadline) {
    // Serialize changes: a rapid Turbo -> Eco switch must not let a late
    // Turbo write re-enable the mode on the next launch.
    final write = _turboWrites.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (deadline == null) {
        await prefs.remove(_turboUntilKey);
      } else {
        await prefs.setInt(_turboUntilKey,
            deadline.millisecondsSinceEpoch);
      }
    });
    _turboWrites = write;
    return write;
  }

  Future<void> attach({
    required ScanProgress Function() readProgress,
    required void Function(String action) onAction,
  }) async {
    progress = readProgress;
    handleAction = onAction;
    _attached = true;
    _menu.setMethodCallHandler((call) async {
      if (_closed) return;
      if (call.method != 'action') return;
      final action = call.arguments?.toString() ?? '';
      if (action == 'toggleIdleTurbo') {
        await setAutoTurboOnIdle(!autoTurboOnIdle);
      } else if (action.startsWith('mode:')) {
        final choice = action.substring(5);
        if (choice.startsWith('turbo')) {
          final minutes = int.tryParse(choice.split(':').last) ?? 60;
          await activateTurbo(
              Duration(minutes: minutes.clamp(1, 120).toInt()));
        } else {
          final mode = ScanMode.values.where((m) => m.name == choice);
          if (mode.isNotEmpty) await setBaseMode(mode.first);
        }
      } else {
        handleAction?.call(action);
      }
      await sendStatus();
    });
    await initialize();
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 4), (_) => poll());
    await poll();
  }

  Future<void> setBaseMode(ScanMode value) async {
    if (value == ScanMode.turbo) {
      await activateTurbo(const Duration(minutes: 60));
      return;
    }
    _manualTurboUntil = null;
    _manualTurboSawIdle = false;
    baseMode = value;
    _reconcile();
    await _saveTurboDeadline(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, value.name);
    await sendStatus();
  }

  Future<void> setAutoTurboOnIdle(bool enabled) async {
    autoTurboOnIdle = enabled;
    _reconcile();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_idleKey, enabled);
    await _turboWrites;
    await sendStatus();
  }

  Future<void> activateTurbo(Duration duration) async {
    final deadline = DateTime.now().add(duration);
    _manualTurboUntil = deadline;
    _manualTurboSawIdle = false;
    _reconcile();
    await _saveTurboDeadline(deadline);
    await sendStatus();
  }

  void _reconcile() {
    final now = DateTime.now();
    if (_manualTurboUntil != null && idleSeconds >= 20) {
      _manualTurboSawIdle = true;
    }
    if (_manualTurboUntil != null &&
        (now.isAfter(_manualTurboUntil!) ||
            (_manualTurboSawIdle && idleSeconds < 5))) {
      _manualTurboUntil = null;
      _manualTurboSawIdle = false;
      unawaited(_saveTurboDeadline(null));
    }
    final newMode = thermalLimited
        ? ScanMode.eco
        : _manualTurboUntil != null
            ? ScanMode.turbo
            : autoTurboOnIdle && onAcPower && idleSeconds >= 600
                ? ScanMode.turbo
                : baseMode;
    if (newMode != activeMode) {
      activeMode = newMode;
      notifyListeners();
    }
  }

  Future<void> poll() async {
    if (_closed) return;
    try {
      final values = await _menu.invokeMapMethod<String, dynamic>('metrics');
      if (values != null) {
        supported = true;
        processCpu = (values['cpu'] as num?)?.toDouble() ?? processCpu;
        ramMb = (values['ramMb'] as num?)?.toDouble() ?? ramMb;
        idleSeconds = (values['idleSeconds'] as num?)?.toDouble() ?? 0;
        onAcPower = values['onAcPower'] == true;
        thermalLimited = values['thermalLimited'] == true;
      }
    } on MissingPluginException {
      supported = false; // Developer/test build without the native bridge.
    } on PlatformException {
      // Transient system metrics failure must not interrupt Photos scanning.
    }
    _reconcile();
    await _turboWrites;
    await sendStatus();
  }

  Future<void> sendStatus() async {
    if (_closed) return;
    final p = progress?.call();
    if (p == null) return;
    try {
      await _menu.invokeMethod<void>('status', <String, Object?>{
        'visited': p.visited,
        'total': p.total,
        'analyzed': p.analyzed,
        'running': p.running,
        'paused': p.paused,
        'complete': p.complete,
        'etaSeconds': p.eta?.inSeconds,
        'elapsedMs': p.elapsedMs,
        'ratePerMinute': p.photosPerMinute,
        'baseMode': baseMode.name,
        'activeMode': activeMode.name,
        'turboSecondsRemaining': manualTurboRemaining?.inSeconds,
        'idleTurbo': autoTurboOnIdle,
        'cpu': processCpu,
        'ramMb': ramMb,
      });
    } on MissingPluginException {
      // Flutter tests and non-macOS platforms have no status item.
    } on PlatformException {
      // Scan progress must never depend on the UI bridge.
    }
  }

  /// Called once for each asset work item. Target CPU is approximate;
  /// PhotoKit and iCloud may briefly exceed the process-level target.
  Future<void> pace({required bool Function() cancelled}) async {
    final mode = activeMode;
    if (mode == ScanMode.turbo) return;
    final target = mode.targetCpu;
    final multiplier = processCpu > target
        ? (processCpu / target).clamp(1.0, 15.0)
        : 1.0;
    final ms = math.min(6000,
        (mode.minimumPacing.inMilliseconds * multiplier).round());
    var remaining = ms;
    while (remaining > 0 && !cancelled()) {
      final chunk = math.min(remaining, 200);
      await Future<void>.delayed(Duration(milliseconds: chunk));
      remaining -= chunk;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _poller?.cancel();
    if (_attached) _menu.setMethodCallHandler(null);
    super.dispose();
  }
}
