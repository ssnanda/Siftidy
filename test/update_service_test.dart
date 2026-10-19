import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/updates/update_service.dart';

void main() {
  test('semantic numeric versions are compared correctly', () {
    expect(compareVersions('0.1.0', 'v0.1.1'), -1);
    expect(compareVersions('0.1.10', '0.1.9'), 1);
    expect(compareVersions('0.1.0+4', '0.1.0'), 0);
    expect(compareVersions('not-a-version', '1.0.0'), isNull);
  });

  test('GitHub release without macOS installer is not installable', () {
    final status = evaluateGitHubRelease(
      {'tag_name': 'v0.2.0', 'assets': []},
      '0.1.0',
    );
    expect(status.state, UpdateState.unpublished);
  });

  test('GitHub release with macOS installer offers update', () {
    final status = evaluateGitHubRelease({
      'tag_name': 'v0.2.0',
      'assets': [
        {
          'name': 'siftidy-macos-v0.2.0.dmg',
          'browser_download_url':
              'https://github.com/ssnanda/Siftidy/releases/download/v0.2.0/siftidy-macos-v0.2.0.dmg',
        },
      ],
    }, '0.1.0');
    expect(status.state, UpdateState.available);
    expect(status.downloadUrl, isNotNull);
  });
}
