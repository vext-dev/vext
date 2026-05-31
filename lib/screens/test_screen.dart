// ── TestScreen — Milestone 3 BLE Mesh Testing UI ──────────────────────────────
//
// Temporary screen for manual mesh testing. Remove after Milestone 3 sign-off.
//
// What it does:
//   • Calls bleStateProvider.startSession() on init — session duty cycle
//     (500 ms scan / 500 ms sleep) for fast peer discovery during testing.
//     [Previously used startIdle() (1s/30s) which was too slow for test sessions]
//   • Requests BLUETOOTH_ADVERTISE via BleTransportLayer._requestBlePermissions().
//     Advertising success/failure is now visible in the status bar and via a
//     warning banner — no longer silently swallowed.
//   • Subscribes to sosPackets, attendancePackets, messagePackets (all 3 lanes).
//   • Shows live peer count and advertising state in AppBar.
//   • Logout button in AppBar (accessible before home shell is routed).
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/proto/mesh_packet.dart';
import '../providers/providers.dart';

class TestScreen extends ConsumerStatefulWidget {
  const TestScreen({super.key});

  @override
  ConsumerState<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends ConsumerState<TestScreen> {
  final _logs = <String>[];

  StreamSubscription<MeshPacket>? _sosSub;
  StreamSubscription<MeshPacket>? _attnSub;
  StreamSubscription<MeshPacket>? _msgSub;

  void _log(String msg) {
    final ts = DateTime.now().toString().substring(11, 23);
    if (mounted) {
      setState(() => _logs.insert(0, '[$ts] $msg'));
    }
  }

  @override
  void initState() {
    super.initState();

    // Use SESSION duty cycle (500 ms / 500 ms = 50%) for the test screen —
    // much faster peer discovery than idle (1 s / 30 s = 3%).
    // Permission request for BLUETOOTH_ADVERTISE is triggered inside start().
    ref.read(bleStateProvider.notifier).startSession();

    ref.read(meshServiceProvider.future).then((mesh) {
      if (!mounted) return;

      _sosSub = mesh.sosPackets.listen((p) {
        _log('SOS RECEIVED  id=${p.id.substring(0, 8)}  ttl=${p.ttl}  from=${p.senderUid}');
      });

      _attnSub = mesh.attendancePackets.listen((p) {
        _log('ATTN RECEIVED id=${p.id.substring(0, 8)}  ttl=${p.ttl}');
      });

      _msgSub = mesh.messagePackets.listen((p) {
        final content = p.decodeMessageContent() ?? '<binary>';
        _log('MSG  RECEIVED id=${p.id.substring(0, 8)}  ttl=${p.ttl}  "${content.substring(0, content.length.clamp(0, 24))}"');
      });

      _log('Mesh initialized. BLE scanning started. Ready.');
    });
  }

  @override
  void dispose() {
    _sosSub?.cancel();
    _attnSub?.cancel();
    _msgSub?.cancel();
    super.dispose();
  }

  // ── Packet senders ─────────────────────────────────────────────────────────

  Future<void> _sendSos() async {
    final mesh = await ref.read(meshServiceProvider.future);
    final id = const Uuid().v4();
    await mesh.sendPacket(MeshPacket.sos(
      id: id,
      senderUid: 'tester-${id.substring(0, 4)}',
      latitude: 12.9716,
      longitude: 77.5946,
    ));
    _log('SOS SENT      id=${id.substring(0, 8)}  ttl=255');
  }

  Future<void> _sendAttendance() async {
    final mesh = await ref.read(meshServiceProvider.future);
    final id = const Uuid().v4();
    await mesh.sendPacket(MeshPacket.attendance(
      id: id,
      senderUid: 'tester-${id.substring(0, 4)}',
      sessionId: 'test-session-001',
      hmacToken: 'testtoken123',
    ));
    _log('ATTN SENT     id=${id.substring(0, 8)}  ttl=5');
  }

  Future<void> _sendMessage() async {
    final mesh = await ref.read(meshServiceProvider.future);
    final id = const Uuid().v4();
    await mesh.sendPacket(MeshPacket.message(
      id: id,
      senderUid: 'tester-${id.substring(0, 4)}',
      contentEncrypted: 'hello from ${id.substring(0, 4)}',
    ));
    _log('MSG  SENT     id=${id.substring(0, 8)}  ttl=7');
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleStateProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1120),
        title: const Text(
          'VEXT Mesh Test',
          style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
        ),
        actions: [
          // Advertising state indicator
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              bleState.advertisingActive
                  ? Icons.broadcast_on_personal
                  : Icons.broadcast_on_personal_outlined,
              color: bleState.advertisingActive
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFEF4444),
              size: 20,
            ),
          ),

          // Live peer count badge
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              backgroundColor: bleState.peerCount > 0
                  ? const Color(0xFF1E3A5F)
                  : const Color(0xFF1A1A2E),
              label: Text(
                '${bleState.peerCount} peer${bleState.peerCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color: bleState.peerCount > 0
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF4D7096),
                  fontSize: 12,
                ),
              ),
            ),
          ),

          // Logout
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF8BA3C0)),
            tooltip: 'Sign Out',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF0F2035),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Text('Sign Out',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  content: const Text(
                    'Are you sure you want to sign out?',
                    style: TextStyle(color: Color(0xFF8BA3C0)),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel',
                          style: TextStyle(color: Color(0xFF8BA3C0))),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Sign Out',
                          style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
              if (confirmed == true && mounted) {
                await ref.read(authServiceProvider).signOut();
                // No explicit context.go('/login') — router navigates
                // reactively via _RouterNotifier when authStateProvider
                // emits null. See profile_screen.dart _handleSignOut() note.
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Advertising error warning banner ───────────────────────────────
          // Only shown when advertising explicitly failed (permission denied etc.)
          if (bleState.advertisingError.isNotEmpty)
            _AdvertisingErrorBanner(error: bleState.advertisingError),

          // ── Send buttons ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _sendSos,
                        icon: const Icon(Icons.warning_amber_rounded,
                            color: Colors.white),
                        label: const Text('Send SOS',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _sendAttendance,
                        icon: const Icon(Icons.how_to_reg_rounded,
                            color: Colors.white),
                        label: const Text('Send Attendance',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1D4ED8),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: Colors.white),
                    label: const Text('Send Social Message',
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Status bar ─────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: const Color(0xFF111827),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                // Scan status
                Text(
                  bleState.isActive
                      ? '● BLE scanning active'
                      : '○ BLE not started',
                  style: TextStyle(
                    color: bleState.isActive
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 12),
                // Advertising status
                Text(
                  bleState.advertisingActive
                      ? '● Advertising'
                      : '○ Not advertising',
                  style: TextStyle(
                    color: bleState.advertisingActive
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFF59E0B), // amber warning
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF1E293B), height: 1),

          // ── Log area ────────────────────────────────────────────────────────
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'Waiting for mesh events…',
                      style: TextStyle(color: Color(0xFF4D7096), fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _logs[i],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: _logs[i].contains('RECEIVED')
                              ? const Color(0xFF22C55E)
                              : _logs[i].contains('MSG  SENT')
                                  ? const Color(0xFF34D399)
                                  : _logs[i].contains('SENT')
                                      ? const Color(0xFF60A5FA)
                                      : const Color(0xFF8BA3C0),
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

// ── Advertising error banner ──────────────────────────────────────────────────

class _AdvertisingErrorBanner extends StatelessWidget {
  const _AdvertisingErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF7F1D1D), // dark red background
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.broadcast_on_personal_outlined,
              color: Color(0xFFFCA5A5), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠ Advertising not running — peer discovery limited',
                  style: TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  error,
                  style: const TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
