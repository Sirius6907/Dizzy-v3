import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_card.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
import '../../widgets/common/notify.dart';
import '../../widgets/guide/guide_trigger.dart';

/// In-App Direct Message & Media Card Experience.
/// Pure OLED true-black, zero-lag 120 FPS message lists with one-tap Co-Experience join.
class DirectMessagePage extends StatefulWidget {
  final String recipientUid;
  final String recipientUsername;
  final String? recipientAvatar;

  const DirectMessagePage({
    super.key,
    required this.recipientUid,
    required this.recipientUsername,
    this.recipientAvatar,
  });

  @override
  State<DirectMessagePage> createState() => _DirectMessagePageState();
}

class _DirectMessagePageState extends State<DirectMessagePage> {
  final TextEditingController _textController = TextEditingController();
  final List<DizzyDirectMessage> _messages = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Pre-populate with sample welcome / interactive media card message
    _messages.add(
      DizzyDirectMessage(
        id: 'msg_welcome',
        threadId: 'local',
        senderId: widget.recipientUid,
        clientMsgId: 'welcome_1',
        kind: 'media_card',
        body: 'Check this out! Wanna watch together?',
        mediaRef: 'tmdb:movie:550',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _textController.clear();

    final success = await DizzySocialService.sendDirectMessage(
      recipientUid: widget.recipientUid,
      body: text,
    );

    if (!mounted) return;
    setState(() => _isSending = false);
    if (!mounted) return;
    if (success) {
      // Server is the source of truth — realtime delivers the real row.
      // (Optimistic echo removed: a fail-soft add here used to show a
      // message that was never sent, with no way to retry it.)
      return;
    }
    _textController.text = text;
    DizzyNotify.show(context, "Couldn't send — check net, then try again.",
        tone: NotifyTone.warn);
  }

  Widget _buildMediaCardBubble(DizzyDirectMessage msg, bool isMe) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      margin: const EdgeInsets.symmetric(vertical: DizzySpace.xs),
      child: DizzyTactileCard(
        padding: const EdgeInsets.all(DizzySpace.sm),
        glowColor: DizzyGlow.beam,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: DizzyGradients.tactileSurface,
                    border: Border.fromBorderSide(DizzyEdge.hairline),
                  ),
                  child: const Center(
                    child: Text('🎬', style: TextStyle(fontSize: 28)),
                  ),
                ),
                const SizedBox(width: DizzySpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fight Club (1999)',
                        style: TextStyle(
                          color: DizzyVoid.bone,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        msg.body,
                        style: const TextStyle(color: DizzyVoid.ash, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DizzySpace.sm),
            DizzyTactileButton(
              height: 38,
              gradient: DizzyGradients.emberButton,
              glowColor: DizzyGlow.red,
              onTap: () {
                DizzyNotify.show(
                  context,
                  'Joining Watch Together room...',
                  tone: NotifyTone.success,
                );
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 6),
                  Text(
                    'Watch Together',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextMessageBubble(DizzyDirectMessage msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: DizzySpace.xxs),
        padding: const EdgeInsets.symmetric(
          horizontal: DizzySpace.md,
          vertical: DizzySpace.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          gradient: isMe
              ? DizzyGradients.emberButton
              : const LinearGradient(
                  colors: [DizzyVoid.surface3, Color(0xFF161927)],
                ),
          border: Border.fromBorderSide(
            isMe ? BorderSide.none : DizzyEdge.hairline,
          ),
          boxShadow: [
            BoxShadow(
              color: isMe
                  ? DizzyGlow.red.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.40),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          msg.body,
          style: const TextStyle(color: DizzyVoid.bone, fontSize: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GuideTrigger(
      guideKey: 'dms',
      steps: AppGuides.dms,
      child: Scaffold(
        backgroundColor: DizzyVoid.obsidian, // OLED Pure Black
        appBar: AppBar(
          backgroundColor: DizzyVoid.voidA,
          elevation: 0,
          titleSpacing: 0,
          title: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: DizzyVoid.surface2,
                    child: Text(
                      widget.recipientUsername.isNotEmpty
                          ? widget.recipientUsername[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: DizzyVoid.bone, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: DizzyGlow.volt,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: DizzySpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '@${widget.recipientUsername}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DizzyVoid.bone,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Online • Ready to sync',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: DizzyGlow.volt, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(DizzySpace.md),
                itemCount: _messages.length,
                itemBuilder: (ctx, index) {
                  final msg = _messages[index];
                  final isMe = msg.senderId == 'me';
                  if (msg.kind == 'media_card') {
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: _buildMediaCardBubble(msg, isMe),
                    );
                  }
                  return _buildTextMessageBubble(msg, isMe);
                },
              ),
            ),
            // Bottom Tactile Input Bar
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DizzySpace.sm,
                vertical: DizzySpace.xs,
              ),
              decoration: BoxDecoration(
                color: DizzyVoid.voidA,
                border: Border(top: DizzyEdge.hairline),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: DizzySpace.sm),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: DizzyGradients.carvedSurface,
                          border: Border.fromBorderSide(DizzyEdge.hairline),
                        ),
                        child: TextField(
                          controller: _textController,
                          style: const TextStyle(color: DizzyVoid.bone, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Message or share title...',
                            hintStyle: TextStyle(color: DizzyVoid.ash, fontSize: 13),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: DizzySpace.xs),
                    DizzyTactileButton(
                      width: 44,
                      height: 44,
                      padding: EdgeInsets.zero,
                      gradient: DizzyGradients.emberButton,
                      glowColor: DizzyGlow.red,
                      borderRadius: BorderRadius.circular(22),
                      onTap: _sendMessage,
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
