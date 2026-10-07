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
(Settings, Intelligence), and the steps to reproduce. You should hear back
within seven days.

## In scope

- Any network egress from the app, including from third-party packages.
- Data written outside the app container, or readable by other apps.
- Exports (`Data/Export.swift`) that include more than the user selected.
- Prompt-injection paths where note content causes the agent to run a
  destructive tool the user did not ask for.

## Supported versions

Only the `main` branch is supported. There are no released versions yet.
