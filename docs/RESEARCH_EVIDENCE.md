# Research evidence behind CEO Forge (v1, partially verified)

## How to read this document — verification limits
- In the environment that produced this file, DOI resolvers, Crossref, PubMed and publisher sites were **unreachable**. I could not open any paper's full text.
- What *was* verified: bibliographic details (authors, venue, volume/pages) and, where noted, the DOI and abstract-level findings, via web-search results that quoted abstracts, PubMed/university-repository records or press releases.
- **DOI status** is marked: `confirmed` (a retrieved record printed it), `secondary` (printed only in a reference list/aggregator), `unverified` (recalled from memory; the search did not return it — check before citing).
- Design/population details not stated in a retrieved source are marked `[background knowledge, not re-checked]`.
- "Established / mixed / preliminary / hypothesis" is *my* grading of how strongly the finding supports the product decision. A study existing does not make a technique "proven".
- **Not one claim here has been validated for this app's own scoring.** The rubric detectors are engineering hypotheses (see §3).

## 1. Sources

### 1.1 Practice, memory and feedback
**E1. Ericsson, K. A., Krampe, R. T., & Tesch-Römer, C. (1993). The role of deliberate practice in the acquisition of expert performance. *Psychological Review*, 100(3), 363–406.** DOI 10.1037/0033-295X.100.3.363 (`confirmed`, two independent records).
- Design: retrospective/diary-based comparisons of expert vs. less accomplished performers, chiefly musicians `[background knowledge]`.
- Finding: expert performance is associated with large amounts of effortful, goal-directed practice with feedback.
- Limits: correlational, retrospective self-report; **not replicated cleanly** — Macnamara & Maitra (2019, *Royal Society Open Science*, DOI 10.1098/rsos.190327, `confirmed` in a result) reported that accumulated practice did not map onto skill level as the original claimed.
- Product use: structured practice with targeted weakness and feedback (daily mission = one weakness). Grade: **mixed** (concept useful; strong quantitative claims not supported).

**E2. Macnamara, B. N., Hambrick, D. Z., & Oswald, F. L. (2014). Deliberate practice and performance in music, games, sports, education, and professions: A meta-analysis. *Psychological Science*, 25(8), 1608–1618.** DOI 10.1177/0956797614535810 (`secondary`: a press-release journal reference).
- Finding (per result): deliberate practice explained ~26% of performance variance in games, 21% music, 18% sports, 4% education, <1% professions.
- Product use: **a guardrail.** Practice volume is not the whole story, so the app reports measured change, not hours or streaks, and never promises mastery. Grade: **established** (as a caution).

**E3. Roediger, H. L., & Karpicke, J. D. (2006). Test-enhanced learning: Taking memory tests improves long-term retention. *Psychological Science*, 17(3), 249–255.** DOI: `unverified` (JSTOR stable record 40064526 seen).
- Finding (abstract, quoted in a result): at a 5-minute test restudying beat testing, but on delayed tests prior testing produced substantially greater retention, even though restudying raised confidence.
- Limits: laboratory prose-passage recall with students `[background knowledge]`; recall of text, not interpersonal skill.
- Product use: attempt-first (no model answer before the first try); delayed retention checks; do not equate feeling fluent with learning. Transfer to speaking/negotiation skill is an **engineering hypothesis**. Grade: **established for recall; hypothesis for skills.**

**E4. Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., & Rohrer, D. (2006). Distributed practice in verbal recall tasks: A review and quantitative synthesis. *Psychological Bulletin*, 132(3), 354–380.** DOI 10.1037/0033-2909.132.3.354 (`confirmed`, PubMed record).
- Design (per result): synthesis of 839 assessments from 317 experiments in 184 articles; examines spacing, lag and expanding intervals.
- Limits: verbal recall tasks (word lists, facts) `[stated in title]`; the best gap depends on how long the material must be retained. Our fixed 1/3/7/14/30/60-day ladder is a **simplification, not an optimised schedule**.
- Product use: spaced review of weak criteria. Grade: **established that spacing helps recall; hypothesis for the exact intervals and for skill performance.**

**E5. Dunlosky, J., Rawson, K. A., Marsh, E. J., Nathan, M. J., & Willingham, D. T. (2013). Improving students' learning with effective learning techniques. *Psychological Science in the Public Interest*, 14(1), 4–58.** DOI 10.1177/1529100612453266 (`unverified`, from memory).
- Finding (per result): of 10 techniques, practice testing and distributed practice rated highest utility; summarisation, highlighting and rereading rated low.
- Limits: mostly student learning of academic content. Product use: justifies retrieval + spacing over rereading tips/lectures. Grade: **established for academic learning; extrapolation to interpersonal skills is a hypothesis.**

**E6. Hattie, J., & Timperley, H. (2007). The power of feedback. *Review of Educational Research*, 77(1), 81–112.** DOI 10.3102/003465430298487 (`confirmed`, several records).
- Finding (abstract): feedback strongly influences learning, but effects can be positive or negative depending on type and delivery; authors propose a feedback model.
- Product use: feedback is task-specific and tied to quoted evidence. Grade: **established that feedback matters; the specific model is a synthesis, not a controlled test.**

**E7. Kluger, A. N., & DeNisi, A. (1996). The effects of feedback interventions on performance: A historical review, a meta-analysis, and a preliminary feedback intervention theory. *Psychological Bulletin*, 119(2), 254–284.** DOI: `unverified`.
- Design (per result): 607 effect sizes, 23,663 observations. Mean d = .41, but **over one third of interventions *reduced* performance**; effectiveness fell as attention moved from the task toward the self.
- Product use (important): feedback must stay on the **behaviour** ("you conceded before asking") and never on the person ("you are weak at negotiating"); no flattery; show next action. Grade: **established.** This is the main reason the coach text avoids self-directed praise/criticism.

### 1.2 Goals and commitments
**E8. Gollwitzer, P. M. (1999). Implementation intentions: Strong effects of simple plans. *American Psychologist*, 54(7), 493–503.** DOI 10.1037/0003-066X.54.7.493 (`confirmed`, Konstanz repository).
**E9. Gollwitzer, P. M., & Sheeran, P. (2006). Implementation intentions and goal achievement: A meta-analysis of effects and processes. *Advances in Experimental Social Psychology*, 38, 69–119.** DOI 10.1016/S0065-2601(06)38002-1 (`confirmed`).
- Finding (abstract): if–then plans help start goal-directed action, shield it from interference, and help disengage from failing courses. A secondary source gave 94 tests, d≈0.65: **unverified.**
- Limits: effects measured mostly on simple, specific behaviours `[background knowledge]`; many outcomes self-reported; publication bias possible.
- Product use: real-world missions are written as "When X happens, I will Y" and completion is recorded. Grade: **established for simple behaviours; hypothesis that it improves negotiation outcomes.**

**E10. Locke, E. A., & Latham, G. P. (2002). Building a practically useful theory of goal setting and task motivation: A 35-year odyssey. *American Psychologist*, 57(9), 705–717.** DOI: `unverified`.
- Finding (abstract): 35-year synthesis; specific, difficult goals (with feedback and commitment) tend to outperform vague "do your best" goals `[background knowledge]`.
- Product use: one measurable success criterion per mission. Grade: **established** (with known moderators: complex tasks can need learning goals).

### 1.3 Negotiation and communication
**E11. Galinsky, A. D., & Mussweiler, T. (2001). First offers as anchors: The role of perspective-taking and negotiator focus. *Journal of Personality and Social Psychology*, 81(4), 657–669.** PMID 11642352; DOI `unverified`.
- Design/finding (per result): three experiments; the first offerer got the better outcome, buyer or seller; the effect **disappeared when the counterpart focused on information inconsistent with the offer**; held face-to-face and by email.
- Limits: mostly laboratory/student negotiations `[background knowledge]`.
- Product use: anchoring and counter-anchoring drills; teaches the *limit* (an anchor can be neutralised by focusing on contrary information). Grade: **established in lab; field generalisation uncertain.**

**E12. Galinsky, A. D., Maddux, W. W., Gilin, D., & White, J. B. (2008). Why it pays to get inside the head of your opponent: The differential effects of perspective taking and empathy in negotiations. *Psychological Science*, 19(4), 378–384.** DOI 10.1111/j.1467-9280.2008.02096.x (`confirmed` from the journal URL).
- Design/finding (per results): three studies; perspective-taking helped find hidden agreements and create and claim value; empathy helped less and sometimes hurt. About 76% of perspective-takers vs 54% of empathisers reached the ideal compromise (journal cover story; effect sizes not verified).
- Product use: the ASK/LISTEN steps train **perspective-taking questions** ("what constraints are you under?") rather than emotional mirroring. Grade: **preliminary–established (small number of lab studies).**

**E13. Weger, H., Castle, G. R., & Emmett, M. C. (2010). Active listening in peer interviews: The influence of message paraphrasing on perceptions of listening skill. *International Journal of Listening*, 24(1), 34–49.** DOI 10.1080/10904010903466311 (`confirmed`).
- Design (per result): 180 undergraduates. Finding: paraphrasing related to perceived social attractiveness of the listener but **not** to conversational satisfaction or feeling understood. A later study by the lead author reported active-listening responses made people feel more understood than advice or simple acknowledgement (abstract-level, not read).
- Product use: **active listening is graded as mixed**; the rubric does not reward paraphrasing as such, and no score claims it works. Grade: **mixed.**

**E14. Thompson, L. L., Wang, J., & Gunia, B. C. (2010). Negotiation. *Annual Review of Psychology*, 61, 491–515.** DOI 10.1146/annurev.psych.093008.100458 (`secondary`).
- Nature: selective descriptive review across five levels of analysis, value creation vs claiming. It is **not** a training-effectiveness study.
- Product use: background for integrative vs distributive framing (multi-issue trades). Grade: **review; supports framing, not the training method.**

### 1.4 Training design and transfer
**E15. Arthur, W., Bennett, W., Edens, P. S., & Bell, S. T. (2003). Effectiveness of training in organizations: A meta-analysis of design and evaluation features. *Journal of Applied Psychology*, 88(2), 234–245.** DOI 10.1037/0021-9010.88.2.234 (`confirmed`).
- Finding (per result): effect sizes ≈ 0.60–0.63 across reaction, learning, behaviour and results criteria; effectiveness depended on training method, the skill trained and the evaluation criteria.
- Limits: organisational classroom/workplace training, heterogeneous; says little about a self-directed app. Grade: **established that training can work; says nothing about this product.**

**E16. Blume, B. D., Ford, J. K., Baldwin, T. T., & Huang, J. L. (2010). Transfer of training: A meta-analytic review. *Journal of Management*, 36(4), 1065–1105.** DOI 10.1177/0149206309352880 (`secondary`).
- Nature (per result): meta-analysis of 89 studies of predictors of transfer (trainee characteristics, work environment, training interventions). Detailed effect sizes not retrieved.
- Product use: motivates real-world missions and varied scenarios; the manager/work-environment factors are outside the app's control. Grade: **established that transfer is not automatic; app-specific benefit is an engineering hypothesis.**

## 2. Evidence → feature map
| Feature | Supported by | Grade |
|---|---|---|
| Attempt before any model answer; model example shown only after the first attempt | E3, E5 | Established for recall; hypothesis for skills |
| Retry of the same moment, only the targeted criterion scored | E1, E6 | Mixed/synthesis; retry is **not** counted as spaced practice (our rule) |
| Feedback anchored to quoted behaviour, no person-level praise/criticism | E6, **E7** | Established |
| Fixed review ladder 1/3/7/14/30/60 days; due items outrank mild weaknesses | E4, E5 | Spacing established; **exact intervals = hypothesis** |
| "Mastery" requires repeats + a second scenario + a delayed success | E2, E3, E16 | Design choice guarding against over-claiming |
| One measurable success criterion per mission | E10 | Established |
| Real-world missions as if–then plans, completion recorded | E8, E9, E16 | Established (simple behaviours); transfer to negotiation: hypothesis |
| Discovery question before price movement; perspective-taking prompts | E12, E14 | Preliminary–established |
| Anchoring / counter-anchoring drills, with stated limits | E11 | Established in lab |
| Active-listening paraphrase not scored as effective | E13 | Mixed |
| No streaks as a progress signal; show measured change and confidence | E2 | Guardrail |

## 3. What is NOT evidence-based (engineering hypotheses)
- Every detector in the rubric (question pattern, concession patterns, value vocabulary, filler/hedge lists, 90-word length threshold, pass mark of 70, weights). **No validation against human raters has been done.** Agreement with a skilled coach is unknown. Planned: collect blind human ratings on ≥50 real replies and report agreement.
- That higher scores on these rubrics predict better real negotiations.
- Difficulty adjustment rules (2 passes up / 2 fails down) and the priority formula.
- Anything about voice: no source here supports inferring confidence/emotion from pitch or loudness, and the app will not do so.

## 4. Not yet researched (do not assume covered)
Public-speaking training outcomes and anxiety-reduction trials; speech fluency/filler-word norms and speaking-rate norms; behavioural rehearsal/role-play efficacy specifically; negotiation-training meta-analyses (the one search for this returned nothing relevant); self-explanation; interleaving; pronunciation/intelligibility assessment; emotion-regulation exercises; ASR accuracy for accented English. Each needs its own source pass before the matching feature is described as evidence-based.
