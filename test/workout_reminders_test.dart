import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/notifications/workout_reminders.dart';
import 'package:repbirds_app/models/json.dart';
import 'package:repbirds_app/models/workout.dart';

void main() {
  // lunedì 10 novembre 2025, ore 12
  final now = DateTime(2025, 11, 10, 12);

  test('mezz\'ora prima dell\'ora della scheda, nei suoi giorni, dalle prossime ore', () {
    const legs = Workout(id: 'w1', name: 'Gambe', dayOfWeek: [1, 4], startTime: TimeOfDayValue(18, 0));
    final list = WorkoutRemindersNotifier.upcomingReminders([legs], now);
    expect(list.first.at, DateTime(2025, 11, 10, 17, 30));
    expect(list[1].at, DateTime(2025, 11, 13, 17, 30));
    expect(list.length, 4); // due settimane, due giorni a settimana
    expect(list.first.body, contains('Gambe'));
  });

  test('senza ora: alle 9, e niente promemoria già passati', () {
    const free = Workout(id: 'w2', name: 'Corsa', dayOfWeek: [1, 2]);
    final list = WorkoutRemindersNotifier.upcomingReminders([free], now);
    // oggi alle 9 è già passato: si parte da domani
    expect(list.first.at, DateTime(2025, 11, 11, 9));
    expect(list.every((r) => r.at.isAfter(now)), isTrue);
  });

  test('al massimo 40, in ordine', () {
    final many = [
      for (var i = 0; i < 5; i++) Workout(id: 'w$i', name: 'S$i', dayOfWeek: const [1, 2, 3, 4, 5, 6, 7]),
    ];
    final list = WorkoutRemindersNotifier.upcomingReminders(many, now);
    expect(list.length, 40);
    for (var i = 1; i < list.length; i++) {
      expect(list[i].at.isBefore(list[i - 1].at), isFalse);
    }
  });
}
