import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';

/// Update checks fetch only public version metadata, never photo content.
class UpdateButton extends StatefulWidget {
  const UpdateButton({super.key});

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  static const _autoCheckKey = 'siftidy.auto_update_checks';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final UpdateService _service = UpdateService();

  bool _automatic = true;
  bool _checking = false;
  UpdateStatus? _status;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final enabled = await _preferences.getBool(_autoCheckKey) ?? true;
      if (!mounted) return;
      setState(() => _automatic = enabled);
      if (enabled) await _check();
    } catch (_) {
      // Preference failures must never block the Photos library.
    }
  }

  Future<void> _check({bool notify = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    final status = await _service.check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = status;
    });
    if (notify || status.hasUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status.message),
          action: status.hasUpdate
              ? SnackBarAction(label: 'View', onPressed: _openDetails)
              : null,
        ),
      );
    }
  }

  Future<void> _openExternal(Uri url) async {
    try {
      final launched =
          await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the update link.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the update link.')),
      );
    }
  }

  void _openDetails() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) {
          final status = _status;
          final base = Platform.isIOS ? 'AltStore' : 'GitHub Releases';
          final installed = status?.installedVersion ?? 'not checked';
          final latest = status?.latestVersion;
          return AlertDialog(
            title: const Text('Siftidy updates'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status?.message ??
                      'No update check has been completed yet.'),
                  const SizedBox(height: 8),
                  Text(latest == null
                      ? 'Installed: $installed'
                      : 'Installed: $installed · Latest: $latest'),
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Check automatically on launch'),
                    subtitle: Text(
                      'Fetches public update metadata from $base only. '
                      'No photos or analytics are uploaded.',
                    ),
                    value: _automatic,
                    onChanged: (value) {
                      setState(() => _automatic = value);
                      updateDialog(() {});
                      _preferences.setBool(_autoCheckKey, value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _check(notify: true);
                },
                child: const Text('Check now'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  if (Platform.isIOS) {
                    final link = Uri.parse('altstore://source?url=${Uri.encodeComponent(altStoreSourceUrl)}');
                    _openExternal(link);
                  } else if (status?.downloadUrl != null) {
                    _openExternal(status!.downloadUrl!);
                  } else {
                    _openExternal(Uri.parse(gitHubReleasesUrl));
                  }
                },
                child: Text(Platform.isIOS
                    ? 'Open in AltStore'
                    : status?.hasUpdate == true
                        ? 'Download update'
                        : 'GitHub Releases'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: _checking
            ? 'Checking for updates'
            : _status?.hasUpdate == true
                ? 'New Siftidy update available'
                : 'Siftidy updates',
        onPressed: _openDetails,
        icon: _checking
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _status?.hasUpdate == true
                    ? Icons.new_releases_outlined
                    : Icons.system_update_outlined,
                color: _status?.hasUpdate == true
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
      );
}
