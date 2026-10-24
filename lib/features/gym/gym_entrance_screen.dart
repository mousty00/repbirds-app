import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/gym/card_code.dart';
import '../../core/gym/nfc_card.dart';
import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../models/gym.dart';
import 'gym_widgets.dart';

/// Ingresso, per il telefono o tablet della reception: legge le tessere con NFC
/// (Android: basta avvicinare il telefono dell'iscritto) e con la fotocamera (il QR
/// della tessera, su qualunque telefono). Ogni lettura va al server, che risponde
/// chi è e se può entrare; il risultato resta a schermo qualche secondo.
class GymEntranceScreen extends ConsumerStatefulWidget {
  const GymEntranceScreen({super.key});

  @override
  ConsumerState<GymEntranceScreen> createState() => _GymEntranceScreenState();
}

class _GymEntranceScreenState extends ConsumerState<GymEntranceScreen> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  StreamSubscription<String>? _nfc;
  bool _nfcOn = false;
  bool _camera = true;
  bool _checking = false;
  CheckIn? _result;
  String? _error;
  String? _lastCode;
  DateTime _lastAt = DateTime(0);
  Timer? _clear;

  @override
  void initState() {
    super.initState();
    _startNfc();
  }

  Future<void> _startNfc() async {
    if (!await NfcCard.available()) return;
    _nfc = NfcCard.codes.listen((code) => _check(code, 'NFC'));
    final on = await NfcCard.startReading();
    if (mounted) setState(() => _nfcOn = on);
  }

  @override
  void dispose() {
    _clear?.cancel();
    _nfc?.cancel();
    NfcCard.stopReading();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _check(String code, String method) async {
    final now = DateTime.now();
    // lo stesso codice letto due volte di fila (il telefono resta vicino, il QR resta inquadrato)
    if (_checking || (code == _lastCode && now.difference(_lastAt) < const Duration(seconds: 5))) return;
    _lastCode = code;
    _lastAt = now;
    if (!CardCode.looksValid(code)) {
      _show(null, tr('Questo non è il QR di una tessera RepBirds'));
      return;
    }
    setState(() => _checking = true);
    try {
      final result = await ref.read(gymRepositoryProvider).checkIn(code, method: method);
      HapticFeedback.mediumImpact();
      ref.invalidate(gymCheckInsProvider);
      ref.invalidate(gymProvider);
      _show(result, null);
    } on ApiException catch (e) {
      _show(null, e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _show(CheckIn? result, String? error) {
    if (!mounted) return;
    setState(() {
      _result = result;
      _error = error;
    });
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _result = _error = null);
    });
  }

  Future<void> _typeCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Codice della tessera')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'RBG1.…'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annulla'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(tr('Verifica'))),
        ],
      ),
    );
    controller.dispose();
    if (code != null && code.trim().isNotEmpty) {
      _lastCode = null;
      await _check(code.trim(), 'QR');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              title: tr('Ingresso'),
              actions: [
                CircleIconButton(
                  icon: _camera ? Icons.videocam_off_rounded : Icons.qr_code_scanner_rounded,
                  size: 44,
                  tooltip: _camera ? tr('Spegni fotocamera') : tr('Accendi fotocamera'),
                  onTap: () => setState(() => _camera = !_camera),
                ),
                CircleIconButton(icon: Icons.keyboard_rounded, size: 44, tooltip: tr('Scrivi il codice'), onTap: _typeCode),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Tag(
                    _nfcOn ? tr('NFC attivo: avvicina il telefono') : tr('NFC non disponibile su questo dispositivo'),
                    color: _nfcOn ? AppColors.mint : AppColors.muted,
                    icon: Icons.contactless_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_camera)
                        MobileScanner(
                          controller: _scanner,
                          onDetect: (capture) {
                            final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                            if (value != null) _check(value, 'QR');
                          },
                          errorBuilder: (context, error) => _Hint(
                            icon: Icons.no_photography_rounded,
                            text: tr('Fotocamera non disponibile. Usa l\'NFC o scrivi il codice.'),
                          ),
                        )
                      else
                        _Hint(
                          icon: Icons.contactless_rounded,
                          text: tr('Fai avvicinare il telefono dell\'iscritto o mostra il QR della tessera.'),
                        ),
                      if (_checking)
                        const ColoredBox(
                          color: Colors.black38,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_result != null || _error != null) _ResultOverlay(result: _result, error: _error),
                    ],
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

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.card,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    ),
  );
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({this.result, this.error});

  final CheckIn? result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ok = result?.accepted == true;
    final color = ok ? AppColors.mint : AppColors.danger;
    final r = result;
    return ColoredBox(
      color: color,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.block_rounded, color: Colors.white, size: 96),
              const SizedBox(height: 12),
              if (r?.member != null) ...[
                UserAvatar(username: r!.member!.username, imageUrl: r.member!.image, size: 72),
                const SizedBox(height: 10),
                Text(
                  r.memberName ?? '@${r.member!.username}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                error ?? (ok ? tr('Benvenuto! Può entrare') : refusalText(r!)),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if (r?.planName != null)
                Text(
                  '${r!.planName} · ${tr('fino al {date}', {'date': formatDate(r.endsOn)})}',
                  style: const TextStyle(color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
