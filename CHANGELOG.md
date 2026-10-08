# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The app
has not been released; versions refer to `MARKETING_VERSION` in
`project.yml`.

## [Unreleased]

## [0.3.0] - Unreleased

Pull request "PocketBrains v0.3: honest generalization, tool trimming,
RAG eval, docs site". Eval numbers, with the CI runs they come from, are in
the README; none are claimed for Foundation Models or MLX.

### Added
- **Eval splits for honest generalization.** A new 53-utterance v0.3
  held-out paraphrase split (`Tests/Eval/HeldOutV3.swift`), committed and
  measured before any router change and never used for tuning; a
  51-utterance v0.3 dev split (`DevParaphrasesV3.swift`), the only split
  v0.3 tuned on. The v0.2 held-out split is frozen as "v0.2 held-out
  (reported)". Misses on both held-out splits are counted, never itemized.
- **Router constructions (`ParaphraseFrames`).** Statements of state,
  subject-first requests, labelled captures, reminders asked for as nouns,
  past-tense reports of work, quoted text into a named note, verbless
  project status, list states and a factual-question fallback to
  `askNotes`; leading interjections are dropped. Lexicon: tick, slip,
  kick, park, hide, pencil.
- **`ToolSelector`.** Deterministic per-request tool trimming for the
  Foundation Models brain: grammar parse, lexicon verbs, cue words and
  dates score each tool; `createTask`, `searchEverything`, `agenda` and
  `undo` are always offered; at most 8 tools. Wired into
  `FoundationModelBackend` behind Settings, Intelligence, "Focused tool
  list" (off by default). Eval: recall@6 and recall@8 per split.
- **RAG eval.** 61 synthetic questions over a 22-note synthetic fixture:
  BM25 recall@1 and @3, answer-span hit rate, citation faithfulness (every
  `[n]` maps to a retrieved passage of note n containing the cited
  sentence) and span attribution; semantic and hybrid in a separate CI
  step that reports "skipped" when the embedding asset is unavailable.
- **Docs site** for GitHub Pages: `scripts/build_site.py` renders an
  overview, eval tables parsed from CI `EVALJSON` lines, architecture,
  product brief and verification pages; `.github/workflows/pages.yml`
  publishes after CI succeeds on `main`.
- `ROADMAP.md` linked to six labelled roadmap issues (#5 to #10), a
  "routing miss" issue template, grouped Dependabot updates for actions.

### Changed
- "Push send the invoice to Monday" now expects `rescheduleTask` (was
  `updateTask`) and checks the task lands on Monday. v0.1 had no reschedule
  tool; v0.2 added one for exactly this request. The router did not change.
- The Reminders export check runs before the command frames; "do" is no
  longer a completion verb (it read questions as completions).
- CI triggers are explicit (`push` to `main`, `pull_request` to `main`,
  manual dispatch); the hygiene job also builds the docs site.
- `SemanticIndex` takes `allowUnderTests` so the embedding eval can opt in.
- `SECURITY.md` covers the integrations and the widget snapshot.
- `MARKETING_VERSION` 0.3.0.

## [0.2.0] - 2026-10-07

Pull request "PocketBrains v2: multi-step agent, cited note Q&A, system
integrations, smarter tools". Not released to users.

### Added
- **Multi-step agent.** `CompoundPlanner` splits a request on "and",
  "then", commas and semicolons (only before a command verb), expands
  "add 3 tasks…" and "add tasks: a, b and c", files tasks under a project
  created earlier in the same request and resolves pronouns.
  `PlanExecutor` runs the plan through the tool registry, passes exact
  `id:<uuid>` references between steps (`$1`, `$1.title`, `$last`),
  checks a postcondition per step, reverts a half-done step and stops with
  a clear message. Plans appear in the thread as a plan card that updates
  in place, with numbered step cards.
- Foundation Models: compound requests get a `@Generable` plan from a
  planning session (deterministic planner as fallback), executed by
  `PlanExecutor` and narrated by a tool-less session; native multi-turn
  tool calls are numbered as steps. MLX: several `<tool_call>` envelopes in
  one reply run as a plan (`ToolCallParser.parseAll`).
- **Undo.** Every mutating tool records its inverse in a SwiftData action
  journal (`JournalEntry`), grouped per turn or plan. `UndoEngine`
  validates every inverse before applying any, so a whole plan reverts
  atomically. New `undo` tool, "undo that" intent, and Undo on tool and
  plan cards.
- **Ask your notes.** `NoteChunker` (sentence-bounded, overlapping
  passages), `NoteChunk` store, BM25 plus NLEmbedding cosine fused by
  reciprocal rank (`NotesRAG`), incremental by content hash. New
  `askNotes` tool answers with inline `[n]` citations; the deterministic
  brain answers extractively, model brains are grounded on the numbered
  passages. Citation chips under the card open the source note.
- **System integrations (opt-in).** EventKit behind `CalendarReading` /
  `RemindersWriting` protocols. `calendarAgenda` (events in a day window,
  free stretches, tasks due) and `exportToReminders` (idempotent,
  undoable). Settings → Integrations permission screen; usage descriptions
  in `project.yml`. The Morning Brief shows a calendar line when enabled.
- App Intents and App Shortcuts: Ask PocketBrains, Add Task, What's
  Blocking `<project>` (with a `ProjectEntity` query), Capture Note. Intents
  go through `ToolBox`, so they are journaled and undoable.
- **Today widget** (WidgetKit extension, small, medium and lock-screen
  rectangular) fed by a JSON snapshot in the App Group container.
- **New tools:** `rescheduleTask`, `snoozeTask`, `setPriority`,
  `setRecurrence`, `listMilestones`, `appendNote`, `searchEverything`
  (plus `askNotes`, `calendarAgenda`, `exportToReminders`, `undo`): 24 tools
  in total, wired into Foundation Models `Tool` conformances, the MLX JSON
  prompt (via the registry) and the deterministic router. `createTask`
  takes a repeat rule.
- **Recurring tasks** (`RecurrenceRule`): daily, weekdays, every N weeks,
  every N days, every other Monday. Completing one spawns the next
  occurrence (never in the past); undo puts everything back.
- **Smarter deterministic router:** synonym `Lexicon`, NLTagger lemmas and
  part of speech (with a rule-based fallback when no assets are present),
  slot-based `CommandFrames`, and fuzzy title matching on stemmed content
  words.
- **Dates:** "next Tues afternoon", "in a fortnight", "end of month",
  "every other Monday", "the day after tomorrow", "this weekend",
  "tomorrow at 4pm"; `match()` returns the exact date phrase to cut from
  titles.
- **Eval:** corpus grows from 40 to 139 synthetic utterances: v0.2
  canonical (30), compound (12), dev paraphrases (23) and a held-out
  paraphrase split (34) committed before the router work and never used to
  tune rules. The original 40 are reported separately.
- Tests for planning, argument passing, failure handling, undo, chunking,
  BM25 recall@k, citation mapping, incremental indexing, EventKit mapping
  behind mocks, the widget snapshot, recurrence and the new tools.

### Changed
- The CI gate now covers every canonical and compound case (59 + 12),
  not only the original 29 canonical utterances.
- `MARKETING_VERSION` 0.2.0. JSON export format version 2 (adds `repeats`).
- The note editor saves through `NoteService.setBody`, the single write
  path.

### Fixed
- Foundation Models streaming read `String(describing:)` of each snapshot;
  it now reads `snapshot.content`.
- `find(matching:)` no longer matches every task for an empty query.

### Added (repository polish before the v0.2 work)
- Reproducible tool-calling eval for the deterministic router
  (`Tests/Eval`): synthetic 40-utterance corpus, tool and end-to-end
  accuracy, latency, results in the CI job summary and README.
- `ToolCallParser`, extracted from the MLX backend so the prompted
  tool-call envelope is compiled and tested in every build.
- Tests for the tool registry, deterministic date parsing against a fixed
  reference date, and router regressions.
- CI on pull requests, a Linux repository-hygiene job
  (`scripts/check-hygiene.sh`), Dependabot for GitHub Actions.
- `docs/PRODUCT.md`, rewritten `docs/ARCHITECTURE.md` and `README.md`,
  `SECURITY.md`, `CONTRIBUTING.md`, issue and pull request templates.

### Fixed (repository polish before the v0.2 work)
- Router: explicit capture commands ("remind me…", "add a task…",
  "note…") now take precedence over keyword rules, so "remind me to
  finish the deck" creates a task instead of completing one.
- Router: "in N days" no longer leaks into task titles.
- Router: "notes about X" searches instead of creating a note.

### Changed (repository polish before the v0.2 work)
- CI no longer force-pushes failure logs to a `ci-log` branch and runs
  with read-only repository permissions.

### Removed (repository polish before the v0.2 work)
- A machine-specific sync script containing an absolute local path.
- The CC0 public-domain dedication, pending a licensing decision.

## [0.1.0] - 2026-07-22

First complete build of the app on `main`: the thread and spaces shell,
Deep Glass design system, SwiftData data layer, 13-tool agent with the
Foundation Models, MLX and deterministic backends, morning brief and
evening reflection, Siri intents, JSON export, privacy manifest, and a
31-test suite running on CI. Includes the data-persistence fixes recorded
in `docs/QA_REPORT.md`.
