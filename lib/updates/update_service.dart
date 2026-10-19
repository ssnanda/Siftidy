import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

const String gitHubReleasesUrl =
    'https://github.com/ssnanda/Siftidy/releases';
const String gitHubLatestReleaseApi =
    'https://api.github.com/repos/ssnanda/Siftidy/releases/latest';

enum UpdateState { available, current, unpublished, failed }

class UpdateStatus {
  const UpdateStatus({
    required this.state,
    required this.message,
    required this.installedVersion,
    this.latestVersion,
    this.downloadUrl,
  });

  final UpdateState state;
  final String message;
  final String installedVersion;
  final String? latestVersion;
  final Uri? downloadUrl;
  bool get hasUpdate => state == UpdateState.available;
}

/// Numeric dotted-version comparison. Returns null for invalid version tags.
int? compareVersions(String installed, String published) {
  List<int>? parse(String value) {
    final normalized =
        value.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    if (!RegExp(r'^[0-9]+(\.[0-9]+){1,3}$').hasMatch(normalized)) {
      return null;
    }
    return normalized.split('.').map(int.parse).toList(growable: false);
  }

  final a = parse(installed);
  final b = parse(published);
  if (a == null || b == null) return null;
  for (var i = 0; i < 4; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

UpdateStatus evaluateGitHubRelease(
    Map<String, dynamic>? release, String installedVersion) {
  if (release == null) {
    return UpdateStatus(
      state: UpdateState.unpublished,
      message: 'No stable GitHub Release has been published yet.',
      installedVersion: installedVersion,
    );
  }
  final tag = release['tag_name']?.toString() ?? '';
  final match = compareVersions(installedVersion, tag);
  if (match == null) {
    throw const FormatException('GitHub Release has an invalid version tag.');
  }
  Uri? package;
  final assets = release['assets'];
  if (assets is List) {
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = (asset['name']?.toString() ?? '').toLowerCase();
      final isMacPackage =
          (name.contains('macos') || name.contains('darwin') ||
              name.contains('mac-')) &&
          (name.endsWith('.dmg') || name.endsWith('.zip') ||
              name.endsWith('.pkg'));
      if (!isMacPackage) continue;
      final url =
          Uri.tryParse(asset['browser_download_url']?.toString() ?? '');
      if (url != null && url.scheme == 'https' && url.host == 'github.com') {
        package = url;
        break;
      }
    }
  }
  final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
  if (match == -1 && package != null) {
    return UpdateStatus(
      state: UpdateState.available,
      message: 'Version $version is available for macOS.',
      installedVersion: installedVersion,
      latestVersion: version,
      downloadUrl: package,
    );
  }
  if (match == -1) {
    return UpdateStatus(
      state: UpdateState.unpublished,
      message: 'GitHub has v$version, but no macOS installer is attached.',
      installedVersion: installedVersion,
      latestVersion: version,
    );
  }
  return UpdateStatus(
    state: UpdateState.current,
    message: 'You have the latest published macOS version.',
    installedVersion: installedVersion,
    latestVersion: version,
  );
}

class UpdateService {
  Future<UpdateStatus> check() async {
    final info = await PackageInfo.fromPlatform();
    try {
      if (Platform.isMacOS) {
        return evaluateGitHubRelease(
            await _readJson(Uri.parse(gitHubLatestReleaseApi)), info.version);
      }
      return UpdateStatus(
        state: UpdateState.unpublished,
        message: 'Update checking is supported on macOS.',
        installedVersion: info.version,
      );
    } catch (_) {
      return UpdateStatus(
        state: UpdateState.failed,
        message: 'Unable to check for updates. Check your connection '
            'and try again.',
        installedVersion: info.version,
      );
    }
  }

  Future<Map<String, dynamic>?> _readJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 8),
          );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Siftidy-UpdateCheck');
      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final body = await utf8.decoder.bind(response).join().timeout(
            const Duration(seconds: 10),
          );
      final value = jsonDecode(body);
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object.');
      }
      return value;
    } finally {
      client.close(force: true);
    }
  }
}
