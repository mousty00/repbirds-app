import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Il logo di RepBirds (l'uccellino che mostra il bicipite) disegnato in
/// vettoriale, così si può animare a pezzi: il braccio che si piega, il
/// bicipite che si gonfia, l'occhio che sbatte.
///
/// Le coordinate sono quelle dell'icona dell'app (riquadro 1024 × 1024).
class RepBird extends StatelessWidget {
  const RepBird({
    super.key,
    this.size = 160,
    this.color = Colors.white,
    this.eyeColor = const Color(0xFF6366F1),
    this.flex = 0,
    this.blink = 0,
  });

  final double size;
  final Color color;

  /// Colore dell'occhio: quello dello sfondo, come nell'icona.
  final Color eyeColor;

  /// 0 = braccio come nell'icona, 1 = braccio alzato e bicipite gonfio.
  final double flex;

  /// 0 = occhio aperto, 1 = chiuso.
  final double blink;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RepBirdPainter(color: color, eyeColor: eyeColor, flex: flex, blink: blink),
    ),
  );
}

class _RepBirdPainter extends CustomPainter {
  _RepBirdPainter({required this.color, required this.eyeColor, required this.flex, required this.blink});

  final Color color;
  final Color eyeColor;
  final double flex;
  final double blink;

  static const _shoulder = Offset(400, 470);

  /// Contorno del braccio preso dall'icona (pugno, avambraccio, bicipite).
  static final _arm = () {
    const pts = [
      264, 229, 249, 240, 241, 257, 237, 287, 239, 296, 248, 310, 230, 346, 208, 409, 198, 453, 196, 470, //
      193, 478, 192, 488, 196, 505, 200, 512, 210, 522, 219, 527, 294, 548, 344, 557, 350, 561, 424, 561,
      424, 396, 372, 388, 358, 383, 342, 382, 323, 386, 309, 393, 300, 400, 299, 399,
      307, 356, 310, 327, 327, 320, 338, 308, 343, 293, 346, 276, 346, 263, 339, 247, 331, 239, 322, 234,
      287, 227, 270, 227,
    ];
    final path = Path()..moveTo(pts[0].toDouble(), pts[1].toDouble());
    for (var i = 2; i < pts.length; i += 2) {
      path.lineTo(pts[i].toDouble(), pts[i + 1].toDouble());
    }
    return path..close();
  }();

  @override
  void paint(Canvas canvas, Size size) {
    // Riquadro utile del logo nell'icona: x 190–850, y 225–785.
    const box = Rect.fromLTRB(185, 220, 855, 790);
    final scale = math.min(size.width / box.width, size.height / box.height);
    canvas
      ..translate(
        (size.width - box.width * scale) / 2 - box.left * scale,
        (size.height - box.height * scale) / 2 - box.top * scale,
      )
      ..scale(scale);

    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // zampe
    stroke.strokeWidth = 19;
    canvas
      ..drawLine(const Offset(521, 700), const Offset(521, 771), stroke)
      ..drawLine(const Offset(602, 700), const Offset(602, 771), stroke);

    // braccio (dietro al corpo): ruota attorno alla spalla e si "gonfia"
    canvas
      ..save()
      ..translate(_shoulder.dx, _shoulder.dy)
      ..rotate(-flex * 0.22)
      ..scale(1 + 0.06 * flex)
      ..translate(-_shoulder.dx, -_shoulder.dy)
      ..drawPath(_arm, fill)
      ..restore();

    // corpo
    canvas.drawCircle(const Offset(561, 501), 220, fill);

    // becco
    canvas.drawPath(
      Path()
        ..moveTo(760, 434)
        ..lineTo(846, 467)
        ..lineTo(770, 495)
        ..close(),
      fill,
    );

    // occhio (ovale che si chiude quando sbatte)
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(674, 431), width: 44, height: math.max(4, 44 * (1 - blink))),
      Paint()..color = eyeColor,
    );
  }

  @override
  bool shouldRepaint(_RepBirdPainter old) =>
      old.color != color || old.eyeColor != eyeColor || old.flex != flex || old.blink != blink;
}
