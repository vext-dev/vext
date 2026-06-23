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
import 'package:go_router/go_router.dart';

import '../../../core/app_constants.dart';
import '../../../core/app_theme.dart';
import '../../../providers/providers.dart';
import '../../../services/drift_service.dart';
import '../social_service.dart';

// Convenience local color aliases — keep in sync with AppTheme
const _kSurface = Color(0xFF060E1A); // AppTheme.backgroundColor
const _kCard = Color(0xFF0F1D30); // AppTheme.cardColor
const _kTextPrimary = Color(0xFFEDF4FF); // AppTheme.primaryTextColor
const _kTextSecondary = Color(0xFF7EA8C8); // AppTheme.secondaryTextColor
const _kHint = Color(0xFF3C6080); // AppTheme.hintTextColor
const _kBubbleOut = Color(0xFF0A2840); // outgoing: deep cyan-tinted dark
const _kBubbleIn = Color(0xFF0F1D30); // incoming: card surface
const _kBorder = Color(0xFF0D2646); // AppTheme.inputBorderColor

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

  /// Opens the 1:1 encrypted DM thread with [peerUid].
  /// Entry points: tapping a sender's name on a broadcast message, or
  /// selecting a result from the user search sheet.
  void _openDirectMessage(String peerUid, String peerName) {
    if (peerUid.isEmpty) return;
    context.push('/home/social/dm/$peerUid', extra: peerName);
  }

  Future<void> _openUserSearch() async {
    final svc = ref.read(socialServiceProvider).valueOrNull;
    if (svc == null) return;
    final selected = await showModalBottomSheet<({String uid, String name})>(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _UserSearchSheet(service: svc),
    );
    if (selected != null && mounted) {
      _openDirectMessage(selected.uid, selected.name);
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
          IconButton(
            tooltip: 'New direct message',
            icon: const Icon(Icons.person_search_rounded,
                color: AppTheme.primaryColor, size: 22),
            onPressed: serviceAsync.hasValue ? _openUserSearch : null,
          ),
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
                        onTapSender: isOwn ? null : _openDirectMessage,
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
    this.onTapSender,
  });

  final MessageRecord message;
  final bool isOwn;

  /// Called with (senderUid, resolvedName) when the sender label is tapped.
  /// Null for own messages (no point DM'ing yourself) — see SocialScreen's
  /// itemBuilder, which only passes this for incoming messages.
  final void Function(String uid, String name)? onTapSender;

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
                // Sender label — only for incoming messages.
                // Tappable: opens a 1:1 encrypted DM with this sender (see
                // SocialScreen._openDirectMessage). This is the "tap a name"
                // DM entry point.
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
                        final text = Text(
                          label,
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            decoration: TextDecoration.underline,
                            decorationColor: AppTheme.primaryColor,
                          ),
                        );
                        if (widget.onTapSender == null) return text;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onTapSender!(
                              widget.message.senderUid, label),
                          child: text,
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

// ── User search sheet ─────────────────────────────────────────────────────────
//
// The "search using the username" DM entry point. There's no separate
// username field in this app — search is by display name (users/{uid}.name),
// matching SocialService.searchUsersByName and the existing sender-name
// lookup pattern used elsewhere in this screen.
//
// Pops with the selected (uid, name) record, or null if dismissed.

class _UserSearchSheet extends StatefulWidget {
  const _UserSearchSheet({required this.service});

  final SocialService service;

  @override
  State<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<_UserSearchSheet> {
  final _searchController = TextEditingController();
  List<({String uid, String name})> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.service.searchUsersByName(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Search failed: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _kBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'NEW MESSAGE',
            style: TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: _kTextPrimary, fontSize: 14),
            onChanged: _runSearch,
            decoration: InputDecoration(
              hintText: 'Search by name…',
              hintStyle: const TextStyle(color: _kHint, fontSize: 14),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: _kHint, size: 20),
              filled: true,
              fillColor: _kCard,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                borderSide:
                    const BorderSide(color: AppTheme.primaryColor, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
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
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: AppTheme.sosColor, fontSize: 12),
                        ),
                      )
                    : _results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              _searchController.text.trim().isEmpty
                                  ? 'Type a name to find someone'
                                  : 'No matches',
                              style: const TextStyle(
                                  color: _kTextSecondary, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final r = _results[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: _kCard,
                                  child: Text(
                                    r.name.isNotEmpty
                                        ? r.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: AppTheme.primaryColor),
                                  ),
                                ),
                                title: Text(
                                  r.name,
                                  style: const TextStyle(
                                      color: _kTextPrimary, fontSize: 14),
                                ),
                                onTap: () => Navigator.of(context).pop(r),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
