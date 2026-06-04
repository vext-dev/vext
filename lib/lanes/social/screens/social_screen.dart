// ── SocialScreen — VEXT Lane B Social Mesh Chat ───────────────────────────────
//
// Chat-style screen for social mesh messaging.
//
// Layout:
//   ┌──────────────────────────────────────────┐
//   │  AppBar: "SOCIAL" + mesh status          │
//   ├──────────────────────────────────────────┤
//   │  Message list (newest at bottom)         │
//   │    • Outgoing: right-aligned blue bubble │
//   │    • Incoming: left-aligned grey bubble  │
//   │      └ sender UID (truncated) + time     │
//   ├──────────────────────────────────────────┤
//   │  Compose bar                             │
//   │    [TextField]  [Send button]            │
//   └──────────────────────────────────────────┘
//
// Data flow:
//   socialServiceProvider → SocialService.messageStream
//     → StreamBuilder<List<MessageRecord>> → ListView (reversed)
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_constants.dart';
import '../../../core/app_theme.dart';
import '../../../providers/providers.dart';
import '../../../services/drift_service.dart';

// Convenience local color aliases (mirrors SOS screen pattern)
const _kSurface = Color(0xFF0F1923);
const _kCard = Color(0xFF1A2535);
const _kTextPrimary = Color(0xFFE2E8F0);
const _kTextSecondary = Color(0xFF8BA3C0);
const _kHint = Color(0xFF4D6480);
const _kBubbleOut = Color(0xFF1E3A5F); // outgoing: dark blue
const _kBubbleIn = Color(0xFF1A2535);  // incoming: card surface
const _kBorder = Color(0xFF1A3352);

// ── SocialScreen ───────────────────────────────────────────────────────────────

class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final svc = ref.read(socialServiceProvider).valueOrNull;
    if (svc == null) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      await svc.sendMessage(text);
      // Scroll to bottom after send
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, // reversed list — 0.0 is the bottom (newest message)
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceAsync = ref.watch(socialServiceProvider);
    final currentUid =
        ref.watch(firebaseUidProvider).valueOrNull ?? '';

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: _kSurface,
        titleSpacing: 20,
        title: const Text(
          'SOCIAL',
          style: TextStyle(
            color: AppTheme.primaryColor,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
        actions: [
          _MeshStatusChip(
            serviceReady: serviceAsync.hasValue && !serviceAsync.hasError,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: serviceAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppTheme.primaryColor,
            strokeWidth: 2,
          ),
        ),
        error: (err, _) => _ServiceErrorView(error: err.toString()),
        data: (svc) => Column(
          children: [
            // ── Message list ─────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<List<MessageRecord>>(
                stream: svc.messageStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  final messages = snapshot.data ?? [];
                  if (messages.isEmpty) {
                    return const _EmptyState();
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    // Reversed so newest message is at the bottom visually;
                    // the Drift stream returns newest-first so index 0 = newest.
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isOwn = msg.senderUid == currentUid;
                      return _MessageBubble(
                        message: msg,
                        isOwn: isOwn,
                      );
                    },
                  );
                },
              ),
            ),

            // ── Compose bar ──────────────────────────────────────────────────
            _ComposeBar(
              controller: _controller,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mesh status chip ──────────────────────────────────────────────────────────

class _MeshStatusChip extends StatelessWidget {
  const _MeshStatusChip({required this.serviceReady});
  final bool serviceReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: serviceReady
            ? const Color(0x1A22C55E)
            : const Color(0x1A4B5563),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: serviceReady
              ? AppTheme.bleActiveColor
              : AppTheme.bleInactiveColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: serviceReady
                  ? AppTheme.bleActiveColor
                  : AppTheme.bleInactiveColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            serviceReady ? 'MESH ON' : 'OFFLINE',
            style: TextStyle(
              color: serviceReady
                  ? AppTheme.bleActiveColor
                  : AppTheme.bleInactiveColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────
//
// Converted to StatefulWidget so the Firestore name lookup future is created
// once in initState and never re-fired on rebuild (avoids flicker on scroll).
// Only incoming messages need a lookup — own messages never show a sender label.

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.isOwn,
  });

  final MessageRecord message;
  final bool isOwn;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  // Null for outgoing messages (no lookup needed).
  Future<String>? _nameFuture;

  @override
  void initState() {
    super.initState();
    if (!widget.isOwn) {
      _nameFuture = _fetchSenderName(widget.message.senderUid);
    }
  }

  /// Reads users/{uid}.name from Firestore.
  /// Falls back to first-8 chars of UID on any error.
  Future<String> _fetchSenderName(String uid) async {
    if (uid.isEmpty) return 'Unknown';
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.fsUsers)
          .doc(uid)
          .get();
      final name = (doc.data()?['name'] as String?)?.trim() ?? '';
      return name.isNotEmpty ? name : _shortUid(uid);
    } catch (_) {
      return _shortUid(uid);
    }
  }

  String _shortUid(String uid) =>
      uid.length > 8 ? uid.substring(0, 8) : uid;

  String _formatTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.hour)}:${pad(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: widget.isOwn ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: widget.isOwn ? _kBubbleOut : _kBubbleIn,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(widget.isOwn ? 16 : 4),
                bottomRight: Radius.circular(widget.isOwn ? 4 : 16),
              ),
              border: Border.all(
                color: widget.isOwn
                    ? AppTheme.primaryColor.withValues(alpha: 0.25)
                    : _kBorder,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: widget.isOwn
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Sender label — only for incoming messages
                if (!widget.isOwn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: FutureBuilder<String>(
                      future: _nameFuture,
                      builder: (context, snapshot) {
                        // While resolving: show short UID as placeholder.
                        // On resolve: show the real name (or UID fallback).
                        final label = snapshot.data ??
                            _shortUid(widget.message.senderUid);
                        return Text(
                          label,
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        );
                      },
                    ),
                  ),

                // Message content
                Text(
                  widget.message.contentEncrypted,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 4),

                // Timestamp
                Text(
                  _formatTime(widget.message.timestamp),
                  style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Compose bar ───────────────────────────────────────────────────────────────

class _ComposeBar extends StatelessWidget {
  const _ComposeBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(
          top: BorderSide(color: _kBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Text input
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !sending,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: _kTextPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Message the mesh…',
                hintStyle: const TextStyle(color: _kHint, fontSize: 14),
                filled: true,
                fillColor: _kCard,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(
                      color: AppTheme.primaryColor, width: 1.5),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),

          const SizedBox(width: 8),

          // Send button
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: sending
                ? const SizedBox(
                    key: ValueKey('loading'),
                    width: 44,
                    height: 44,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryColor,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                : Material(
                    key: const ValueKey('send'),
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      onTap: onSend,
                      borderRadius: BorderRadius.circular(22),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.chat_bubble_outline_rounded,
              color: _kHint, size: 48),
          SizedBox(height: 12),
          Text(
            'No messages yet',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Messages sent over BLE mesh — no internet required',
            style: TextStyle(color: _kHint, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Service error fallback ────────────────────────────────────────────────────

class _ServiceErrorView extends StatelessWidget {
  const _ServiceErrorView({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: AppTheme.sosColor, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Social unavailable',
              style: TextStyle(
                color: _kTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(color: _kTextSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
