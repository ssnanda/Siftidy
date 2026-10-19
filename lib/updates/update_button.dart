import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';
import 'mac_quick_updater.dart';

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
  bool _installing = false;
  String _installProgress = '';
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

  Future<void> _installNow() async {
    final status = _status;
    if (status == null || _installing) return;
    setState(() {
      _installing = true;
      _installProgress = 'Starting update…';
    });
    final error = await const MacQuickUpdater().install(status, (message) {
      if (mounted) setState(() => _installProgress = message);
    });
    if (!mounted) return;
    setState(() => _installing = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 12)),
      );
    }
  }

  Future<void> _openSecuritySettings() async {
    final success = await openMacPrivacySecurity();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open System Settings → Privacy & Security.')),
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
          const base = 'GitHub Releases';
          final installed = status?.installedVersion ?? 'not checked';
          final latest = status?.latestVersion;
          final canQuickUpdate = status?.hasUpdate == true &&
              status?.sha256 != null && status?.downloadUrl != null;
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
                  const SizedBox(height: 10),
                  if (_installing) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(_installProgress),
                    const SizedBox(height: 10),
                  ],
                  if (status?.hasUpdate == true)
                    const Text('Update & Restart replaces the copy of Siftidy '
                        'in Applications. The older app is kept until the '
                        'replacement is ready.'),
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
                onPressed: _installing ? null : _openSecuritySettings,
                child: const Text('Privacy & Security'),
              ),
              TextButton(
                onPressed: _installing ? null : () {
                  Navigator.pop(dialogContext);
                  _check(notify: true);
                },
                child: const Text('Check Now'),
              ),
              if (canQuickUpdate)
                FilledButton.icon(
                  onPressed: _installing ? null : () {
                    Navigator.pop(dialogContext);
                    _installNow();
                  },
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('Update & Restart'),
                )
              else
                TextButton(
                  onPressed: _installing ? null : () {
                    Navigator.pop(dialogContext);
                    if (status?.downloadUrl != null) {
                      _openExternal(status!.downloadUrl!);
                    } else {
                      _openExternal(Uri.parse(gitHubReleasesUrl));
                    }
                  },
                  child: Text(status?.hasUpdate == true
                      ? 'Download ZIP' : 'GitHub Releases'),
                ),
              TextButton(
                onPressed: _installing ? null : () => Navigator.pop(dialogContext),
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
        tooltip: _installing ? _installProgress : _checking
            ? 'Checking for updates'
            : _status?.hasUpdate == true
                ? 'New Siftidy update available'
                : 'Siftidy updates',
        onPressed: _installing ? null : _openDetails,
        icon: _checking || _installing
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
