import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';
import 'mac_quick_updater.dart';

/// A compact toolbar menu rather than modal dialogs or surprise notifications.
/// Green means up-to-date; red means a newer verified release was found.
enum _UpdateAction {
  automatic,
  check,
  install,
  download,
  releases,
  privacy,
}

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
  String? _installProgress;
  String? _installError;
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
      // Settings must never interfere with browsing the photo library.
    }
  }

  Future<void> _setAutomatic(bool enabled) async {
    setState(() => _automatic = enabled);
    try {
      await _preferences.setBool(_autoCheckKey, enabled);
    } catch (_) {
      // A failed preference write must not block the UI.
    }
    if (enabled && _status == null && mounted) await _check();
  }

  Future<void> _check() async {
    if (_checking || _installing) return;
    setState(() {
      _checking = true;
      _installError = null;
    });
    try {
      final status = await _service.check();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = const UpdateStatus(
        state: UpdateState.failed,
        message: 'Unable to check for updates.',
        installedVersion: 'unknown',
      ));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _installNow() async {
    final status = _status;
    if (status == null || !status.hasUpdate || _installing) return;
    setState(() {
      _installing = true;
      _installError = null;
      _installProgress = 'Checking update prerequisites…';
    });
    try {
      final error = await const MacQuickUpdater().install(status, (message) {
        if (mounted) setState(() => _installProgress = message);
      });
      // On successful handoff, the updater exits the app process.
      if (!mounted) return;
      setState(() {
        _installError = error;
        _installProgress = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installError = error.toString();
        _installProgress = null;
      });
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _openExternal(Uri url) async {
    try {
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        setState(() => _installError = 'Unable to open link.');
      }
    } catch (_) {
      if (mounted) setState(() => _installError = 'Unable to open link.');
    }
  }

  void _choose(_UpdateAction action) {
    switch (action) {
      case _UpdateAction.automatic:
        _setAutomatic(!_automatic);
      case _UpdateAction.check:
        _check();
      case _UpdateAction.install:
        _installNow();
      case _UpdateAction.download:
        final url = _status?.downloadUrl;
        if (url != null) _openExternal(url);
      case _UpdateAction.releases:
        _openExternal(Uri.parse(gitHubReleasesUrl));
      case _UpdateAction.privacy:
        openMacPrivacySecurity();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUpdate = _status?.hasUpdate == true;
    final statusColor = hasUpdate
        ? const Color(0xFFCA2934)
        : _status?.state == UpdateState.current
            ? const Color(0xFF168344)
            : const Color(0xFF66787D);
    final statusLabel = _installError != null
        ? 'Update error: $_installError'
        : _installProgress ??
            _status?.message ??
            (_checking ? 'Checking for updates…' : 'Not checked yet');
    final canInstall = hasUpdate && _status?.downloadUrl != null &&
        _status?.sha256 != null && !_installing;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _checking ? 'Checking…' : 'Check for updates',
          onPressed: _checking || _installing ? null : _check,
          icon: _checking || _installing
              ? SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: statusColor,
                  ),
                )
              : Icon(
                  Icons.system_update_outlined,
                  color: statusColor,
                  size: 25,
                ),
        ),
        PopupMenuButton<_UpdateAction>(
          tooltip: 'Update settings',
          offset: const Offset(0, 42),
          padding: EdgeInsets.zero,
          iconSize: 20,
          position: PopupMenuPosition.under,
          onSelected: _choose,
          icon: const Icon(Icons.arrow_drop_down),
          itemBuilder: (context) => [
        PopupMenuItem<_UpdateAction>(
          enabled: false,
          child: SizedBox(
            width: 290,
            child: Text(statusLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _installError == null ? null : const Color(0xFFCA2934),
              ),
            ),
          ),
        ),
        PopupMenuItem<_UpdateAction>(
          value: _UpdateAction.automatic,
          enabled: !_installing,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
                child: Checkbox(
                  value: _automatic,
                  onChanged: (_) {},
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Expanded(child: Text('Check automatically on launch')),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_UpdateAction>(
          value: _UpdateAction.check,
          enabled: !_checking && !_installing,
          child: const Text('Check now'),
        ),
        if (hasUpdate)
          PopupMenuItem<_UpdateAction>(
            value: _UpdateAction.install,
            enabled: canInstall,
            child: const Row(children: [
              Icon(Icons.system_update_alt, size: 20),
              SizedBox(width: 10),
              Text('Update & Restart'),
            ]),
          ),
        if (_status?.downloadUrl != null)
          const PopupMenuItem<_UpdateAction>(
            value: _UpdateAction.download,
            child: Text('Download ZIP'),
          ),
        const PopupMenuItem<_UpdateAction>(
          value: _UpdateAction.releases,
          child: Text('GitHub Releases'),
        ),
        const PopupMenuItem<_UpdateAction>(
          value: _UpdateAction.privacy,
          child: Text('Privacy & Security'),
        ),
          ],
        ),
      ],
    );
  }
}
