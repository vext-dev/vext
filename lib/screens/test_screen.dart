// ── TestScreen — Milestone 3 BLE Mesh Testing UI ──────────────────────────────
//
// Temporary screen for manual mesh testing. Remove after Milestone 3 sign-off.
//
// What it does:
//   • Calls bleStateProvider.startIdle() on init to start BLE scanning/advertising.
//     Without this, _peerDevices in BleTransportLayer is always empty and
//     broadcastPacket() silently no-ops (no peers to write to).
//   • Subscribes to sosPackets, attendancePackets, AND messagePackets streams
//     from MeshService (all 3 lanes: A, B, C).
//   • Shows live on-screen log of sent and received packets.
//   • Displays peer count from BLE state.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // ALL three lane subscriptions must be stored so they can be cancelled in dispose().
  StreamSubscription<MeshPacket>? _sosSub;
  StreamSubscription<MeshPacket>? _attnSub;
  StreamSubscription<MeshPacket>? _msgSub; // Lane B — Social

  void _log(String msg) {
    final ts = DateTime.now().toString().substring(11, 23);
    if (mounted) {
      setState(() => _logs.insert(0, '[$ts] $msg'));
    }
  }

  @override
  void initState() {
    super.initState();

    // ── Start BLE scanning + advertising ──────────────────────────────────────
    // CRITICAL: without this, BleTransportLayer._peerDevices stays empty and
    // broadcastPacket() silently no-ops. Must be called before sendPacket().
    ref.read(bleStateProvider.notifier).startIdle();

    // ── Wire MeshService lane streams ─────────────────────────────────────────
    ref.read(meshServiceProvider.future).then((mesh) {
      if (!mounted) return;

      _sosSub = mesh.sosPackets.listen((p) {
        _log('SOS RECEIVED  id=${p.id.substring(0, 8)}  ttl=${p.ttl}  from=${p.senderUid}');
      });

      _attnSub = mesh.attendancePackets.listen((p) {
        _log('ATTN RECEIVED id=${p.id.substring(0, 8)}  ttl=${p.ttl}');
      });

      // Lane B — Social messaging
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
    _msgSub?.cancel(); // Lane B — must be cancelled to avoid stream leak
    // BLE continues running intentionally — MainActivity.onDestroy() cleans up.
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
          // Live peer count badge
          Padding(
            padding: const EdgeInsets.only(right: 16),
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
        ],
      ),
      body: Column(
        children: [
          // ── Buttons ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Row 1: SOS + Attendance (Lane C and Lane A)
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
                // Row 2: Social Message (Lane B) — full width
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: Colors.white),
                    label: const Text('Send Social Message',
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669), // emerald green
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Status bar ──────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: const Color(0xFF111827),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
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
                              ? const Color(0xFF22C55E)  // green
                              : _logs[i].contains('MSG  SENT')
                                  ? const Color(0xFF34D399) // emerald
                                  : _logs[i].contains('SENT')
                                      ? const Color(0xFF60A5FA) // blue
                                      : const Color(0xFF8BA3C0), // grey
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
