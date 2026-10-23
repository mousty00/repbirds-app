import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mock/mock_backend.dart';
import '../theme/app_theme.dart';

/// Immagine da URL di rete, da asset (`asset:percorso`, usato dai dati mock)
/// o caricata in modalità mock (`mock-upload:id`).
class AppImage extends StatelessWidget {
  const AppImage(this.src, {super.key, this.fit = BoxFit.cover, this.width, this.height, required this.fallback});

  final String src;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget fallback;

  /// True se [src] è un'immagine che sappiamo mostrare.
  static bool supports(String? src) =>
      src != null &&
      (src.startsWith('http') || src.startsWith('asset:') || src.startsWith(MockBackend.uploadScheme));

  /// I byte dell'immagine [src] (per modificarla), o null se non si riesce a leggerla.
  static Future<Uint8List?> load(String src) async {
    try {
      if (src.startsWith('asset:')) return (await rootBundle.load(src.substring(6))).buffer.asUint8List();
      if (src.startsWith(MockBackend.uploadScheme)) return MockBackend.uploads[src.substring(MockBackend.uploadScheme.length)];
      // URL già firmato: niente token né base URL dell'API
      final res = await Dio().get<List<int>>(src, options: Options(responseType: ResponseType.bytes));
      return res.data == null ? null : Uint8List.fromList(res.data!);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget error(BuildContext _, Object _, StackTrace? _) => fallback;
    if (src.startsWith('asset:')) {
      return Image.asset(src.substring(6), fit: fit, width: width, height: height, errorBuilder: error);
    }
    if (src.startsWith(MockBackend.uploadScheme)) {
      final bytes = MockBackend.uploads[src.substring(MockBackend.uploadScheme.length)];
      if (bytes == null) return fallback;
      return Image.memory(bytes, fit: fit, width: width, height: height, errorBuilder: error);
    }
    return Image.network(
      src,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: error,
      loadingBuilder: (_, child, progress) => progress == null ? child : ColoredBox(color: AppColors.bg),
    );
  }
}
