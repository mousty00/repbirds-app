import 'json.dart';

/// Il mio Premium (`PremiumDTO`).
class PremiumStatus {
  const PremiumStatus({
    this.premium = false,
    this.platform,
    this.productId,
    this.expiresAt,
    this.autoRenew,
    this.products = const ['repbirds_premium_monthly', 'repbirds_premium_yearly'],
    this.freeBodyPhotos = 20,
  });

  final bool premium;
  final String? platform;
  final String? productId;
  final DateTime? expiresAt;
  final bool? autoRenew;

  /// Gli id dei prodotti negli store.
  final List<String> products;
  final int freeBodyPhotos;

  factory PremiumStatus.fromJson(Json j) => PremiumStatus(
        premium: j['premium'] as bool? ?? false,
        platform: j['platform'] as String?,
        productId: j['productId'] as String?,
        expiresAt: parseInstant(j['expiresAt']),
        autoRenew: j['autoRenew'] as bool?,
        products: [for (final p in (j['products'] as List? ?? const [])) '$p'],
        freeBodyPhotos: parseInt(j['freeBodyPhotos'], 20),
      );
}

class ProgramItem {
  const ProgramItem({required this.exercise, required this.muscleGroup, required this.sets, required this.reps, required this.restSeconds});

  final String exercise;
  final String muscleGroup;
  final int sets;
  final int reps;
  final int restSeconds;

  factory ProgramItem.fromJson(Json j) => ProgramItem(
        exercise: j['exercise'] as String? ?? '',
        muscleGroup: j['muscleGroup'] as String? ?? '',
        sets: parseInt(j['sets']),
        reps: parseInt(j['reps']),
        restSeconds: parseInt(j['restSeconds']),
      );
}

class ProgramDay {
  const ProgramDay({required this.name, required this.dayOfWeek, this.items = const []});

  final String name;

  /// 1 = lunedì … 7 = domenica.
  final int dayOfWeek;
  final List<ProgramItem> items;

  factory ProgramDay.fromJson(Json j) => ProgramDay(
        name: j['name'] as String? ?? '',
        dayOfWeek: parseInt(j['dayOfWeek'], 1),
        items: parseList(j['items'], ProgramItem.fromJson),
      );
}

/// Un programma guidato; [locked] per chi non ha Premium.
class Program {
  const Program({
    required this.slug,
    required this.name,
    this.description = '',
    this.level = '',
    this.weeks = 0,
    this.daysPerWeek = 0,
    this.days = const [],
    this.locked = true,
  });

  final String slug;
  final String name;
  final String description;
  final String level;
  final int weeks;
  final int daysPerWeek;
  final List<ProgramDay> days;
  final bool locked;

  factory Program.fromJson(Json j) => Program(
        slug: j['slug'] as String? ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        level: j['level'] as String? ?? '',
        weeks: parseInt(j['weeks']),
        daysPerWeek: parseInt(j['daysPerWeek']),
        days: parseList(j['days'], ProgramDay.fromJson),
        locked: j['locked'] as bool? ?? true,
      );
}

class StatsWeek {
  const StatsWeek({required this.weekStart, this.sessions = 0, this.minutes = 0, this.volumeKg = 0});

  final DateTime weekStart;
  final int sessions;
  final int minutes;
  final double volumeKg;
}

/// Statistiche avanzate (`AdvancedStatsDTO`).
class AdvancedStats {
  const AdvancedStats({
    this.weeks = const [],
    this.muscleGroups = const [],
    this.currentStreakWeeks = 0,
    this.longestStreakWeeks = 0,
    this.totalSessions = 0,
    this.personalBests = const [],
  });

  final List<StatsWeek> weeks;
  final List<(String, int)> muscleGroups;
  final int currentStreakWeeks;
  final int longestStreakWeeks;
  final int totalSessions;

  /// (esercizio, kg, ripetizioni)
  final List<(String, double, int?)> personalBests;

  factory AdvancedStats.fromJson(Json j) => AdvancedStats(
        weeks: [
          for (final w in (j['weeks'] as List? ?? const []).whereType<Map>())
            StatsWeek(
              weekStart: DateTime.tryParse('${w['weekStart']}') ?? DateTime.now(),
              sessions: parseInt(w['sessions']),
              minutes: parseInt(w['minutes']),
              volumeKg: (w['volumeKg'] as num?)?.toDouble() ?? 0,
            ),
        ],
        muscleGroups: [
          for (final m in (j['muscleGroups'] as List? ?? const []).whereType<Map>()) ('${m['muscleGroup']}', parseInt(m['sets'])),
        ],
        currentStreakWeeks: parseInt(j['currentStreakWeeks']),
        longestStreakWeeks: parseInt(j['longestStreakWeeks']),
        totalSessions: parseInt(j['totalSessions']),
        personalBests: [
          for (final b in (j['personalBests'] as List? ?? const []).whereType<Map>())
            ('${b['exercise']}', (b['weightKg'] as num?)?.toDouble() ?? 0, (b['reps'] as num?)?.toInt()),
        ],
      );
}
