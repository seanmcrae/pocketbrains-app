# Roadmap

What comes next for PocketBrains, in order. Each item is a GitHub issue
labelled `roadmap`; the product reasoning behind the order is in
[docs/PRODUCT.md](docs/PRODUCT.md). Nothing here is a commitment to a date.

## Now

- [#5 Measure the Foundation Models brain on device](https://github.com/seanmcrae/pocketbrains-app/issues/5):
  run the full router corpus (including both held-out splits and the
  compound requests) on an Apple Intelligence device; publish tool and
  end-to-end accuracy and time to first token. Until then, no model
  accuracy is claimed.
- [#6 Validate per-request tool trimming on device](https://github.com/seanmcrae/pocketbrains-app/issues/6):
  trimming on versus off on the same corpus, then choose its default.
- [#7 Hand-labelled faithfulness set for model-written cited answers](https://github.com/seanmcrae/pocketbrains-app/issues/7).

## Next

- [#8 Dynamic Type and a full VoiceOver pass](https://github.com/seanmcrae/pocketbrains-app/issues/8).
- [#9 Interactive Today widget](https://github.com/seanmcrae/pocketbrains-app/issues/9):
  complete a task from the widget, journaled and undoable.
- [#10 Replace the O(n^2) blocker lookup](https://github.com/seanmcrae/pocketbrains-app/issues/10).

## Later

- Localization of UI strings; multilingual requests through the model
  tiers (the deterministic router stays English).
- Opt-in iCloud private-database sync, with the trade-off stated in the
  privacy story.
- TestFlight and App Store release, after the licensing and naming
  decisions.

## Deliberately not planned

- A cloud model fallback. If no on-device model is usable, the
  deterministic router answers; prompts never leave the phone.
- Delete tools for the agent. Everything the agent does stays undoable.
