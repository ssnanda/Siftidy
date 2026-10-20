// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'update_service.dart';

/// SHA-256 verified GitHub ZIP, staged before replacing an installed Mac app.
class MacQuickUpdater {
  const MacQuickUpdater();

  static String? installedAppPath(String executable) {
    if (!executable.contains('/Contents/MacOS/')) return null;
    final root = File(executable).parent.parent.parent.path;
    return root.toLowerCase().endsWith('.app') ? root : null;
  }

  static bool isAllowedInstallPath(String path, String home) {
    final parent = Directory(path).parent.path;
    return path.toLowerCase().endsWith('.app') &&
        (parent == '/Applications' || parent == '$home/Applications');
  }

  static Future<bool> canWriteInstallDirectory(String path) async {
    Directory? probe;
    try {
      probe = await Directory(path)
          .createTemp('.siftidy-write-check-')
          .timeout(const Duration(seconds: 8));
      return true;
    } on FileSystemException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      if (probe != null) {
        try {
          await probe.delete(recursive: true);
        } catch (_) {
          // A failed cleanup must not mask the write permission result.
        }
      }
    }
  }

  Future<String?> install(
      UpdateStatus status, void Function(String) progress) async {
    if (!Platform.isMacOS) return 'Updates work only on macOS.';
    final url = status.downloadUrl;
    final checksum = status.sha256;
    final version = status.latestVersion;
    if (!status.hasUpdate || url == null || version == null) {
      return 'No newer Mac version is available.';
    }
    if (checksum == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
      return 'GitHub has no verifiable SHA-256 for this release. '
          'Please use GitHub Releases.';
    }
    if (url.scheme != 'https' || url.host != 'github.com' ||
        !url.path.startsWith('/ssnanda/Siftidy/releases/download/') ||
        !url.path.endsWith('.zip')) {
      return 'Update URL is not a trusted GitHub ZIP.';
    }
    final current = installedAppPath(Platform.resolvedExecutable);
    final home = Platform.environment['HOME'] ?? '';
    if (current == null || !isAllowedInstallPath(current, home)) {
      return 'Move Siftidy.app into /Applications (or ~/Applications), '
          'launch it from there, then retry.';
    }
    Directory? temp;
    var helperStarted = false;
    try {
      progress('Checking Applications folder permissions…');
      final writable = await canWriteInstallDirectory(Directory(current).parent.path);
      if (!writable) {
        return 'Your Applications folder is not writable by this account. '
            'Download the ZIP and replace the app manually.';
      }

      progress('Preparing the update download…');
      temp = await Directory.systemTemp
          .createTemp('siftidy-update-')
          .timeout(const Duration(seconds: 8));
      final zip = File('${temp.path}/download.zip');
      final stage = Directory('${temp.path}/extracted');
      progress('Downloading Siftidy $version…');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final request =
            await client.getUrl(url).timeout(const Duration(seconds: 20));
        request.headers.set(HttpHeaders.userAgentHeader, 'Siftidy-MacUpdater');
        final response =
            await request.close().timeout(const Duration(seconds: 30));
        if (response.statusCode != HttpStatus.ok) {
          return 'Download failed (HTTP ' + response.statusCode.toString() + ').';
        }
        final sink = zip.openWrite();
        var bytes = 0;
        try {
          await for (final chunk
              in response.timeout(const Duration(seconds: 40))) {
            bytes += chunk.length;
            if (bytes > 600 * 1024 * 1024) {
              throw const FormatException('Archive too large.');
            }
            sink.add(chunk);
            if (bytes % (1024 * 1024) < chunk.length) {
              progress('Downloaded ' +
                  (bytes / 1048576).toStringAsFixed(1) + ' MB…');
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (status.downloadSize != null && bytes != status.downloadSize) {
          return 'ZIP size differs from GitHub Release metadata.';
        }
      } finally {
        client.close(force: true);
      }
      progress('Verifying SHA-256…');
      final digest = await sha256.bind(zip.openRead()).first;
      if (digest.toString() != checksum) {
        return 'Update verification failed: SHA-256 checksum mismatch.';
      }
      progress('Preparing new app…');
      await stage.create();
      final unpack = await Process.run(
          '/usr/bin/ditto', ['-x', '-k', zip.path, stage.path])
          .timeout(const Duration(minutes: 3));
      if (unpack.exitCode != 0) return 'Unable to unpack GitHub ZIP.';
      final apps = await stage
          .list(followLinks: false)
          .where((entry) => entry is Directory &&
              entry.path.toLowerCase().endsWith('.app'))
          .toList();
      if (apps.length != 1) return 'ZIP must contain exactly one Mac app.';
      final next = apps.single.path;
      final oldId = await _plist(current, 'CFBundleIdentifier');
      final nextId = await _plist(next, 'CFBundleIdentifier');
      final nextVersion = await _plist(next, 'CFBundleShortVersionString');
      if (oldId.isEmpty || nextId != oldId || nextVersion != version) {
        return 'Downloaded app has the wrong bundle identifier or version.';
      }
      final executable = Directory(next + '/Contents/MacOS');
      if (!await executable.exists() || await executable.list().isEmpty) {
        return 'Downloaded app executable is missing.';
      }
      progress('Installing and restarting…');
      final script = File(temp.path + '/install.sh');
      await script.writeAsString(helperScript);
      final logs = Directory(home + '/Library/Logs/Siftidy');
      await logs.create(recursive: true);
      await Process.start('/bin/sh', [
        script.path, current, next, pid.toString(),
        temp.path, logs.path + '/updater.log',
      ], mode: ProcessStartMode.detached).timeout(const Duration(seconds: 10));
      helperStarted = true;
      // The detached helper waits for this process to quit and rolls back
      // if copying the new app fails. Do not delete the staged files.
      exit(0);
    } on TimeoutException {
      return 'The update timed out. Please retry or download the ZIP from '
          'GitHub Releases.';
    } catch (error) {
      return 'The update could not start: $error';
    } finally {
      if (!helperStarted && temp != null) {
        try {
          if (await temp.exists()) {
            await temp.delete(recursive: true);
          }
        } catch (_) {
          // Never conceal the original update error due to cleanup.
        }
      }
    }
  }

  Future<String> _plist(String app, String key) async {
    final result = await Process.run('/usr/libexec/PlistBuddy',
        ['-c', 'Print :$key', app + '/Contents/Info.plist'])
        .timeout(const Duration(seconds: 8));
    return result.exitCode == 0 ? result.stdout.toString().trim() : '';
  }

  /// The detached helper is deliberately plain POSIX shell, so it continues
  /// after the Flutter process terminates and can reopen the updated app.
  static const String helperScript = r'''#!/bin/sh
set -eu
TARGET="$1"
SOURCE="$2"
APP_PID="$3"
WORK="$4"
LOG="$5"
exec >> "$LOG" 2>&1
echo "Siftidy updater awaiting pid $APP_PID"
i=0
while kill -0 "$APP_PID" 2>/dev/null && [ "$i" -lt 120 ]; do
  sleep 0.5
  i=$((i + 1))
done
if kill -0 "$APP_PID" 2>/dev/null; then
  echo "App did not exit; original app preserved."
  exit 1
fi
NEW="$TARGET.siftidy-new-$APP_PID"
BACKUP="$TARGET.siftidy-backup-$APP_PID"
if ! /usr/bin/ditto "$SOURCE" "$NEW"; then
  echo "Unable to stage app; old app preserved."
  exit 1
fi
if ! /bin/mv "$TARGET" "$BACKUP"; then
  /bin/rm -rf "$NEW"
  echo "Cannot replace app; original preserved."
  exit 1
fi
if ! /bin/mv "$NEW" "$TARGET"; then
  /bin/mv "$BACKUP" "$TARGET" || true
  echo "Replacement failed; restored original."
  /usr/bin/open -n -a "$TARGET" || true
  exit 1
fi

# A successful 'open' exit status does not prove Gatekeeper allowed launch.
# -n avoids LaunchServices reusing the just-terminated, old app instance.
echo "Replaced Siftidy. Requesting a fresh launch."
if ! /usr/bin/open -n -a "$TARGET"; then
  echo "LaunchServices declined the launch request."
fi

# Verify there is a running executable rather than trusting 'open' alone.
# CFBundleExecutable is more reliable than assuming a fixed binary name.
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TARGET/Contents/Info.plist" 2>/dev/null || true)
i=0
while [ "$i" -lt 24 ]; do
  if /usr/bin/pgrep -f "$TARGET/Contents/MacOS/" >/dev/null 2>&1 ||
     { [ -n "$EXECUTABLE" ] && /usr/bin/pgrep -x "$EXECUTABLE" >/dev/null 2>&1; }; then
    echo "Confirmed Siftidy restarted."
    /bin/rm -rf "$BACKUP"
    /bin/rm -rf "$WORK"
    exit 0
  fi
  sleep 0.5
  i=$((i + 1))
done

# Keep the updated app installed so the user approves THAT version.
# An approval may be necessary, but only macOS can authorize it.
echo "Relaunch could not be confirmed. Opening Privacy & Security."
if ! /usr/bin/open 'x-apple.systempreferences:com.apple.preference.security'; then
  /usr/bin/open -a 'System Settings' || true
fi
# Preserve the previous app as a rollback until a future successful install.
/bin/rm -rf "$WORK"
exit 0
''';
}

/// Opens macOS Privacy & Security. Apple's 'Open Anyway' control
/// is not exposed as a public deep-link destination.
Future<bool> openMacPrivacySecurity() async {
  if (!Platform.isMacOS) return false;
  try {
    final result = await Process.run('/usr/bin/open',
        ['x-apple.systempreferences:com.apple.preference.security']);
    if (result.exitCode == 0) return true;
    final fallback =
        await Process.run('/usr/bin/open', ['-a', 'System Settings']);
    return fallback.exitCode == 0;
  } catch (_) {
    return false;
  }
}
