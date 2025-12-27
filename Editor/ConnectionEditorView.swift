// CosmoOS/Editor/ConnectionEditorView.swift
// Mental Model Framework Editor
// Structured sections for crystallizing understanding

import SwiftUI
import GRDB

struct ConnectionEditorView: View {
    let connectionId: Int64
    let presentation: EditorPresentation

    @Environment(\.dismiss) var dismiss
    
    // Use shared store for instant sync with floating blocks
    @StateObject private var store = ConnectionStore.shared
    
    // Local UI state only
    @State private var showReferencePicker = false
    @State private var isGeneratingLinks = false
    @State private var canvasSize: CGSize = .zero // Track size for blocks layer
    @State private var isLoading = true

    private let database = CosmoDatabase.shared
    private let contextTracker = EditingContextTracker.shared

    init(connectionId: Int64, presentation: EditorPresentation = .focus) {
        self.connectionId = connectionId
        self.presentation = presentation
    }

    // Get connection from shared store for instant reactivity
    private var connection: Connection? {
        store.connection(for: connectionId)
    }

    // Create bindings that update through the store
    private var modelBindings: ConnectionModelBindings {
        ConnectionModelBindings(store: store, connectionId: connectionId)
    }

    // MARK: - Responsive Layout Properties

    /// Horizontal padding adapts to presentation mode
    private var horizontalPadding: CGFloat {
        presentation == .focus ? 40 : 12
    }

    /// Max width for content - only constrain in focus mode
    private var contentMaxWidth: CGFloat? {
        presentation == .focus ? 1000 : nil
    }

    /// Top spacing
    private var topSpacing: CGFloat {
        presentation == .focus ? 40 : 8
    }

    /// Section spacing
    private var sectionSpacing: CGFloat {
        presentation == .focus ? 32 : 16
    }

    /// Grid spacing
    private var gridSpacing: CGFloat {
        presentation == .focus ? 16 : 10
    }

    /// Title font adapts to presentation
    private var titleFont: Font {
        presentation == .focus ? CosmoTypography.displayLarge : CosmoTypography.title
    }

    /// Whether to use two-column grid (needs width > 400 in embedded mode)
    private var useTwoColumnGrid: Bool {
        presentation == .focus
    }

    var body: some View {
        ZStack {
            // LAYER 1: Background (only in focus mode)
            if presentation == .focus {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { canvasSize = geo.size }
                }
                .background(CosmoColors.background)
            }

            // LAYER 2: Scrollable Content
            if let conn = connection {
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: topSpacing)

                        VStack(alignment: .leading, spacing: sectionSpacing) {
                            // 1. Header (Title)
                            VStack(alignment: .leading, spacing: presentation == .focus ? 8 : 4) {
                                TextField("Concept Name", text: modelBindings.conceptName)
                                    .font(titleFont)
                                    .foregroundColor(CosmoColors.textPrimary)
                                    .textFieldStyle(.plain)
                                    .submitLabel(.done)

                                if presentation == .focus {
                                    HStack {
                                        Image(systemName: "link.circle.fill")
                                        Text("Mental Model")
                                        Text("• Updated \(timeAgo(from: conn.updatedAt))")
                                    }
                                    .font(CosmoTypography.label)
                                    .foregroundColor(CosmoColors.textTertiary)
                                }
                            }
                            .padding(.horizontal, 4)

                            // 2. Core Idea (Hero) - simplified in embedded mode
                            if presentation == .focus {
                                CoreIdeaHero(content: modelBindings.coreIdea)
                            } else {
                                CompactCoreIdeaCard(content: modelBindings.coreIdea)
                            }

                            // 3. Masonry Grid for Sections
                            if useTwoColumnGrid {
                                // Two-column layout for focus mode
                                HStack(alignment: .top, spacing: gridSpacing) {
                                    // Left Column
                                    VStack(spacing: gridSpacing) {
                                        PremiumSectionCard(
                                            title: "Goal",
                                            subtitle: "What is the desired outcome?",
                                            placeholder: "Define the goal...",
                                            content: modelBindings.goal,
                                            accentColor: CosmoColors.emerald
                                        )

                                        PremiumSectionCard(
                                            title: "Benefits",
                                            subtitle: "Why is this valuable?",
                                            placeholder: "List the benefits...",
                                            content: modelBindings.benefits,
                                            accentColor: CosmoColors.skyBlue
                                        )

                                        PremiumSectionCard(
                                            title: "Example",
                                            subtitle: "Concrete application",
                                            placeholder: "e.g. ...",
                                            content: modelBindings.example,
                                            accentColor: CosmoColors.lavender
                                        )
                                    }

                                    // Right Column
                                    VStack(spacing: gridSpacing) {
                                        PremiumSectionCard(
                                            title: "Problem",
                                            subtitle: "What friction does this solve?",
                                            placeholder: "Describe the problem...",
                                            content: modelBindings.problem,
                                            accentColor: CosmoColors.coral
                                        )

                                        PremiumSectionCard(
                                            title: "Beliefs & Objections",
                                            subtitle: "What holds you back?",
                                            placeholder: "Common limiting beliefs...",
                                            content: modelBindings.beliefsObjections,
                                            accentColor: CosmoColors.amber
                                        )

                                        PremiumSectionCard(
                                            title: "Process",
                                            subtitle: "Actionable steps",
                                            placeholder: "1. ...\n2. ...",
                                            content: modelBindings.process,
                                            accentColor: CosmoColors.slate
                                        )
                                    }
                                }
                            } else {
                                // Single-column compact layout for embedded mode
                                VStack(spacing: gridSpacing) {
                                    CompactConnectionSectionCard(title: "Goal", content: modelBindings.goal, accentColor: CosmoColors.emerald)
                                    CompactConnectionSectionCard(title: "Problem", content: modelBindings.problem, accentColor: CosmoColors.coral)
                                    CompactConnectionSectionCard(title: "Benefits", content: modelBindings.benefits, accentColor: CosmoColors.skyBlue)
                                    CompactConnectionSectionCard(title: "Beliefs", content: modelBindings.beliefsObjections, accentColor: CosmoColors.amber)
                                    CompactConnectionSectionCard(title: "Example", content: modelBindings.example, accentColor: CosmoColors.lavender)
                                    CompactConnectionSectionCard(title: "Process", content: modelBindings.process, accentColor: CosmoColors.slate)
                                }
                            }

                            // 4. References & Linked Knowledge (only in focus mode)
                            if presentation == .focus {
                                VStack(spacing: 24) {
                                    ReferencesSection(
                                        references: conn.references,
                                        onAdd: { showReferencePicker = true },
                                        onRemove: removeReference
                                    )

                                    LinkedKnowledgeSection(
                                        items: conn.linkedKnowledgeItems,
                                        isGenerating: isGeneratingLinks,
                                        onRefresh: generateLinkedKnowledge
                                    )
                                }
                            }

                            Spacer(minLength: presentation == .focus ? 100 : 20)
                        }
                        .padding(.horizontal, horizontalPadding)
                        .frame(maxWidth: contentMaxWidth)
                    }
                }
                .scrollIndicators(presentation == .focus ? .visible : .hidden)
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading connection...")
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.textTertiary)
                }
            }

            // LAYER 3: Persistent Floating Blocks (only in focus mode)
            if presentation == .focus, let id = connection?.id {
                DocumentBlocksLayer(
                    documentType: "connection",
                    documentId: id,
                    canvasCenter: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                )
            }

            // LAYER 4: Chrome/Overlay Controls
            if presentation.showsChromeHeader {
                VStack {
                    EditorHeader()
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    Spacer()
                }
            }
        }
        .background(CosmoColors.background)
        .onAppear { loadConnection() }
        .onDisappear {
            Task { await store.forceSave(connectionId) }
            scheduleKnowledgeLinking()
            contextTracker.clearEditingContext()
        }
        .onChange(of: connection) { _, newConnection in
            // Update context when connection content changes
            if let conn = newConnection {
                updateEditingContextFromConnection(conn)
            }
        }
        .sheet(isPresented: $showReferencePicker) {
            ReferencePickerSheet(onSelect: addReference)
        }
    }

    private func timeAgo(from dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Header
    @ViewBuilder
    private func EditorHeader() -> some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CosmoColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
            
            Spacer()
            
            // Right side actions
            HStack(spacing: 12) {
                Button(action: generateLinkedKnowledge) {
                    HStack(spacing: 6) {
                        if isGeneratingLinks {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                        }
                        Text("AI Insights")
                            .font(CosmoTypography.labelSmall)
                    }
                    .foregroundColor(CosmoColors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingLinks)
                
                Button(action: { Task { await store.forceSave(connectionId) } }) {
                    Text("Save")
                        .font(CosmoTypography.labelSmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(CosmoMentionColors.connection, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s")
            }
        }
    }

    // MARK: - Data Operations
    private func loadConnection() {
        Task {
            await store.loadConnection(connectionId)
            isLoading = false

            // Update editing context for telepathy/context-aware search
            if let conn = store.connection(for: connectionId) {
                updateEditingContextFromConnection(conn)
            }
        }
    }

    private func updateEditingContextFromConnection(_ conn: Connection) {
        let model = conn.mentalModelOrNew
        let fullContent = [
            model.conceptName,
            model.coreIdea,
            model.goal,
            model.problem,
            model.benefits,
            model.beliefsObjections,
            model.example,
            model.process
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")

        contextTracker.updateEditingContext(
            entityType: .connection,
            entityId: conn.id ?? connectionId,
            entityUUID: conn.uuid,
            title: conn.title ?? "Untitled",
            content: fullContent,
            cursorPosition: 0
        )
    }

    private func scheduleKnowledgeLinking() {
        Task {
            await KnowledgeLinker.shared.scheduleUpdate(for: connectionId)
        }
    }

    private func generateLinkedKnowledge() {
        isGeneratingLinks = true
        Task {
            await KnowledgeLinker.shared.updateLinkedKnowledge(for: connectionId)
            await MainActor.run {
                // Reload from store (it will pick up DB changes via observation)
                isGeneratingLinks = false
            }
        }
    }

    private func addReference(_ ref: ConnectionReference) {
        guard var conn = connection else { return }
        conn.addReference(ref)
        store.update(conn)
    }

    private func removeReference(at index: Int) {
        guard var conn = connection else { return }
        var refs = conn.references
        refs.remove(at: index)
        conn.setReferences(refs)
        store.update(conn)
    }
}

// MARK: - Connection Model Bindings
/// Helper struct to create store-backed bindings for model fields
@MainActor
private struct ConnectionModelBindings {
    let store: ConnectionStore
    let connectionId: Int64

    
    private var connection: Connection? {
        store.connection(for: connectionId)
    }
    
    private var model: ConnectionMentalModel {
        connection?.mentalModel ?? ConnectionMentalModel()
    }
    
    private func updateSection(_ keyPath: WritableKeyPath<ConnectionMentalModel, String?>, value: String?) {
        store.updateSection(connectionId, keyPath: keyPath, value: value)
    }
    
    var conceptName: Binding<String> {
        Binding(
            get: { model.conceptName ?? "" },
            set: { newValue in
                store.updateSection(connectionId, keyPath: \.conceptName, value: newValue.isEmpty ? nil : newValue)
                // Also update the connection title
                if var conn = connection {
                    conn.title = newValue.isEmpty ? conn.title : newValue
                    store.update(conn)
                }
            }
        )
    }
    
    var coreIdea: Binding<String> {
        Binding(
            get: { model.coreIdea ?? "" },
            set: { updateSection(\.coreIdea, value: $0.isEmpty ? nil : $0) }
        )
    }
    
    var goal: Binding<String> {
        Binding(
            get: { model.goal ?? "" },
            set: { updateSection(\.goal, value: $0.isEmpty ? nil : $0) }
        )
    }
    
    var problem: Binding<String> {
        Binding(
            get: { model.problem ?? "" },
            set: { updateSection(\.problem, value: $0.isEmpty ? nil : $0) }
        )
    }
    
    var benefits: Binding<String> {
        Binding(
            get: { model.benefits ?? "" },
            set: { updateSection(\.benefits, value: $0.isEmpty ? nil : $0) }
        )
    }
    
    var beliefsObjections: Binding<String> {
        Binding(
            get: { model.beliefsObjections ?? "" },
            set: { updateSection(\.beliefsObjections, value: $0.isEmpty ? nil : $0) }
        )
    }
    
    var example: Binding<String> {
        Binding(
            get: { model.example ?? "" },
            set: { updateSection(\.example, value: $0.isEmpty ? nil : $0) }
        )
    }
    
    var process: Binding<String> {
        Binding(
            get: { model.process ?? "" },
            set: { updateSection(\.process, value: $0.isEmpty ? nil : $0) }
        )
    }
}



// MARK: - Reference Card
struct ReferenceCard: View {
    let reference: ConnectionReference
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconFor(reference.entityType ?? "unknown"))
                .font(.system(size: 12))
                .foregroundColor(colorFor(reference.entityType ?? "unknown"))

            Text(reference.title)
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.textPrimary)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8))
                    .foregroundColor(CosmoColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CosmoColors.glassGrey.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    private func iconFor(_ type: String) -> String {
        switch type {
        case "research": return "magnifyingglass"
        case "idea": return "lightbulb"
        case "connection": return "link.circle"
        default: return "doc"
        }
    }

    private func colorFor(_ type: String) -> Color {
        switch type {
        case "research": return CosmoMentionColors.research
        case "idea": return CosmoMentionColors.idea
        case "connection": return CosmoMentionColors.connection
        default: return CosmoColors.textSecondary
        }
    }
}

// MARK: - Linked Knowledge Section
struct LinkedKnowledgeSection: View {
    let items: [LinkedKnowledgeItem]
    let isGenerating: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Linked Knowledge")
                    .font(CosmoTypography.titleSmall)
                    .foregroundColor(CosmoColors.textPrimary)

                Text("(Auto-generated)")
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)

                Spacer()

                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Refresh")
                            .font(CosmoTypography.labelSmall)
                    }
                    .foregroundColor(CosmoColors.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
            }

            if isGenerating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Finding related content...")
                        .font(CosmoTypography.bodySmall)
                        .foregroundColor(CosmoColors.textTertiary)
                }
                .padding()
            } else if items.isEmpty {
                Text("Related items will appear here when generated")
                    .font(CosmoTypography.bodySmall)
                    .foregroundColor(CosmoColors.textTertiary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(CosmoColors.glassGrey.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        LinkedKnowledgeRow(item: item)
                    }
                }
            }
        }
        .padding(20)
        .background(CosmoColors.mistGrey.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Linked Knowledge Row
struct LinkedKnowledgeRow: View {
    let item: LinkedKnowledgeItem

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(colorFor(item.entityType ?? item.type).opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: iconFor(item.entityType ?? item.type))
                        .font(.system(size: 10))
                        .foregroundColor(colorFor(item.entityType ?? item.type))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textPrimary)

                if let explanation = item.explanation {
                    Text(explanation)
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Relevance indicator
            Text("\(Int((item.relevanceScore ?? item.relevance) * 100))%")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private func iconFor(_ type: String) -> String {
        switch type {
        case "research": return "magnifyingglass"
        case "idea": return "lightbulb"
        case "connection": return "link.circle"
        default: return "doc"
        }
    }

    private func colorFor(_ type: String) -> Color {
        switch type {
        case "research": return CosmoMentionColors.research
        case "idea": return CosmoMentionColors.idea
        case "connection": return CosmoMentionColors.connection
        default: return CosmoColors.textSecondary
        }
    }
}

// MARK: - Reference Picker Sheet
struct ReferencePickerSheet: View {
    let onSelect: (ConnectionReference) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var searchQuery = ""
    @State private var results: [(type: String, id: Int64, title: String)] = []

    private let database = CosmoDatabase.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Reference")
                    .font(CosmoTypography.title)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            // Search
            TextField("Search ideas, research, connections...", text: $searchQuery)
                .textFieldStyle(.plain)
                .padding(12)
                .background(CosmoColors.glassGrey.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .onChange(of: searchQuery) { _, _ in search() }

            // Results
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(results, id: \.id) { result in
                        Button {
                            let ref = ConnectionReference(
                                title: result.title,
                                entityType: result.type,
                                entityId: result.id
                            )
                            onSelect(ref)
                            dismiss()
                        } label: {
                            HStack {
                                Text(result.title)
                                    .font(CosmoTypography.body)
                                Spacer()
                                Text(result.type)
                                    .font(CosmoTypography.caption)
                                    .foregroundColor(CosmoColors.textTertiary)
                            }
                            .padding()
                            .background(CosmoColors.glassGrey.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 500)
        .background(CosmoColors.softWhite)
        .onAppear { search() }
    }

    private func search() {
        // Capture MainActor-isolated property before entering async context
        let query = searchQuery
        
        Task {
            var allResults: [(type: String, id: Int64, title: String)] = []

            // Search ideas
            let queryCapture = query
            let ideas: [Idea] = (try? await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("title").like("%\(queryCapture)%"))
                    .limit(10)
                    .fetchAll(db)
                    .map { IdeaWrapper(atom: $0) }
            }) ?? []
            allResults.append(contentsOf: ideas.map { idea in
                (type: "idea", id: idea.id ?? 0, title: idea.title ?? "Untitled")
            })

            // Search research
            let research: [Research] = (try? await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.research.rawValue)
                    .filter(Column("title").like("%\(queryCapture)%"))
                    .limit(10)
                    .fetchAll(db)
                    .map { ResearchWrapper(atom: $0) }
            }) ?? []
            allResults.append(contentsOf: research.map { item in
                (type: "research", id: item.id ?? 0, title: item.title ?? "Untitled")
            })

            await MainActor.run {
                results = allResults
            }
        }
    }
}

// MARK: - Compact Core Idea Card (for embedded mode)

struct CompactCoreIdeaCard: View {
    @Binding var content: String

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(CosmoMentionColors.connection)

                Text("Core Idea")
                    .font(CosmoTypography.labelSmall)
                    .foregroundColor(CosmoMentionColors.connection)
            }

            ZStack(alignment: .topLeading) {
                if content.isEmpty && !isFocused {
                    Text("What is the central concept?")
                        .font(CosmoTypography.bodySmall)
                        .foregroundColor(CosmoColors.textTertiary.opacity(0.5))
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $content)
                    .font(CosmoTypography.bodySmall)
                    .foregroundColor(CosmoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 40, maxHeight: 80)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoMentionColors.connection.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused ? CosmoMentionColors.connection.opacity(0.4) : CosmoMentionColors.connection.opacity(0.15),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Compact Connection Section Card (for embedded mode)

struct CompactConnectionSectionCard: View {
    let title: String
    @Binding var content: String
    let accentColor: Color

    @FocusState private var isFocused: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(content.isEmpty ? CosmoColors.glassGrey : accentColor)
                        .frame(width: 6, height: 6)

                    Text(title)
                        .font(CosmoTypography.labelSmall)
                        .foregroundColor(CosmoColors.textPrimary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CosmoColors.textTertiary)
                }
            }
            .buttonStyle(.plain)

            // Content (expanded)
            if isExpanded {
                ZStack(alignment: .topLeading) {
                    if content.isEmpty && !isFocused {
                        Text("Add content...")
                            .font(CosmoTypography.bodySmall)
                            .foregroundColor(CosmoColors.textTertiary.opacity(0.5))
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $content)
                        .font(CosmoTypography.bodySmall)
                        .foregroundColor(CosmoColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .frame(minHeight: 40, maxHeight: 100)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !content.isEmpty {
                // Preview when collapsed
                Text(content)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(accentColor.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused ? accentColor.opacity(0.4) : accentColor.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}
