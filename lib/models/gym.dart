import 'json.dart';
import 'user.dart';

/// Palestra (`GymDTO`). [stats] arriva solo alla palestra stessa (`/gym/me`).
class Gym {
  const Gym({
    required this.id,
    required this.username,
    required this.name,
    this.description,
    this.address,
    this.city,
    this.phone,
    this.image,
    this.stats,
  });

  final String id;
  final String username;
  final String name;
  final String? description;
  final String? address;
  final String? city;
  final String? phone;
  final String? image;
  final GymStats? stats;

  /// "Via Roma 1, Milano", o quello che c'è.
  String? get place {
    final parts = [address, city].whereType<String>().where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory Gym.fromJson(Json j) => Gym(
    id: '${j['id']}',
    username: j['username'] as String? ?? '',
    name: j['name'] as String? ?? '',
    description: j['description'] as String?,
    address: j['address'] as String?,
    city: j['city'] as String?,
    phone: j['phone'] as String?,
    image: j['image'] as String?,
    stats: j['stats'] is Map ? GymStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)) : null,
  );
}

class GymStats {
  const GymStats({
    this.activeMembers = 0,
    this.totalMembers = 0,
    this.activePlans = 0,
    this.courses = 0,
    this.workouts = 0,
    this.checkInsToday = 0,
  });

  final int activeMembers;
  final int totalMembers;
  final int activePlans;
  final int courses;
  final int workouts;
  final int checkInsToday;

  factory GymStats.fromJson(Json j) => GymStats(
    activeMembers: parseInt(j['activeMembers']),
    totalMembers: parseInt(j['totalMembers']),
    activePlans: parseInt(j['activePlans']),
    courses: parseInt(j['courses']),
    workouts: parseInt(j['workouts']),
    checkInsToday: parseInt(j['checkInsToday']),
  );
}

/// Abbonamento in vendita (`GymPlanDTO`).
class GymPlan {
  const GymPlan({
    required this.id,
    required this.name,
    this.description,
    this.priceCents,
    required this.durationDays,
    this.active = true,
  });

  final String id;
  final String name;
  final String? description;
  final int? priceCents;
  final int durationDays;
  final bool active;

  factory GymPlan.fromJson(Json j) => GymPlan(
    id: '${j['id']}',
    name: j['name'] as String? ?? '',
    description: j['description'] as String?,
    priceCents: j['priceCents'] == null ? null : parseInt(j['priceCents']),
    durationDays: parseInt(j['durationDays']),
    active: j['active'] != false,
  );
}

enum MembershipStatus {
  active('ACTIVE'),
  suspended('SUSPENDED');

  const MembershipStatus(this.wire);

  final String wire;

  static MembershipStatus parse(Object? v) => v == 'SUSPENDED' ? suspended : active;
}

/// Iscritto come lo vede la palestra (`GymMemberDTO`). [active]: abilitato e nelle date oggi.
class GymMember {
  const GymMember({
    required this.id,
    required this.user,
    this.firstName,
    this.lastName,
    this.planId,
    this.planName,
    required this.startsOn,
    required this.endsOn,
    this.status = MembershipStatus.active,
    this.active = false,
    this.lastCheckInAt,
  });

  final String id;
  final SimpleUser user;
  final String? firstName;
  final String? lastName;
  final String? planId;
  final String? planName;
  final DateTime startsOn;
  final DateTime endsOn;
  final MembershipStatus status;
  final bool active;
  final DateTime? lastCheckInAt;

  String get displayName {
    final full = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return full.isEmpty ? user.username : full;
  }

  factory GymMember.fromJson(Json j) => GymMember(
    id: '${j['id']}',
    user: SimpleUser.fromJson(Map<String, dynamic>.from(j['user'] as Map)),
    firstName: j['firstName'] as String?,
    lastName: j['lastName'] as String?,
    planId: j['planId']?.toString(),
    planName: j['planName'] as String?,
    startsOn: parseLocalDate(j['startsOn']) ?? DateTime.now(),
    endsOn: parseLocalDate(j['endsOn']) ?? DateTime.now(),
    status: MembershipStatus.parse(j['status']),
    active: j['active'] == true,
    lastCheckInAt: parseInstant(j['lastCheckInAt']),
  );
}

/// Corso settimanale (`GymCourseDTO`). [enrolled]: ci sono iscritto io.
class GymCourse {
  const GymCourse({
    required this.id,
    required this.gymId,
    this.gymName,
    required this.name,
    this.description,
    this.instructor,
    this.room,
    this.dayOfWeek = const [],
    this.startTime,
    this.durationMinutes,
    this.capacity,
    this.enrolledCount = 0,
    this.enrolled = false,
  });

  final String id;
  final String gymId;
  final String? gymName;
  final String name;
  final String? description;
  final String? instructor;
  final String? room;
  final List<int> dayOfWeek;
  final TimeOfDayValue? startTime;
  final int? durationMinutes;
  final int? capacity;
  final int enrolledCount;
  final bool enrolled;

  bool get full => capacity != null && enrolledCount >= capacity!;

  bool isOn(DateTime day) => dayOfWeek.contains(day.weekday);

  factory GymCourse.fromJson(Json j) => GymCourse(
    id: '${j['id']}',
    gymId: '${j['gymId']}',
    gymName: j['gymName'] as String?,
    name: j['name'] as String? ?? '',
    description: j['description'] as String?,
    instructor: j['instructor'] as String?,
    room: j['room'] as String?,
    dayOfWeek: (j['dayOfWeek'] as List?)?.map((e) => parseInt(e)).toList() ?? const [],
    startTime: TimeOfDayValue.parse(j['startTime']),
    durationMinutes: j['durationMinutes'] == null ? null : parseInt(j['durationMinutes']),
    capacity: j['capacity'] == null ? null : parseInt(j['capacity']),
    enrolledCount: parseInt(j['enrolledCount']),
    enrolled: j['enrolled'] == true,
  );
}

class GymEnrollment {
  const GymEnrollment({required this.id, required this.user, this.createdAt});

  final String id;
  final SimpleUser user;
  final DateTime? createdAt;

  factory GymEnrollment.fromJson(Json j) => GymEnrollment(
    id: '${j['id']}',
    user: SimpleUser.fromJson(Map<String, dynamic>.from(j['user'] as Map)),
    createdAt: parseInstant(j['createdAt']),
  );
}

/// Perché un ingresso è stato rifiutato (`CheckInDTO.reason`).
enum CheckInRefusal { invalidCode, notAMember, suspended, notStarted, expired, other }

/// Una lettura della tessera all'ingresso (`CheckInDTO`).
class CheckIn {
  const CheckIn({
    required this.id,
    required this.accepted,
    this.reason,
    this.member,
    this.memberName,
    this.planName,
    this.endsOn,
    this.method,
    this.checkedInAt,
  });

  final String id;
  final bool accepted;
  final String? reason;
  final SimpleUser? member;
  final String? memberName;
  final String? planName;
  final DateTime? endsOn;
  final String? method;
  final DateTime? checkedInAt;

  CheckInRefusal? get refusal => accepted
      ? null
      : switch (reason) {
          'INVALID_CODE' => CheckInRefusal.invalidCode,
          'NOT_A_MEMBER' => CheckInRefusal.notAMember,
          'SUSPENDED' => CheckInRefusal.suspended,
          'NOT_STARTED' => CheckInRefusal.notStarted,
          'EXPIRED' => CheckInRefusal.expired,
          _ => CheckInRefusal.other,
        };

  factory CheckIn.fromJson(Json j) => CheckIn(
    id: '${j['id']}',
    accepted: j['accepted'] == true,
    reason: j['reason'] as String?,
    member: j['member'] is Map ? SimpleUser.fromJson(Map<String, dynamic>.from(j['member'] as Map)) : null,
    memberName: j['memberName'] as String?,
    planName: j['planName'] as String?,
    endsOn: parseLocalDate(j['endsOn']),
    method: j['method'] as String?,
    checkedInAt: parseInstant(j['checkedInAt']),
  );
}

/// Il mio abbonamento a una palestra (`MembershipDTO`). [card] c'è solo se è attivo.
class Membership {
  const Membership({
    required this.id,
    required this.gym,
    this.planName,
    required this.startsOn,
    required this.endsOn,
    this.status = MembershipStatus.active,
    this.active = false,
    this.card,
  });

  final String id;
  final Gym gym;
  final String? planName;
  final DateTime startsOn;
  final DateTime endsOn;
  final MembershipStatus status;
  final bool active;
  final MembershipCard? card;

  factory Membership.fromJson(Json j) => Membership(
    id: '${j['id']}',
    gym: Gym.fromJson(Map<String, dynamic>.from(j['gym'] as Map)),
    planName: j['planName'] as String?,
    startsOn: parseLocalDate(j['startsOn']) ?? DateTime.now(),
    endsOn: parseLocalDate(j['endsOn']) ?? DateTime.now(),
    status: MembershipStatus.parse(j['status']),
    active: j['active'] == true,
    card: j['card'] is Map ? MembershipCard.fromJson(Map<String, dynamic>.from(j['card'] as Map)) : null,
  );
}

/// Quello che serve per fare il codice della tessera anche offline (vedi `CardCode`).
class MembershipCard {
  const MembershipCard({required this.cardId, required this.secret, this.periodSeconds = 30});

  final String cardId;
  final String secret;
  final int periodSeconds;

  factory MembershipCard.fromJson(Json j) => MembershipCard(
    cardId: '${j['cardId']}',
    secret: j['secret'] as String? ?? '',
    periodSeconds: j['periodSeconds'] == null ? 30 : parseInt(j['periodSeconds']),
  );

  Json toJson() => {'cardId': cardId, 'secret': secret, 'periodSeconds': periodSeconds};
}
