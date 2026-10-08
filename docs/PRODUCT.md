# PocketBrains: Product brief

Status: pre-release (v0.3 in review; v0.2.0 is the latest source
release). Built and tested in CI on the iOS 26 simulator; not yet on the
App Store and without users. Numbers in this document come from
the repository's own eval and CI, and say so; targets are marked as
targets.

## v0.3 at a glance

v0.3 (pull request "PocketBrains v0.3: honest generalization, tool
trimming, RAG eval, docs site") is a measurement release. It makes the
generalization number trustworthy before improving it, prepares the
Foundation Models brain for a smaller tool budget, and gives "ask your
notes" an eval large enough to mean something.

| Area | What shipped | Why it matters |
|---|---|---|
| Honest generalization | New 53-utterance held-out split frozen before any router change; 51-utterance dev split; v0.2 held-out frozen as "reported"; router constructions tuned on dev only | The v0.2 held-out number had been published, so it could no longer be a clean test |
| Tool trimming | Deterministic `ToolSelector` (about 8 of 24 tools per request, core tools always in), behind a Settings switch, with recall@k in CI | A ~3B model with 22 to 24 tool schemas is the largest known risk to on-device accuracy |
| RAG eval | 61 synthetic questions over 22 notes: recall@1/@3, answer-span hit, citation faithfulness, span attribution | 12 questions could not separate a real change from noise |
| Docs site | GitHub Pages site generated from CI logs | One place to read the evidence, with no hand-typed numbers |

### v0.3 metrics (from CI, deterministic brain and trimmer only)

| Metric | Before | v0.3 | Source (GitHub Actions run) |
|---|---|---|---|
| Tests | 112 in 15 suites | 129 in 18 suites | 37721075662, 37723402205 |
| v0.3 held-out paraphrases (53), end-to-end, never tuned on | 30.2% | 39.6% | 37721075662, 37723402205 |
| v0.2 held-out paraphrases (34), end-to-end, frozen | 35.3% | 47.1% | same |
| v0.3 dev paraphrases (51), end-to-end, tuned on | 5.9% | 100% | same |
| Canonical + compound (71), end-to-end | 100% (gated) | 100% (gated) | same |
| Tool-trimming recall@8, all 243 cases / v0.3 held-out | n/a | 96.3% / 90.6% | 37723402205 |
| Tool-trimming recall@6, all 243 cases / v0.3 held-out | n/a | 94.7% / 86.8% | 37723402205 |
| Ask-your-notes BM25 recall@1 / recall@3, 61 questions | n/a | 93.4% / 96.7% | 37723402205 |
| Citation faithfulness (extractive answers, 130 markers) | n/a | 100% | 37723402205 |
| Semantic / hybrid retrieval | n/a | skipped: no embedding asset on the CI runner | 37723402205 |

"Before" is the v0.3 branch with the new splits committed and the router
unchanged. Not measured: anything about Foundation Models or MLX, and
whether trimming helps the model; those need a device (roadmap).

### v0.3 trade-offs

- **A lower headline number on purpose.** The new held-out split scored
  30.2% before any work, below v0.2's 35.3% on its own held-out split.
  Reporting the new split as the headline makes the product look weaker
  this release and is the only way the next number means anything.
- **Constructions, not sentences.** The router gained frames for general
  constructions ("X is done", "can X slip to Y", "Idea: …") rather than
  rules for each dev miss. Dev reached 100%; the held-out split moved 9.4
  points. The remaining 32 held-out misses are left to the model tiers
  rather than chased with rules that would only fit this corpus.
- **Trimming ships off.** Recall@8 is 96.3%, so roughly 1 corpus case in 27
  would be offered a set without the right tool, and the trimmed session
  drops multi-turn context. Without on-device evidence that the smaller
  schema helps the model, the safer default is the full catalog.
- **"Push the invoice to Monday" is a reschedule.** The v0.1 expectation
  (`updateTask`) predates `rescheduleTask`; the expectation was corrected
  and the reason recorded, rather than keeping a known-wrong test or
  bending the router to it.

## v0.2 at a glance

v0.2 (pull request "PocketBrains v2: multi-step agent, cited note Q&A,
system integrations, smarter tools") moves the agent from "one sentence,
one tool call" to "one request, a checked plan", and makes every action
reversible.

| Area | What shipped | Job it serves |
|---|---|---|
| Multi-step agent | Planner (deterministic, plus Foundation Models guided generation), step executor with id passing and postconditions, plan card | Capture without filing: one sentence sets up a project |
| Undo | Action journal with inverses, atomic per plan; Undo on cards and "undo that" | Trust it |
| Ask your notes | Passage index (BM25 plus on-device embeddings), cited answers | Find what I already know |
| Integrations (opt-in) | Calendar read for briefs and "what's my afternoon look like", Reminders export, App Intents, Today widget | Start the day oriented; reach without opening the app |
| Tools and router | 24 tools (recurrence, reschedule, snooze, priority, milestones, append, search everything); lexicon, lemma and slot-frame router; richer dates | Capture without filing; know where things stand |

### v0.2 metrics (from CI, deterministic brain only)

| Metric | v0.1 | v0.2 | Source (GitHub Actions run) |
|---|---|---|---|
| Tests | 55 in 10 suites | 112 in 15 suites | 37644353241, 37652691087 |
| Original 40 utterances, end-to-end | 77.5% | 97.5% | same |
| Canonical + compound phrasing (71), end-to-end | n/a | 100% (gated) | 37652691087 |
| Held-out paraphrases (34), end-to-end | n/a | 35.3% (11.8% before the router upgrade) | 37650929852, 37652691087 |
| Ask-your-notes recall@3, BM25 path, 12 questions | n/a | 91.7% | 37652691087 |
| Routing + execution latency p95, CI simulator | 7.3 ms | 25.7 ms | 37644353241, 37652691087 |

Not measured: anything about Foundation Models or MLX (planning accuracy,
grounded-answer faithfulness, latency). Those need hardware and are the
first roadmap item.

### v0.2 trade-offs

- **Opt-in system data (EventKit) versus the privacy story.** Calendar
  read and Reminders write are the first time PocketBrains touches data it
  did not create. Both are off by default, explained on a dedicated screen
  before the iOS prompt, and requested as separate permissions. The app
  still makes no network calls. But if the user's calendars or reminder
  lists sync through iCloud (or accounts such as Google or Exchange added
  to iOS), reminders that PocketBrains exports leave the device through the
  *system's* sync, under the user's account settings, and calendar events
  it reads may have come from those services. The Integrations screen says
  so. Calendar data is read per request and never stored in PocketBrains'
  database; only the identifiers of exported reminders are kept, so an
  export can be undone.
- **Full-access calendar permission.** iOS 17+ offers write-only calendar
  access, but reading agenda context requires full access. PocketBrains
  asks for the least that delivers the feature and never writes events.
- **Undo instead of confirmation.** The agent acts first and makes every
  action reversible, rather than asking "are you sure?" on each step. That
  keeps capture fast; the journal is the safety net. There are still no
  delete tools.
- **Plans stop on first failure and keep completed steps.** Completed
  steps stay applied (and are undoable as a group) rather than rolling
  back automatically; a step that ran but failed its postcondition is
  reverted before stopping. Auto-rollback would hide partial progress the
  user may want.
- **Tool count versus a ~3B model.** 22 to 24 tools is a lot of schema for
  a small context window; integration tools are offered only after
  opt-in. (v0.3 added per-request trimming behind a switch.)
- **Widget reads a snapshot, not the database.** Moving the SwiftData
  store into the App Group would be a data migration with real risk; a
  small JSON snapshot written after each task change is enough for a
  glanceable widget.
- **Held-out honesty over a higher number.** The deterministic router was
  tuned on dev paraphrases only; the held-out split shows what that buys
  off-grammar (35.3%), and the rest is the model tiers' job.

## Problem

People who run their own work (independent consultants, founders, product
and project leads, students with heavy course loads) keep their tasks,
project status and notes in three or four apps. Capturing is easy;
connecting is not. "What's blocking the website?" means opening the task
app, finding the project, reading dependencies, then searching notes for
context. The cloud assistants that can answer that question in one
sentence need the user's entire work life on someone else's servers, which
many of these users either cannot accept (client confidentiality, NDAs,
regulated work) or do not want.

On-device language models in iOS 26 change what is possible: a capable
model that runs locally, with native tool calling. The gap is a product
that uses it to act on real structured data, works when the model is not
available, and makes the privacy guarantee verifiable instead of a
marketing line.

## Target users

| Segment | Situation | Why on-device matters |
|---|---|---|
| Independent professionals | Several clients, each with tasks and notes, often under NDA | Client data cannot go to a third-party AI service |
| Product and project leads | Many workstreams, dependencies, weekly status | Fast "what's blocked" answers without a team tool |
| Privacy-first individuals | Already avoid cloud note apps | Want AI help without the trade |

Primary persona for v1: an independent professional on a recent iPhone who
captures on the move and plans at a desk, and who will not upload client
material to a chatbot.

## Jobs to be done

1. **Capture without filing.** "Remind me to send the invoice Friday"
   becomes a dated task in the right project, from one sentence.
2. **Know where things stand.** "What's blocking the website redesign?"
   returns blockers, what they wait on, and the next milestone.
3. **Start the day oriented.** A morning brief and an agenda of overdue,
   due, blocked and this week's work.
4. **Find what I already know.** Semantic and keyword search across notes;
   "summarize my notes from yesterday".
5. **Connect ideas to work.** Link a note to a project; new notes are
   linked automatically to the projects and tasks they mention.
6. **Trust it.** Know, and be able to check, that nothing leaves the phone.

## Scope

**In (built on `main`)**

- One conversational thread over a local SwiftData store, with a 24-tool
  agent (v0.1 shipped 13; v0.2 added planning, undo, cited note Q&A,
  recurrence, scheduling and opt-in integrations).
- Three-tier brain: Apple Foundation Models, optional MLX Qwen3 build, and
  a deterministic intent router that always works.
- Spaces: Today, Projects and a Knowledge constellation, sharing one write
  path with the agent.
- Morning brief and evening reflection, due-date notifications, Siri and
  Shortcuts intents for capture, full JSON export.
- Deep Glass design system with Metal shaders and Reduce Motion support.
- Privacy manifest declaring no tracking and no collected data.

**Out (deliberately)**

- Accounts, sync, collaboration and any server component.
- Cloud model fallback. If no on-device model is usable, the deterministic
  router answers; the app never sends a prompt off the device.
- Email ingestion. (Calendar read shipped in v0.2 as an explicit opt-in;
  see "v0.2 trade-offs".)
- Non-English input for the deterministic router.

## Requirements

- Every agent action goes through a tool and is shown as a card; the model
  may not claim an action it did not perform (`AgentVoice` instructions).
- One write path (`DataServices`) for agent, views and intents.
- A turn never dead-ends: model failure falls back to the deterministic
  router; a failed turn offers retry.
- Works in Airplane Mode with full functionality of the active brain.
- Store failures never silently drop data: the broken store is backed up
  before falling back.

## Success metrics and evals

| Metric | How it is measured | Current | Target for v1 |
|---|---|---|---|
| Tool-selection accuracy, deterministic router, canonical phrasing | `Tests/Eval` on the bundled synthetic corpus, every CI run | See README "Evaluation" | 100% on canonical phrasing |
| End-to-end accuracy (right tool, succeeded, right arguments) | Same eval | See README | 100% canonical |
| Paraphrase accuracy of the deterministic router | Same eval: dev splits (tuned on) and two frozen held-out splits (never tuned on) | See README | Tracked, not gated: paraphrase is the language model's job; the v0.3 held-out split is the headline |
| Tool-trimming recall@k | Share of corpus cases whose expected tool is in the `ToolSelector` set, every CI run | See README | 95% or more at k = 8 on held-out before the switch defaults on |
| "Ask your notes" retrieval and citations | `RAGEval`: 61 synthetic questions; recall@1/@3, answer-span hit, citation faithfulness | See README | Faithfulness 100% (gated by test); recall@3 at or above 90% (gated) |
| Tool-call accuracy, Foundation Models brain | Same corpus run on an Apple Intelligence device | Not measured yet (needs hardware) | Target 90% end-to-end on the combined corpus |
| Routing plus tool execution latency, deterministic | Eval timing on the CI simulator, in-memory store | See README | Under 50 ms p95 |
| Time to first token, Foundation Models | Instrumented on device | Not measured yet | Target under 1 s on an iPhone 16 Pro class device |
| Network requests made by the app | Code has no networking APIs; to be verified with a proxy and Airplane Mode on device | Zero by construction | Zero, verified per release |
| Data collected | Privacy manifest and App Store label | None declared | None |

The accuracy floor in CI is set just below the measured canonical score so
a routing regression fails the build. Paraphrase results are reported but
not gated, because improving them with more rules would overfit the
corpus; that is what the language-model tiers are for.

## Local versus cloud: trade-offs

| Dimension | On-device (chosen) | Cloud LLM |
|---|---|---|
| Privacy | Data never leaves the phone; easy to explain and verify | Requires trust in a provider and its retention policy |
| Capability | ~3B model: good at tool selection and short replies, weaker at long reasoning | Much stronger reasoning and long context |
| Availability | Apple Intelligence devices only; mitigated by MLX tier and deterministic floor | Any device with a connection |
| Latency | No network round trip; model load and device thermals matter | Network-bound, variable |
| Cost | No per-request cost; no backend to run | Per-token cost that scales with engagement |
| Offline | Full function | None |

The decision follows from the target user: for someone under NDA, a
stronger cloud model they cannot use has no value. The capability gap is
narrowed by keeping the model's job small (pick a tool, fill arguments,
phrase a short reply) while deterministic code does the data work.

## Key decisions

| Decision | Why | Alternative considered |
|---|---|---|
| Tools as the only way to act | Prevents claimed-but-not-done actions; every action is visible as a card | Free-form generation with post-hoc parsing |
| Backend-neutral `ToolBox` with thin adapters | One implementation, three brains, one test surface | Per-backend tool code |
| Deterministic floor instead of "AI unavailable" | The product must work on every device and in the simulator | Gate the app on Apple Intelligence |
| Brain swap on generation failure | Availability checks can pass while generation fails | Surface an error |
| No cloud fallback at all | Keeps the privacy promise absolute and simple | Opt-in cloud for hard queries |
| SwiftData with conservative attribute types | Several richer shapes trapped on the iOS 26 runtime in CI | Core Data or a third-party store |
| Single conversational surface plus spaces | Talk to act, look to understand | Tabbed task, project and note apps |

## Risks

| Risk | Mitigation |
|---|---|
| Foundation Models API changes between iOS 26 point releases | API hedges listed in `docs/VERIFICATION.md`; adapter is one file |
| Trimming hides the tool a request needs | Core tools always offered; recall@k tracked in CI; the switch is off by default until measured on device |
| Small model picks the wrong tool or misparses a date | Dates are re-parsed by `NaturalDateParser`; tool cards make actions visible and undoable from the spaces |
| Prompt injection through note content triggers a destructive tool | No delete tools are exposed to the agent; every agent mutation is journaled and undoable |
| A planned request does the wrong thing in several places at once | The plan card shows every step; postconditions stop the plan; one Undo reverts the whole plan atomically |
| Exported reminders leave the device through the user's iCloud sync | Off by default; stated on the Integrations screen before the iOS prompt |
| Deterministic router feels rigid | In-app guidance teaches the grammar; the model tiers handle paraphrase |
| SwiftData migration failures | Backup-then-fallback path in `Store` |

## Roadmap

**Now**

- Run the 243-utterance corpus (including both held-out splits and the
  compound requests) against the Foundation Models brain on device;
  publish tool and plan accuracy, and time to first token (issue #5).
- Validate tool trimming on device, trimming on versus off, then choose
  its default (issue #6).
- Measure cited-answer faithfulness of model-written answers on a small
  hand-labelled set (issue #7).
- Fix the O(n²) blocker lookup flagged in `docs/QA_REPORT.md` (issue #10).

**Next**

- Dynamic Type mapping and a full VoiceOver pass (issue #8).
- Localization of UI strings; multilingual routing via the model tiers.
- Interactive widget (complete a task from the widget through App Intents, issue #9).

**Later**

- iCloud private-database sync as an explicit opt-in, with the trade-off
  stated in the privacy story.
- TestFlight and App Store release, subject to the licensing and naming
  decisions recorded in the pull request that introduced this document.
