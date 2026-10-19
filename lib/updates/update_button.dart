import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';
import 'mac_quick_updater.dart';

/// State is observed by the modal separately from the page's setState.
class _InstallUiState {
  const _InstallUiState({
    required this.busy,
    required this.message,
    this.error,
  });
  final bool busy;
  final String message;
  final String? error;
}

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
  final ValueNotifier<_InstallUiState> _installUi =
      ValueNotifier(const _InstallUiState(busy: false, message: ''));
  UpdateStatus? _status;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _installUi.dispose();
    super.dispose();
  }

  void _updateInstallUi(bool busy, String message, {String? error}) {
    if (!mounted) return;
    _installUi.value = _InstallUiState(
      busy: busy,
      message: message,
      error: error,
    );
    setState(() => _installing = busy);
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
    _updateInstallUi(true, 'Checking update prerequisites…');
    try {
      final error = await const MacQuickUpdater().install(status, (message) {
        _updateInstallUi(true, message);
      });
      // Success exits Siftidy after starting its independent updater.
      if (!mounted) return;
      _updateInstallUi(
        false,
        error == null
            ? 'Update handed off. Siftidy will reopen when ready.'
            : 'Update failed — the installed app has not been replaced.',
        error: error,
      );
    } catch (error) {
      _updateInstallUi(
        false,
        'Update failed — the installed app has not been replaced.',
        error: error.toString(),
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
        builder: (dialogContext, updateDialog) =>
            ValueListenableBuilder<_InstallUiState>(
          valueListenable: _installUi,
          builder: (dialogContext, installUi, _) {
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
                  if (installUi.busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(installUi.message),
                    const SizedBox(height: 10),
                  ],
                  if (installUi.error != null) ...[
                    Text(installUi.message,
                      style: const TextStyle(
                        color: Color(0xFFA52835),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(installUi.error!,
                      style: const TextStyle(fontSize: 13),
                    ),
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
                onPressed: _openSecuritySettings,
                child: const Text('Privacy & Security'),
              ),
              TextButton(
                onPressed: installUi.busy ? null : () {
                  Navigator.pop(dialogContext);
                  _check(notify: true);
                },
                child: const Text('Check Now'),
              ),
              if (status?.downloadUrl != null)
                TextButton(
                  onPressed: () => _openExternal(status!.downloadUrl!),
                  child: const Text('Download ZIP'),
                ),
              if (canQuickUpdate)
                FilledButton.icon(
                  onPressed: installUi.busy ? null : _installNow,
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('Update & Restart'),
                )
              else
                TextButton(
                  onPressed: () => _openExternal(Uri.parse(gitHubReleasesUrl)),
                  child: const Text('GitHub Releases'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: _installing ? _installUi.value.message : _checking
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
