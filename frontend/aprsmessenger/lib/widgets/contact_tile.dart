import 'package:flutter/material.dart';
import '../models/contact.dart';

class ContactTile extends StatelessWidget {
  final RecentContact contact;
  final bool selected;
  final VoidCallback onTap;
  final String displayTime;

  const ContactTile({
    super.key,
    required this.contact,
    required this.selected,
    required this.onTap,
    required this.displayTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isAdmin = contact.isAdminMessage;

    return Material(
      color: isAdmin
          ? Colors.red.withOpacity(0.08)
          : (selected
              ? theme.colorScheme.secondary.withOpacity(0.14)
              : Colors.transparent),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isAdmin
                    ? Colors.red.shade100
                    : theme.colorScheme.primary.withOpacity(0.13),
                foregroundColor:
                    isAdmin ? Colors.red.shade700 : theme.colorScheme.primary,
                child: isAdmin
                    ? const Icon(Icons.campaign, size: 22)
                    : Text(contact.callsign.substring(0, 1)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          contact.callsign,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isAdmin
                                ? Colors.red.shade700
                                : theme.colorScheme.primary,
                            fontSize: 16,
                          ),
                        ),
                        if (contact.unread && !isAdmin)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contact.lastMessage,
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          overflow: TextOverflow.ellipsis),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                displayTime,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}