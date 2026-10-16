import 'package:ceo_forge/app_state.dart';
import 'package:ceo_forge/core/missions.dart';
import 'package:ceo_forge/core/planner.dart';
import 'package:ceo_forge/core/session.dart';
import 'package:ceo_forge/data/database.dart';
import 'package:ceo_forge/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryRepo implements ProgressRepository {
  final Map<String, SessionRecord> _s = {};
  SkillBook _book = SkillBook();
  List<Mission> _missions = [];
  bool failNextSave = false;
  bool failMissionSave = false;
  bool failDelete = false;
  int get sessionCount => _s.length;
  int get missionCount => _missions.length;
  bool get bookEmpty => _book.states.isEmpty;

  @override
  Future<void> saveSession(SessionRecord r) async => _s[r.id] = r;
  @override
  Future<void> saveCompleted(SessionRecord r, SkillBook b, {List<Mission>? missions}) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('disk full');
    }
    _s[r.id] = r;
    _book = SkillBook.fromJson(b.toJson());
    if (missions != null) _missions = missions;
  }

  @override
  Future<List<Mission>> missions() async => _missions;
  @override
  Future<void> saveMissions(List<Mission> m) async {
    if (failMissionSave) throw StateError('disk full');
    _missions = m;
  }

  @override
  Future<List<SessionRecord>> sessions() async => _s.values.toList();
  @override
  Future<SkillBook> loadBook() async => _book;
  @override
  Future<void> saveBook(SkillBook b) async => _book = b;
  @override
  Future<Map<String, Object?>> exportAll() async => {};
  @override
  Future<void> deleteAll() async {
    if (failDelete) throw StateError('io');
    _s.clear();
    _missions = [];
    _book = SkillBook();
  }
}

Future<void> pumpApp(WidgetTester t, MemoryRepo repo) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 2, 9)),
    ],
    child: const CeoForgeApp(),
  ));
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
}

Future<void> tapText(WidgetTester t, Finder f) async {
  await reveal(t, f);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> reply(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField).last, text);
  await t.tap(find.text('Send'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('home shows a baseline mission with success criterion and no scores', (t) async {
    await pumpApp(t, MemoryRepo());
    expect(find.text('Baseline session'), findsOneWidget);
    expect(find.text('Start session'), findsOneWidget);
    expect(find.textContaining('Success looks like'), findsOneWidget);
    await reveal(t, find.textContaining('No scores yet'));
    expect(find.textContaining('No scores yet'), findsOneWidget);
  });

  testWidgets('complete session: roleplay → feedback → retry → summary → saved → home updates', (t) async {
    final repo = MemoryRepo();
    await pumpApp(t, repo);
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();

    expect(find.textContaining('15 percent'), findsOneWidget, reason: 'persona opens');
    await reply(t, 'Okay, I can give you 10 percent off the whole quote right now to close this today.');
    expect(find.textContaining('room in your price'), findsOneWidget, reason: 'persona reacts to the concession');
    await reply(t, 'Fine, I can also take another 5 percent off if that helps you decide on this.');
    await reply(t, 'We can see how things go and talk again whenever it suits you in the coming weeks.');

    // Feedback: scores per criterion, evidence, stronger example only now.
    expect(find.textContaining('Your first attempt'), findsOneWidget);
    expect(find.text('Price discipline'), findsOneWidget);
    await reveal(t, find.textContaining('A stronger response'));
    expect(find.textContaining('A stronger response'), findsOneWidget);
    expect(repo._s, isEmpty, reason: 'nothing saved before the session completes');

    await tapText(t, find.textContaining('Retry the moment'));
    await reply(t, "I can't move on price until I understand the scope. What are the other quotes including, and how are you comparing them?");

    expect(find.text('Session complete'), findsOneWidget);
    expect(find.textContaining('Provisional'), findsOneWidget);
    expect(repo._s.length, 1);
    expect(repo._book.states, isNotEmpty);

    await tapText(t, find.text('Done'));
    expect(find.textContaining("Today's mission"), findsOneWidget);
    await reveal(t, find.text('Recent sessions'));
    expect(find.text('Recent sessions'), findsOneWidget);
    expect(find.textContaining('n=1'), findsWidgets);
  });

  testWidgets('end early before any reply saves nothing', (t) async {
    final repo = MemoryRepo();
    await pumpApp(t, repo);
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();
    await t.tap(find.text('End early'));
    await t.pumpAndSettle();
    expect(repo._s, isEmpty);
    expect(find.textContaining('Nothing was saved'), findsOneWidget);
  });

  testWidgets('save failure is shown, not hidden, and retry succeeds', (t) async {
    final repo = MemoryRepo()..failNextSave = true;
    await pumpApp(t, repo);
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();
    await reply(t, 'Okay, I can give you 10 percent off the whole quote right now to close this today.');
    await reply(t, 'Fine, I can also take another 5 percent off if that helps you decide on this.');
    await reply(t, 'We can see how things go and talk again whenever it suits you in the coming weeks.');
    await tapText(t, find.text('Skip retry and finish'));
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(repo._s, isEmpty);
    await tapText(t, find.text('Retry saving'));
    expect(find.textContaining('Could not save'), findsNothing);
    expect(repo._s.length, 1);
  });

  testWidgets('correcting a transcript line re-assesses', (t) async {
    await pumpApp(t, MemoryRepo());
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();
    await reply(t, 'Okay, I can give you 10 percent off the whole quote right now to close this today.');
    await reply(t, 'What matters most to you in this project and the scope you want covered?');
    await reply(t, 'I will send the revised scope by Friday and you confirm by Monday.');
    await tapText(t, find.textContaining('Correct a transcript'));
    await t.tap(find.textContaining('Reply 1:'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'What would need to be true for this price to work for you? I cannot move before I know.');
    await t.tap(find.text('Re-assess'));
    await t.pumpAndSettle();
    final fixed = find.textContaining('did not move on price unprompted');
    await t.scrollUntilVisible(fixed, -300, scrollable: find.byType(Scrollable).first);
    expect(fixed, findsOneWidget);
    expect(find.textContaining('conceded on price before asking'), findsNothing);
  });

  testWidgets('finishing a scored session creates a mission; completing it with a reflection persists', (t) async {
    final repo = MemoryRepo();
    await pumpApp(t, repo);
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();
    await reply(t, 'Okay, I can give you 10 percent off the whole quote right now to close this today.');
    await reply(t, 'Fine, I can also take another 5 percent off if that helps you decide on this.');
    await reply(t, 'We can see how things go and talk again whenever it suits you in the coming weeks.');
    await tapText(t, find.text('Skip retry and finish'));
    expect(repo._missions.length, 1);
    expect(repo._missions.single.status, MissionStatus.open);
    await tapText(t, find.text('Done'));

    await t.tap(find.text('Missions'));
    await t.pumpAndSettle();
    expect(find.textContaining('When '), findsOneWidget);
    await t.tap(find.text('I did this'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save')); // empty outcome is rejected
    await t.pumpAndSettle();
    expect(find.text('Write at least a few words.'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Asked what drove the discount; they wanted speed.');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(repo._missions.single.status, MissionStatus.done);
    expect(repo._missions.single.outcome, contains('wanted speed'));
    expect(find.textContaining('What happened:'), findsOneWidget);
  });

  testWidgets('a failed mission save leaves the mission open and says so', (t) async {
    final repo = MemoryRepo();
    await pumpApp(t, repo);
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();
    await reply(t, 'Okay, I can give you 10 percent off the whole quote right now to close this today.');
    await reply(t, 'Fine, I can also take another 5 percent off if that helps you decide on this.');
    await reply(t, 'We can see how things go and talk again whenever it suits you in the coming weeks.');
    await tapText(t, find.text('Skip retry and finish'));
    await tapText(t, find.text('Done'));
    await t.tap(find.text('Missions'));
    await t.pumpAndSettle();
    repo.failMissionSave = true;
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(find.textContaining('Could not save this change'), findsOneWidget);
    expect(find.text('I did this'), findsOneWidget, reason: 'mission must still be open on screen');
    expect(repo._missions.single.status, MissionStatus.open);
  });

  testWidgets('reports tab shows today\'s saved session and the weekly caveats', (t) async {
    final repo = MemoryRepo();
    await pumpApp(t, repo);
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();
    await reply(t, 'Okay, I can give you 10 percent off the whole quote right now to close this today.');
    await reply(t, 'Fine, I can also take another 5 percent off if that helps you decide on this.');
    await reply(t, 'We can see how things go and talk again whenever it suits you in the coming weeks.');
    await tapText(t, find.text('Skip retry and finish'));
    await tapText(t, find.text('Done'));
    await t.tap(find.text('Reports'));
    await t.pumpAndSettle();
    expect(find.textContaining('1 session(s)'), findsOneWidget);
    expect(find.textContaining('Overall'), findsWidgets);
    await t.tap(find.text('This week'));
    await t.pumpAndSettle();
    expect(find.textContaining('1 session(s) on 1 day(s)'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('not a validated'), 300,
        scrollable: find.descendant(of: find.byKey(const Key('weekly-list')), matching: find.byType(Scrollable)));
    expect(find.textContaining('Fewer than 3 scored sessions'), findsOneWidget);
  });

  testWidgets('monthly tab shows the report, template plan and caveats', (t) async {
    final repo = MemoryRepo();
    await pumpApp(t, repo);
    await t.tap(find.text('Start session'));
    await t.pumpAndSettle();
    await reply(t, 'Okay, I can give you 10 percent off the whole quote right now to close this today.');
    await reply(t, 'Fine, I can also take another 5 percent off if that helps you decide on this.');
    await reply(t, 'We can see how things go and talk again whenever it suits you in the coming weeks.');
    await tapText(t, find.text('Skip retry and finish'));
    await tapText(t, find.text('Done'));
    await t.tap(find.text('Reports'));
    await t.pumpAndSettle();
    await t.tap(find.text('This month'));
    await t.pumpAndSettle();
    expect(find.textContaining('1 session(s) on 1 of 30 days'), findsOneWidget);
    expect(find.textContaining('First score'), findsWidgets);
    final scroll = find.descendant(of: find.byKey(const Key('monthly-list')), matching: find.byType(Scrollable));
    await t.scrollUntilVisible(find.text('28-day template'), 300, scrollable: scroll);
    expect(find.textContaining('Day 1: Reassessment'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('not a validated'), 300, scrollable: scroll);
    expect(find.textContaining('tentative'), findsOneWidget);
  });
}
