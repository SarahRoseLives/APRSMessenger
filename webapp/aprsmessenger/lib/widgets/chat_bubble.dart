import 'package:flutter/material.dart';
import '../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromMe = message.fromMe;
    final color = fromMe ? theme.colorScheme.primary : Colors.grey.shade100;
    final textColor = fromMe ? Colors.white : Colors.black87;
    final align = fromMe ? Alignment.centerRight : Alignment.centerLeft;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: fromMe ? const Radius.circular(18) : const Radius.circular(4),
      bottomRight: fromMe ? const Radius.circular(4) : const Radius.circular(18),
    );

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          boxShadow: [
            if (fromMe)
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
              ),
            ),
            if (message.time != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  message.time!,
                  style: TextStyle(
                    fontSize: 11,
                    color: fromMe ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
