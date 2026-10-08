## What and why

<!-- One or two sentences on the change and the problem it solves. -->

## How it was tested

<!-- Simulator / device, iOS version, brain in use, tests added. -->

## Checklist

- [ ] CI is green (build, unit tests, hygiene)
- [ ] No new network access; data stays on device
- [ ] New or changed tools are covered by registry tests and, where relevant, eval cases
- [ ] Eval numbers in the README updated if routing behaviour changed, quoted from a CI log with its run ID
- [ ] Router rules were tuned on dev splits only; held-out utterances and expectations untouched
- [ ] No Foundation Models or MLX accuracy claimed without an on-device run
- [ ] Docs updated (`README.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`)
