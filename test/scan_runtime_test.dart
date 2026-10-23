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
    expect(ScanMode.turbo.concurrency, 4);
    expect(ScanMode.minimal.targetCpu, lessThan(ScanMode.eco.targetCpu));
    runtime.dispose();
  });

  test('manual lunch break Turbo returns to Eco after user resumes input',
      () async {
    final runtime = ScanRuntime();
    await runtime.initialize();
    runtime.activateTurbo(const Duration(minutes: 60));
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
    runtime.activateTurbo(const Duration(minutes: 30));
    expect(runtime.activeMode, ScanMode.eco);
    runtime.dispose();
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
