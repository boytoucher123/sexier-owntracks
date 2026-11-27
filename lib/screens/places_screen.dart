// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/account_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/family_map.dart';
import '../strings.dart';

/// The group's shared places, inside its card on the Groups screen.
class GroupPlaces extends StatelessWidget {
  const GroupPlaces({super.key, required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final me = app.settings.username;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          Txt.placesTitle,
          style: t.titleSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (group.places.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              Txt.noPlacesYet,
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        for (final p in group.places)
          ListTile(
            contentPadding: const EdgeInsets.only(right: 4),
            leading: const CircleAvatar(
              backgroundColor: Color(0x1F6C4CF1),
              child: Icon(Icons.place_rounded, color: FlockColors.brand),
            ),
            title: Text(p.name),
            subtitle: Text(Txt.placeSize(formatDistance(p.radius * 2))),
            trailing: p.createdBy == me || group.isLeader
                ? IconButton(
                    tooltip: Txt.removePlace,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _remove(context, app, p),
                  )
                : null,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text(Txt.addAPlace),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddPlaceScreen(group: group)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _remove(BuildContext context, AppState app, Place p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Txt.removePlaceQ(p.name)),
        content: const Text(Txt.removePlaceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(Txt.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(Txt.removeButton),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await app.removePlace(group, p);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

/// Move the map so the pin is on the spot, name it, pick its size.
class AddPlaceScreen extends StatefulWidget {
  const AddPlaceScreen({super.key, required this.group});
  final Group group;

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  final _map = FamilyMapController();
  final _name = TextEditingController();
  double _radius = 100;
  LatLng? _center;
  bool _saving = false;
  String? _error;

  /// Radius in metres (shown as the distance across).
  static const _sizes = [50.0, 100.0, 250.0, 500.0, 1000.0];

  @override
  void initState() {
    super.initState();
    // Start where you are (or wherever the group is).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      final me = app.people.where(app.isMe).firstOrNull?.last;
      if (me != null) {
        _map.focus(me.latLng, zoom: 16);
        setState(() => _center = me.latLng);
      } else {
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (mounted && _center == null) {
            setState(() => _center = _map.center);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(AppState app) async {
    final at = _map.center ?? _center;
    if (at == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await app.addPlace(
      widget.group,
      name: _name.text.trim(),
      at: at,
      radius: _radius,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = err;
    });
    if (err == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final c = _center;
    return Scaffold(
      appBar: AppBar(title: Text(Txt.addPlaceTo(widget.group.name))),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: FamilyMap(
                    provider: app.mapProvider,
                    style: app.settings.mapStyle,
                    controller: _map,
                    people: const [], // the pin in the middle is what counts
                    onPersonTap: (_) {},
                    markStale: false,
                    // The new place previewed where the map last stopped.
                    places: [
                      ...widget.group.places,
                      if (c != null)
                        Place(
                          id: -1,
                          name: _name.text.trim().isEmpty
                              ? Txt.newPlace
                              : _name.text.trim(),
                          lat: c.latitude,
                          lon: c.longitude,
                          radius: _radius,
                        ),
                    ],
                    onCameraIdle: (p) => setState(() => _center = p),
                  ),
                ),
                // The spot: the middle of the map.
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 40),
                      child: Icon(
                        Icons.location_on_rounded,
                        size: 44,
                        color: FlockColors.brand,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black38)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: Material(
                    color: cs.surface.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(Txt.movePinHint, style: t.bodyMedium),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 40,
                    decoration: InputDecoration(
                      labelText: Txt.placeName,
                      hintText: Txt.placeNameHint,
                      prefixIcon: const Icon(Icons.edit_location_alt_rounded),
                      errorText: _error,
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Txt.placeSize(formatDistance(_radius * 2)),
                    style: t.labelLarge,
                  ),
                  SegmentedButton<double>(
                    segments: [
                      for (final r in _sizes)
                        ButtonSegment(
                          value: r,
                          label: Text(formatDistance(r * 2)),
                        ),
                    ],
                    selected: {_radius},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) =>
                        setState(() => _radius = v.first),
                  ),
                  const SizedBox(height: 14),
                  ListenableBuilder(
                    listenable: _name,
                    builder: (context, _) => FilledButton(
                      onPressed:
                          _name.text.trim().isNotEmpty && c != null && !_saving
                          ? () => _save(app)
                          : null,
                      child: Text(_saving ? Txt.saving : Txt.savePlace),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
