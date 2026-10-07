# PocketBrains: Product brief

Status: pre-release. Built and tested in CI on the iOS 26 simulator; not
yet on the App Store and without users. Numbers in this document come from
the repository's own eval and CI, and say so; targets are marked as
targets.

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

- One conversational thread over a local SwiftData store, with a 13-tool
  agent (task, project, note, knowledge-graph, agenda and recall tools).
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
- Calendar and email ingestion (would widen the privacy surface; revisit
  with explicit per-source consent).
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
| Paraphrase accuracy of the deterministic router | Same eval, paraphrase split | See README | Tracked, not gated: paraphrase is the language model's job |
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
| Small model picks the wrong tool or misparses a date | Dates are re-parsed by `NaturalDateParser`; tool cards make actions visible and undoable from the spaces |
| Prompt injection through note content triggers a destructive tool | No delete tools are exposed to the agent today; keep it that way or require confirmation |
| Deterministic router feels rigid | In-app guidance teaches the grammar; the model tiers handle paraphrase |
| SwiftData migration failures | Backup-then-fallback path in `Store` |

## Roadmap

**Now**

- Run the eval corpus against the Foundation Models brain on device and
  publish tool-call accuracy and time to first token.
- Expose `appendNote` as a tool and add an `updateNote` capability.
- Fix the O(n²) blocker lookup flagged in `docs/QA_REPORT.md`.

**Next**

- Rescheduling and milestone phrasing in the deterministic router
  ("push X to Monday", "add a milestone").
- Dynamic Type mapping and a full VoiceOver pass.
- Localization of UI strings; multilingual routing via the model tiers.

**Later**

- Optional, consented local ingestion of calendar events.
- iCloud private-database sync as an explicit opt-in, with the trade-off
  stated in the privacy story.
- TestFlight and App Store release, subject to the licensing and naming
  decisions recorded in the pull request that introduced this document.
