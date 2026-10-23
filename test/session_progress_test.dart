import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:repbirds_app/features/workouts/saved_session.dart';
import 'package:repbirds_app/features/workouts/session_progress.dart';
import 'package:repbirds_app/models/workout.dart';

WorkoutExercise ex(String id, int sets) =>
    WorkoutExercise(id: id, workoutId: 'w', exerciseId: id, exerciseName: id, sets: sets, reps: 10, restSeconds: 60, position: 0);

void main() {
  test('una serie alla volta, "a seguire" solo sull\'ultima serie', () {
    final p = SessionProgress([ex('panca', 2), ex('croci', 1), ex('dip', 1)]);
    expect(p.current!.id, 'panca');
    expect(p.currentSet, 1);
    expect(p.isLastSet, isFalse);

    p.completeSet();
    expect(p.isLastSet, isTrue);
    expect(p.next!.id, 'croci');

    p.completeSet();
    expect(p.current!.id, 'croci');
    expect(p.isLastSet, isTrue);
    expect(p.next!.id, 'dip');

    p.completeSet();
    expect(p.isLastSet, isTrue);
    expect(p.next, isNull, reason: 'ultimo esercizio: niente "a seguire"');
    p.completeSet();
    expect(p.allDone, isTrue);
    expect(p.doneSets, p.totalSets);
  });

  test('dalla lista salto un esercizio, poi torno a quelli lasciati indietro', () {
    final p = SessionProgress([ex('a', 1), ex('b', 1), ex('c', 1)]);
    p.focus(p.exercises[1]);
    p.completeSet();
    expect(p.current!.id, 'c');
    p.completeSet();
    expect(p.current!.id, 'a');
  });

  test('annulla una serie', () {
    final p = SessionProgress([ex('a', 2)]);
    final e = p.completeSet()!;
    p.undo(e);
    expect(p.doneOf(e), 0);
    expect(p.currentSet, 1);
  });

  test('app chiusa a metà: la sessione salvata riparte da dove eri', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final p = SessionProgress([ex('panca', 2), ex('croci', 1)])..completeSet();
    final end = DateTime.now().add(const Duration(seconds: 50));
    await SavedSession(workoutId: 'w', startedAt: DateTime.now(), done: p.done, focus: p.focusIndex, restEndsAt: end, restTotal: 60, notes: 'ok')
        .save();

    final s = (await SavedSession.load())!;
    final resumed = SessionProgress(p.exercises)..restore(s.done, s.focus);
    expect(resumed.current!.id, 'panca');
    expect(resumed.currentSet, 2);
    expect(s.restEndsAt, end);
    expect(s.notes, 'ok');

    await SavedSession.clear();
    expect(await SavedSession.load(), isNull);
  });

  test('una sessione troppo vecchia non si riprende', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await SavedSession(workoutId: 'w', startedAt: DateTime.now().subtract(const Duration(hours: 13))).save();
    expect(await SavedSession.load(), isNull);
  });

  test('scheda modificata durante l\'allenamento: le serie fatte restano, l\'esercizio nuovo è da fare', () {
    final before = SessionProgress([ex('a', 2), ex('b', 1)])..completeSet();
    // tolgo una serie ad "a" e aggiungo "c": si riparte dagli stessi id
    final after = SessionProgress([ex('a', 1), ex('b', 1), ex('c', 2)])..restore(before.done, before.focusIndex);
    expect(after.isComplete(after.exercises[0]), isTrue);
    expect(after.current!.id, 'b');
    expect(after.totalSets, 4);
    expect(after.doneSets, 1);
  });
}
