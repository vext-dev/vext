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
  StreamSubscription? _sub;

  void _log(String msg) {
    final ts = DateTime.now().toString().substring(11, 23);
    setState(() => _logs.insert(0, '[$ts] $msg'));
  }

  @override
  void initState() {
    super.initState();
    ref.read(meshServiceProvider.future).then((mesh) {
      _sub = mesh.sosPackets.listen((p) {
        _log('SOS RECEIVED  id=${p.id.substring(0,8)} ttl=${p.ttl} from=${p.senderUid}');
      });
      mesh.attendancePackets.listen((p) {
        _log('ATTN RECEIVED id=${p.id.substring(0,8)} ttl=${p.ttl}');
      });
      _log('Mesh initialized. Ready.');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _sendSos() async {
    final mesh = await ref.read(meshServiceProvider.future);
    final id = const Uuid().v4();
    await mesh.sendPacket(MeshPacket.sos(
      id: id,
      senderUid: 'tester-${id.substring(0,4)}',
      latitude: 12.9716,
      longitude: 77.5946,
    ));
    _log('SOS SENT      id=${id.substring(0,8)} ttl=255');
  }

  Future<void> _sendAttendance() async {
    final mesh = await ref.read(meshServiceProvider.future);
    final id = const Uuid().v4();
    await mesh.sendPacket(MeshPacket.attendance(
      id: id,
      senderUid: 'tester-${id.substring(0,4)}',
      sessionId: 'test-session-001',
      hmacToken: 'testtoken123',
    ));
    _log('ATTN SENT     id=${id.substring(0,8)} ttl=5');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VEXT Mesh Test')),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _sendSos,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Send SOS', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                onPressed: _sendAttendance,
                child: const Text('Send Attendance'),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(_logs[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}