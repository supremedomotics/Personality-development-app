import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_state.dart';
import '../app_state.dart';
import '../core/models.dart';
import '../core/session.dart';
import 'theme.dart';

const _budget = Duration(minutes: 10);

class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key, required this.controller});
  final SessionController controller;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final Timer _timer;
  late final DateTime _start;
  Duration _elapsed = Duration.zero;
  bool _saving = false;
  bool _thinking = false;
  String? _saveError;

  SessionController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = DateTime.now().difference(_start));
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _thinking) return;
    if (c.phase == SessionPhase.retry) {
      setState(() {
        c.submitRetry(text);
        _input.clear();
      });
      _persist();
      return;
    }
    final voice = ref.read(voiceProvider).voice;
    setState(() {
      _thinking = voice != null;
      _input.clear();
    });
    await c.submitReplyAsync(
      text,
      reword: voice == null
          ? null
          : (line, reply) async {
              final r = await voice.rephrase(
                  personaName: c.scenario.persona,
                  setting: c.scenario.setting,
                  intendedLine: line,
                  lastUserReply: reply);
              return r.fromModel ? r.text : null;
            },
    );
    if (!mounted) return;
    setState(() => _thinking = false);
    if (c.phase == SessionPhase.summary) _persist();
    _scrollDown();
  }

  Future<void> _persist() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref.read(appControllerProvider.notifier).complete(c);
    } catch (e) {
      _saveError = 'Could not save this session. Your device storage may be full.';
    }
    if (mounted) setState(() => _saving = false);
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final over = _elapsed > _budget;
    final left = _budget - _elapsed;
    final mm = left.isNegative ? '+${(-left.inMinutes).abs()}' : left.inMinutes.toString();
    final ss = (left.inSeconds.abs() % 60).toString().padLeft(2, '0');
    return PopScope(
      canPop: c.phase == SessionPhase.summary,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave this session?'),
            content: const Text('Nothing from this unfinished session will be saved or scored.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
            ],
          ),
        );
        if ((leave ?? false) && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.scenario.title),
          actions: [
            Semantics(
              label: over ? 'Over the 10 minute budget' : 'Time left $mm minutes $ss seconds',
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text('$mm:$ss',
                      style: TextStyle(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: over ? context.t.danger : context.t.muted)),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(child: _buildPhase(context)),
      ),
    );
  }

  Widget _buildPhase(BuildContext context) {
    switch (c.phase) {
      case SessionPhase.roleplay:
        return _roleplay(context);
      case SessionPhase.feedback:
        return _feedback(context);
      case SessionPhase.retry:
        return _retry(context);
      case SessionPhase.briefing:
      case SessionPhase.summary:
        return _summary(context);
    }
  }

  // ---- roleplay ------------------------------------------------------

  Widget _roleplay(BuildContext context) {
    final theme = Theme.of(context);
    final turns = <Widget>[
      Text(c.scenario.setting, style: theme.textTheme.labelMedium),
      const SizedBox(height: 12),
    ];
    for (var i = 0; i < c.record.personaLines.length; i++) {
      turns.add(_Bubble(who: c.scenario.persona, text: c.record.personaLines[i], mine: false));
      if (i < c.record.replies.length) {
        turns.add(_Bubble(who: 'You', text: c.record.replies[i].text, mine: true));
      }
    }
    return Column(children: [
      Expanded(
        child: ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: turns),
      ),
      if (_thinking) const LinearProgressIndicator(),
      _Composer(
        controller: _input,
        hint: 'Type your reply (voice input is not installed yet)',
        onSend: _thinking ? null : _send,
        onEnd: _thinking ? null : () => setState(c.endEarly),
        label: 'Reply ${c.replyCount + 1} of ${3}',
      ),
    ]);
  }

  // ---- feedback ------------------------------------------------------

  Widget _feedback(BuildContext context) {
    final a = c.record.assessment!;
    final fb = c.feedback!;
    final theme = Theme.of(context);
    final t = context.t;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Your first attempt', style: theme.textTheme.labelMedium),
      Text(a.overall == null ? 'Not scored' : '${a.overall}/100',
          style: theme.textTheme.headlineMedium),
      Text(
          'Weighted over the ${a.criteria.where((x) => x.assessed).length} criteria that applied. Confidence ${_conf(a.confidence)}. Each criterion is shown separately below so a good average cannot hide a weak one.',
          style: theme.textTheme.bodyMedium),
      const SizedBox(height: 16),
      for (final cr in a.criteria) _CriterionCard(cr: cr, isFocus: cr.id == fb.primaryCriterion, replies: c.record.replies),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('What a skilled negotiator does differently', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(fb.missed),
            const SizedBox(height: 12),
            Text('Technique', style: theme.textTheme.labelMedium),
            Text(fb.technique),
            const SizedBox(height: 12),
            Text('A stronger response (an example, not the only right answer)', style: theme.textTheme.labelMedium),
            Text(fb.strongerExample, style: TextStyle(fontStyle: FontStyle.italic, color: t.text)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      for (final cv in a.caveats)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(cv, style: theme.textTheme.labelMedium),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _editTranscript,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Correct a transcript line and re-assess'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => setState(c.startRetry),
        child: Text('Retry the moment: ${c.mission.criterionLabel}'),
      ),
      TextButton(
        onPressed: () {
          setState(c.skipRetry);
          _persist();
        },
        child: const Text('Skip retry and finish'),
      ),
    ]);
  }

  Future<void> _editTranscript() async {
    final pick = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Which line?'),
        children: [
          for (final r in c.record.replies)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r.turn),
              child: Text('Reply ${r.turn}: ${r.text}', maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    final cur = c.record.replies.firstWhere((r) => r.turn == pick).text;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => _TranscriptDialog(initial: cur),
    );
    if (text != null && text.trim().isNotEmpty && mounted) {
      setState(() => c.correctTranscript(pick, text));
    }
  }

  // ---- retry ---------------------------------------------------------

  Widget _retry(BuildContext context) => Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Replay the moment. Same situation, your better answer. Focus: ${c.mission.criterionLabel}.',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 12),
            _Bubble(who: c.scenario.persona, text: c.retryPrompt, mine: false),
            const SizedBox(height: 8),
            Text('Success looks like: ${c.mission.successCriterion}', style: Theme.of(context).textTheme.bodyMedium),
          ]),
        ),
        _Composer(controller: _input, hint: 'Your second attempt', onSend: _send, onEnd: null, label: 'Retry'),
      ]);

  // ---- summary -------------------------------------------------------

  Widget _summary(BuildContext context) {
    final s = c.summary;
    final theme = Theme.of(context);
    if (s == null) {
      return Center(child: Text(c.record.endedEarly ? 'Session ended before any reply. Nothing was saved.' : 'Done.'));
    }
    final t = context.t;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Session complete', style: theme.textTheme.labelMedium),
      const SizedBox(height: 8),
      if (s.baselineScore != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _Big(label: 'First attempt', value: '${s.baselineScore}'),
              Icon(Icons.arrow_forward, color: t.muted),
              _Big(label: 'Retry', value: s.finalScore == null ? '—' : '${s.finalScore}'),
            ]),
          ),
        ),
      if (s.corrected != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          Icon(s.corrected! ? Icons.check_circle_outline : Icons.info_outline, color: s.corrected! ? t.ok : t.muted),
          const SizedBox(width: 8),
          Expanded(
              child: Text(s.corrected!
                  ? 'You corrected the original mistake on the replayed moment.'
                  : 'The original mistake was not fully corrected yet. It will come back for review.')),
        ]),
      ],
      const SizedBox(height: 16),
      _Section('Demonstrated improvement', s.improvement),
      _Section('Remaining weakness', s.remainingWeakness),
      _Section('Rule to remember', s.rule),
      _Section('One real-world action', s.action),
      _Section("Tomorrow's provisional priority", s.tomorrow),
      if (_saving) const LinearProgressIndicator(),
      if (_saveError != null) ...[
        Text(_saveError!, style: TextStyle(color: t.danger)),
        TextButton(onPressed: _persist, child: const Text('Retry saving')),
      ],
      const SizedBox(height: 16),
      FilledButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Done')),
    ]);
  }
}

String _conf(double c) => c >= 0.7 ? 'higher' : (c >= 0.5 ? 'moderate' : 'low');

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ]);
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.body);
  final String title, body;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(body, style: Theme.of(context).textTheme.bodyLarge),
        ]),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.who, required this.text, required this.mine});
  final String who, text;
  final bool mine;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        decoration: BoxDecoration(
          color: mine ? t.accent.withValues(alpha: 0.18) : t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border.withValues(alpha: 0.6)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(text),
        ]),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.hint, required this.onSend, required this.onEnd, required this.label});
  final TextEditingController controller;
  final String hint, label;
  final VoidCallback? onSend;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (onEnd != null) TextButton(onPressed: onEnd, child: const Text('End early')),
            const Spacer(),
            SizedBox(width: 140, child: FilledButton(onPressed: onSend, child: const Text('Send'))),
          ]),
        ]),
      );
}

class _CriterionCard extends StatelessWidget {
  const _CriterionCard({required this.cr, required this.isFocus, required this.replies});
  final CriterionResult cr;
  final bool isFocus;
  final List<Utterance> replies;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final pass = (cr.score ?? 0) >= 70;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        container: true,
        label: cr.assessed
            ? '${cr.label}: ${cr.score} out of 100. ${cr.comment}'
            : '${cr.label}: not assessed. ${cr.comment}',
        child: Card(
          shape: isFocus
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.accent, width: 2))
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(cr.label, style: theme.textTheme.titleMedium)),
                if (cr.assessed) ...[
                  Icon(pass ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: pass ? t.ok : t.danger),
                  const SizedBox(width: 6),
                  Text('${cr.score}', style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                ] else
                  Text('n/a', style: theme.textTheme.labelMedium),
              ]),
              const SizedBox(height: 4),
              Text(cr.comment, style: theme.textTheme.bodyMedium),
              if (cr.evidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final e in cr.evidence.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Reply ${e.turn} · ${e.note}: “${_quote(e)}”', style: theme.textTheme.labelMedium),
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  String _quote(Evidence e) {
    final u = replies.firstWhere((r) => r.turn == e.turn);
    if (e.end > u.text.length) return e.quote;
    // Show the evidence in its surrounding sentence context.
    final s = (e.start - 25).clamp(0, u.text.length);
    final en = (e.end + 25).clamp(0, u.text.length);
    return '${s > 0 ? '…' : ''}${u.text.substring(s, en)}${en < u.text.length ? '…' : ''}';
  }
}

/// Owns its controller so it is disposed only after the dialog route is gone.
class _TranscriptDialog extends StatefulWidget {
  const _TranscriptDialog({required this.initial});
  final String initial;
  @override
  State<_TranscriptDialog> createState() => _TranscriptDialogState();
}

class _TranscriptDialogState extends State<_TranscriptDialog> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Correct the transcript'),
        content: TextField(controller: _ctl, maxLines: 6, autofocus: true, enableSuggestions: false, autocorrect: false, enableIMEPersonalizedLearning: false),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, _ctl.text), child: const Text('Re-assess')),
        ],
      );
}
