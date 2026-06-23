// ── DirectMessageScreen — VEXT Lane B 1:1 Encrypted DM ────────────────────────
//
// Mirrors SocialScreen's layout (message list + compose bar) but scoped to a
// single peer's 1:1 thread, end-to-end encrypted with X25519 ECDH +
// AES-256-GCM (CryptoService). See SocialService.sendDirectMessage /
// .directMessageStream for the encryption + mesh/Firestore wiring.
//
// Reached via:
//   • Tapping a sender's name on an incoming broadcast message in SocialScreen
//   • Searching for a user by display name from SocialScreen's search action
//
// Data flow:
//   socialServiceProvider → SocialService.directMessageStream(peerUid)
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

// Same palette as SocialScreen — keep in sync with AppTheme
const _kSurface = Color(0xFF060E1A);
const _kCard = Color(0xFF0F1D30);
const _kTextPrimary = Color(0xFFEDF4FF);
const _kTextSecondary = Color(0xFF7EA8C8);
const _kHint = Color(0xFF3C6080);
const _kBubbleOut = Color(0xFF0A2840);
const _kBubbleIn = Color(0xFF0F1D30);
const _kBorder = Color(0xFF0D2646);

// ── DirectMessageScreen ────────────────────────────────────────────────────────

class DirectMessageScreen extends ConsumerStatefulWidget {
  const DirectMessageScreen({
    super.key,
    required this.peerUid,
    this.peerName,
  });

  /// UID of the peer this DM thread is with.
  final String peerUid;

  /// Display name passed in from the entry point (tap-name or search result).
  /// If null/empty, this screen resolves it itself via users/{uid}.name.
  final String? peerName;

  @override
  ConsumerState<DirectMessageScreen> createState() =>
      _DirectMessageScreenState();
}

class _DirectMessageScreenState extends ConsumerState<DirectMessageScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _resolvedName;

  @override
  void initState() {
    super.initState();
    if (widget.peerName == null || widget.peerName!.trim().isEmpty) {
      _fetchPeerName();
    }
  }

  Future<void> _fetchPeerName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.fsUsers)
          .doc(widget.peerUid)
          .get();
      final name = (doc.data()?['name'] as String?)?.trim() ?? '';
      if (!mounted) return;
      setState(() => _resolvedName = name.isNotEmpty ? name : _shortUid(widget.peerUid));
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolvedName = _shortUid(widget.peerUid));
    }
  }

  String _shortUid(String uid) => uid.length > 8 ? uid.substring(0, 8) : uid;

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
      await svc.sendDirectMessage(widget.peerUid, text);
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
    final currentUid = ref.watch(firebaseUidProvider).valueOrNull ?? '';

    final passedName = widget.peerName?.trim() ?? '';
    final title =
        passedName.isNotEmpty ? passedName : (_resolvedName ?? _shortUid(widget.peerUid));

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: _kSurface,
        titleSpacing: 4,
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: AppTheme.primaryColor, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
      body: serviceAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppTheme.primaryColor,
            strokeWidth: 2,
          ),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'DM unavailable: $err',
              style: const TextStyle(color: _kTextSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (svc) => Column(
          children: [
            // ── Message list ─────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<List<MessageRecord>>(
                stream: svc.directMessageStream(widget.peerUid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  final messages = snapshot.data ?? [];
                  if (messages.isEmpty) {
                    return const _DmEmptyState();
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isOwn = msg.senderUid == currentUid;
                      return _DmBubble(message: msg, isOwn: isOwn);
                    },
                  );
                },
              ),
            ),

            // ── Compose bar ──────────────────────────────────────────────────
            _DmComposeBar(
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

// ── Message bubble ────────────────────────────────────────────────────────────
//
// Simpler than SocialScreen's _MessageBubble — no sender-name lookup needed,
// the thread already has exactly one other participant (shown in the AppBar).

class _DmBubble extends StatelessWidget {
  const _DmBubble({required this.message, required this.isOwn});

  final MessageRecord message;
  final bool isOwn;

  String _formatTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.hour)}:${pad(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isOwn ? _kBubbleOut : _kBubbleIn,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isOwn ? 16 : 4),
                bottomRight: Radius.circular(isOwn ? 4 : 16),
              ),
              border: Border.all(
                color: isOwn
                    ? AppTheme.primaryColor.withValues(alpha: 0.25)
                    : _kBorder,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  message.contentEncrypted,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
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

class _DmComposeBar extends StatelessWidget {
  const _DmComposeBar({
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
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !sending,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: _kTextPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Encrypted message…',
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

class _DmEmptyState extends StatelessWidget {
  const _DmEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.lock_outline_rounded, color: _kHint, size: 48),
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
            'End-to-end encrypted — only you and this person can read these',
            style: TextStyle(color: _kHint, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
