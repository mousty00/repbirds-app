import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/workout_repository.dart';
import '../../models/group.dart';
import '../../models/social.dart';
import '../../models/workout.dart';
import '../auth/session.dart';

/// Manda una scheda ad amici e gruppi dentro l'app: ricevono una notifica e
/// possono aprirla e allenarsi con quella, anche se è privata.
Future<void> showSendWorkoutSheet(BuildContext context, Workout workout) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
    builder: (_) => _SendWorkoutSheet(workout: workout),
  );
}

class _SendWorkoutSheet extends ConsumerStatefulWidget {
  const _SendWorkoutSheet({required this.workout});

  final Workout workout;

  @override
  ConsumerState<_SendWorkoutSheet> createState() => _SendWorkoutSheetState();
}

class _SendWorkoutSheetState extends ConsumerState<_SendWorkoutSheet> {
  final _friends = <String>{};
  final _groups = <String>{};
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final count = await ref
          .read(workoutRepositoryProvider)
          .share(widget.workout.id, usernames: _friends.toList(), groupIds: _groups.toList());
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(count == 1 ? tr('Scheda inviata a 1 persona') : tr('Scheda inviata a {count} persone', {'count': count})),
          backgroundColor: AppColors.ink,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final friends = ref.watch(friendsProvider);
    final groups = ref.watch(groupsProvider);
    final loading = friends.isLoading || groups.isLoading;
    final friendList = (friends.value ?? const <Friendship>[]).map((f) => f.other(me.username)).toList();
    final groupList = groups.value ?? const <WorkoutGroup>[];
    final selected = _friends.length + _groups.length;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Invia "{name}"', {'name': widget.workout.name}),
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                tr('Riceveranno una notifica e potranno allenarsi con questa scheda.'),
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: loading
                    ? const SkeletonList(item: SkeletonTile(circle: true), count: 4, padding: EdgeInsets.zero)
                    : friendList.isEmpty && groupList.isEmpty
                    ? EmptyState(
                        icon: Icons.person_add_alt_1_rounded,
                        title: tr('Nessuno a cui inviarla'),
                        message: tr('Aggiungi amici o entra in un gruppo per condividere le tue schede.'),
                      )
                    : ListView(
                        children: [
                          if (groupList.isNotEmpty) ...[
                            SectionHeader(tr('Gruppi')),
                            for (final g in groupList)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _groups.contains(g.id),
                                onChanged: (v) => setState(() => v == true ? _groups.add(g.id) : _groups.remove(g.id)),
                                secondary: const IconChip(icon: Icons.groups_rounded, color: AppColors.lilac, size: 40),
                                title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            const SizedBox(height: 8),
                          ],
                          if (friendList.isNotEmpty) ...[
                            SectionHeader(tr('Amici')),
                            for (final u in friendList)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _friends.contains(u.username),
                                onChanged: (v) =>
                                    setState(() => v == true ? _friends.add(u.username) : _friends.remove(u.username)),
                                secondary: UserAvatar(username: u.username, imageUrl: u.image, size: 40),
                                title: Text('@${u.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(
                label: selected == 0 ? tr('Scegli a chi inviarla') : tr('Invia'),
                icon: Icons.send_rounded,
                loading: _sending,
                onPressed: selected == 0 ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
