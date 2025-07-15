import 'chat_message.dart';

class RecentContact {
  final String groupingId; // Base callsign of the contact, e.g., "K8CY"
  final String callsign; // Full, most recent callsign of the contact, e.g., "K8CY-5"
  final String? ownCallsign; // The user's full callsign for this chat, e.g., "AD8NT-10"
  final String lastMessage;
  final String time;
  final bool unread;
  final List<ChatMessage> messages;
  RecentContact({
    required this.groupingId,
    required this.callsign,
    this.ownCallsign,
    required this.lastMessage,
    required this.time,
    this.unread = false,
    required this.messages,
  });

  RecentContact copyWith({
    String? groupingId,
    String? callsign,
    String? ownCallsign,
    String? lastMessage,
    String? time,
    bool? unread,
    List<ChatMessage>? messages,
  }) {
    return RecentContact(
      groupingId: groupingId ?? this.groupingId,
      callsign: callsign ?? this.callsign,
      ownCallsign: ownCallsign ?? this.ownCallsign,
      lastMessage: lastMessage ?? this.lastMessage,
      time: time ?? this.time,
      unread: unread ?? this.unread,
      messages: messages ?? this.messages,
    );
  }
}