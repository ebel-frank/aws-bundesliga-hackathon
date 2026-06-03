import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../controllers/arena_controller.dart';

/// A chat message model for the live chat.
class ChatMessage {
  final String userId;
  final String displayName;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.userId,
    required this.displayName,
    required this.text,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// A floating emoji reaction model.
class FloatingReaction {
  final String emoji;
  final double startX;
  final String id;

  FloatingReaction({
    required this.emoji,
    required this.startX,
  }) : id = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
}

/// Live chat and emoji reactions overlay — Instagram Live / TikTok style.
/// Messages float up from bottom-left, emojis float up from bottom-right.
class LiveChatWidget extends StatefulWidget {
  const LiveChatWidget({super.key});

  @override
  State<LiveChatWidget> createState() => _LiveChatWidgetState();
}

class _LiveChatWidgetState extends State<LiveChatWidget> {
  final controller = Get.find<ArenaController>();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final RxBool _isTyping = false.obs;
  final RxBool _showEmojis = false.obs;

  static const List<String> _quickEmojis = ['❤️', '🔥', '⚽', '👏', '😂', '😮'];

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    controller.sendChatMessage(text);
    _textController.clear();
    _isTyping.value = false;
    _focusNode.unfocus();
  }

  void _sendReaction(String emoji) {
    controller.sendReaction(emoji);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Chat messages + floating reactions area
        SizedBox(
          height: 120,
          child: Stack(
            children: [
              // Chat messages (bottom-left, floating up)
              Positioned(
                left: 0,
                right: 60,
                bottom: 0,
                top: 0,
                child: Obx(() => _buildChatMessages()),
              ),
              // Floating emoji reactions (bottom-right, floating up)
              Positioned(
                right: 0,
                bottom: 0,
                top: 0,
                width: 50,
                child: Obx(() => _buildFloatingReactions()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Input bar + quick emoji row
        _buildInputBar(),
      ],
    );
  }

  Widget _buildChatMessages() {
    final messages = controller.chatMessages;
    if (messages.isEmpty) return const SizedBox.shrink();

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      itemCount: messages.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        // Reverse index since list is reversed
        final msg = messages[messages.length - 1 - index];
        return _ChatBubble(message: msg);
      },
    );
  }

  Widget _buildFloatingReactions() {
    final reactions = controller.floatingReactions;
    return Stack(
      children: reactions.map((reaction) => _FloatingEmoji(
        key: ValueKey(reaction.id),
        reaction: reaction,
        onComplete: () => controller.removeReaction(reaction.id),
      )).toList(),
    );
  }

  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Expandable emoji row
        Obx(() => _showEmojis.value
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _quickEmojis.map((emoji) => GestureDetector(
                          onTap: () {
                            _sendReaction(emoji);
                            _showEmojis.value = false;
                          },
                          child: Text(emoji, style: const TextStyle(fontSize: 26)),
                        )).toList(),
                  ),
                ),
              )
            : const SizedBox.shrink()),
        // Input row
        Row(
          children: [
            // Text input
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.cardSurface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Say something...',
                          hintStyle: TextStyle(fontSize: 13, color: AppColors.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (v) => _isTyping.value = v.trim().isNotEmpty,
                        onSubmitted: (_) => _sendMessage(),
                        onTap: () => _showEmojis.value = false,
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                    Obx(() => _isTyping.value
                        ? GestureDetector(
                            onTap: _sendMessage,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Icon(Icons.send_rounded, size: 20, color: AppColors.arenaAccent),
                            ),
                          )
                        : const SizedBox(width: 8)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Single emoji toggle button
            GestureDetector(
              onTap: () => _showEmojis.value = !_showEmojis.value,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.cardSurface.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: const Center(
                  child: Text('😊', style: TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A single chat bubble that appears with a fade-in animation.
class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.displayName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.arenaAccent,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                message.text,
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single floating emoji that animates upward and fades out.
class _FloatingEmoji extends StatefulWidget {
  final FloatingReaction reaction;
  final VoidCallback onComplete;

  const _FloatingEmoji({super.key, required this.reaction, required this.onComplete});

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _positionAnimation;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _scaleAnimation;
  final double _horizontalDrift = (Random().nextDouble() - 0.5) * 30;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    _positionAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.6, 1.0)),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.2), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 60),
    ]).animate(_controller);

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          bottom: _positionAnimation.value * 140,
          left: 10 + _horizontalDrift * _positionAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Text(
                widget.reaction.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
        );
      },
    );
  }
}
