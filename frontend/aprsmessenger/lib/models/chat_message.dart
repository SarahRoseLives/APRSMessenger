// models/chat_message.dart

enum MessageStatus { sending, sent, delivered, failed }

class ChatMessage {
  final String messageId; // e.g., "01", "02", etc. Specific to the conversation.
  final bool fromMe;
  final String text;
  final String? time;
  final MessageStatus status;
  final int retryCount; // To track retransmissions for the color change

  ChatMessage({
    required this.messageId,
    required this.fromMe,
    required this.text,
    this.time,
    this.status = MessageStatus.sending,
    this.retryCount = 0,
  });

  // copyWith method for immutable updates
  ChatMessage copyWith({
    String? messageId,
    bool? fromMe,
    String? text,
    String? time,
    MessageStatus? status,
    int? retryCount,
  }) {
    return ChatMessage(
      messageId: messageId ?? this.messageId,
      fromMe: fromMe ?? this.fromMe,
      text: text ?? this.text,
      time: time ?? this.time,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}