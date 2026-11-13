import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../models/workout.dart';
import '../l10n/l10n.dart';
import 'rest_alarm.dart';

/// Un promemoria da programmare.
typedef Reminder = ({DateTime at, String title, String body});

/// Promemoria degli allenamenti, dai giorni e dall'ora delle schede: mezz'ora prima
/// dell'ora indicata, o alle 9 se la scheda non ha un'ora. Sono notifiche locali:
/// funzionano offline e il server non ne sa niente.
///
/// Si programmano le prossime due settimane come notifiche singole (in UTC, calcolate
/// sull'ora locale), così il cambio dell'ora legale non le sposta; ogni volta che le
/// schede cambiano o l'app si apre si riprogrammano.
class WorkoutRemindersNotifier extends Notifier<bool> {
  static const _key = 'repbirds.reminders';
  static const _storage = FlutterSecureStorage();
  static const _firstId = 5000;
  static const _max = 40;
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Letto in main() prima di avviare l'app.
  static bool on = false;

  static Future<void> load() async {
    try {
      on = await _storage.read(key: _key) == 'on';
    } catch (_) {}
  }

  @override
  bool build() => on;

  Future<void> set(bool value, List<Workout> workouts) async {
    state = on = value;
    try {
      await _storage.write(key: _key, value: value ? 'on' : 'off');
    } catch (_) {}
    if (value) await RestAlarm.requestPermission();
    await sync(workouts);
  }

  /// Riprogramma tutto da capo.
  Future<void> sync(List<Workout> workouts) async {
    if (kIsWeb) return;
    try {
      await cancelAll();
      if (!state) return;
      final list = upcomingReminders(workouts, DateTime.now());
      for (var i = 0; i < list.length; i++) {
        await _plugin.zonedSchedule(
          id: _firstId + i,
          title: list[i].title,
          body: list[i].body,
          scheduledDate: tz.TZDateTime.from(list[i].at.toUtc(), tz.UTC),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('workout_reminders', 'Promemoria allenamenti'),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Promemoria non programmati: $e');
    }
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      for (var i = 0; i < _max; i++) {
        await _plugin.cancel(id: _firstId + i);
      }
    } catch (_) {}
  }

  /// I promemoria dei prossimi 14 giorni, in ordine, al massimo [_max].
  @visibleForTesting
  static List<Reminder> upcomingReminders(List<Workout> workouts, DateTime now) {
    final out = <Reminder>[];
    final today = DateTime(now.year, now.month, now.day);
    for (var d = 0; d < 14; d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      for (final w in workouts) {
        if (!w.dayOfWeek.contains(day.weekday)) continue;
        final time = w.startTime;
        final at = time == null
            ? DateTime(day.year, day.month, day.day, 9)
            : DateTime(day.year, day.month, day.day, time.hour, time.minute).subtract(const Duration(minutes: 30));
        if (!at.isAfter(now)) continue;
        out.add((
          at: at,
          title: time == null ? tr('Oggi ti alleni') : tr('Tra mezz\'ora ti alleni'),
          body: time == null ? w.name : tr('{name} alle {time}', {'name': w.name, 'time': time.label}),
        ));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.take(_max).toList();
  }
}

final workoutRemindersProvider = NotifierProvider<WorkoutRemindersNotifier, bool>(WorkoutRemindersNotifier.new);
