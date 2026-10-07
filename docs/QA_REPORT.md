# PocketBrains — QA Report
_Session: 2026-07-22 · Reviewer: Oz (Warp AI)_

---

## Scope

Full audit of the Data and Intelligence modules:

- `Sources/Data/` — Models, Services, Store, SearchEngine, SemanticIndex, NotificationPlanner, Export, SeedData
- `Sources/Intelligence/` — ModelBackend, FoundationModelBackend, MLXBackend, IntentFallbackBackend, SemanticIndex
- `Sources/Agent/` — ToolBox, AgentTool, AgentOrchestrator, BriefEngine, NaturalDateParser
- `Tests/` — all five suites (31 tests)

---

## Shipped fixes (PR #1 · merged to main · commit 3a6c4ea)

### Critical — SemanticIndex: embedding cache non-functional across launches
**File:** `Sources/Intelligence/Embeddings/SemanticIndex.swift`

Swift's `hashValue` is randomised per-process (SE-0206, Swift 4.2). Every cold
start produced a different hash, so `EmbeddingRecord.contentHash` never matched
and all embeddings were deleted and recomputed on every launch.

**Fix:** Replaced `hashValue` with a DJB2-style polynomial hash over the note's
UTF-8 bytes (`stableHash`). Deterministic across processes and reboots. Overflow-
safe with `&*`/`&+` operators. Also simplified `sqrt(na) * sqrt(nb)` → `sqrt(na * nb)`.

---

### Critical — Store: silent data loss on schema migration failure
**File:** `Sources/Data/Store.swift`

A `ModelContainer` init failure (e.g. a schema migration after an app update)
silently fell back to a blank in-memory store with no log, no backup, and no
alert. User data vanished without indication. The inner `try!` would also
produce an opaque crash if the in-memory fallback itself failed.

**Fix:**
- Logs the error to Console/crash reporters via `print()`.
- Exposes `Store.migrationError: Error?` and `Store.lastStoreBackupURL: URL?`
  so the app model can show a recovery banner on next launch.
- `backupBrokenStore()` renames all `.store`/`.sqlite`/`.db` files and their
  WAL/SHM companions to timestamped `.bak-<unix>` copies before abandoning
  the store, preserving data for manual recovery.
- Replaces the blind `try!` with a `do/catch` + `fatalError` that names both
  the original and the fallback error.

---

### Medium — Note.tags: newline corruption possible
**File:** `Sources/Data/Models.swift`

Tags are stored with `"\n"` as a separator. Neither the computed-property setter
nor `init` validated that incoming strings were newline-free. A pasted or
model-generated tag containing `\n` would silently split into phantom tags on
the next read.

**Fix:** Both the setter and `init` now strip all newline characters from each
tag via `.components(separatedBy: .newlines).joined()` and drop empty strings
before writing `tagsRaw`.

---

### Test results after fixes

```
31 tests · 6 suites · 0 failures  (iOS 26 simulator, Xcode 26.5)

AAStoreDiagnostics          1/1  ✓
IntentFallbackBackendTests  3/3  ✓
ChunkClockTests             3/3  ✓
NaturalDateParserTests      7/7  ✓
OrbitalLayoutTests          5/5  ✓
ToolBoxTests               12/12 ✓
```

---

## Open backlog (prioritised)

> Update, 2026-10-07 (`portfolio-polish`): #10 is fixed and tested (the
> router's `dueText` now recognises "in N days"). #4 is a false positive:
> in Swift, `??` binds tighter than `&&`, so the expression already reads
> as `(dueDate.map { … } ?? false) && !isOverdue`. #3 is resolved by the
> rewritten `docs/ARCHITECTURE.md`. The rest remain open.

### High

| # | File | Issue |
|---|---|---|
| 1 | `ToolBox.swift`, all backends | `appendNote` implemented but never wired into `AgentToolRegistry` or `FoundationModelBackend.tools()` — agent cannot append to notes |
| 2 | `Models.swift:63` | `TaskItem.blockers` calls `context.fetchAll(TaskItem.self)` inside a computed property; called repeatedly from project views → O(n²) fetch work |
| 3 | `ARCHITECTURE.md` | Documents non-existent `Tag` model; `ModelBackend` protocol signature and event names are stale |

### Medium

| # | File | Issue |
|---|---|---|
| 4 | `BriefEngine.swift:22` | `?? false && !$0.isOverdue` — `&&` binds tighter than `??`, so `!$0.isOverdue` is dead code (behaviour accidentally correct but intent is wrong) |
| 5 | `FoundationModelBackend.swift:41` | `String(describing: partial)` on stream elements — may emit debug-description noise if SDK element type is not a plain `String` |
| 6 | `Services.swift` + `ToolBox.swift` | No `updateNote` capability: agent cannot rename a note, replace its body, or change its tags |
| 7 | `MLXBackend.swift:103` | Hard-coded 1024-token generation cap — long responses silently truncated |

### Low / code quality

| # | File | Issue |
|---|---|---|
| 8 | `Services.swift:83` | Bidirectional title match (`q.contains(title)`) overly broad on short task/project names |
| 9 | `Services.swift:147` | Force-unwrap `m.reachedAt!` safe by guard but fragile |
| 10 | `IntentFallbackBackend.swift:159` | `dueText()` doesn't handle "in N days" — date phrase leaks into task title |

---

## Test coverage gaps

- No test for `appendNote` (and it is not wired up — see backlog #1)
- No round-trip test for `blockedByIDs` Data packing/unpacking
- No test for `autoWeave` false-positive suppression (4-char minimum)
- No test for `Store.makeContainer` migration-failure path
- No test for `SemanticIndex.reindexAll` content-change detection (would have caught the `hashValue` bug immediately)
