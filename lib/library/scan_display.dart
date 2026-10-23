/// A single progress indicator belongs in the scan control, not in every
/// individual cleanup category.
String scanButtonLabel({
  required bool running,
  required bool completed,
  required int visited,
  required int total,
}) {
  if (!running && !completed && total <= 0) {
    return 'Intelligent Cleanup';
  }
  final percent = completed
      ? 100
      : total <= 0
          ? 0
          : (100 * visited / total).round().clamp(0, 100);
  return 'Scan $percent%';
}
