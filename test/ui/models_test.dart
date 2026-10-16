import 'package:ceo_forge/ai/ai_state.dart';
import 'package:ceo_forge/ai/local_model.dart';
import 'package:ceo_forge/app_state.dart';
import 'package:ceo_forge/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ai/local_model_test.dart' show FakeRuntime;
import 'flow_test.dart' show MemoryRepo;

class Fs implements ModelFs {
  Fs(this.sizes);
  final Map<String, int> sizes;
  @override
  Future<int?> sizeOf(String path) async => sizes[path];
  @override
  Future<String> sha256Of(String path) async => 'a' * 64;
}

class FailingLoadRuntime extends FakeRuntime {
  @override
  Future<Duration> load(String path, {int threads = 4, int contextSize = 2048, int? gpuLayers}) async =>
      throw StateError('bad gguf');
}

Future<void> pump(WidgetTester t, {required Map<String, int> files, LocalModelRuntime? runtime}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(MemoryRepo()),
      modelDirProvider.overrideWith((ref) async => '/m'),
      modelFsProvider.overrideWithValue(Fs(files)),
      if (runtime != null) modelRuntimeProvider.overrideWithValue(runtime),
    ],
    child: const CeoForgeApp(),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Models'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('nothing installed: shows Not installed, states the experimental limits, no load button', (t) async {
    await pump(t, files: {}, runtime: FakeRuntime(loaded: false));
    expect(find.text('Not installed'), findsNWidgets(2));
    expect(find.textContaining('never affects scores'), findsOneWidget);
    expect(find.text('Load for role-play'), findsNothing);
  });

  testWidgets('file present is "integrity not verified" (never Verified) and hashing shows the digest but not "verified"', (t) async {
    await pump(t, files: {'/m/Qwen3-1.7B-Q4_K_M.gguf': 1048576 * 1100}, runtime: FakeRuntime(loaded: false));
    expect(find.textContaining('integrity not verified'), findsOneWidget);
    expect(find.textContaining('1100 MB'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
    await t.tap(find.text('Compute SHA-256'));
    await t.pumpAndSettle();
    expect(find.textContaining('cannot be called verified'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('no runtime on this build: says so and cannot load', (t) async {
    await pump(t, files: {'/m/Qwen3-1.7B-Q4_K_M.gguf': 5000000});
    expect(find.textContaining('no local-model runtime'), findsOneWidget);
    final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Load for role-play'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('successful load shows load time only, with the not-a-quality-test disclaimer; unload works', (t) async {
    final rt = FakeRuntime(loaded: false);
    await pump(t, files: {'/m/Qwen3-1.7B-Q4_K_M.gguf': 5000000}, runtime: rt);
    await t.tap(find.text('Load for role-play'));
    await t.pumpAndSettle();
    expect(rt.isLoaded, isTrue);
    expect(find.textContaining('Loaded in 5 ms'), findsOneWidget);
    expect(find.textContaining('not a quality or speed test'), findsOneWidget);
    await t.tap(find.text('Unload'));
    await t.pumpAndSettle();
    expect(rt.isLoaded, isFalse);
  });

  testWidgets('a model that fails to load shows an error and the app keeps working', (t) async {
    await pump(t, files: {'/m/Qwen3-1.7B-Q4_K_M.gguf': 5000000}, runtime: FailingLoadRuntime());
    await t.tap(find.text('Load for role-play'));
    await t.pumpAndSettle();
    expect(find.textContaining('Could not load'), findsOneWidget);
    expect(find.textContaining('scripted replies'), findsOneWidget);
    await t.tap(find.text('Today'));
    await t.pumpAndSettle();
    expect(find.text('Start session'), findsOneWidget);
  });

  testWidgets('with a loaded model, the live session uses reworded persona lines and still finishes', (t) async {
    final rt = FakeRuntime(loaded: false, chunks: ['Hmm, so there is flexibility in your price after all.']);
    await pump(t, files: {'/m/Qwen3-1.7B-Q4_K_M.gguf': 5000000}, runtime: rt);
    await t.tap(find.text('Load for role-play'));
    await t.pumpAndSettle();
    await t.tap(find.text('Today'));
    await t.pumpAndSettle();
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Okay, I can give you 10 percent off the whole quote right now to close this today.');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.textContaining('there is flexibility in your price'), findsOneWidget);
    expect(find.textContaining('room in your price all along'), findsNothing);
  });
}
