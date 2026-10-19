import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/l10n/l10n.dart';
import '../../core/sound/sounds.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/body_photo_repository.dart';
import '../../data/user_repository.dart';
import '../../models/social.dart';
import '../auth/session.dart';
import 'themes.dart';
import '../body/body_calendar.dart';
import '../friends/user_profile_screen.dart';
import '../share/share_actions.dart';
import '../share/share_links.dart';
import '../shell/app_shell.dart';
import '../../core/widgets/skeleton.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploading = false;

  Future<void> _changeAvatar() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(userRepositoryProvider).updateProfileImage(await file.readAsBytes(), file.name);
      await ref.read(sessionProvider.notifier).reloadProfile();
      if (mounted) showMessage(context, tr('Foto profilo aggiornata'));
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _logout() async {
    if (!await confirm(context, title: tr('Vuoi uscire?'), ok: tr('Esci dall\'account'))) return;
    await ref.read(sessionProvider.notifier).logout();
  }

  Future<void> _deleteAccount() async {
    final ok = await confirm(
      context,
      title: tr('Eliminare l\'account?'),
      message: tr('Schede, post e storico verranno cancellati definitivamente.'),
      ok: tr('Elimina account'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(userRepositoryProvider).deleteMe();
      await ref.read(sessionProvider.notifier).forget();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  /// Account e impostazioni: tutto quello che non serve tutti i giorni.
  void _showSettings() {
    final me = ref.read(currentUserProvider);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        void go(VoidCallback action) {
          Navigator.pop(ctx);
          action();
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('Account'), style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    children: [
                      _InfoRow(label: tr('Email'), value: me.email ?? '—'),
                      if (me.birthDate != null) _InfoRow(label: tr('Data di nascita'), value: formatDate(me.birthDate)),
                      if (me.createdAt != null) _InfoRow(label: tr('Iscritto da'), value: formatMonthYear(me.createdAt)),
                      if (Env.serverLabel != null) _InfoRow(label: tr('Server'), value: Env.serverLabel!),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      _MenuRow(
                        icon: Icons.edit_rounded,
                        color: AppColors.blue,
                        label: tr('Modifica profilo'),
                        onTap: () => go(() => context.push('/profile/edit')),
                      ),
                      _MenuRow(
                        icon: Icons.language_rounded,
                        color: AppColors.lilac,
                        label: tr('Lingua'),
                        onTap: () => go(_chooseLanguage),
                      ),
                      _MenuRow(
                        icon: Icons.dark_mode_rounded,
                        color: AppColors.brand,
                        label: tr('Tema'),
                        onTap: () => go(() => showThemePicker(context, ref)),
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final on = ref.watch(soundProvider);
                          return Column(
                            children: [
                              SwitchListTile(
                                value: on,
                                onChanged: ref.read(soundProvider.notifier).set,
                                secondary: IconChip(
                                  icon: on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                  color: AppColors.amber,
                                  size: 36,
                                ),
                                title: Text(tr('Suoni'), style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              const Divider(indent: 70, endIndent: 16),
                            ],
                          );
                        },
                      ),
                      _MenuRow(
                        icon: Icons.bug_report_outlined,
                        color: AppColors.danger,
                        label: tr('Segnala un problema'),
                        onTap: () => go(() => context.push('/support/report')),
                      ),
                      _MenuRow(
                        icon: Icons.privacy_tip_outlined,
                        color: AppColors.blue,
                        label: tr('Privacy policy'),
                        onTap: () => go(() => launchUrl(Uri.parse(ShareLinks.privacy))),
                      ),
                      _MenuRow(
                        icon: Icons.description_outlined,
                        color: AppColors.inkSoft,
                        label: tr('Termini di servizio'),
                        onTap: () => go(() => launchUrl(Uri.parse(ShareLinks.terms))),
                      ),
                      _MenuRow(
                        icon: Icons.logout_rounded,
                        color: AppColors.ink,
                        label: tr('Esci dall\'account'),
                        onTap: () => go(_logout),
                        last: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => go(_deleteAccount),
                  child: Text(tr('Elimina account'), style: const TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _chooseLanguage() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (ctx) {
        final current = ref.read(languageProvider);
        void pick(String? lang) {
          Navigator.pop(ctx);
          ref.read(languageProvider.notifier).set(lang);
        }

        return SafeArea(
          child: RadioGroup<String?>(
            groupValue: current,
            onChanged: pick,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String?>(value: null, title: Text(tr('Lingua del dispositivo'))),
                for (final e in L10n.languages.entries) RadioListTile<String?>(value: e.key, title: Text(e.value)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final posts = ref.watch(userPostsProvider(me.username));
    final history = ref.watch(historyProvider).value ?? const [];
    final friends = ref.watch(friendsProvider).value ?? const <Friendship>[];
    final total = history.fold<Duration>(Duration.zero, (a, h) => a + (h.duration ?? Duration.zero));
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(historyProvider);
              ref.invalidate(friendsProvider);
              ref.invalidate(userPostsProvider(me.username));
              ref.invalidate(bodyPhotosProvider);
              await ref.read(sessionProvider.notifier).reloadProfile();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, navBarClearance),
              children: [
                Row(
                  children: [
                    Expanded(child: Text('@${me.username}', style: t.titleLarge, overflow: TextOverflow.ellipsis)),
                    CircleIconButton(
                      icon: Icons.ios_share_rounded,
                      tooltip: tr('Condividi profilo'),
                      onTap: () => shareProfile(context, me,
                          mine: true, sessions: history.length, trained: total, friends: friends.length),
                    ),
                    const SizedBox(width: 10),
                    CircleIconButton(icon: Icons.settings_outlined, tooltip: tr('Account'), onTap: _showSettings),
                  ],
                ),
                const SizedBox(height: 20),
                // Foto, nome e numeri su una riga, come un profilo social.
                Row(
                  children: [
                    GestureDetector(
                      onTap: _uploading ? null : _changeAvatar,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          UserAvatar(username: me.username, imageUrl: me.image, size: 92, ring: true),
                          if (_uploading) const CircularProgressIndicator(),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.ink,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.card, width: 2),
                              ),
                              child: Icon(Icons.photo_camera_rounded, size: 14, color: AppColors.onInk),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Counter(value: '${posts.value?.length ?? '–'}', label: tr('Post')),
                          _Counter(value: '${history.length}', label: tr('Sessioni'), onTap: () => context.push('/history')),
                          _Counter(
                            value: '${friends.length}',
                            label: tr('Amici'),
                            onTap: () => context.push('/friends'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Flexible(child: Text(me.displayName, style: t.titleMedium, overflow: TextOverflow.ellipsis)),
                    if (me.isAccountVerified == true) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, color: AppColors.blue, size: 18),
                    ],
                  ],
                ),
                if (total > Duration.zero)
                  Text(tr('{duration} di allenamento', {'duration': formatDuration(total)}), style: t.bodyMedium?.copyWith(color: AppColors.muted)),
                const SizedBox(height: 28),
                BodyCalendar(username: me.username, mine: true),
                const SizedBox(height: 28),
                SectionHeader(tr('I miei post')),
                AsyncView<List<Post>>(
                  value: posts,
                  onRetry: () => ref.invalidate(userPostsProvider(me.username)),
                  loading: const SkeletonGrid(),
                  data: (list) => list.isEmpty
                      ? SoftCard(
                          onTap: () => context.push('/posts/new'),
                          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                          child: Column(
                            children: [
                              Icon(Icons.photo_camera_rounded, size: 32, color: AppColors.muted),
                              const SizedBox(height: 8),
                              Text(tr('Condividi il tuo primo allenamento'),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      : PostGrid(posts: list),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.color, required this.label, required this.onTap, this.last = false});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          leading: IconChip(icon: icon, color: color, size: 36),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ),
        if (!last) const Divider(indent: 70, endIndent: 16),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: AppColors.muted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
