# CEO Forge — Design System (v0)

**Provenance (honest):** The "Impeccable" skill was not available in this environment (not installed, not in the skills registry).
Guidance below applies the written rules of the `ui-ux-pro-max` skill (its `SKILL.md` only; its search scripts/data were not synced, so no generated recommendations were used)
plus `frontend-design` principles. Contrast ratios were computed, not eyeballed. If you supply Impeccable files, reconcile them against this doc.

## Direction
Restrained executive instrument: warm near-black / warm paper, one brass accent, serif display + clean sans body. No chatbot bubbles-on-gradient look.
One primary action per screen. Motion only to convey cause/effect (150–300 ms, exit ≈ 65% of enter, reduced-motion respected).

## Tokens (semantic only — no raw hex in widgets)
| Token | Dark | Light |
|---|---|---|
| bg | #0E1116 | #F6F3EC |
| surface | #171B22 | #FFFFFF |
| text | #ECE8DF | #16191F |
| textMuted | #A8AFBA | #4A515C |
| accent | #D4B16A | #7A5A14 |
| onAccent | #0E1116 | #FFFFFF |
| danger | #E5877A | #A8321F |
| ok | #7FC3A0 | #1F6B47 |
| border | #2A303A | (tbd, must reach ≥3:1 for dividers that carry meaning) |

Measured contrast (WCAG): dark text/bg 15.5, muted/bg 8.6, accent/bg 9.3, danger/surface 6.6, ok/surface 8.4;
light text/bg 15.9, muted/bg 7.2, accent/bg 5.7, danger 6.7, ok 6.5. All text pairs ≥ 4.5:1.
Known gap: dark `border` is 1.4:1 — acceptable only for decorative separation; never use it as the sole boundary for an interactive control.

## Type & spacing
Scale 12/14/16/18/24/32; body 16, line-height 1.5; tabular figures for scores/timers. Display: a serif (e.g. Fraunces/Newsreader), body: Inter-class sans — bundled as assets (app must not fetch fonts online).
Spacing 4/8 rhythm (8, 16, 24, 32, 48). Touch targets ≥ 48dp; ≥ 8dp gaps. Support system text scaling without truncation.

## Rules specific to this product
- Scores always show value **and** confidence/“not comparable” flags; never color-only (icon + text).
- Recording state: persistent label + icon + timer (not color alone); mic permission-denied has a text fallback path.
- Offline/model readiness shown as verified state only ("verified" requires a checksum pass, otherwise "not installed").
- Bottom nav ≤ 5: Today, Skills, Progress, Missions, Settings. Reports/Models/Research live under Progress/Settings.
- No emoji as icons; one icon family, one stroke weight.
- Light and dark designed together and tested separately.
