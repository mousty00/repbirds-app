import 'json.dart';
import 'user.dart';

enum ConversationType {
  direct,
  group,
  gym;

  static ConversationType parse(Object? v) => switch ('$v'.toUpperCase()) {
        'GROUP' => group,
        'GYM' => gym,
        _ => direct,
      };
}

class ChatMember {
  const ChatMember({required this.user, this.admin = false});

  final SimpleUser user;
  final bool admin;

  factory ChatMember.fromJson(Json j) => ChatMember(
        user: SimpleUser.fromJson(Map<String, dynamic>.from(j['user'] as Map)),
        admin: j['role'] == 'ADMIN',
      );
}

/// Una chat (`ConversationDTO`): con un amico, un gruppo o il canale di una palestra.
class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.name,
    this.encrypted = true,
    this.gymId,
    this.members = const [],
    this.lastMessageAt,
    this.unreadCount = 0,
    this.muted = false,
    this.admin = false,
    this.canWrite = true,
  });

  final String id;
  final ConversationType type;
  final String name;

  /// Cifrata end-to-end (amici e gruppi). Il canale della palestra no.
  final bool encrypted;
  final String? gymId;
  final List<ChatMember> members;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool muted;
  final bool admin;
  final bool canWrite;

  /// Per l'avatar di una chat a due: l'altra persona.
  SimpleUser? other(String myUsername) {
    if (type != ConversationType.direct) return null;
    for (final m in members) {
      if (m.user.username != myUsername) return m.user;
    }
    return null;
  }

  factory Conversation.fromJson(Json j) => Conversation(
        id: '${j['id']}',
        type: ConversationType.parse(j['type']),
        name: j['name'] as String? ?? '',
        encrypted: j['encrypted'] as bool? ?? true,
        gymId: j['gymId'] as String?,
        members: parseList(j['members'], ChatMember.fromJson),
        lastMessageAt: parseInstant(j['lastMessageAt']),
        unreadCount: parseInt(j['unreadCount']),
        muted: j['muted'] as bool? ?? false,
        admin: j['admin'] as bool? ?? false,
        canWrite: j['canWrite'] as bool? ?? true,
      );
}

/// Un dispositivo dei membri, per cui il mittente cifra la chiave del messaggio.
class ChatDevice {
  const ChatDevice({required this.id, required this.username, required this.publicKey});

  final String id;
  final String username;
  final String publicKey;

  factory ChatDevice.fromJson(Json j) =>
      ChatDevice(id: '${j['id']}', username: j['username'] as String? ?? '', publicKey: j['publicKey'] as String? ?? '');
}

/// Un messaggio. [text] è già decifrato (o il testo del canale palestra); null
/// quando su questo dispositivo non si può leggere.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.sender,
    this.text,
    this.createdAt,
    this.pending = false,
  });

  final String id;
  final String conversationId;
  final SimpleUser sender;
  final String? text;
  final DateTime? createdAt;

  /// Appena scritto, in viaggio verso il server.
  final bool pending;
}
