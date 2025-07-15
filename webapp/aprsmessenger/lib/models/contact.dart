import 'chat_message.dart';

class RecentContact {
  final String callsign;
  final String lastMessage;
  final String time;
  final bool unread;
  final List<ChatMessage> messages;
  RecentContact({
    required this.callsign,
    required this.lastMessage,
    required this.time,
    this.unread = false,
    required this.messages,
  });

  RecentContact copyWith({
    String? callsign,
    String? lastMessage,
    String? time,
    bool? unread,
    List<ChatMessage>? messages,
  }) {
    return RecentContact(
      callsign: callsign ?? this.callsign,
      lastMessage: lastMessage ?? this.lastMessage,
      time: time ?? this.time,
      unread: unread ?? this.unread,
      messages: messages ?? this.messages,
    );
  }
}
