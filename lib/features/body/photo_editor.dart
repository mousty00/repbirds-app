import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import 'photo_edit.dart';

/// Apre l'editor sulla foto [bytes]: ritaglio, rotazione, specchio, filtri,
/// regolazioni e testo, come nelle storie. La foto modificata in JPEG, o null
/// se si chiude senza confermare.
Future<Uint8List?> showPhotoEditor(BuildContext context, Uint8List bytes, {String? done}) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<Uint8List>(
        fullscreenDialog: true,
        builder: (_) => PhotoEditorScreen(bytes: bytes, done: done),
      ),
    );

enum _Tool { crop, adjust, filters, text }

enum _Adjust { brightness, contrast, saturation, warmth }

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.bytes, this.done});

  final Uint8List bytes;

  /// Testo del pulsante che conferma (di default "Fatto").
  final String? done;

  static List<Color> get textColors => [
    const Color(0xFFFFFFFF),
    const Color(0xFF111322),
    AppColors.brand,
    AppColors.pink,
    AppColors.amber,
    AppColors.mint,
  ];

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  ui.Image? _image;
  Object? _error;
  PhotoEdits _edits = const PhotoEdits();
  _Tool _tool = _Tool.crop;
  _Adjust _adjust = _Adjust.brightness;
  bool _saving = false;
  late final _text = TextEditingController();

  Size get _source => Size(_image!.width.toDouble(), _image!.height.toDouble());

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) return frame.image.dispose();
      setState(() => _image = frame.image);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    _text.dispose();
    super.dispose();
  }

  void _set(PhotoEdits e) => setState(() => _edits = e);

  Future<void> _done() async {
    setState(() => _saving = true);
    try {
      final out = await renderEdited(_image!, _edits);
      if (mounted) Navigator.pop(context, out);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, tr('Non sono riuscito a salvare le modifiche. Riprova.'), error: true);
      }
    }
  }

  void _reset() {
    _text.clear();
    _set(const PhotoEdits());
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(colorScheme: ColorScheme.dark(primary: AppColors.brand)),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            tooltip: tr('Chiudi'),
            icon: const Icon(Icons.close_rounded),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
          actions: [
            if (image != null && !_edits.isIdentity)
              TextButton(onPressed: _saving ? null : _reset, child: Text(tr('Ripristina'))),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: image == null || _saving ? null : _done,
                child: _saving
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.done ?? tr('Fatto')),
              ),
            ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Text(tr('Non riesco ad aprire questa foto.'), style: const TextStyle(color: Colors.white70)),
              )
            : image == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _tool == _Tool.crop
                            ? _CropView(
                                image: image,
                                edits: _edits,
                                onCrop: (r) => _set(_edits.copyWith(crop: r)),
                              )
                            : _Preview(
                                image: image,
                                edits: _edits,
                                onMoveText: (p) => _set(_edits.copyWith(textPosition: p)),
                              ),
                      ),
                    ),
                    SizedBox(height: 132, child: _panel()),
                    _toolBar(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _toolBar() {
    Widget tab(_Tool t, IconData icon, String label) {
      final on = _tool == t;
      final color = on ? Colors.white : Colors.white54;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tool = t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: on ? FontWeight.w700 : null),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(_Tool.crop, Icons.crop_rotate_rounded, tr('Ritaglia')),
        tab(_Tool.adjust, Icons.tune_rounded, tr('Regola')),
        tab(_Tool.filters, Icons.auto_awesome_rounded, tr('Filtri')),
        tab(_Tool.text, Icons.text_fields_rounded, tr('Testo')),
      ],
    );
  }

  Widget _panel() => switch (_tool) {
    _Tool.crop => _cropPanel(),
    _Tool.adjust => _adjustPanel(),
    _Tool.filters => _filtersPanel(),
    _Tool.text => _textPanel(),
  };

  Widget _cropPanel() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: tr('Ruota'),
            icon: const Icon(Icons.rotate_90_degrees_cw_rounded),
            onPressed: () => _set(_edits.rotated(_source)),
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: tr('Specchia'),
            icon: const Icon(Icons.flip_rounded),
            onPressed: () => _set(_edits.mirrored()),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final a in CropAspect.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(a.label),
                  selected: _edits.aspect == a,
                  onSelected: (_) => _set(_edits.withAspect(a, _source)),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _adjustPanel() {
    final (value, apply) = switch (_adjust) {
      _Adjust.brightness => (_edits.brightness, (double v) => _edits.copyWith(brightness: v)),
      _Adjust.contrast => (_edits.contrast, (double v) => _edits.copyWith(contrast: v)),
      _Adjust.saturation => (_edits.saturation, (double v) => _edits.copyWith(saturation: v)),
      _Adjust.warmth => (_edits.warmth, (double v) => _edits.copyWith(warmth: v)),
    };
    String label(_Adjust a) => switch (a) {
      _Adjust.brightness => tr('Luminosità'),
      _Adjust.contrast => tr('Contrasto'),
      _Adjust.saturation => tr('Saturazione'),
      _Adjust.warmth => tr('Calore'),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final a in _Adjust.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label(a)),
                    selected: _adjust == a,
                    onSelected: (_) => setState(() => _adjust = a),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Slider(value: value, min: -1, max: 1, label: label(_adjust), onChanged: (v) => _set(apply(v))),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${(value * 100).round()}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filtersPanel() => ListView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    children: [
      for (final f in PhotoFilter.values)
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: GestureDetector(
            onTap: () => _set(_edits.copyWith(filter: f)),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _edits.filter == f ? Colors.white : Colors.transparent, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: _EditPainter(
                      _image!,
                      PhotoEdits(filter: f).withAspect(CropAspect.portrait, _source),
                      text: false,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(f.label, style: const TextStyle(fontSize: 12, color: Colors.white)),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _textPanel() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextField(
          controller: _text,
          maxLength: 80,
          decoration: InputDecoration(
            hintText: tr('Scrivi qualcosa… e trascinalo sulla foto'),
            counterText: '',
            isDense: true,
            suffixIcon: IconButton(
              tooltip: _edits.textBackground ? tr('Senza sfondo') : tr('Con sfondo'),
              icon: Icon(_edits.textBackground ? Icons.format_color_fill_rounded : Icons.format_color_text_rounded),
              onPressed: () => _set(_edits.copyWith(textBackground: !_edits.textBackground)),
            ),
          ),
          onChanged: (v) => _set(_edits.copyWith(text: v)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final c in PhotoEditorScreen.textColors)
              GestureDetector(
                onTap: () => _set(_edits.copyWith(textColor: c)),
                child: Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: _edits.textColor == c ? Colors.white : Colors.white24, width: 2),
                  ),
                ),
              ),
            Expanded(
              child: Slider(
                value: _edits.textSize,
                min: 0.04,
                max: 0.16,
                onChanged: (v) => _set(_edits.copyWith(textSize: v)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Dipinge la foto modificata nello spazio che le si dà (con le proporzioni del ritaglio).
class _EditPainter extends CustomPainter {
  _EditPainter(this.image, this.edits, {this.text = true});

  final ui.Image image;
  final PhotoEdits edits;
  final bool text;

  @override
  void paint(Canvas canvas, Size size) => paintEdited(canvas, size, image, edits, text: text);

  @override
  bool shouldRepaint(_EditPainter old) => old.image != image || old.edits != edits || old.text != text;
}

/// L'anteprima del risultato; il testo si sposta trascinandolo.
class _Preview extends StatelessWidget {
  const _Preview({required this.image, required this.edits, required this.onMoveText});

  final ui.Image image;
  final PhotoEdits edits;
  final ValueChanged<Offset> onMoveText;

  @override
  Widget build(BuildContext context) {
    final crop = edits.cropIn(Size(image.width.toDouble(), image.height.toDouble()));
    return Center(
      child: AspectRatio(
        aspectRatio: crop.width / crop.height,
        child: LayoutBuilder(
          builder: (_, box) => GestureDetector(
            onPanUpdate: edits.text.trim().isEmpty
                ? null
                : (d) => onMoveText(
                    Offset(
                      (edits.textPosition.dx + d.delta.dx / box.maxWidth).clamp(0.0, 1.0),
                      (edits.textPosition.dy + d.delta.dy / box.maxHeight).clamp(0.0, 1.0),
                    ),
                  ),
            child: CustomPaint(size: box.biggest, painter: _EditPainter(image, edits)),
          ),
        ),
      ),
    );
  }
}

/// Tutta la foto orientata, con il riquadro del ritaglio: si trascina dentro
/// per spostarlo e dagli angoli per ridimensionarlo.
class _CropView extends StatefulWidget {
  const _CropView({required this.image, required this.edits, required this.onCrop});

  final ui.Image image;
  final PhotoEdits edits;
  final ValueChanged<Rect> onCrop;

  @override
  State<_CropView> createState() => _CropViewState();
}

class _CropViewState extends State<_CropView> {
  static const _handle = 32.0;

  /// L'angolo che si sta trascinando (null = si sposta tutto il riquadro).
  int? _corner;
  bool _dragging = false;
  Offset _point = Offset.zero;

  Size get _source => Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  @override
  Widget build(BuildContext context) {
    final o = widget.edits.oriented(_source);
    final whole = widget.edits.copyWith(crop: PhotoEdits.full, text: '');
    return Center(
      child: AspectRatio(
        aspectRatio: o.width / o.height,
        child: LayoutBuilder(
          builder: (_, box) {
            final size = box.biggest;
            final crop = widget.edits.crop;
            Offset toNorm(Offset p) => Offset(p.dx / size.width, p.dy / size.height);
            return GestureDetector(
              onPanStart: (d) {
                final corners = [crop.topLeft, crop.topRight, crop.bottomRight, crop.bottomLeft];
                _corner = null;
                for (var i = 0; i < 4; i++) {
                  final c = Offset(corners[i].dx * size.width, corners[i].dy * size.height);
                  if ((c - d.localPosition).distance <= _handle) {
                    _corner = i;
                    _point = corners[i];
                  }
                }
                final inside = Rect.fromLTRB(
                  crop.left * size.width,
                  crop.top * size.height,
                  crop.right * size.width,
                  crop.bottom * size.height,
                ).contains(d.localPosition);
                _dragging = _corner != null || inside;
              },
              onPanUpdate: (d) {
                if (!_dragging) return;
                final delta = toNorm(d.delta);
                if (_corner == null) {
                  widget.onCrop(moveCrop(crop, delta));
                } else {
                  _point += delta;
                  widget.onCrop(resizeCrop(crop, _corner!, _point, aspect: widget.edits.normalizedAspect(_source)));
                }
              },
              onPanEnd: (_) => _dragging = false,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _EditPainter(widget.image, whole, text: false)),
                  CustomPaint(painter: _CropFramePainter(crop)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CropFramePainter extends CustomPainter {
  _CropFramePainter(this.crop);

  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRect(r)),
      Paint()..color = Colors.black54,
    );
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke;
    canvas.drawRect(r, line..strokeWidth = 1.5);
    // griglia dei terzi
    final thin = Paint()
      ..color = Colors.white38
      ..strokeWidth = 0.7;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(r.left + r.width * i / 3, r.top), Offset(r.left + r.width * i / 3, r.bottom), thin);
      canvas.drawLine(Offset(r.left, r.top + r.height * i / 3), Offset(r.right, r.top + r.height * i / 3), thin);
    }
    final corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 18.0;
    for (final (p, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomRight, -1.0, -1.0),
      (r.bottomLeft, 1.0, -1.0),
    ]) {
      canvas.drawLine(p, p + Offset(l * dx, 0), corner);
      canvas.drawLine(p, p + Offset(0, l * dy), corner);
    }
  }

  @override
  bool shouldRepaint(_CropFramePainter old) => old.crop != crop;
}
