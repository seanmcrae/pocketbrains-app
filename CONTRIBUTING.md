# Contributing

Thanks for taking a look. PocketBrains is a single-developer project, so
issues and small, focused pull requests are the best way to help.

## Development setup

Requirements: macOS with Xcode 26 (iOS 26 SDK) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate          # writes PocketBrains.xcodeproj from project.yml
open PocketBrains.xcodeproj
```

`./scripts/dev.sh` does the pull, regenerate and open in one step. The
`.xcodeproj` is generated and git-ignored; edit `project.yml` instead.

## Running the tests

```bash
xcodebuild test \
  -project PocketBrains.xcodeproj -scheme PocketBrains \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

This is the same command CI runs. The intent-router eval runs as part of
the suite and prints `EVAL` lines with its results.

Before pushing, also run `./scripts/check-hygiene.sh`, which fails on
absolute home-directory paths, credential-shaped strings and large files.

## Ground rules

- **No network calls.** The product promise is that nothing leaves the
  device. A change that adds a network dependency needs an issue first.
- **One write path.** Agent tools and views both mutate data through
  `DataServices`; do not write to the `ModelContext` from a view or tool.
- **Every new tool** goes into `ToolBox`, `AgentToolRegistry` and the
  Foundation Models bridge, with a registry test and, where the fallback
  router should handle it, eval cases in `Tests/Eval/IntentEvalCorpus.swift`.
- **Tests keep their `ModelContainer` alive** for the whole test
  (`withExtendedLifetime`); see `docs/VERIFICATION.md` for why.
- Design values come from the token system in `Sources/DesignSystem`.

## Pull requests

Keep each PR to one concern, describe how you tested it, and make sure CI
is green. The PR template has the checklist.
