import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/missions.dart';
import 'core/planner.dart';
import 'core/rubric.dart';
import 'core/scenario.dart';
import 'core/session.dart';
import 'data/database.dart';

/// Overridden in main() / tests. Never constructed implicitly.
final repositoryProvider = Provider<ProgressRepository>((ref) => throw UnimplementedError('repositoryProvider must be overridden'));

/// Injectable clock so planning and tests are reproducible.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class AppData {
  const AppData(this.book, this.sessions, [this.missions = const []]);
  final SkillBook book;
  final List<SessionRecord> sessions;
  final List<Mission> missions;

  DailyMission mission(DateTime now) => const LearningPlanner().planDay(
        book: book,
        now: now,
        scenarios: negotiationScenarios,
        rubric: negotiationRubric,
        lastScenarioId: sessions.isEmpty ? null : sessions.last.scenarioId,
      );

  /// Completed sessions on distinct days in the last 7 days. Informational, not a streak.
  int daysPracticedLast7(DateTime now) {
    final days = <String>{};
    for (final s in sessions) {
      if (s.completedAt != null && !s.endedEarly && now.difference(s.completedAt!).inDays < 7) {
        days.add('${s.completedAt!.year}-${s.completedAt!.month}-${s.completedAt!.day}');
      }
    }
    return days.length;
  }
}

class AppController extends AsyncNotifier<AppData> {
  @override
  Future<AppData> build() async {
    final r = ref.read(repositoryProvider);
    return AppData(await r.loadBook(), await r.sessions(), await r.missions());
  }

  /// Sessions run on a copy of the book so an abandoned session cannot change progress.
  SkillBook bookCopy() => SkillBook.fromJson(state.requireValue.book.toJson());

  /// Persists first, then updates memory: UI never shows progress that isn't saved.
  Future<void> complete(SessionController c) async {
    final repo = ref.read(repositoryProvider);
    final cur = state.requireValue;
    final fb = c.feedback;
    // A real-world mission only follows a scored session.
    final newMission = (fb != null && c.record.completedAt != null)
        ? missionFor(sessionId: c.record.id, criterionId: fb.primaryCriterion, now: c.record.completedAt!)
        : null;
    final missions = [
      ...cur.missions.where((m) => m.id != newMission?.id),
      ?newMission,
    ];
    await repo.saveCompleted(c.record, c.book, missions: missions);
    state = AsyncData(AppData(c.book, [...cur.sessions.where((s) => s.id != c.record.id), c.record], missions));
  }

  /// Applies [change] to a COPY, persists it, and only then replaces the
  /// in-memory mission: a failed write leaves the visible state unchanged.
  Future<void> updateMission(String id, void Function(Mission copy) change) async {
    final cur = state.requireValue;
    final copy = Mission.fromJson(cur.missions.firstWhere((m) => m.id == id).toJson());
    change(copy);
    final next = [for (final x in cur.missions) x.id == id ? copy : x];
    await ref.read(repositoryProvider).saveMissions(next);
    state = AsyncData(AppData(cur.book, cur.sessions, next));
  }

  Future<void> deleteEverything() async {
    await ref.read(repositoryProvider).deleteAll();
    state = AsyncData(AppData(SkillBook(), const [], const []));
  }
}

final appControllerProvider =
    AsyncNotifierProvider<AppController, AppData>(AppController.new);
