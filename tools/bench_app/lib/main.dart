import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'wer.dart';

/// CEO Forge on-device AI benchmark harness.
/// Purpose: MEASURE, on the real phone, model load time, latency, memory,
/// ASR speed/accuracy and sustained-load behaviour. It never invents numbers:
/// every figure shown comes from a stopwatch, /proc, or a plugin call.
void main() => runApp(const MaterialApp(home: BenchPage()));

class BenchPage extends StatefulWidget {
  const BenchPage({super.key});
  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  final results = <String, Object?>{};
  final log = <String>[];
  Directory? modelDir;
  List<FileSystemEntity> files = [];
  String? gguf;
  final threads = TextEditingController(text: '4');
  final gpuLayers = TextEditingController(text: '0');
  final asrDir = TextEditingController(text: 'whisper');
  final asrLang = TextEditingController(text: 'en');
  final reference = TextEditingController();
  bool busy = false;

  void say(String s) => setState(() => log.add('${DateTime.now().toIso8601String().substring(11, 19)} $s'));

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    modelDir = await getExternalStorageDirectory();
    await _refresh();
    final di = await DeviceInfoPlugin().androidInfo;
    final mem = _meminfo();
    results['device'] = {
      'model': di.model,
      'manufacturer': di.manufacturer,
      'androidSdk': di.version.sdkInt,
      'supportedAbis': di.supportedAbis,
      'physicalRamMB': di.physicalRamSize,
      'availableRamMBAtStart': di.availableRamSize,
      'memTotalKB': mem['MemTotal'],
      'memAvailableKB': mem['MemAvailable'],
    };
    try {
      final gpu = await LlamaController().detectGpu();
      results['gpu'] = {
        'name': gpu.gpuName,
        'vulkanSupported': gpu.vulkanSupported,
        'recommendedGpuLayers': gpu.recommendedGpuLayers,
      };
    } catch (e) {
      results['gpu'] = {'error': '$e'};
    }
    setState(() {});
  }

  Future<void> _refresh() async {
    final d = modelDir;
    if (d == null) return;
    files = d.listSync();
    setState(() {});
  }

  Map<String, int> _meminfo() {
    final out = <String, int>{};
    for (final l in File('/proc/meminfo').readAsLinesSync()) {
      final m = RegExp(r'^(\w+):\s+(\d+)').firstMatch(l);
      if (m != null) out[m.group(1)!] = int.parse(m.group(2)!);
    }
    return out;
  }

  /// Resident set size of THIS process in KB (native allocations included).
  int _rssKb() {
    for (final l in File('/proc/self/status').readAsLinesSync()) {
      if (l.startsWith('VmRSS:')) return int.parse(RegExp(r'\d+').firstMatch(l)!.group(0)!);
    }
    return -1;
  }

  Future<void> _guard(String name, Future<void> Function() f) async {
    if (busy) return;
    setState(() => busy = true);
    say('START $name');
    try {
      await f();
      say('DONE $name');
    } catch (e, st) {
      results['${name}_error'] = '$e';
      say('FAILED $name: $e\n$st');
    }
    setState(() => busy = false);
  }

  // ---------------------------------------------------------------- LLM
  static const _system =
      'You are Mr. Hale, a demanding luxury homeowner negotiating a KNX smart-home quote. '
      'Stay in character. Reply in at most 2 sentences. React to what the user actually said.';
  static const _userTurns = [
    'I can give you ten percent off if you sign today.',
    'What are the other quotes including, and what matters most to you?',
    'If you confirm the lighting scope and a 40 percent deposit, I can look at five percent.',
  ];

  Future<void> _benchLlm() => _guard('llm', () async {
        final path = gguf;
        if (path == null) throw StateError('Select a .gguf file first');
        final c = LlamaController();
        final battery = Battery();
        final rss0 = _rssKb();
        final bat0 = await battery.batteryLevel;
        final sw = Stopwatch()..start();
        await c.loadModel(
            modelPath: path,
            threads: int.parse(threads.text),
            contextSize: 2048,
            gpuLayers: int.tryParse(gpuLayers.text));
        final loadMs = sw.elapsedMilliseconds;
        final rssLoaded = _rssKb();
        say('loaded in ${loadMs}ms, RSS ${rssLoaded ~/ 1024}MB');

        final runs = <Map<String, Object?>>[];
        // 12 sequential generations = sustained load. Falling tokens/s over the
        // run is a throttling indicator, NOT a temperature reading.
        for (var i = 0; i < 12; i++) {
          final turn = _userTurns[i % _userTurns.length];
          var first = -1, chunks = 0;
          final sb = StringBuffer();
          final t = Stopwatch()..start();
          await for (final tok in c.generateChat(
            messages: [
              ChatMessage(role: 'system', content: _system),
              ChatMessage(role: 'user', content: turn),
            ],
            maxTokens: 80,
            temperature: 0.7,
          )) {
            if (first < 0) first = t.elapsedMilliseconds;
            chunks++;
            sb.write(tok);
          }
          final total = t.elapsedMilliseconds;
          final decodeMs = total - (first < 0 ? 0 : first);
          runs.add({
            'i': i,
            'ttftMs': first,
            'totalMs': total,
            'streamedChunks': chunks, // chunks != tokens for every plugin; treat as approximate
            'chunksPerSecDecode': decodeMs > 0 ? (chunks - 1) * 1000 / decodeMs : null,
            'rssMB': _rssKb() ~/ 1024,
            'reply': sb.toString(),
          });
          say('run $i ttft=${first}ms total=${total}ms rss=${_rssKb() ~/ 1024}MB');
        }
        final bat1 = await battery.batteryLevel;
        results['llm'] = {
          'file': path.split('/').last,
          'fileSizeMB': File(path).lengthSync() ~/ (1024 * 1024),
          'threads': threads.text,
          'gpuLayers': gpuLayers.text,
          'loadMs': loadMs,
          'rssBeforeMB': rss0 ~/ 1024,
          'rssAfterLoadMB': rssLoaded ~/ 1024,
          'batteryPctBefore': bat0,
          'batteryPctAfter': bat1,
          'runs': runs,
        };
        await c.dispose();
      });

  // ---------------------------------------------------------------- ASR
  String? _wav;

  Future<void> _record() => _guard('record', () async {
        final rec = AudioRecorder();
        if (!await rec.hasPermission()) throw StateError('Microphone permission denied');
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/bench.wav';
        await rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
        say('recording 15 s: read the reference text aloud');
        await Future<void>.delayed(const Duration(seconds: 15));
        await rec.stop();
        await rec.dispose();
        _wav = path;
        say('saved $path (${File(path).lengthSync()} bytes)');
      });

  Future<void> _benchAsr() => _guard('asr', () async {
        final wav = _wav;
        final d = modelDir;
        if (wav == null || d == null) throw StateError('Record audio first');
        final dir = '${d.path}/${asrDir.text}';
        // Expects sherpa-onnx Whisper files: *-encoder.int8.onnx, *-decoder.int8.onnx, *-tokens.txt
        final names = Directory(dir).listSync().map((e) => e.path).toList();
        String pick(String suffix) => names.firstWhere((n) => n.endsWith(suffix),
            orElse: () => throw StateError('No *$suffix in $dir'));
        final enc = names.firstWhere((n) => n.contains('encoder') && n.endsWith('.onnx'));
        final dec = names.firstWhere((n) => n.contains('decoder') && n.endsWith('.onnx'));
        final tok = pick('tokens.txt');

        sherpa.initBindings();
        final rss0 = _rssKb();
        final sw = Stopwatch()..start();
        final recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
                encoder: enc, decoder: dec, language: asrLang.text, task: 'transcribe'),
            tokens: tok,
            numThreads: int.parse(threads.text),
            debug: false,
          ),
        ));
        final loadMs = sw.elapsedMilliseconds;
        final rssLoaded = _rssKb();

        final bytes = File(wav).readAsBytesSync();
        final samples = _wavToFloat(bytes); // 16 kHz mono PCM16, 44-byte header
        final audioSec = samples.length / 16000;
        sw
          ..reset()
          ..start();
        final stream = recognizer.createStream();
        stream.acceptWaveform(samples: samples, sampleRate: 16000);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text;
        final decodeMs = sw.elapsedMilliseconds;
        stream.free();
        recognizer.free();
        results['asr'] = {
          'modelDir': asrDir.text,
          'language': asrLang.text,
          'loadMs': loadMs,
          'rssBeforeMB': rss0 ~/ 1024,
          'rssAfterLoadMB': rssLoaded ~/ 1024,
          'audioSeconds': audioSec,
          'decodeMs': decodeMs,
          'realTimeFactor': decodeMs / 1000 / audioSec, // <1 is faster than real time
          'transcript': text,
          'reference': reference.text,
          'wer': wordErrorRate(reference.text, text),
        };
        say('asr rtf=${(decodeMs / 1000 / audioSec).toStringAsFixed(2)} wer=${wordErrorRate(reference.text, text)}');
      });

  Float32List _wavToFloat(Uint8List b) {
    final bd = ByteData.sublistView(b);
    final n = (b.length - 44) ~/ 2;
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(44 + i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  // ---------------------------------------------------------------- UI
  Future<void> _save() async {
    final d = await getApplicationDocumentsDirectory();
    final f = File('${d.path}/bench_results.json');
    final text = const JsonEncoder.withIndent('  ').convert(results);
    await f.writeAsString(text);
    await Clipboard.setData(ClipboardData(text: text));
    say('saved ${f.path} and copied to clipboard');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('CEO Forge bench')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const Text(
              '1) Enable airplane mode. 2) adb push models to the folder below. 3) Run LLM bench, record, run ASR bench. 4) Save and send me the JSON.'),
          SelectableText('Model folder: ${modelDir?.path}'),
          Wrap(spacing: 8, children: [
            for (final f in files.whereType<File>().where((f) => f.path.endsWith('.gguf')))
              ChoiceChip(
                label: Text(f.path.split('/').last),
                selected: gguf == f.path,
                onSelected: (_) => setState(() => gguf = f.path),
              ),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: threads, decoration: const InputDecoration(labelText: 'threads'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: gpuLayers, decoration: const InputDecoration(labelText: 'gpu layers (0=CPU)'))),
          ]),
          FilledButton(onPressed: busy ? null : _benchLlm, child: const Text('Run LLM benchmark (12 sustained turns)')),
          const Divider(),
          Row(children: [
            Expanded(child: TextField(controller: asrDir, decoration: const InputDecoration(labelText: 'ASR subfolder (sherpa-onnx whisper)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: asrLang, decoration: const InputDecoration(labelText: 'language'))),
          ]),
          TextField(controller: reference, maxLines: 3, decoration: const InputDecoration(labelText: 'Reference text you will read aloud')),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: busy ? null : _record, child: const Text('Record 15 s'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: busy ? null : _benchAsr, child: const Text('Run ASR benchmark'))),
          ]),
          const Divider(),
          FilledButton(onPressed: _save, child: const Text('Save + copy results JSON')),
          if (busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          SelectableText(log.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ]),
      );
}
