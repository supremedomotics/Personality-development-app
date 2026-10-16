import 'dart:convert';

import 'package:ceo_forge/core/planner.dart';
import 'package:ceo_forge/core/rubric.dart';
import 'package:ceo_forge/core/scenario.dart';
import 'package:ceo_forge/core/session.dart';
import 'package:ceo_forge/data/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 11, 2, 9);

(SessionRecord, SkillBook) completed({String id = 's1', DateTime? at}) {
  final book = SkillBook();
  final n = at ?? t0;
  final m = const LearningPlanner()
      .planDay(book: book, now: n, scenarios: negotiationScenarios, rubric: negotiationRubric);
  final c = SessionController(
      mission: m,
      scenario: negotiationScenarios.firstWhere((s) => s.id == m.scenarioId),
      book: book,
      clock: () => n,
      rubric: negotiationRubric,
      id: id);
  c.submitReply('Okay, I can give you 10 percent off the whole quote right now to close this today.');
  c.submitReply('Fine, I can also take another 5 percent off if that helps you decide on this.');
  c.submitReply('We can see how things go and talk again whenever it suits you in the coming weeks.');
  c.skipRetry();
  return (c.record, book);
}

void main() {
  late AppDatabase db;
  late DriftProgressRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftProgressRepository(db);
  });
  tearDown(() => db.close());

  test('empty database yields empty book and no sessions (first launch)', () async {
    expect((await repo.loadBook()).states, isEmpty);
    expect(await repo.sessions(), isEmpty);
  });

  test('completed session and skill book persist atomically and reload identically', () async {
    final (rec, book) = completed();
    await repo.saveCompleted(rec, book);
    final sessions = await repo.sessions();
    expect(sessions.length, 1);
    expect(jsonEncode(sessions.single.toJson()), jsonEncode(rec.toJson()));
    expect(jsonEncode((await repo.loadBook()).toJson()), jsonEncode(book.toJson()));
  });

  test('saving the same session id twice is idempotent', () async {
    final (rec, book) = completed();
    await repo.saveCompleted(rec, book);
    await repo.saveCompleted(rec, book);
    expect((await repo.sessions()).length, 1);
  });

  test('sessions are returned oldest first', () async {
    final (a, b1) = completed(id: 'a', at: t0);
    final (b, b2) = completed(id: 'b', at: t0.add(const Duration(days: 1)));
    await repo.saveCompleted(b, b2);
    await repo.saveCompleted(a, b1);
    expect((await repo.sessions()).map((s) => s.id), ['a', 'b']);
  });

  test('export contains everything; delete-all removes it', () async {
    final (rec, book) = completed();
    await repo.saveCompleted(rec, book);
    final ex = await repo.exportAll();
    expect(ex['format'], 'ceo-forge-export');
    expect((ex['sessions'] as List).length, 1);
    expect((ex['book'] as Map), isNotEmpty);
    await repo.deleteAll();
    expect(await repo.sessions(), isEmpty);
    expect((await repo.loadBook()).states, isEmpty);
  });

  test('transaction rolls back if the book write fails (no half-saved session)', () async {
    final (rec, _) = completed();
    await expectLater(
        db.transaction(() async {
          await repo.saveSession(rec);
          throw StateError('boom');
        }),
        throwsStateError);
    expect(await repo.sessions(), isEmpty);
  });

  test('schema version is pinned (a bump requires a migration test)', () {
    expect(db.schemaVersion, 1);
  });
}
