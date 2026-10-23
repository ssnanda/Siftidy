import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siftidy/background/scan_runtime.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Eco is the initial default and each profile has bounded workers', () {
    final runtime = ScanRuntime();
    expect(runtime.baseMode, ScanMode.eco);
    expect(ScanMode.minimal.concurrency, 1);
    expect(ScanMode.eco.concurrency, 1);
    expect(ScanMode.balanced.concurrency, 2);
    expect(ScanMode.turbo.concurrency, 6);
    expect(ScanMode.minimal.targetCpu, lessThan(ScanMode.eco.targetCpu));
    runtime.dispose();
  });

  test('manual lunch break Turbo returns to Eco after user resumes input',
      () async {
    final runtime = ScanRuntime();
    await runtime.initialize();
    await runtime.activateTurbo(const Duration(minutes: 60));
    expect(runtime.activeMode, ScanMode.turbo);
    runtime.idleSeconds = 42;
    await runtime.setAutoTurboOnIdle(false);
    expect(runtime.activeMode, ScanMode.turbo);
    runtime.idleSeconds = 2;
    await runtime.setAutoTurboOnIdle(false);
    expect(runtime.activeMode, ScanMode.eco);
    runtime.dispose();
  });

  test('auto idle Turbo needs AC power and reverts on activity', () async {
    final runtime = ScanRuntime();
    await runtime.initialize();
    runtime.onAcPower = true;
    runtime.idleSeconds = 605;
    await runtime.setAutoTurboOnIdle(true);
    expect(runtime.activeMode, ScanMode.turbo);
    runtime.idleSeconds = 3;
    await runtime.setAutoTurboOnIdle(true);
    expect(runtime.activeMode, ScanMode.eco);
    runtime.onAcPower = false;
    runtime.idleSeconds = 700;
    await runtime.setAutoTurboOnIdle(true);
    expect(runtime.activeMode, ScanMode.eco);
    runtime.dispose();
  });

  test('serious thermal pressure backs Turbo down to Eco', () async {
    final runtime = ScanRuntime();
    runtime.thermalLimited = true;
    await runtime.activateTurbo(const Duration(minutes: 30));
    expect(runtime.activeMode, ScanMode.eco);
    runtime.dispose();
  });

  test('timed Turbo restores after a full Quit without resetting its timer',
      () async {
    final first = ScanRuntime();
    await first.initialize();
    await first.activateTurbo(const Duration(minutes: 60));
    final prefs = await SharedPreferences.getInstance();
    final savedUntil = prefs.getInt('scan_manual_turbo_until_v02');
    expect(savedUntil, isNotNull);
    first.dispose();

    final reopened = ScanRuntime();
    await reopened.initialize();
    expect(reopened.baseMode, ScanMode.eco);
    expect(reopened.activeMode, ScanMode.turbo);
    expect(reopened.manualTurboRemaining, isNotNull);
    expect(reopened.manualTurboRemaining!.inMinutes, inInclusiveRange(58, 60));
    expect(prefs.getInt('scan_manual_turbo_until_v02'), savedUntil);
    reopened.dispose();
  });

  test('expired manual Turbo falls back to saved normal speed at launch',
      () async {
    SharedPreferences.setMockInitialValues({
      'scan_base_mode_v02': 'balanced',
      'scan_manual_turbo_until_v02':
          DateTime.now().subtract(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
    });
    final runtime = ScanRuntime();
    await runtime.initialize();
    expect(runtime.baseMode, ScanMode.balanced);
    expect(runtime.activeMode, ScanMode.balanced);
    expect(runtime.manualTurboRemaining, isNull);
    runtime.dispose();
  });

  test('a manual speed change cancels the persisted Turbo session', () async {
    final first = ScanRuntime();
    await first.initialize();
    await first.activateTurbo(const Duration(minutes: 60));
    await first.setBaseMode(ScanMode.minimal);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('scan_manual_turbo_until_v02'), isNull);
    first.dispose();

    final reopened = ScanRuntime();
    await reopened.initialize();
    expect(reopened.baseMode, ScanMode.minimal);
    expect(reopened.activeMode, ScanMode.minimal);
    reopened.dispose();
  });

  test('base mode persists across future starts', () async {
    final first = ScanRuntime();
    await first.initialize();
    await first.setBaseMode(ScanMode.minimal);
    first.dispose();
    final second = ScanRuntime();
    await second.initialize();
    expect(second.baseMode, ScanMode.minimal);
    second.dispose();
  });
}
