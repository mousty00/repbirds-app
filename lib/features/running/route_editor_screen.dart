import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/running_repository.dart';
import '../../models/running.dart';
import 'geo.dart';
import 'location_source.dart';
import 'route_map.dart';

/// Nuovo percorso, o modifica di uno esistente ([routeId]).
class RouteEditorScreen extends ConsumerWidget {
  const RouteEditorScreen({super.key, this.routeId});

  final String? routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (routeId == null) return const _Editor();
    return Scaffold(
      body: AsyncView<RunRoute>(
        value: ref.watch(runRouteProvider(routeId!)),
        onRetry: () => ref.invalidate(runRouteProvider(routeId!)),
        data: (route) => _Editor(initial: route),
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({this.initial});

  final RunRoute? initial;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _map = MapController();
  late final List<LatLng> _waypoints = [...?widget.initial?.waypoints];
  RoutePlan? _plan;
  bool _trails = false;
  bool _planning = false;
  bool _saving = false;
  int _request = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _plan = RoutePlan(
        points: initial.points,
        rawPoints: initial.rawPoints,
        distanceM: initial.distanceM,
        elevationGainM: initial.elevationGainM,
        snapped: initial.points.length > initial.waypoints.length,
      );
    } else {
      _centerOnMe();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _centerOnMe() async {
    final source = LocationSource.create();
    try {
      await source.ensureReady();
      final me = await source.current();
      if (me != null && mounted) _map.move(me, 15);
    } on LocationUnavailable {
      // senza posizione si parte dalla vista dell'Italia e l'utente sposta la mappa
    }
  }

  void _changed() {
    setState(() {
      if (_waypoints.length < 2) _plan = null;
    });
    _debounce?.cancel();
    if (_waypoints.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 450), _replan);
  }

  Future<void> _replan() async {
    final request = ++_request;
    setState(() => _planning = true);
    try {
      final plan = await ref.read(runningRepositoryProvider).plan(_waypoints, trails: _trails);
      if (mounted && request == _request) setState(() => _plan = plan);
    } on ApiException catch (e) {
      if (mounted && request == _request) showMessage(context, e.message, error: true);
    } finally {
      if (mounted && request == _request) setState(() => _planning = false);
    }
  }

  void _add(LatLng p) {
    if (_waypoints.length >= 50) {
      showMessage(context, tr('Puoi mettere al massimo 50 punti'), error: true);
      return;
    }
    _waypoints.add(p);
    _changed();
  }

  void _undo() {
    if (_waypoints.isEmpty) return;
    _waypoints.removeLast();
    _changed();
  }

  void _closeLoop() {
    if (_waypoints.length < 2) return;
    _add(_waypoints.first);
  }

  Future<void> _clear() async {
    if (_waypoints.isEmpty) return;
    if (!await confirm(context, title: tr('Cancellare il tracciato?'), ok: tr('Cancella'), destructive: true)) return;
    _waypoints.clear();
    _changed();
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null || _planning) return;
    final details = await showModalBottomSheet<_RouteDetails>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _DetailsSheet(initial: widget.initial),
    );
    if (details == null) return;
    setState(() => _saving = true);
    try {
      final saved = await ref.read(runningRepositoryProvider).saveRoute(
            id: widget.initial?.id,
            name: details.name,
            description: details.description,
            isPublic: details.isPublic,
            waypoints: _waypoints,
            points: plan.rawPoints,
            trails: _trails,
          );
      ref.invalidate(myRoutesProvider);
      if (widget.initial != null) ref.invalidate(runRouteProvider(saved.id));
      if (!mounted) return;
      if (widget.initial == null) {
        context.pushReplacement('/running/route/${saved.id}');
      } else {
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final line = plan?.points ?? _waypoints;
    final initial = widget.initial;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: initial?.points.firstOrNull ?? const LatLng(41.9028, 12.4964),
              initialZoom: initial == null ? 5.5 : 14,
              initialCameraFit: initial != null && initial.points.length > 1
                  ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(initial.points), padding: const EdgeInsets.all(60))
                  : null,
              onTap: (_, p) => _add(p),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              ...baseMapLayers(),
              PolylineLayer(polylines: [if (line.length > 1) routeLine(line)]),
              MarkerLayer(markers: [
                for (var i = 1; i < _waypoints.length - 1; i++)
                  pointMarker(_waypoints[i], color: AppColors.blue, size: 14),
                ...startEndMarkers(_waypoints),
              ]),
              mapAttribution(top: true),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  CircleIconButton(icon: Icons.close_rounded, size: 44, onTap: () => context.pop()),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(30), boxShadow: AppShadows.soft),
                      child: Text(
                        _waypoints.isEmpty ? tr('Tocca la mappa per mettere la partenza') : tr('Tocca per aggiungere punti'),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleIconButton(icon: Icons.my_location_rounded, size: 44, tooltip: tr('La mia posizione'), onTap: _centerOnMe),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SoftCard(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(plan == null ? '0 m' : formatDistance(plan.distanceM),
                                    style: Theme.of(context).textTheme.headlineSmall),
                                Text(
                                  plan == null
                                      ? tr('Almeno due punti')
                                      : [
                                          if (plan.elevationGainM != null) tr('+{meters} m di dislivello', {'meters': plan.elevationGainM}),
                                          estimateTime(plan.distanceM),
                                        ].join(' · '),
                                  style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          if (_planning)
                            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ),
                      if (plan != null && !plan.snapped && _waypoints.length > 1) ...[
                        const SizedBox(height: 6),
                        Text(tr('Tratti in linea retta: metti più punti lungo le strade che vuoi fare.'),
                            style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _ToolButton(icon: Icons.undo_rounded, label: tr('Annulla'), onTap: _waypoints.isEmpty ? null : _undo),
                          _ToolButton(icon: Icons.loop_rounded, label: tr('Chiudi giro'), onTap: _waypoints.length < 2 ? null : _closeLoop),
                          _ToolButton(icon: Icons.delete_outline_rounded, label: tr('Cancella'), onTap: _waypoints.isEmpty ? null : _clear),
                          _ToolButton(
                            icon: Icons.forest_rounded,
                            label: tr('Sentieri'),
                            selected: _trails,
                            onTap: () {
                              setState(() => _trails = !_trails);
                              _changed();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PrimaryButton(
                        label: initial == null ? tr('Salva percorso') : tr('Salva modifiche'),
                        icon: Icons.check_rounded,
                        loading: _saving,
                        onPressed: plan == null || _planning ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, this.onTap, this.selected = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? AppColors.muted : (selected ? AppColors.mint : AppColors.ink);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteDetails {
  const _RouteDetails(this.name, this.description, this.isPublic);

  final String name;
  final String? description;
  final bool isPublic;
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({this.initial});

  final RunRoute? initial;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _description = TextEditingController(text: widget.initial?.description);
  late bool _public = widget.initial?.isPublic ?? false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final description = _description.text.trim();
    Navigator.pop(context, _RouteDetails(name, description.isEmpty ? null : description, _public));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Il tuo percorso'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: widget.initial == null,
            maxLength: 100,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: tr('Nome, es. Giro del parco')),
          ),
          TextField(
            controller: _description,
            maxLength: 500,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: tr('Note (fondo, fontanelle, salite…)')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _public,
            onChanged: (v) => setState(() => _public = v),
            title: Text(tr('Pubblico'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('I tuoi amici lo vedono e possono salvarlo per correrlo da soli.')),
          ),
          const SizedBox(height: 8),
          PrimaryButton(label: tr('Salva'), onPressed: _submit),
        ],
      ),
    );
  }
}
