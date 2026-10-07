# Verification status

Honest accounting of what has and hasn't been verified, and the exact
checklist for the first build on a Mac.

## Status: CI green ✅

Every push now **builds and passes the full test suite** on a macOS CI
runner (XcodeGen → xcodebuild test on an iOS simulator), and the app has
been run by hand on an iOS 26 simulator (thread, spaces, agent fallback,
seeding all verified working).

### Lessons banked from the CI debugging campaign

1. **`ModelContext` does not retain its `ModelContainer`.** Drop the
   container and every later context operation traps (`EXC_BREAKPOINT`
   via `swift_weakLoadStrong`) with no fatal message. Anything that holds
   a context must also hold the container — tests pin it with
   `withExtendedLifetime`.
2. Swift Testing runs suites **in parallel** — the "last started" test in
   a crash log is often an innocent bystander. Serialize before trusting
   logs.
3. A **test host app must be inert**: no Metal, no CoreMotion, no stores —
   headless CI simulators have no GPU surface and runs wedge.
4. String indices must never cross `lowercased()` copies (hardened
   runtime traps); CI artifacts/job logs live on Azure blob storage that
   restricted egress can't reach — publish failure logs to a git branch
   instead.

## Verified by construction

- One write path: agent tools and views both mutate through `DataServices`;
  `@Query`-driven views update automatically after any agent action.
- The zoom transition is driven by a single scalar (`AppModel.zoom` +
  in-flight drag delta) — properties cannot desynchronize.
- Backend fallback chain never leaves the user without a working agent:
  FoundationModels → (optional) MLX → deterministic intent parser.
- All Metal arithmetic keeps `half`/`float` types segregated (MSL does not
  implicitly convert in `mix`/vector ops).
- No spacing, radius, color, or font outside the token system.

## Known API hedges (check these first on Mac)

1. **FoundationModels `Tool.call` return type** — written as
   `async throws -> String`. If the SDK in use requires `ToolOutput`,
   wrap each return: `ToolOutput(detail)`. One-line change per tool
   (13 sites in `FoundationModelBackend.swift`).
2. **`LanguageModelSession(tools:instructions:)`** — instructions passed as
   `String`. If the initializer wants an `Instructions` builder, change to
   `LanguageModelSession(tools: t) { AgentVoice.instructions() }`.
3. **`streamResponse(to:)` element type** — v0.2 reads `snapshot.content`
   (v0.1 used `String(describing:)`, which rendered the snapshot struct
   rather than its text). If the SDK in use exposes a different property,
   this is the one line to change in `FoundationModelBackend.reply`.
4. **`@Generable` optional properties** (`let due: String?`) — supported per
   WWDC25/26 docs; if a seed rejects optionals, make them non-optional with
   "" sentinel and `@Guide` text "empty string if unknown".
5. **Self-referential SwiftData relationship** (`TaskItem.blockedBy` /
   `blocking` explicit inverse) — if the macro rejects the keypath, fall
   back to storing `blockedByIDs: [UUID]` and resolving via fetch.
6. **`Text.Layout` iteration** in `CondensationRenderer` follows the WWDC24
   "Create custom visual effects" sample (`layout → line → run → slice`).
7. **Guided-generation plans (v0.2)** — `session.respond(to:generating:)`
   with `GeneratedPlan` (`@Generable`, arrays of nested `@Generable`
   structs). If the SDK rejects nested arrays, flatten `arguments` into a
   single `"name=value; …"` string; the executor already falls back to the
   deterministic planner when generation throws.
8. **`ToolOutput` / tool count (v0.2)** — 22 tools are offered by default,
   24 with integrations on. If the session's context or tool budget is
   exceeded on device, the first remedy is trimming the tool list per
   request.
9. **MLX backend** is opt-in and untested by definition (needs the package
   + `-D POCKETBRAINS_MLX`); the `mlx-swift-examples` generate API moves —
   treat `MLXBackend.generate` as the adaptation point.

## First-run checklist (simulator/device)

Functional:
- [ ] Seeded content appears; thread welcome shows; suggestions fire.
- [ ] "Remind me to send the invoice Friday" → tool card → task visible in
      Today with Friday chip (works even in fallback mode).
- [ ] "What's blocking the website redesign?" → blocker named ("Build
      homepage in Framer" waiting on copy + photography).
- [ ] "Summarize my notes from yesterday" → notesFrom tool fires.
- [ ] Completing a task in Today updates project progress ring.
- [ ] Knowledge: tap node → refocus animation; tap focus → note opens;
      pinch/pan; link created by agent appears as new edge.
- [ ] Airplane Mode: everything above still works.

v0.2 (simulator or device):
- [ ] "Create a project Launch, add 3 tasks for Friday and link it to
      brand voice" → plan card with 5 numbered steps, all ✓; the tasks are
      in Launch; Undo on the plan card removes all of it.
- [ ] "Undo that" after a single action reverts just that turn.
- [ ] "What do my notes say about …?" → answer with `[1]` chips; tapping a
      chip opens the note. Edit the note, ask again: the answer reflects
      the edit.
- [ ] Settings → Integrations: switching Calendar on shows the iOS prompt
      once; "what's my afternoon look like?" lists real events. Denying
      shows the inline hint and leaves the switch off.
- [ ] "Export today's tasks to Reminders" → reminders appear in the
      Reminders app; "undo that" removes exactly those.
- [ ] Shortcuts app lists Ask PocketBrains, Add Task, What's Blocking,
      Capture Note; "Hey Siri, what's blocking my project in PocketBrains"
      asks for the project and answers.
- [ ] Add the Today widget (small, medium, lock screen); complete a task in
      the app and the widget updates. Needs the App Group capability on
      both targets when signed.
- [ ] Complete a recurring task in Today: the next occurrence appears.

Design (record simulator captures, step frame-by-frame):
- [ ] Horizon pull: thread recedes smoothly, no corner-radius pop at
      dock/undock boundaries; interrupt mid-gesture both directions.
- [ ] Condensation reveal: glyphs never flash at full opacity before
      settling; landing glow subtle; 60fps during streaming.
- [ ] Glass speculars track device tilt (hardware only); no shimmer strobe.
- [ ] Tool cards slide from the orb without layout jump in the scroll.
- [ ] Project card → dossier hero expansion holds the hue and radius
      concentricity; no double-render flash of the matched pair.
- [ ] TabView page swipe vs. constellation pan: if they fight, gate the
      pan gesture to `scale > 1.05` or swap TabView for a custom pager.

Performance:
- [ ] Many glass chips on screen (Today with 10+ tasks) holds 60fps on an
      A17-class device; if not, drop `GlassSheen` timeline to 10Hz for
      `depth < 0.5` surfaces.
