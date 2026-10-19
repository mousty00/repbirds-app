import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/running_repository.dart';
import '../../models/running.dart';
import 'geo.dart';
import 'location_source.dart';
import 'route_map.dart';
import 'run_recorder.dart';

enum _Phase { loading, ready, running, paused, saving }

/// Registra una corsa col GPS: libera, su un percorso ([routeId]) o per una corsa di gruppo ([eventId]).
class RunTrackerScreen extends ConsumerStatefulWidget {
  const RunTrackerScreen({super.key, this.routeId, this.eventId});

  final String? routeId;
  final String? eventId;

  @override
  ConsumerState<RunTrackerScreen> createState() => _RunTrackerScreenState();
}

class _RunTrackerScreenState extends ConsumerState<RunTrackerScreen> {
  final _map = MapController();
  _Phase _phase = _Phase.loading;
  RunRoute? _route;
  RunRecorder _recorder = RunRecorder();
  StreamSubscription<Fix>? _subscription;
  Timer? _ticker;
  LatLng? _position;
  bool _follow = true;
  bool _wasOffRoute = false;
  String? _error;
  bool _openSettings = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      if (widget.routeId != null) {
        _route = await ref.read(runningRepositoryProvider).route(widget.routeId!);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    _recorder = RunRecorder(route: _route?.points ?? const []);
    final source = LocationSource.create(route: _route?.points ?? const []);
    try {
      await source.ensureReady();
    } on LocationUnavailable catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _openSettings = e.openSettings;
        });
      }
      return;
    }
    _position = await source.current();
    if (!mounted) return;
    setState(() => _phase = _Phase.ready);
    if (_position != null && _route == null) _map.move(_position!, 16);
    _subscription = source.fixes().listen(_onFix, onError: (Object e) {
      if (mounted) showMessage(context, tr('GPS non disponibile: {error}', {'error': e}), error: true);
    });
  }

  void _onFix(Fix fix) {
    if (!mounted) return;
    _recorder.add(fix);
    final offRoute = _recorder.isOffRoute;
    if (offRoute && !_wasOffRoute) HapticFeedback.heavyImpact();
    _wasOffRoute = offRoute;
    setState(() => _position = fix.point);
    if (_follow && _phase != _Phase.ready) _map.move(fix.point, _map.camera.zoom < 15 ? 16 : _map.camera.zoom);
  }

  void _start() {
    _recorder.start(DateTime.now());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.running;
      _follow = true;
    });
    if (_position != null) _map.move(_position!, 16);
  }

  void _togglePause() {
    final now = DateTime.now();
    setState(() {
      if (_phase == _Phase.running) {
        _recorder.pause(now);
        _phase = _Phase.paused;
      } else {
        _recorder.resume(now);
        _phase = _Phase.running;
      }
    });
  }

  Future<void> _finish() async {
    final now = DateTime.now();
    if (_phase == _Phase.running) _recorder.pause(now);
    final moving = _recorder.movingTime(now);
    if (_recorder.track.length < 2 || _recorder.distance < 50) {
      final discard = await confirm(
        context,
        title: tr('Corsa troppo corta'),
        message: tr('Servono almeno 50 metri per salvarla. Vuoi uscire senza salvare?'),
        ok: tr('Esci'),
        destructive: true,
      );
      if (discard && mounted) {
        await _stop();
        if (mounted) context.pop();
      } else if (mounted && _phase == _Phase.running) {
        _recorder.resume(DateTime.now());
      }
      return;
    }
    final save = await confirm(
      context,
      title: tr('Finire la corsa?'),
      message: tr('{distance} in {time}', {'distance': formatDistance(_recorder.distance), 'time': formatSeconds(moving.inSeconds)}),
      ok: tr('Salva'),
    );
    if (!save) {
      if (_phase == _Phase.running) _recorder.resume(DateTime.now());
      return;
    }
    await _stop();
    setState(() => _phase = _Phase.saving);
    try {
      final run = await ref.read(runningRepositoryProvider).saveRun(
            routeId: _route?.id,
            eventId: widget.eventId,
            startedAt: _recorder.startedAt!,
            completedAt: now,
            durationS: moving.inSeconds.clamp(1, 1 << 31),
            track: _recorder.track,
          );
      ref.invalidate(myRunsProvider);
      if (widget.eventId != null) ref.invalidate(eventRunsProvider(widget.eventId!));
      if (mounted) context.pushReplacement('/running/runs/${run.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.paused);
      showMessage(context, tr('Non sono riuscito a salvare: {error}. Riprova.', {'error': e.message}), error: true);
    }
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<bool> _confirmLeave() async {
    if (_phase != _Phase.running && _phase != _Phase.paused) return true;
    return confirm(context, title: tr('Abbandonare la corsa?'), message: tr('La corsa non verrà salvata.'), ok: tr('Abbandona'), destructive: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorView(message: _error!, openSettings: _openSettings);
    // la mappa parte già inquadrata sul percorso: aspetta di averlo
    if (widget.routeId != null && _route == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    final now = DateTime.now();
    final active = _phase == _Phase.running || _phase == _Phase.paused || _phase == _Phase.saving;
    final route = _route?.points ?? const <LatLng>[];
    // Pieghevole mezzo aperto e appoggiato: la mappa sopra la piega, tempo e comandi sotto.
    final fold = tabletopFold(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    return PopScope(
      canPop: !active,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          await _stop();
          if (context.mounted) context.pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              bottom: fold == null ? 0 : screenHeight - fold.top,
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: route.firstOrNull ?? _position ?? const LatLng(41.9028, 12.4964),
                  initialZoom: 15,
                  initialCameraFit: route.length > 1
                      ? CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(route),
                          padding: fold == null ? const EdgeInsets.fromLTRB(40, 120, 40, 320) : const EdgeInsets.fromLTRB(40, 80, 40, 24),
                        )
                      : null,
                  onPositionChanged: (_, hasGesture) {
                    if (hasGesture && _follow) setState(() => _follow = false);
                  },
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                ),
                children: [
                  ...baseMapLayers(),
                  PolylineLayer(polylines: [
                    if (route.length > 1) routeLine(route),
                    if (_recorder.points.length > 1) trackLine(_recorder.points),
                  ]),
                  MarkerLayer(markers: [
                    ...startEndMarkers(route),
                    if (_position != null) pointMarker(_position!, color: AppColors.blue, size: 24),
                  ]),
                  mapAttribution(top: true),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleIconButton(
                          icon: Icons.close_rounded,
                          size: 44,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _route?.name ?? tr('Corsa libera'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!_follow)
                          CircleIconButton(
                            icon: Icons.my_location_rounded,
                            size: 44,
                            tooltip: tr('Segui la posizione'),
                            onTap: () {
                              setState(() => _follow = true);
                              if (_position != null) _map.move(_position!, 16);
                            },
                          ),
                      ],
                    ),
                    if (_recorder.isOffRoute && _phase == _Phase.running) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(AppRadius.md)),
                        child: Text(
                          tr('Sei fuori percorso ({meters} m): torna sulla linea blu', {'meters': _recorder.distanceFromRoute?.round() ?? '?'}),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned.fill(
              top: fold?.bottom ?? 0,
              child: Align(
                alignment: fold == null ? Alignment.bottomCenter : Alignment.center,
                child: SafeArea(
                  top: fold == null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SoftCard(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatSeconds(_phase == _Phase.ready || _phase == _Phase.loading ? 0 : _recorder.movingTime(now).inSeconds),
                            style: Theme.of(context).textTheme.displayMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                          if (_phase == _Phase.paused)
                            Text(tr('In pausa'), style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _Live(label: tr('Distanza'), value: formatDistance(_recorder.distance)),
                              _Live(label: tr('Passo'), value: formatPace(_recorder.currentPace())),
                              _Live(label: tr('Medio'), value: formatPace(_recorder.averagePace(now))),
                            ],
                          ),
                          if (route.length > 1) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: (_recorder.distance / (_route!.distanceM == 0 ? 1 : _route!.distanceM)).clamp(0.0, 1.0),
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(6),
                              backgroundColor: AppColors.stroke,
                              color: AppColors.blue,
                            ),
                            const SizedBox(height: 4),
                            Text(tr('di {distance}', {'distance': formatDistance(_route!.distanceM)}), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                          ],
                          const SizedBox(height: 14),
                          switch (_phase) {
                            _Phase.loading => Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(tr('Cerco il segnale GPS…'), style: TextStyle(color: AppColors.inkSoft)),
                              ),
                            _Phase.ready => PrimaryButton(
                                label: _position == null ? tr('Inizia (cerco il GPS…)') : tr('Inizia'),
                                icon: Icons.play_arrow_rounded,
                                onPressed: _start,
                              ),
                            _Phase.saving => PrimaryButton(label: tr('Salvo…'), loading: true, onPressed: null),
                            _ => Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _togglePause,
                                      icon: Icon(_phase == _Phase.running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                      label: Text(_phase == _Phase.running ? tr('Pausa') : tr('Riprendi')),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: PrimaryButton(label: tr('Fine'), icon: Icons.stop_rounded, color: AppColors.danger, onPressed: _finish),
                                  ),
                                ],
                              ),
                          },
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Live extends StatelessWidget {
  const _Live({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.openSettings});

  final String message;
  final bool openSettings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Corsa')),
            Expanded(
              child: Center(
                child: EmptyState(
                  icon: Icons.location_off_rounded,
                  title: tr('Non posso registrare'),
                  message: message,
                  action: openSettings ? tr('Apri impostazioni') : null,
                  onAction: openSettings ? Geolocator.openAppSettings : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
