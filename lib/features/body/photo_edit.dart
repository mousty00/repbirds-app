import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import '../../core/l10n/l10n.dart';

/// Le proporzioni del ritaglio: libero o fisso (larghezza / altezza in pixel).
enum CropAspect {
  free(null),
  story(9 / 16),
  portrait(4 / 5),
  square(1);

  const CropAspect(this.ratio);

  final double? ratio;

  String get label => switch (this) {
    CropAspect.free => tr('Libero'),
    CropAspect.story => '9:16',
    CropAspect.portrait => '4:5',
    CropAspect.square => '1:1',
  };
}

/// I filtri già pronti: combinazioni delle stesse regolazioni dei cursori.
enum PhotoFilter {
  none(),
  mono(saturation: -1, contrast: 0.15),
  warm(warmth: 0.5, saturation: 0.1),
  cool(warmth: -0.5),
  vivid(saturation: 0.45, contrast: 0.25),
  faded(brightness: 0.06, contrast: -0.3, saturation: -0.25);

  const PhotoFilter({this.brightness = 0, this.contrast = 0, this.saturation = 0, this.warmth = 0});

  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  String get label => switch (this) {
    PhotoFilter.none => tr('Originale'),
    PhotoFilter.mono => tr('B/N'),
    PhotoFilter.warm => tr('Caldo'),
    PhotoFilter.cool => tr('Freddo'),
    PhotoFilter.vivid => tr('Vivido'),
    PhotoFilter.faded => tr('Sbiadito'),
  };
}

/// Le modifiche a una foto prima di pubblicarla. Non toccano l'originale:
/// [renderEdited] le applica tutte insieme quando si conferma.
///
/// L'orientamento è "ruota di [quarterTurns] quarti in senso orario, poi
/// specchia se [flipped]"; [crop] è normalizzato (0..1) sulla foto già
/// orientata, e il testo è posizionato (centro, 0..1) sul ritaglio.
@immutable
class PhotoEdits {
  const PhotoEdits({
    this.quarterTurns = 0,
    this.flipped = false,
    this.crop = full,
    this.aspect = CropAspect.free,
    this.filter = PhotoFilter.none,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
    this.text = '',
    this.textColor = const Color(0xFFFFFFFF),
    this.textBackground = false,
    this.textPosition = const Offset(0.5, 0.5),
    this.textSize = 0.08,
  });

  static const full = Rect.fromLTRB(0, 0, 1, 1);

  final int quarterTurns;
  final bool flipped;
  final Rect crop;
  final CropAspect aspect;
  final PhotoFilter filter;

  /// Regolazioni, da -1 a 1 (0 = come scattata).
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  final String text;
  final Color textColor;
  final bool textBackground;
  final Offset textPosition;

  /// Altezza del testo rispetto alla larghezza del ritaglio.
  final double textSize;

  bool get isIdentity => this == const PhotoEdits();

  PhotoEdits copyWith({
    int? quarterTurns,
    bool? flipped,
    Rect? crop,
    CropAspect? aspect,
    PhotoFilter? filter,
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    String? text,
    Color? textColor,
    bool? textBackground,
    Offset? textPosition,
    double? textSize,
  }) => PhotoEdits(
    quarterTurns: quarterTurns ?? this.quarterTurns,
    flipped: flipped ?? this.flipped,
    crop: crop ?? this.crop,
    aspect: aspect ?? this.aspect,
    filter: filter ?? this.filter,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    warmth: warmth ?? this.warmth,
    text: text ?? this.text,
    textColor: textColor ?? this.textColor,
    textBackground: textBackground ?? this.textBackground,
    textPosition: textPosition ?? this.textPosition,
    textSize: textSize ?? this.textSize,
  );

  /// Dimensioni della foto [source] dopo la rotazione.
  Size oriented(Size source) => quarterTurns.isOdd ? source.flipped : source;

  /// Il ritaglio in pixel, sulla foto orientata.
  Rect cropIn(Size source) {
    final o = oriented(source);
    return Rect.fromLTRB(crop.left * o.width, crop.top * o.height, crop.right * o.width, crop.bottom * o.height);
  }

  /// Le proporzioni fisse in coordinate normalizzate (null se libere).
  double? normalizedAspect(Size source) {
    final r = aspect.ratio;
    if (r == null) return null;
    final o = oriented(source);
    return r * o.height / o.width;
  }

  /// Un quarto di giro in senso orario di quello che si vede, ritaglio compreso.
  PhotoEdits rotated(Size source) {
    // specchiare e poi ruotare in orario equivale a ruotare in antiorario e poi specchiare
    final next = copyWith(
      quarterTurns: (quarterTurns + (flipped ? 3 : 1)) % 4,
      crop: Rect.fromLTRB(1 - crop.bottom, crop.left, 1 - crop.top, crop.right),
    );
    // con proporzioni fisse il ritaglio girato non le rispetta più: si ricentra
    return aspect.ratio == null ? next : next.withAspect(aspect, source);
  }

  /// Specchiata in orizzontale, ritaglio compreso.
  PhotoEdits mirrored() =>
      copyWith(flipped: !flipped, crop: Rect.fromLTRB(1 - crop.right, crop.top, 1 - crop.left, crop.bottom));

  /// Il ritaglio più grande con le proporzioni [a], al centro della foto.
  PhotoEdits withAspect(CropAspect a, Size source) {
    final withA = copyWith(aspect: a);
    final n = withA.normalizedAspect(source);
    if (n == null) return withA;
    final (w, h) = n <= 1 ? (n, 1.0) : (1.0, 1 / n);
    return withA.copyWith(
      crop: Rect.fromCenter(center: const Offset(0.5, 0.5), width: w, height: h),
    );
  }

  /// La matrice di colore di filtro e regolazioni insieme, per [ColorFilter.matrix].
  List<double> get colorMatrix {
    var m = _identity;
    for (final (b, c, s, w) in [
      (filter.brightness, filter.contrast, filter.saturation, filter.warmth),
      (brightness, contrast, saturation, warmth),
    ]) {
      m = _then(m, _warmth(w));
      m = _then(m, _saturation(s));
      m = _then(m, _contrast(c));
      m = _then(m, _brightness(b));
    }
    return m;
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoEdits &&
      other.quarterTurns == quarterTurns &&
      other.flipped == flipped &&
      other.crop == crop &&
      other.aspect == aspect &&
      other.filter == filter &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.warmth == warmth &&
      other.text == text &&
      other.textColor == textColor &&
      other.textBackground == textBackground &&
      other.textPosition == textPosition &&
      other.textSize == textSize;

  @override
  int get hashCode => Object.hash(
    quarterTurns,
    flipped,
    crop,
    aspect,
    filter,
    brightness,
    contrast,
    saturation,
    warmth,
    text,
    textColor,
    textBackground,
    textPosition,
    textSize,
  );
}

/// Sposta l'angolo [corner] del ritaglio [r] (0 in alto a sinistra, poi in
/// senso orario) in [to], tenendo fermo quello opposto, dentro la foto e non
/// più piccolo di [min]. Con [aspect] (normalizzato) le proporzioni restano quelle.
Rect resizeCrop(Rect r, int corner, Offset to, {double? aspect, double min = 0.1}) {
  final anchor = [r.bottomRight, r.bottomLeft, r.topLeft, r.topRight][corner];
  final sx = corner == 0 || corner == 3 ? -1.0 : 1.0;
  final sy = corner < 2 ? -1.0 : 1.0;
  final maxW = sx > 0 ? 1 - anchor.dx : anchor.dx;
  final maxH = sy > 0 ? 1 - anchor.dy : anchor.dy;
  var w = ((to.dx - anchor.dx) * sx).clamp(math.min(min, maxW), maxW);
  var h = ((to.dy - anchor.dy) * sy).clamp(math.min(min, maxH), maxH);
  if (aspect != null) {
    // segue il lato tirato di più, poi rientra nella foto
    if (w / aspect > h) {
      h = w / aspect;
    } else {
      w = h * aspect;
    }
    if (w > maxW) {
      w = maxW;
      h = w / aspect;
    }
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }
  }
  return Rect.fromPoints(anchor, anchor + Offset(w * sx, h * sy));
}

/// Il ritaglio [r] spostato di [delta], senza uscire dalla foto.
Rect moveCrop(Rect r, Offset delta) => r.shift(
  Offset((r.left + delta.dx).clamp(0.0, 1 - r.width) - r.left, (r.top + delta.dy).clamp(0.0, 1 - r.height) - r.top),
);

/// Disegna [image] con le modifiche [e] riempiendo [out], che ha le
/// proporzioni del ritaglio. Lo usano sia l'anteprima sia [renderEdited], così
/// quello che si pubblica è quello che si è visto.
void paintEdited(Canvas canvas, Size out, ui.Image image, PhotoEdits e, {bool text = true}) {
  final source = Size(image.width.toDouble(), image.height.toDouble());
  final o = e.oriented(source);
  final crop = e.cropIn(source);
  canvas.save();
  canvas.clipRect(Offset.zero & out);
  canvas.scale(out.width / crop.width, out.height / crop.height);
  canvas.translate(-crop.left, -crop.top);
  if (e.flipped) {
    canvas.translate(o.width, 0);
    canvas.scale(-1, 1);
  }
  switch (e.quarterTurns) {
    case 1:
      canvas.translate(o.width, 0);
    case 2:
      canvas.translate(o.width, o.height);
    case 3:
      canvas.translate(0, o.height);
  }
  canvas.rotate(e.quarterTurns * math.pi / 2);
  canvas.drawImage(
    image,
    Offset.zero,
    Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = ColorFilter.matrix(e.colorMatrix),
  );
  canvas.restore();
  if (text && e.text.trim().isNotEmpty) paintCaption(canvas, out, e);
}

/// Il testo delle modifiche [e] sulla foto di dimensioni [out].
void paintCaption(Canvas canvas, Size out, PhotoEdits e) {
  final fontSize = e.textSize * out.width;
  final onBackground = e.textColor.computeLuminance() > 0.5 ? const Color(0xFF111322) : const Color(0xFFFFFFFF);
  final painter = TextPainter(
    text: TextSpan(
      text: e.text.trim(),
      style: TextStyle(
        color: e.textBackground ? onBackground : e.textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.15,
        shadows: e.textBackground ? null : [Shadow(color: const Color(0x99000000), blurRadius: fontSize * 0.15)],
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: out.width * 0.9);
  final center = Offset(e.textPosition.dx * out.width, e.textPosition.dy * out.height);
  final topLeft = center - Offset(painter.width / 2, painter.height / 2);
  if (e.textBackground) {
    final pad = fontSize * 0.35;
    canvas.drawRRect(
      RRect.fromRectAndRadius((topLeft & painter.size).inflate(pad), Radius.circular(pad)),
      Paint()..color = e.textColor,
    );
  }
  painter.paint(canvas, topLeft);
  painter.dispose();
}

/// La foto modificata come JPEG, al massimo [maxSide] pixel sul lato lungo.
Future<Uint8List> renderEdited(ui.Image image, PhotoEdits e, {int maxSide = 2160}) async {
  final crop = e.cropIn(Size(image.width.toDouble(), image.height.toDouble()));
  final scale = math.min(1.0, maxSide / math.max(crop.width, crop.height));
  final w = math.max(1, (crop.width * scale).round());
  final h = math.max(1, (crop.height * scale).round());
  final recorder = ui.PictureRecorder();
  paintEdited(Canvas(recorder), Size(w.toDouble(), h.toDouble()), image, e);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(w, h);
  picture.dispose();
  final rgba = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  rendered.dispose();
  return compute(_encodeJpg, (rgba!.buffer.asUint8List(), w, h));
}

Uint8List _encodeJpg((Uint8List, int, int) raw) {
  final (bytes, w, h) = raw;
  final pixels = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: bytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(pixels, quality: 88);
}

// ---------- matrici di colore 4x5 ----------

const _identity = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Applica [first], poi [second].
List<double> _then(List<double> first, List<double> second) => [
  for (var i = 0; i < 4; i++)
    for (var j = 0; j < 5; j++)
      [for (var k = 0; k < 4; k++) second[i * 5 + k] * first[k * 5 + j]].fold<double>(0, (a, b) => a + b) +
          (j == 4 ? second[i * 5 + 4] : 0),
];

List<double> _brightness(double v) {
  final o = v * 0.4 * 255;
  return [1, 0, 0, 0, o, 0, 1, 0, 0, o, 0, 0, 1, 0, o, 0, 0, 0, 1, 0];
}

List<double> _contrast(double v) {
  final c = 1 + v * 0.6;
  final o = 128 * (1 - c);
  return [c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0];
}

List<double> _saturation(double v) {
  final s = 1 + v;
  const r = 0.2126, g = 0.7152, b = 0.0722;
  return [
    r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

List<double> _warmth(double v) {
  final o = v * 30;
  return [1, 0, 0, 0, o, 0, 1, 0, 0, o * 0.3, 0, 0, 1, 0, -o, 0, 0, 0, 1, 0];
}
