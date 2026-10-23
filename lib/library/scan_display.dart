import 'package:flutter/material.dart';

/// A static scan-progress readout. The percent changes as work advances,
/// but this button intentionally never draws an animated progress spinner.
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

/// A single simple percent badge stays still during running, paused,
/// restoring, and completed scans. Only its number updates.
class ScanProgressButton extends StatelessWidget {
  const ScanProgressButton({
    super.key,
    required this.running,
    required this.completed,
    required this.visited,
    required this.total,
    this.onPressed,
  });

  final bool running;
  final bool completed;
  final int visited;
  final int total;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(scanButtonLabel(
        running: running,
        completed: completed,
        visited: visited,
        total: total,
      )),
    );
  }
}
