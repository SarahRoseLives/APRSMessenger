class ChatMessage {
  final bool fromMe;
  final String text;
  final String? time;
  ChatMessage({
    required this.fromMe,
    required this.text,
    this.time,
  });
}
