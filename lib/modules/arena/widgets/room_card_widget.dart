import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../models/squad_model.dart';

/// Room card for the room list page.
/// Shows room name, host, player count, and join action.
class RoomCardWidget extends StatefulWidget {
  final SquadModel room;
  final VoidCallback onTap;
  final bool isJoined;

  const RoomCardWidget({
    super.key,
    required this.room,
    required this.onTap,
    this.isJoined = false,
  });

  @override
  State<RoomCardWidget> createState() => _RoomCardWidgetState();
}

class _RoomCardWidgetState extends State<RoomCardWidget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Left: room info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Room name
                    Text(
                      widget.room.roomName.isNotEmpty
                          ? widget.room.roomName
                          : 'Unnamed Room',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2138),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Host + player count
                    Row(
                      children: [
                        Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          widget.room.hostDisplayName,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.people_outline, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.room.members.length}/${widget.room.maxPlayers}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: widget.room.isFull ? AppColors.error : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Right: action
              if (widget.room.isPrivate)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.fantasyAccent.withValues(alpha: 0.1),
                    border: Border.all(color: AppColors.fantasyAccent.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 13, color: AppColors.fantasyAccent),
                      SizedBox(width: 4),
                      Text('CODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.fantasyAccent)),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: widget.isJoined
                        ? Colors.grey.shade400
                        : AppColors.arenaAccent,
                  ),
                  child: Text(
                    widget.isJoined ? 'JOINED' : 'JOIN',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
