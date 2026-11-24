// voice_memo_service.dart: "Snelle Spraaknotitie Coach": neemt een korte
// audio-memo op (AAC, .m4a) in de app-map op het toestel. De bestanden
// gaan niet naar Supabase; de sessie onthoudt alleen hoeveel er zijn.

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceMemoRecorder {
  AudioRecorder? _recorder;
  DateTime? startedAt;

  bool get isRecording => startedAt != null;

  /// false als er geen microfoontoestemming is.
  Future<bool> start({required int round}) async {
    final rec = _recorder ??= AudioRecorder();
    if (!await rec.hasPermission()) return false;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/coach_memos');
    await dir.create(recursive: true);
    final path = '${dir.path}/memo_${DateTime.now().millisecondsSinceEpoch}_r$round.m4a';
    await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    startedAt = DateTime.now();
    return true;
  }

  /// Pad van de opname, of null als er niets liep.
  Future<String?> stop() async {
    final rec = _recorder;
    if (rec == null || !isRecording) return null;
    startedAt = null;
    return rec.stop();
  }

  Future<void> dispose() async {
    final rec = _recorder;
    _recorder = null;
    if (rec == null) return;
    try {
      await rec.dispose();
    } catch (_) {}
  }
}
