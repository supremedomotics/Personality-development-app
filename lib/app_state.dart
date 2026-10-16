import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const AppData(this.book, this.sessions);
  final SkillBook book;
  final List<SessionRecord> sessions;

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
    return AppData(await r.loadBook(), await r.sessions());
  }

  /// Sessions run on a copy of the book so an abandoned session cannot change progress.
  SkillBook bookCopy() => SkillBook.fromJson(state.requireValue.book.toJson());

  /// Persists first, then updates memory: UI never shows progress that isn't saved.
  Future<void> complete(SessionController c) async {
    final repo = ref.read(repositoryProvider);
    await repo.saveCompleted(c.record, c.book);
    final cur = state.requireValue;
    state = AsyncData(AppData(c.book, [...cur.sessions, c.record]));
  }

  Future<void> deleteEverything() async {
    await ref.read(repositoryProvider).deleteAll();
    state = AsyncData(AppData(SkillBook(), const []));
  }
}

final appControllerProvider =
    AsyncNotifierProvider<AppController, AppData>(AppController.new);
