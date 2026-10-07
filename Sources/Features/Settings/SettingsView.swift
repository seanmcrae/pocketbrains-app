import SwiftUI

/// Settings as a designed surface: the brain, the conversation, the library,
/// the privacy receipt — on glass, in the product's own voice.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pb.brain") private var brainRaw = BrainPreference.auto.rawValue

    @State private var confirmClearChat = false
    @State private var confirmErase = false
    @State private var remindersOn = NotificationPlanner.isEnabled
    @State private var exportURL: URL?
    @State private var showIntegrations = false

    var body: some View {
        ZStack {
            InkBackdrop()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: Space.l) {
                        intelligence
                        reminders
                        integrations
                        conversation
                        library
                        privacy
                        about
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.xl)
                    .frame(maxWidth: Layout.readingWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear { exportURL = Exporter.makeFile(services: app.services) }
        .sheet(isPresented: $showIntegrations) {
            IntegrationsView()
                .presentationDetents([.large])
                .presentationBackground(.clear)
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .displayStyle()
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paper.secondary)
                    .frame(width: 32, height: 32)
                    .glass(Radius.control, depth: 0.4)
            }
            .buttonStyle(GlassPressStyle())
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.l)
    }

    // MARK: Sections

    private var intelligence: some View {
        section("Intelligence") {
            HStack(spacing: Space.s) {
                AuroraOrb(energy: 0.35, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.agent.backendName)
                        .font(Type.callout)
                        .foregroundStyle(Paper.primary)
                    Text("Everything runs on this device.")
                        .font(Type.micro)
                        .foregroundStyle(Paper.tertiary)
                }
                Spacer()
            }
            .padding(.bottom, Space.xs)

            ForEach(BrainPreference.allCases) { preference in
                Button {
                    Haptics.touch()
                    brainRaw = preference.rawValue
                    app.agent.applyBrainPreference()
                } label: {
                    HStack(alignment: .top, spacing: Space.s) {
                        Image(systemName: brainRaw == preference.rawValue
                            ? "circle.inset.filled" : "circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(brainRaw == preference.rawValue ? lumen : Paper.tertiary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preference.label)
                                .font(Type.bodyMedium)
                                .foregroundStyle(Paper.primary)
                            Text(preference.detail)
                                .font(Type.caption)
                                .foregroundStyle(Paper.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(GlassPressStyle(scale: 0.99))
            }
        }
    }

    private var reminders: some View {
        section("Reminders") {
            Toggle(isOn: $remindersOn) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Due-date reminders")
                        .font(Type.bodyMedium)
                        .foregroundStyle(Paper.primary)
                    Text("A 9am nudge on the day a task is due. Scheduled locally — nothing leaves the device.")
                        .font(Type.caption)
                        .foregroundStyle(Paper.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(lumen)
            .onChange(of: remindersOn) { _, wantOn in
                Task { @MainActor in
                    let result = await NotificationPlanner.setEnabled(
                        wantOn, tasks: app.services.tasks.all())
                    if result != wantOn { remindersOn = result } // permission denied
                }
            }
        }
    }

    private var integrations: some View {
        let settings = IntegrationSettings.standard
        let on = [settings.calendarEnabled ? "Calendar" : nil,
                  settings.remindersEnabled ? "Reminders" : nil].compactMap { $0 }
        return section("Integrations") {
            row(icon: "calendar.badge.checkmark", title: "Calendar & Reminders",
                detail: on.isEmpty ? "Off · opt in to calendar context and Reminders export"
                                   : "On: " + on.joined(separator: ", ")) {
                showIntegrations = true
            }
        }
    }

    private var conversation: some View {
        section("Conversation") {
            row(icon: "eraser", title: "Clear conversation",
                detail: "\(app.agent.messages.count) message\(app.agent.messages.count == 1 ? "" : "s")") {
                confirmClearChat = true
            }
        }
        .confirmationDialog("Clear the entire conversation?",
                            isPresented: $confirmClearChat, titleVisibility: .visible) {
            Button("Clear conversation", role: .destructive) {
                Haptics.commit()
                app.agent.clearHistory()
            }
        }
    }

    private var library: some View {
        let counts = app.libraryCounts
        return section("Library") {
            HStack(spacing: Space.xs) {
                GlassChip(text: "\(counts.tasks) tasks", tint: DomainHue.task)
                GlassChip(text: "\(counts.projects) projects", tint: lumen)
                GlassChip(text: "\(counts.notes) notes", tint: DomainHue.note)
                GlassChip(text: "\(counts.links) links", tint: DomainHue.knowledge)
                Spacer()
            }
            .padding(.bottom, Space.xs)

            if let exportURL {
                ShareLink(item: exportURL) {
                    HStack(spacing: Space.s) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Paper.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Export everything")
                                .font(Type.bodyMedium)
                                .foregroundStyle(Paper.primary)
                            Text("Readable JSON — your data is yours")
                                .font(Type.caption)
                                .foregroundStyle(Paper.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Paper.faint)
                    }
                }
                .buttonStyle(GlassPressStyle(scale: 0.99))
            }
            row(icon: "sparkles.rectangle.stack", title: "Restore sample content",
                detail: "Bring back the starter projects and notes") {
                Haptics.commit()
                app.restoreSampleContent()
            }
            row(icon: "trash", title: "Erase everything",
                detail: "All tasks, projects, notes and links", destructive: true) {
                confirmErase = true
            }
        }
        .confirmationDialog("Erase all data on this device?",
                            isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) {
                Haptics.commit()
                app.eraseAllData()
            }
        }
    }

    private var privacy: some View {
        section("Privacy") {
            VStack(alignment: .leading, spacing: Space.s) {
                receiptLine("Inference", app.agent.backendName)
                receiptLine("Network calls", "Zero")
                receiptLine("Accounts & telemetry", "None")
                Text("Don't take our word for it — turn on Airplane Mode. Everything keeps working.")
                    .font(Type.caption)
                    .foregroundStyle(Paper.tertiary)
                    .padding(.top, Space.xxs)
            }
        }
    }

    private var about: some View {
        section("About") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PocketBrains")
                        .font(Type.bodyMedium)
                        .foregroundStyle(Paper.primary)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                        .font(Type.caption)
                        .foregroundStyle(Paper.tertiary)
                }
                Spacer()
                AuroraOrb(energy: 0.25, size: 26)
            }
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: title)
            VStack(alignment: .leading, spacing: Space.s) {
                content()
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(Radius.card, depth: 0.5)
        }
    }

    private func row(icon: String, title: String, detail: String,
                     destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(destructive ? DomainHue.task : Paper.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Type.bodyMedium)
                        .foregroundStyle(destructive ? DomainHue.task : Paper.primary)
                    Text(detail)
                        .font(Type.caption)
                        .foregroundStyle(Paper.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Paper.faint)
            }
        }
        .buttonStyle(GlassPressStyle(scale: 0.99))
    }

    private func receiptLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            MicroLabel(text: label)
            Spacer()
            Text(value)
                .font(Type.caption)
                .foregroundStyle(Paper.primary)
        }
    }
}
