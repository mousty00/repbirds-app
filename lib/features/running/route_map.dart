import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';

/// Strato delle tile con attribuzione, comune a tutte le mappe della corsa.
List<Widget> baseMapLayers() => [
      TileLayer(
        urlTemplate: Env.mapTileUrl,
        userAgentPackageName: 'com.mousty.repbirds',
        maxZoom: 19,
      ),
    ];

/// Attribuzione dei dati della mappa, obbligatoria per OpenStreetMap: piccola, in basso a destra.
/// Sulle mappe a tutto schermo va in alto ([top]), sotto la barra, perché in basso c'è il pannello.
Widget mapAttribution({bool top = false}) => Align(
      alignment: top ? Alignment.topRight : Alignment.bottomRight,
      child: Container(
        margin: top ? const EdgeInsets.fromLTRB(4, 110, 12, 4) : const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(6)),
        child: const Text(Env.mapAttribution, style: TextStyle(fontSize: 9, color: LightColors.inkSoft)),
      ),
    );

/// Il percorso da seguire.
Polyline routeLine(List<LatLng> points) => Polyline(
      points: points,
      strokeWidth: 5,
      color: AppColors.blue,
      borderStrokeWidth: 2,
      borderColor: Colors.white,
    );

/// La traccia registrata.
Polyline trackLine(List<LatLng> points) => Polyline(points: points, strokeWidth: 5, color: AppColors.pink);

Marker pointMarker(LatLng point, {required Color color, IconData? icon, double size = 22}) => Marker(
      point: point,
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
        ),
        child: icon == null ? null : Icon(icon, size: size * 0.55, color: Colors.white),
      ),
    );

/// Partenza (verde) e arrivo (scuro) di una linea.
List<Marker> startEndMarkers(List<LatLng> points) => [
      if (points.length > 1) pointMarker(points.last, color: LightColors.ink, icon: Icons.flag_rounded),
      if (points.isNotEmpty) pointMarker(points.first, color: AppColors.mint, icon: Icons.play_arrow_rounded),
    ];

/// Mappa che mostra un percorso (e/o una traccia) inquadrandolo tutto.
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    this.route = const [],
    this.track = const [],
    this.extraMarkers = const [],
    this.interactive = true,
    this.height,
  });

  final List<LatLng> route;
  final List<LatLng> track;
  final List<Marker> extraMarkers;
  final bool interactive;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final all = [...route, ...track];
    final map = FlutterMap(
      options: MapOptions(
        initialCenter: all.isEmpty ? const LatLng(41.9028, 12.4964) : all.first,
        initialZoom: all.isEmpty ? 5 : 14,
        initialCameraFit: all.length < 2
            ? null
            : CameraFit.bounds(bounds: LatLngBounds.fromPoints(all), padding: const EdgeInsets.all(36)),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        ...baseMapLayers(),
        PolylineLayer(polylines: [
          if (route.length > 1) routeLine(route),
          if (track.length > 1) trackLine(track),
        ]),
        MarkerLayer(markers: [...startEndMarkers(route.isNotEmpty ? route : track), ...extraMarkers]),
        mapAttribution(),
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: height == null ? map : SizedBox(height: height, child: map),
    );
  }
}
