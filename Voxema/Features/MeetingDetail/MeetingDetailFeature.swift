import SwiftUI
import UniformTypeIdentifiers

// MARK: - MeetingDetailView

struct MeetingDetailView: View {
    @EnvironmentObject private var appState: AppState
    let meeting: Meeting

    @State private var selectedTab: DetailTab = .summary
    @State private var editingTitle: String = ""
    @State private var isEditingTitle = false
    @State private var showDeleteConfirmation = false
    @State private var exportError: String? = nil

    enum DetailTab: String, CaseIterable {
        case summary = "Summary"
        case transcript = "Transcript"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            tabContent
            exportBar
        }
        .onAppear { editingTitle = meeting.title }
        .onChange(of: meeting.meetingId) { _ in editingTitle = meeting.title }
        .confirmationDialog(
            "Delete \"\(meeting.title)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.deleteMeeting(id: meeting.meetingId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action is permanent and cannot be undone.")
        }
        .alert(
            String(localized: "Export Failed"),
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            ),
            presenting: exportError
        ) { _ in
            Button(String(localized: "OK"), role: .cancel) { exportError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if isEditingTitle {
                    TextField("Meeting title", text: $editingTitle, onCommit: commitRename)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .bold))
                        .onExitCommand { cancelRename() }
                } else {
                    Text(meeting.title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Button {
                        editingTitle = meeting.title
                        isEditingTitle = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Rename meeting")
                }
            }
            HStack(spacing: 12) {
                Label(formattedDate, systemImage: "calendar")
                Label(formattedDuration, systemImage: "timer")
                if !meeting.speakers.isEmpty {
                    Label("\(meeting.speakers.count) speaker\(meeting.speakers.count == 1 ? "" : "s")", systemImage: "person.2")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .offset(y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            switch selectedTab {
            case .summary:  SummaryTabView(meeting: meeting)
            case .transcript: TranscriptTabView(meeting: meeting)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Export Bar

    private var exportBar: some View {
        HStack(spacing: 8) {
            Button {
                exportMarkdown()
            } label: {
                Label("MD", systemImage: "doc.text")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(ExportButtonStyle())

            Button {
                exportJSON()
            } label: {
                Label("JSON", systemImage: "curlybraces")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(ExportButtonStyle())

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Delete")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.red.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Actions

    private func commitRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            appState.renameMeeting(id: meeting.meetingId, title: trimmed)
        }
        isEditingTitle = false
    }

    private func cancelRename() {
        editingTitle = meeting.title
        isEditingTitle = false
    }

    private func exportMarkdown() {
        let config = ExportConfiguration.default
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "\(meeting.title).md"
        panel.directoryURL = config.exportsDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MarkdownExporter.render(meeting).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportJSON() {
        let config = ExportConfiguration.default
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(meeting.title).json"
        panel.directoryURL = config.exportsDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try JSONExporter.render(meeting).write(to: url, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: meeting.recordedAt)
    }

    private var formattedDuration: String {
        let m = Int(meeting.durationSeconds) / 60
        let s = Int(meeting.durationSeconds) % 60
        return s == 0 ? "\(m) min" : "\(m)m \(s)s"
    }
}

// MARK: - SummaryTabView

private struct SummaryTabView: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let summary = meeting.summary {
                if !summary.summaryText.isEmpty {
                    section("Overview") {
                        Text(summary.summaryText)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                if !summary.actionItems.isEmpty {
                    section("Action Items") {
                        VStack(spacing: 0) {
                            ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                                ActionItemRow(item: item)
                                if item.actionDescription != summary.actionItems.last?.actionDescription {
                                    Divider().padding(.leading, 26)
                                }
                            }
                        }
                    }
                }
                if !summary.keyDecisions.isEmpty {
                    section("Key Decisions") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(summary.keyDecisions, id: \.self) { decision in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(decision)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(2)
                                }
                            }
                        }
                    }
                }
                if !summary.openQuestions.isEmpty {
                    section("Open Questions") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(summary.openQuestions, id: \.self) { q in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("?").foregroundStyle(.secondary)
                                    Text(q)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(2)
                                }
                            }
                        }
                    }
                }
            } else {
                emptySummary
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptySummary: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("No summary available")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.7)
            content()
        }
    }
}

// MARK: - ActionItemRow

private struct ActionItemRow: View {
    let item: ActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(nsColor: .tertiaryLabelColor), lineWidth: 1.5)
                .frame(width: 15, height: 15)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.actionDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                HStack(spacing: 8) {
                    if let assignee = item.assignee {
                        Text("→ \(assignee)")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                    if let deadline = item.deadline {
                        Text("Due: \(deadline)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - TranscriptTabView

private struct TranscriptTabView: View {
    let meeting: Meeting

    var body: some View {
        if meeting.transcript.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 32))
                    .foregroundStyle(.quaternary)
                Text("No transcript available")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(meeting.transcript) { segment in
                    TranscriptSegmentRow(segment: segment)
                    Divider().opacity(0.4)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct TranscriptSegmentRow: View {
    let segment: DiarizedSegment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(formattedTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 38, alignment: .trailing)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.speaker.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(segment.speaker.isUser ? .accentColor : .green)
                Text(segment.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
    }

    private var formattedTime: String {
        String(format: "%02d:%02d", Int(segment.startTime) / 60, Int(segment.startTime) % 60)
    }
}

// MARK: - ExportButtonStyle

private struct ExportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
