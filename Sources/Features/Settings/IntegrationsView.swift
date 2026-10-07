import SwiftUI

/// The explicit permission screen for the opt-in system integrations.
/// Nothing here is on by default; each switch explains exactly what is read
/// or written before the OS permission prompt appears.
struct IntegrationsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var calendarOn = IntegrationSettings.standard.calendarEnabled
    @State private var remindersOn = IntegrationSettings.standard.remindersEnabled
    @State private var calendarDenied = false
    @State private var remindersDenied = false

    var body: some View {
        ZStack {
            InkBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    HStack {
                        Text("Integrations").displayStyle()
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Paper.secondary)
                                .frame(width: 32, height: 32)
                                .glass(Radius.control, depth: 0.4)
                        }
                        .buttonStyle(GlassPressStyle())
                    }
                    .padding(.top, Space.xl)

                    Text("Both are off until you turn them on. PocketBrains reads and writes these on this device only and never sends them anywhere. If your calendars or lists sync through iCloud, iOS does that syncing under your own account settings.")
                        .font(Type.caption)
                        .foregroundStyle(Paper.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    card(icon: "calendar", title: "Calendar context",
                         what: "Reads event titles, times and locations so briefs and questions like “what's my afternoon look like?” include your meetings. PocketBrains never edits or creates events.",
                         isOn: $calendarOn, denied: calendarDenied)
                    card(icon: "checklist", title: "Reminders export",
                         what: "Copies tasks into Apple Reminders when you ask (“send today's tasks to Reminders”). Each export can be undone, which deletes only the reminders PocketBrains created.",
                         isOn: $remindersOn, denied: remindersDenied)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xl)
                .frame(maxWidth: Layout.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: calendarOn) { _, wantOn in
            Task { @MainActor in
                let integrations = app.toolbox.integrations
                if wantOn {
                    var granted = integrations.calendar.isAuthorized
                    if !granted { granted = await integrations.calendar.requestAccess() }
                    calendarDenied = !granted
                    if !granted { calendarOn = false }
                    integrations.settings.calendarEnabled = granted
                } else {
                    integrations.settings.calendarEnabled = false
                }
                app.agent.applyBrainPreference() // offer or withdraw the tool
            }
        }
        .onChange(of: remindersOn) { _, wantOn in
            Task { @MainActor in
                let integrations = app.toolbox.integrations
                if wantOn {
                    var granted = integrations.reminders.isAuthorized
                    if !granted { granted = await integrations.reminders.requestAccess() }
                    remindersDenied = !granted
                    if !granted { remindersOn = false }
                    integrations.settings.remindersEnabled = granted
                } else {
                    integrations.settings.remindersEnabled = false
                }
                app.agent.applyBrainPreference()
            }
        }
    }

    private func card(icon: String, title: String, what: String,
                      isOn: Binding<Bool>, denied: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Toggle(isOn: isOn) {
                Label(title, systemImage: icon)
                    .font(Type.bodyMedium)
                    .foregroundStyle(Paper.primary)
            }
            .tint(lumen)
            Text(what)
                .font(Type.caption)
                .foregroundStyle(Paper.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if denied {
                Text("Permission was declined. You can allow it in the Settings app → PocketBrains.")
                    .font(Type.caption)
                    .foregroundStyle(DomainHue.task)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(Radius.card, depth: 0.5)
    }
}
