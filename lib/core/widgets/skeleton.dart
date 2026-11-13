import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Pulsa dolcemente il proprio contenuto mentre i dati caricano.
/// Rispetta "riduci animazioni" del sistema.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final _opacity = _c.drive(Tween(begin: 1.0, end: 0.45).chain(CurveTween(curve: Curves.easeInOut)));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: tr('Caricamento'),
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: still ? widget.child : FadeTransition(opacity: _opacity, child: widget.child),
        ),
      ),
    );
  }
}

/// Blocco grigio arrotondato che sostituisce testo, immagini o icone.
/// `width`/`height` null = riempie lo spazio disponibile.
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius = 8, this.color}) : circle = false;

  const Bone.circle(double size, {super.key, this.color}) : width = size, height = size, radius = 0, circle = true;

  final double? width;
  final double? height;
  final double radius;
  /// Di default [AppColors.stroke].
  final Color? color;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color ?? AppColors.stroke,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
    ),
  );
}

/// Lista di [item] ripetuti. Non scorre e si adatta sia dentro `Expanded`
/// sia dentro altre liste o sliver.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.item = const SkeletonTile(),
    this.count = 6,
    this.spacing = 10,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  final Widget item;
  final int count;
  final double spacing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Skeleton(
    child: ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: count,
      separatorBuilder: (_, _) => SizedBox(height: spacing),
      itemBuilder: (_, _) => item,
    ),
  );
}

/// Riga in card: icona/avatar, titolo + sottotitolo, valore a destra opzionale.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({
    super.key,
    this.leading = 40,
    this.circle = false,
    this.trailing = false,
    this.padding = const EdgeInsets.all(14),
    this.radius = AppRadius.md + 2,
  });

  /// Lato dell'icona/avatar; 0 = nessuno.
  final double leading;
  final bool circle;
  final bool trailing;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: padding,
      radius: radius,
      child: Row(
        children: [
          if (leading > 0) ...[
            circle ? Bone.circle(leading) : Bone(width: leading, height: leading, radius: leading * 0.36),
            const SizedBox(width: 12),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Bone(width: 140, height: 14), SizedBox(height: 8), Bone(width: 90, height: 10)],
            ),
          ),
          if (trailing) ...[const SizedBox(width: 8), const Bone(width: 28, height: 22)],
        ],
      ),
    );
  }
}

/// Stessa forma di `PostCard`.
class SkeletonPost extends StatelessWidget {
  const SkeletonPost({super.key});

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(4, 2, 4, 12),
            child: Row(
              children: [
                Bone.circle(40),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Bone(width: 100, height: 13), SizedBox(height: 6), Bone(width: 60, height: 10)],
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 3.4,
            child: Bone(height: null, radius: AppRadius.md),
          ),
          Padding(padding: EdgeInsets.fromLTRB(6, 14, 6, 0), child: Bone(width: 200, height: 12)),
          Padding(
            padding: EdgeInsets.only(top: 14),
            child: Row(children: [Bone(width: 64, height: 36, radius: 18), SizedBox(width: 8), Bone(width: 64, height: 36, radius: 18)]),
          ),
        ],
      ),
    );
  }
}

/// Stessa forma di `GroupCard`.
class SkeletonGroupCard extends StatelessWidget {
  const SkeletonGroupCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Bone(width: 110, height: 26, radius: 30), Spacer(), Bone.circle(38)]),
          SizedBox(height: 18),
          Bone(width: 160, height: 20),
          SizedBox(height: 8),
          Bone(width: 120, height: 12),
          SizedBox(height: 14),
          Row(
            children: [
              Bone.circle(32),
              SizedBox(width: 4),
              Bone.circle(32),
              SizedBox(width: 4),
              Bone.circle(32),
              Spacer(),
              Bone(width: 60, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

/// Griglia 3 colonne di `PostGrid`.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) => Skeleton(child: _bones(count));

  static Widget _bones(int count) => GridView.count(
    crossAxisCount: 3,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: [for (var i = 0; i < count; i++) const Bone(height: null, radius: AppRadius.sm + 2)],
  );
}

/// Pagina di dettaglio (scheda, gruppo, sessione): barra con "indietro",
/// tag, titolo, metriche ed elenco. La barra resta cliccabile.
class SkeletonDetail extends StatelessWidget {
  const SkeletonDetail({super.key});

  @override
  Widget build(BuildContext context) {
    Widget metric() => const Expanded(
      child: SoftCard(
        padding: EdgeInsets.all(14),
        radius: AppRadius.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Bone(width: 32, height: 22), SizedBox(height: 6), Bone(width: 54, height: 10)],
        ),
      ),
    );
    return Column(
      children: [
        const TopBar(title: ''),
        Expanded(
          child: Skeleton(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const Row(children: [Bone(width: 90, height: 26, radius: 30), SizedBox(width: 8), Bone(width: 70, height: 26, radius: 30)]),
                const SizedBox(height: 14),
                const Align(alignment: Alignment.centerLeft, child: Bone(width: 220, height: 34, radius: 10)),
                const SizedBox(height: 12),
                const Bone(),
                const SizedBox(height: 8),
                const Align(alignment: Alignment.centerLeft, child: Bone(width: 180)),
                const SizedBox(height: 20),
                Row(children: [metric(), const SizedBox(width: 10), metric(), const SizedBox(width: 10), metric()]),
                const SizedBox(height: 26),
                const Align(alignment: Alignment.centerLeft, child: Bone(width: 120, height: 18)),
                const SizedBox(height: 14),
                for (var i = 0; i < 3; i++) ...[const SkeletonTile(trailing: true), const SizedBox(height: 10)],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Stessa forma di `ProfileHeader` + bottone + griglia post.
class SkeletonProfile extends StatelessWidget {
  const SkeletonProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Center(child: Bone.circle(112)),
          const SizedBox(height: 14),
          const Center(child: Bone(width: 140, height: 22)),
          const SizedBox(height: 8),
          const Center(child: Bone(width: 90)),
          const SizedBox(height: 20),
          const Center(child: Bone(width: 160, height: 44, radius: 30)),
          const SizedBox(height: 32),
          const Align(alignment: Alignment.centerLeft, child: Bone(width: 80, height: 18)),
          const SizedBox(height: 14),
          SkeletonGrid._bones(6),
        ],
      ),
    );
  }
}
