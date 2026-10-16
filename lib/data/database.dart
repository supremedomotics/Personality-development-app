import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/missions.dart';
import '../core/planner.dart';
import '../core/session.dart';

part 'database.g.dart';

/// Sessions are stored as full JSON records (reproducible reports) plus
/// indexed columns for listing. Schema is versioned for migrations.
class Sessions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startedAt => dateTime()();
  TextColumn get scenarioId => text()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row key/value store for the skill book and settings.
class KeyValues extends Table {
  TextColumn get k => text()();
  TextColumn get v => text()();
  @override
  Set<Column> get primaryKey => {k};
}

@DriftDatabase(tables: [Sessions, KeyValues])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // v2+ migrations go here; every bump needs a migration test.
      );
}

/// Repository boundary used by the app and by tests.
abstract class ProgressRepository {
  Future<void> saveSession(SessionRecord r);

  /// Atomically stores a finished session and the updated skill book.
  Future<void> saveCompleted(SessionRecord r, SkillBook b, {List<Mission>? missions});
  Future<List<Mission>> missions();
  Future<void> saveMissions(List<Mission> m);
  Future<List<SessionRecord>> sessions();
  Future<SkillBook> loadBook();
  Future<void> saveBook(SkillBook b);
  Future<Map<String, Object?>> exportAll();
  Future<void> deleteAll();
}

class DriftProgressRepository implements ProgressRepository {
  DriftProgressRepository(this.db);
  final AppDatabase db;

  @override
  Future<void> saveSession(SessionRecord r) =>
      db.into(db.sessions).insertOnConflictUpdate(SessionsCompanion.insert(
          id: r.id,
          startedAt: r.startedAt,
          scenarioId: r.scenarioId,
          json: jsonEncode(r.toJson())));

  @override
  Future<void> saveCompleted(SessionRecord r, SkillBook b, {List<Mission>? missions}) =>
      db.transaction(() async {
        await saveSession(r);
        await saveBook(b);
        if (missions != null) await saveMissions(missions);
      });

  @override
  Future<List<Mission>> missions() async {
    final row = await (db.select(db.keyValues)..where((t) => t.k.equals('missions'))).getSingleOrNull();
    if (row == null) return [];
    return [
      for (final m in jsonDecode(row.v) as List)
        Mission.fromJson((m as Map).cast<String, Object?>())
    ];
  }

  @override
  Future<void> saveMissions(List<Mission> m) => db.into(db.keyValues).insertOnConflictUpdate(
      KeyValuesCompanion.insert(k: 'missions', v: jsonEncode([for (final x in m) x.toJson()])));

  @override
  Future<List<SessionRecord>> sessions() async {
    final rows = await (db.select(db.sessions)
          ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
        .get();
    return [
      for (final r in rows)
        SessionRecord.fromJson(jsonDecode(r.json) as Map<String, Object?>)
    ];
  }

  @override
  Future<SkillBook> loadBook() async {
    final row = await (db.select(db.keyValues)..where((t) => t.k.equals('book')))
        .getSingleOrNull();
    return row == null
        ? SkillBook()
        : SkillBook.fromJson(jsonDecode(row.v) as Map<String, Object?>);
  }

  @override
  Future<void> saveBook(SkillBook b) => db
      .into(db.keyValues)
      .insertOnConflictUpdate(KeyValuesCompanion.insert(k: 'book', v: jsonEncode(b.toJson())));

  @override
  Future<Map<String, Object?>> exportAll() async => {
        'format': 'ceo-forge-export',
        'version': 1,
        'book': (await loadBook()).toJson(),
        'missions': [for (final m in await missions()) m.toJson()],
        'sessions': [for (final s in await sessions()) s.toJson()],
      };

  @override
  Future<void> deleteAll() async {
    await db.transaction(() async {
      await db.delete(db.sessions).go();
      await db.delete(db.keyValues).go();
    });
  }
}
