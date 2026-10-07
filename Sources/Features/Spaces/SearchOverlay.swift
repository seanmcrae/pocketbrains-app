import SwiftUI

/// Search across the whole library, live as you type. Results navigate:
/// a task lands you in Today, a project opens its dossier, a note opens.
struct SearchOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: SearchEngine.Results {
        SearchEngine.search(query, services: app.services, index: app.semanticIndex)
    }

    var body: some View {
        ZStack {
            InkBackdrop()
            VStack(spacing: 0) {
                field
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        let found = results
                        if found.isEmpty && query.count >= 2 {
                            EmptyState(icon: "magnifyingglass",
                                       title: "Nothing yet",
                                       message: "Try fewer words — search covers titles, bodies and meaning.")
                        }
                        resultSection("Tasks", icon: "circle.dashed", tint: DomainHue.task,
                                      items: found.tasks.map { ($0.title, $0.id) }) { id in
                            go { app.space = .today }
                        }
                        resultSection("Projects", icon: "square.stack", tint: lumen,
                                      items: found.projects.map { ($0.name, $0.id) }) { id in
                            let project = found.projects.first { $0.id == id }
                            go {
                                app.space = .projects
                                app.focusedProject = project
                            }
                        }
                        resultSection("Notes", icon: "square.and.pencil", tint: DomainHue.note,
                                      items: found.notes.map { ($0.title, $0.id) }) { id in
                            let note = found.notes.first { $0.id == id }
                            go(after: 0.5) { app.focusedNote = note }
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.xl)
                    .frame(maxWidth: Layout.readingWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear { focused = true }
    }

    private var field: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Paper.tertiary)
            TextField("", text: $query,
                      prompt: Text("Search everything…").foregroundColor(Paper.tertiary))
                .font(Type.body)
                .foregroundStyle(Paper.primary)
                .tint(lumen)
                .focused($focused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Paper.tertiary)
                }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s + 2)
        .glass(Radius.control, depth: 0.6)
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.m)
        .frame(maxWidth: Layout.readingWidth)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func resultSection(_ title: String, icon: String, tint: Color,
                               items: [(String, UUID)],
                               open: @escaping (UUID) -> Void) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionHeader(title: title, detail: "\(items.count)")
                ForEach(items, id: \.1) { title, id in
                    Button {
                        Haptics.touch()
                        open(id)
                    } label: {
                        HStack(spacing: Space.s) {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tint)
                                .frame(width: 20)
                            Text(title)
                                .font(Type.callout)
                                .foregroundStyle(Paper.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Paper.faint)
                        }
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.s)
                        .glass(Radius.control, tint: tint, depth: 0.35)
                    }
                    .buttonStyle(GlassPressStyle())
                }
            }
        }
    }

    /// Dismiss, then navigate — optionally after the sheet has fully left
    /// (required when the destination is itself a sheet).
    private func go(after delay: Double = 0, _ navigate: @escaping () -> Void) {
        dismiss()
        if delay > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                navigate()
            }
        } else {
            withAnimation(Motion.glide) { navigate() }
        }
    }
}
