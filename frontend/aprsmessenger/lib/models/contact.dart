import 'chat_message.dart';
import '../widgets/message_route_map.dart';

class RecentContact {
  final String groupingId;
  final String callsign;
  final String ownCallsign;
  final String lastMessage;
  final String time;
  final List<ChatMessage> messages;
  final bool unread;
  final List<RouteHop>? route; // <--- ADDED

  final String? lastReceivedMessageId; // ID of the last message we got from them

  RecentContact({
    required this.groupingId,
    required this.callsign,
    required this.ownCallsign,
    required this.lastMessage,
    required this.time,
    required this.messages,
    required this.unread,
    this.route,
    this.lastReceivedMessageId,
  });

  RecentContact copyWith({
    String? groupingId,
    String? callsign,
    String? ownCallsign,
    String? lastMessage,
    String? time,
    List<ChatMessage>? messages,
    bool? unread,
    List<RouteHop>? route,
    String? lastReceivedMessageId,
  }) {
    return RecentContact(
      groupingId: groupingId ?? this.groupingId,
      callsign: callsign ?? this.callsign,
      ownCallsign: ownCallsign ?? this.ownCallsign,
      lastMessage: lastMessage ?? this.lastMessage,
      time: time ?? this.time,
      messages: messages ?? this.messages,
      unread: unread ?? this.unread,
      route: route ?? this.route,
      lastReceivedMessageId: lastReceivedMessageId ?? this.lastReceivedMessageId,
    );
  }
}