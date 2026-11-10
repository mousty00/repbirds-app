part of 'mock_backend.dart';

/// Premium in modalità mock (`/premium`, `/programs` di repbirds-api). L'account demo
/// ha Premium, così le funzioni si possono provare senza store.
extension _MockPremium on MockBackend {
  static const _programs = [
    {
      'slug': 'full-body-start',
      'name': 'Full body start',
      'description': 'Tre allenamenti completi a settimana per iniziare bene.',
      'level': 'Principiante',
      'weeks': 8,
      'days': [
        {'name': 'A', 'dayOfWeek': 1, 'items': [
          {'exercise': 'Squat', 'muscleGroup': 'Gambe', 'sets': 3, 'reps': 10, 'restSeconds': 90},
          {'exercise': 'Panca piana', 'muscleGroup': 'Petto', 'sets': 3, 'reps': 10, 'restSeconds': 90},
        ]},
        {'name': 'B', 'dayOfWeek': 3, 'items': [
          {'exercise': 'Stacco da terra', 'muscleGroup': 'Schiena', 'sets': 3, 'reps': 8, 'restSeconds': 120},
          {'exercise': 'Military press', 'muscleGroup': 'Spalle', 'sets': 3, 'reps': 10, 'restSeconds': 90},
        ]},
        {'name': 'C', 'dayOfWeek': 5, 'items': [
          {'exercise': 'Affondi', 'muscleGroup': 'Gambe', 'sets': 3, 'reps': 12, 'restSeconds': 60},
          {'exercise': 'Trazioni', 'muscleGroup': 'Schiena', 'sets': 3, 'reps': 6, 'restSeconds': 120},
        ]},
      ],
    },
    {
      'slug': 'corsa-5k',
      'name': 'Primi 5 km',
      'description': 'Corsa e camminata alternate fino a 5 km di fila.',
      'level': 'Principiante',
      'weeks': 6,
      'days': [
        {'name': 'Ripetute', 'dayOfWeek': 2, 'items': [
          {'exercise': 'Corsa', 'muscleGroup': 'Cardio', 'sets': 6, 'reps': 1, 'restSeconds': 90},
        ]},
        {'name': 'Lungo lento', 'dayOfWeek': 6, 'items': [
          {'exercise': 'Corsa', 'muscleGroup': 'Cardio', 'sets': 1, 'reps': 1, 'restSeconds': 0},
        ]},
      ],
    },
  ];

  Object? _premiumRoutes(bool Function(String, String) match, List<String> seg) {
    if (match('GET', '/premium')) {
      return {
        'premium': true,
        'platform': 'PROMO',
        'productId': 'repbirds_premium_yearly',
        'expiresAt': MockBackend._iso(_now.add(const Duration(days: 200))),
        'autoRenew': false,
        'products': ['repbirds_premium_monthly', 'repbirds_premium_yearly'],
        'freeBodyPhotos': 20,
      };
    }
    if (match('GET', '/premium/stats')) {
      final monday = _day(_now).subtract(Duration(days: _now.weekday - 1));
      return {
        'weeks': [
          for (var i = 11; i >= 0; i--)
            {
              'weekStart': monday.subtract(Duration(days: 7 * i)).toIso8601String().substring(0, 10),
              'sessions': (i * 7 + 3) % 5,
              'minutes': ((i * 7 + 3) % 5) * 55,
              'volumeKg': ((i * 7 + 3) % 5) * 3200.0,
            },
        ],
        'muscleGroups': [
          {'muscleGroup': 'Gambe', 'sets': 64},
          {'muscleGroup': 'Petto', 'sets': 48},
          {'muscleGroup': 'Schiena', 'sets': 45},
          {'muscleGroup': 'Spalle', 'sets': 21},
        ],
        'currentStreakWeeks': 4,
        'longestStreakWeeks': 9,
        'totalSessions': _history.length,
        'personalBests': [
          {'exercise': 'Stacco da terra', 'weightKg': 140.0, 'reps': 3},
          {'exercise': 'Squat', 'weightKg': 120.0, 'reps': 5},
          {'exercise': 'Panca piana', 'weightKg': 90.0, 'reps': 5},
        ],
      };
    }
    if (match('GET', '/premium/export')) {
      return [
        'date,started_at,completed_at,minutes,workout,exercises,notes',
        for (final h in _history)
          '${'${h['startedAt']}'.substring(0, 10)},${h['startedAt']},${h['completedAt']},60,Allenamento,,',
      ].join('\n');
    }
    if (match('GET', '/programs')) {
      return [for (final p in _programs) {...p, 'daysPerWeek': (p['days'] as List).length, 'locked': false}];
    }
    if (match('POST', '/programs/:slug/start')) {
      final p = _programs.firstWhere((p) => p['slug'] == seg[1], orElse: () => throw _MockError(404, 'Programma non trovato'));
      return [
        for (final d in p['days'] as List)
          () {
            final w = _workout(_id('w'), _me, '${p['name']} · ${d['name']}', '${p['description']}', false, [d['dayOfWeek'] as int],
                null, []);
            _workouts.add(w);
            return w;
          }(),
      ];
    }
    return _unhandled;
  }
}
