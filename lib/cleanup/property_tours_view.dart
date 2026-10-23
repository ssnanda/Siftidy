import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'photo_analysis.dart';

/// Suggested, local photo collections. No Photos albums are created, and no
/// photo may be deleted from this screen.
class PropertyToursView extends StatefulWidget {
  const PropertyToursView({super.key, required this.tours});
  final List<PropertyTourSuggestion> tours;

  @override
  State<PropertyToursView> createState() => _PropertyToursViewState();
}

class _PropertyToursViewState extends State<PropertyToursView> {
  static const _geocoding = MethodChannel('siftidy/geocoding');
  final Map<String, String> _labels = {};
  final Map<String, TextEditingController> _editors = {};
  final Set<String> _rejected = {};
  String? _busyTour;
  String? _message;

  String _key(PropertyTourSuggestion tour) => tour.ids.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) { return; }
    setState(() {
      for (final tour in widget.tours) {
        final id = _key(tour);
        final saved = prefs.getString('property_label_$id');
        if (saved != null) { _labels[id] = saved; }
        if (prefs.getBool('property_rejected_$id') == true) { _rejected.add(id); }
      }
    });
  }

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  Future<void> _save(PropertyTourSuggestion tour) async {
    final key = _key(tour);
    final text = _editors[key]?.text.trim() ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('property_label_$key', text);
    if (mounted) setState(() {
      if (text.isEmpty) {
        _labels.remove(key);
      } else {
        _labels[key] = text;
      }
      _message = 'Tour label saved locally.';
    });
  }

  Future<void> _dismiss(PropertyTourSuggestion tour) async {
    final key = _key(tour);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('property_rejected_$key', true);
    if (mounted) { setState(() => _rejected.add(key)); }
  }

  Future<void> _lookupAddress(PropertyTourSuggestion tour) async {
    if (tour.latitude == null || tour.longitude == null) { return; }
    final key = _key(tour);
    setState(() { _busyTour = key; _message = null; });
    try {
      // Only this explicit tap contacts Apple's geocoding service.
      final address = await _geocoding.invokeMethod<String>('reverseAddress', {
        'latitude': tour.latitude!,
        'longitude': tour.longitude!,
      });
      if (!mounted) { return; }
      if (address == null || address.trim().isEmpty) {
        setState(() => _message = 'Apple did not return a street address.');
        return;
      }
      _editors.putIfAbsent(key, () =>
          TextEditingController(text: _labels[key] ?? ''))
          .text = address;
      await _save(tour);
    } on PlatformException catch (error) {
      if (mounted) { setState(() => _message =
          'Address lookup failed: ${error.message ?? error.code}'); }
    } on MissingPluginException {
      if (mounted) { setState(() => _message =
          'Address lookup is unavailable in this build.'); }
    } finally {
      if (mounted) { setState(() => _busyTour = null); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.tours.where(
        (tour) => !_rejected.contains(_key(tour))).toList();
    return ListView(padding: const EdgeInsets.all(18), children: [
      Text('Property tours', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 5),
      const Text('Possible groups of 5+ consecutive home photos, verified '
          'using on-device visual classification. They are suggestions, '
          'not new Apple Photos albums. No photos are moved or deleted.'),
      const SizedBox(height: 8),
      const Text('Addresses stay on this Mac. Apple address lookup is '
          'optional and sends only the selected GPS coordinates.'),
      if (_message != null) Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_message!)),
      if (visible.isEmpty) const Padding(
        padding: EdgeInsets.all(20),
        child: Text('No suggested property tours in this scan. '
            'Try scanning a series of at least five home/interior photos.')),
      for (final tour in visible)
        _tourCard(context, tour),
    ]);
  }

  Widget _tourCard(BuildContext context, PropertyTourSuggestion tour) {
    final key = _key(tour);
    final date = DateTime.fromMillisecondsSinceEpoch(tour.startedAtMs);
    final label = _labels[key];
    final coords = tour.latitude != null && tour.longitude != null
        ? '${tour.latitude!.toStringAsFixed(5)}, '
          '${tour.longitude!.toStringAsFixed(5)}'
        : 'No location metadata';
    final editor = _editors.putIfAbsent(key, () =>
        TextEditingController(text: label ?? ''));
    return Card(margin: const EdgeInsets.symmetric(vertical: 8), child:
      ExpansionTile(
        title: Text(label == null || label.isEmpty
            ? 'Property tour · ${tour.ids.length} photos' : label),
        subtitle: Text('${date.year}-${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')} · $coords'),
        childrenPadding: const EdgeInsets.all(14),
        children: [
          SizedBox(height: 105, child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final id in tour.ids.take(12))
                Padding(padding: const EdgeInsets.only(right: 8),
                    child: _TourThumbnail(id: id)),
              if (tour.ids.length > 12) Center(
                  child: Text('+${tour.ids.length - 12} more')),
            ],
          )),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: editor,
              decoration: const InputDecoration(
                labelText: 'Address or name',
                hintText: 'Enter address or tour name',
                border: OutlineInputBorder()),
              onSubmitted: (_) => _save(tour),
            )),
            const SizedBox(width: 8),
            TextButton(onPressed: () => _save(tour),
              child: const Text('Save')),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 8, children: [
            if (tour.latitude != null && tour.longitude != null)
              OutlinedButton.icon(
                onPressed: _busyTour == null ? () => _lookupAddress(tour) : null,
                icon: const Icon(Icons.place_outlined),
                label: Text(_busyTour == key
                    ? 'Looking up address…'
                    : 'Look up with Apple'),
              ),
            TextButton.icon(
              onPressed: () => _dismiss(tour),
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('Not a property tour'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _TourThumbnail extends StatefulWidget {
  const _TourThumbnail({required this.id});
  final String id;
  @override
  State<_TourThumbnail> createState() => _TourThumbnailState();
}

class _TourThumbnailState extends State<_TourThumbnail> {
  late Future<AssetEntity?> _asset;
  @override
  void initState() {
    super.initState();
    _asset = AssetEntity.fromId(widget.id);
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<AssetEntity?>(
    future: _asset,
    builder: (context, snapshot) => SizedBox(width: 105, height: 105,
      child: ClipRRect(borderRadius: BorderRadius.circular(8),
        child: snapshot.data == null
          ? Container(color: Theme.of(context).colorScheme.surfaceContainer,
              child: Icon(snapshot.connectionState == ConnectionState.done
                ? Icons.broken_image_outlined : Icons.photo_outlined))
          : AssetEntityImage(snapshot.data!, isOriginal: false,
              thumbnailSize: const ThumbnailSize(220, 220),
              fit: BoxFit.cover)),
    ),
  );
}
