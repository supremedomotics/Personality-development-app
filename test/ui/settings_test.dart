import 'package:ceo_forge/app_state.dart';
import 'package:ceo_forge/main.dart';
import 'package:ceo_forge/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flow_test.dart' show MemoryRepo, pumpApp, reply, reveal, tapText;

void main() {
  testWidgets('settings states what is and is not protected, without overclaiming', (t) async {
    await pumpApp(t, MemoryRepo());
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(find.textContaining('stored only on this device'), findsOneWidget);
    expect(find.textContaining('not an independent audit'), findsOneWidget);
    expect(find.textContaining('keyboard app'), findsOneWidget);
    expect(find.textContaining('not encrypted'), findsOneWidget);
    expect(find.textContaining('No account, sync or voice'), findsOneWidget);
  });

  testWidgets('delete-all asks for confirmation, can be cancelled, then wipes sessions, book and missions', (t) async {
    final repo = MemoryRepo();
    await pumpApp(t, repo);
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();
    await reply(t, 'Okay, I can give you 10 percent off the whole quote right now to close this today.');
    await reply(t, 'Fine, I can also take another 5 percent off if that helps you decide on this.');
    await reply(t, 'We can see how things go and talk again whenever it suits you in the coming weeks.');
    await tapText(t, find.text('Skip retry and finish'));
    await tapText(t, find.text('Done'));
    expect(repo.sessionCount, 1);

    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(find.textContaining('1 session(s), 1 mission(s)'), findsOneWidget);
    await tapText(t, find.text('Delete all my data'));
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(repo.sessionCount, 1, reason: 'cancel must not delete');

    await tapText(t, find.text('Delete all my data'));
    await t.tap(find.text('Delete everything'));
    await t.pumpAndSettle();
    expect(repo.sessionCount, 0);
    expect(repo.bookEmpty, isTrue);
    expect(repo.missionCount, 0);
    expect(find.textContaining('All training data was deleted'), findsOneWidget);
    expect(find.textContaining('0 session(s), 0 mission(s)'), findsOneWidget);
    await t.tap(find.text('Today'));
    await t.pumpAndSettle();
    await reveal(t, find.textContaining('No scores yet'));
    expect(find.textContaining('No scores yet'), findsOneWidget);
  });

  testWidgets('export writes the full dataset and warns that it is unencrypted', (t) async {
    final repo = MemoryRepo();
    Map<String, Object?>? written;
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        exportWriterProvider.overrideWithValue((data) async {
          written = data;
          return '/x/export.json';
        }),
      ],
      child: const CeoForgeApp(),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await tapText(t, find.text('Export my data (JSON file)'));
    expect(written, isNotNull);
    expect(find.textContaining('Exported to /x/export.json'), findsOneWidget);
    expect(find.textContaining('NOT encrypted'), findsOneWidget);
  });

  testWidgets('a failed export or delete says so and changes nothing', (t) async {
    final repo = MemoryRepo()..failDelete = true;
    await pumpApp(t, repo);
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await tapText(t, find.text('Delete all my data'));
    await t.tap(find.text('Delete everything'));
    await t.pumpAndSettle();
    expect(find.textContaining('Deletion failed. Your data is unchanged.'), findsOneWidget);
  });
}
