# Security policy

PocketBrains is designed to keep everything on the device: the SwiftData
store, the semantic index, and every model call live in the app sandbox,
and the app makes no network requests of its own. A security report is
therefore most valuable when it shows data leaving the device, being
readable by another app, or surviving a deletion the user asked for.

## Reporting a vulnerability

Please report privately through GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository ("Security" tab, "Report a vulnerability"). Do not open
a public issue for a suspected vulnerability.

Include the iOS version, the device or simulator, the brain in use
(Settings, Intelligence, including whether "Focused tool list" is on),
which integrations are enabled, and the steps to reproduce. You should
hear back within seven days. Please give a reasonable window to ship a fix
before any public disclosure; you will be credited in the advisory unless
you prefer not to be.

## In scope

- Any network egress from the app, including from third-party packages.
- Data written outside the app container, or readable by other apps.
- Exports (`Data/Export.swift`) that include more than the user selected.
- Prompt-injection paths where note content causes the agent to run a
  destructive tool the user did not ask for, or an action that the undo
  journal cannot revert.
- The opt-in integrations: calendar data persisted by PocketBrains,
  reminders exported without a request, or exports that undo cannot remove.
- The widget snapshot in the App Group container exposing more than the
  brief headline, counts and next task titles.

## Out of scope

- Data that leaves the device through the user's own iCloud or account
  sync of Calendar and Reminders (documented in the Integrations screen).
- Issues that need a jailbroken device or physical access to an unlocked
  phone.

## Supported versions

The latest tagged release and `main` are supported. The app is not on the
App Store; releases are source releases on GitHub.
