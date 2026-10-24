import '../core/l10n/l10n.dart';
import 'json.dart';
import 'user.dart';

/// Giorni della settimana come li salva il backend (1 = lunedì … 7 = domenica).
List<String> get weekdayShort => [tr('Lun'), tr('Mar'), tr('Mer'), tr('Gio'), tr('Ven'), tr('Sab'), tr('Dom')];

String weekdaysLabel(List<int> days) {
  if (days.isEmpty) return tr('Quando vuoi');
  if (days.length == 7) return tr('Tutti i giorni');
  final sorted = [...days]..sort();
  return sorted.where((d) => d >= 1 && d <= 7).map((d) => weekdayShort[d - 1]).join(' · ');
}

class Workout {
  const Workout({
    required this.id,
    required this.name,
    this.user,
    this.description,
    this.isPublic = false,
    this.dayOfWeek = const [],
    this.startTime,
    this.createdAt,
    this.exercises = const [],
    this.history = const [],
    this.gymId,
    this.gymName,
  });

  final String id;
  final String name;
  final SimpleUser? user;

  /// Scheda di una palestra per i suoi iscritti: non si condivide e non si porta nei gruppi.
  final String? gymId;
  final String? gymName;
  final String? description;
  final bool isPublic;
  final List<int> dayOfWeek;
  final TimeOfDayValue? startTime;
  final DateTime? createdAt;
  final List<WorkoutExercise> exercises;
  final List<WorkoutHistory> history;

  bool isScheduledOn(DateTime day) => dayOfWeek.contains(day.weekday);

  factory Workout.fromJson(Json j) {
    final u = j['user'];
    final exercises = parseList(j['workoutExercises'], WorkoutExercise.fromJson)
      ..sort((a, b) => a.position.compareTo(b.position));
    return Workout(
      id: '${j['id']}',
      name: j['name'] as String? ?? '',
      user: u is Map ? SimpleUser.fromJson(Map<String, dynamic>.from(u)) : null,
      description: j['description'] as String?,
      isPublic: j['isPublic'] == true,
      dayOfWeek: (j['dayOfWeek'] as List?)?.map((e) => parseInt(e)).toList() ?? const [],
      startTime: TimeOfDayValue.parse(j['startTime']),
      createdAt: parseInstant(j['createdAt']),
      exercises: exercises,
      history: parseList(j['workoutHistories'], WorkoutHistory.fromJson),
      gymId: j['gymId']?.toString(),
      gymName: j['gymName'] as String?,
    );
  }
}

class WorkoutInput {
  const WorkoutInput({
    this.id,
    required this.name,
    this.description,
    this.isPublic = false,
    this.dayOfWeek = const [],
    this.startTime,
  });

  final String? id;
  final String name;
  final String? description;
  final bool isPublic;
  final List<int> dayOfWeek;
  final TimeOfDayValue? startTime;

  Json toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'isPublic': isPublic,
        'dayOfWeek': dayOfWeek,
        'startTime': startTime?.toJson(),
      };
}

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    this.description,
    this.isPublic = true,
    this.createdBy,
  });

  final String id;
  final String name;
  final String muscleGroup;
  final String? description;
  final bool isPublic;
  final String? createdBy;

  factory Exercise.fromJson(Json j) => Exercise(
        id: '${j['id']}',
        name: j['name'] as String? ?? '',
        muscleGroup: j['muscleGroup'] as String? ?? '',
        description: j['description'] as String?,
        isPublic: j['isPublic'] == true,
        createdBy: (j['createdBy'] as Map?)?['username'] as String?,
      );
}

/// Gruppi muscolari proposti nel form (il backend accetta testo libero, max 50).
const muscleGroups = [
  'Petto',
  'Schiena',
  'Spalle',
  'Bicipiti',
  'Tricipiti',
  'Gambe',
  'Glutei',
  'Addome',
  'Cardio',
  'Full body',
];

/// Nome da mostrare di un gruppo muscolare: il valore salvato sul server resta
/// in italiano, quelli scritti a mano dall'utente restano com'erano.
String muscleGroupLabel(String group) => switch (group) {
  'Petto' => tr('Petto'),
  'Schiena' => tr('Schiena'),
  'Spalle' => tr('Spalle'),
  'Bicipiti' => tr('Bicipiti'),
  'Tricipiti' => tr('Tricipiti'),
  'Gambe' => tr('Gambe'),
  'Glutei' => tr('Glutei'),
  'Addome' => tr('Addome'),
  'Cardio' => tr('Cardio'),
  'Full body' => tr('Full body'),
  _ => group,
};

class WorkoutExercise {
  const WorkoutExercise({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    this.exerciseName,
    required this.sets,
    required this.reps,
    this.weight,
    required this.restSeconds,
    required this.position,
  });

  final String id;
  final String workoutId;
  final String exerciseId;
  final String? exerciseName;
  final int sets;
  final int reps;
  final double? weight;
  final int restSeconds;
  final int position;

  String get summary {
    final w = weight != null && weight! > 0 ? ' · ${_fmt(weight!)} kg' : '';
    return '$sets × $reps$w';
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  factory WorkoutExercise.fromJson(Json j) => WorkoutExercise(
        id: '${j['id']}',
        workoutId: '${j['workoutId']}',
        exerciseId: '${j['exerciseId']}',
        exerciseName: j['exerciseName'] as String?,
        sets: parseInt(j['sets']),
        reps: parseInt(j['reps']),
        weight: parseDouble(j['weight']),
        restSeconds: parseInt(j['restSeconds']),
        position: parseInt(j['position']),
      );
}

class WorkoutExerciseInput {
  const WorkoutExerciseInput({
    this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.sets,
    required this.reps,
    this.weight,
    required this.restSeconds,
    required this.position,
  });

  final String? id;
  final String workoutId;
  final String exerciseId;
  final int sets;
  final int reps;
  final double? weight;
  final int restSeconds;
  final int position;

  Json toJson() => {
        if (id != null) 'id': id,
        'workoutId': workoutId,
        'exerciseId': exerciseId,
        'sets': sets,
        'reps': reps,
        'weight': weight,
        'restSeconds': restSeconds,
        'position': position,
      };
}

class WorkoutHistory {
  const WorkoutHistory({
    required this.id,
    this.userId,
    this.workoutId,
    this.groupId,
    this.startedAt,
    this.completedAt,
    this.notes,
  });

  final String id;
  final String? userId;
  final String? workoutId;
  final String? groupId;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? notes;

  Duration? get duration =>
      startedAt != null && completedAt != null ? completedAt!.difference(startedAt!) : null;

  factory WorkoutHistory.fromJson(Json j) => WorkoutHistory(
        id: '${j['id']}',
        userId: j['userId']?.toString(),
        workoutId: j['workoutId']?.toString(),
        groupId: j['groupId']?.toString(),
        startedAt: parseInstant(j['startedAt']),
        completedAt: parseInstant(j['completedAt']),
        notes: j['notes'] as String?,
      );
}
