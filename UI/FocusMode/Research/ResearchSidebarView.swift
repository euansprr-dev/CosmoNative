// CosmoOS/UI/FocusMode/Research/ResearchSidebarView.swift
// Intelligent sidebar for Research Focus Mode with 4 sections:
// Related Knowledge, Insight Atoms, AI Analysis, Linked Items
// February 2026

import SwiftUI

// MARK: - Research Sidebar View

struct ResearchSidebarView: View {
    let atom: Atom
    @Binding var state: ResearchFocusModeState
    let isVisible: Bool

    @State private var selectedSection: SidebarSection = .relatedKnowledge
    @State private var relatedItems: [RelatedItem] = []
    @State private var isLoadingRelated = false
    @State private var draftInsights: [DraftInsightAtom] = []
    @State private var isExtractingInsights = false
    @State private var analysis: ResearchAnalysis?
    @State private var isAnalyzing = false
    @State private var linkedConnections: [Atom] = []
    @State private var linkedContent: [Atom] = []
    @State private var linkedResearch: [Atom] = []
    @State private var showConnectionPicker = false
    @State private var connectionPickerAnnotationID: UUID?
    @State private var allConnections: [Atom] = []
    @State private var connectionRelevanceScores: [String: Double] = [:]
    @State private var filteredConnections: [RelatedItem] = []
    @State private var filteredResearch: [RelatedItem] = []
    @State private var filteredContent: [RelatedItem] = []

    private let panelWidth: CGFloat = 320
    private let accentColor = DS.accent

    @StateObject private var ambientEngine = AmbientFieldEngine()

    enum SidebarSection: String, CaseIterable {
        case relatedKnowledge = "Related"
        case insightAtoms = "Insights"
        case aiAnalysis = "Analysis"
        case linkedItems = "Linked"
        case ambient = "Ambient"
    }

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                sidebarHeader
                sectionTabs
                Divider().background(DS.border)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedSection {
                        case .relatedKnowledge:
                            relatedKnowledgeSection
                        case .insightAtoms:
                            insightAtomsSection
                        case .aiAnalysis:
                            aiAnalysisSection
                        case .linkedItems:
                            linkedItemsSection
                        case .ambient:
                            ambientSection
                        }
                    }
                    .padding(16)
                }
            }
            .frame(width: panelWidth)
            .background(DS.surface)
            .onAppear {
                Task { await loadInitialData() }
                // Seed ambient engine with research atom context
                let queryText = [atom.title ?? "", String((atom.body ?? "").prefix(200))].joined(separator: " ")
                ambientEngine.updateContext(focusAtomUUID: atom.uuid, currentText: queryText)
            }
            .onChange(of: state.allAnnotations.count) { _ in
                Task { await refreshRelatedItems() }
            }
            .onChange(of: relatedItems.count) { _ in
                filteredConnections = relatedItems.filter { $0.type == .connection }
                filteredResearch = relatedItems.filter { $0.type == .research }
                filteredContent = relatedItems.filter { $0.type == .content }
            }
            .sheet(isPresented: $showConnectionPicker) {
                connectionPickerSheet
            }
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13))
                .foregroundColor(accentColor)

            Text("Intelligence")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.text)

            Spacer()

            // Annotation count badge
            if !state.allAnnotations.isEmpty {
                Text("\(state.allAnnotations.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Section Tabs

    private var sectionTabs: some View {
        HStack(spacing: 0) {
            ForEach(SidebarSection.allCases, id: \.rawValue) { section in
                sectionTabButton(section)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func sectionTabButton(_ section: SidebarSection) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                selectedSection = section
            }
        } label: {
            Text(section.rawValue)
                .font(.system(size: 10, weight: selectedSection == section ? .bold : .medium))
                .foregroundColor(selectedSection == section ? accentColor : DS.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selectedSection == section ? accentColor.opacity(0.12) : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 1: Related Knowledge

    @ViewBuilder
    private var relatedKnowledgeSection: some View {
        if isLoadingRelated {
            loadingIndicator("Searching knowledge graph...")
        } else if relatedItems.isEmpty {
            emptyState(
                icon: "magnifyingglass",
                message: "No related items found yet",
                detail: "Add annotations to refine the search"
            )
        } else {
            relatedKnowledgeList
        }
    }

    private var relatedKnowledgeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Connections (cached)
            if !filteredConnections.isEmpty {
                sectionLabel(title: "CONNECTIONS", icon: "link.circle.fill")
                ForEach(filteredConnections) { item in
                    relatedItemCard(item)
                }
            }

            // Research (cached)
            if !filteredResearch.isEmpty {
                sectionLabel(title: "RELATED RESEARCH", icon: "magnifyingglass")
                ForEach(filteredResearch) { item in
                    relatedItemCard(item)
                }
            }

            // Content (cached)
            if !filteredContent.isEmpty {
                sectionLabel(title: "CONTENT", icon: "doc.text.fill")
                ForEach(filteredContent) { item in
                    relatedItemCard(item)
                }
            }
        }
    }

    private func relatedItemCard(_ item: RelatedItem) -> some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": item.atomUUID]
            )
        } label: {
            relatedItemCardLabel(item)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func relatedItemCardLabel(_ item: RelatedItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForType(item.type))
                .font(.system(size: 11))
                .foregroundColor(colorForType(item.type))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(2)

                if !item.preview.isEmpty {
                    Text(item.preview)
                        .font(.system(size: 9))
                        .foregroundColor(DS.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(String(format: "%.0f%%", item.relevanceScore * 100))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(DS.textMuted)
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Section 2: Insight Atoms

    @ViewBuilder
    private var insightAtomsSection: some View {
        // Existing annotations
        let annotations = state.allAnnotations
        if !annotations.isEmpty {
            sectionLabel(title: "YOUR ANNOTATIONS", icon: "note.text")
            ForEach(annotations) { annotation in
                annotationCard(annotation)
            }
        }

        // AI-suggested insights
        let pending = draftInsights.filter { !$0.isAccepted && !$0.isDismissed }
        if !pending.isEmpty {
            sectionLabel(title: "AI SUGGESTED", icon: "sparkles")
            ForEach(pending) { draft in
                draftInsightCard(draft)
            }
        }

        if annotations.isEmpty && pending.isEmpty && !isExtractingInsights {
            emptyState(
                icon: "lightbulb",
                message: "No insights yet",
                detail: "Add annotations or run AI Analysis to extract insights"
            )
        }

        if isExtractingInsights {
            loadingIndicator("Extracting insights...")
        }
    }

    private func annotationCard(_ annotation: ResearchAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type badge + timestamp
            HStack(spacing: 6) {
                annotationTypeBadge(annotation.type)
                Spacer()
                Text(annotation.timestampString)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textMuted)
            }

            // Content
            Text(annotation.content.isEmpty ? "(empty annotation)" : annotation.content)
                .font(.system(size: 11))
                .foregroundColor(annotation.content.isEmpty ? DS.textMuted : DS.textSecondary)
                .lineLimit(4)

            // Highlighted text reference
            if let highlighted = annotation.highlightedText, !highlighted.isEmpty {
                highlightedTextReference(highlighted)
            }

            // Action buttons
            annotationActionButtons(annotation)
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func highlightedTextReference(_ text: String) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(DS.borderActive)
                .frame(width: 2)
            Text(text)
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)
                .lineLimit(2)
                .italic()
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func annotationActionButtons(_ annotation: ResearchAnnotation) -> some View {
        HStack(spacing: 8) {
            Button {
                connectionPickerAnnotationID = annotation.id
                showConnectionPicker = true
            } label: {
                actionButtonLabel(text: "Link", icon: "link")
            }
            .buttonStyle(.plain)

            Button {
                Task { await createConnectionFromAnnotation(annotation) }
            } label: {
                actionButtonLabel(text: "Create Connection", icon: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButtonLabel(text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(accentColor.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accentColor.opacity(0.08), in: Capsule())
    }

    private func draftInsightCard(_ draft: DraftInsightAtom) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                annotationTypeBadge(draft.type)

                Text("AI")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(hex: "#06B6D4"))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#06B6D4").opacity(0.15), in: Capsule())

                Spacer()

                Text(String(format: "%.0f%%", draft.confidence * 100))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textMuted)
            }

            Text(draft.content)
                .font(.system(size: 11))
                .foregroundColor(DS.textSecondary)
                .lineLimit(4)

            // Accept / Dismiss
            HStack(spacing: 8) {
                Button {
                    acceptDraftInsight(draft)
                } label: {
                    draftActionLabel(text: "Accept", icon: "checkmark.circle.fill", color: Color(hex: "#22C55E"))
                }
                .buttonStyle(.plain)

                Button {
                    dismissDraftInsight(draft)
                } label: {
                    draftActionLabel(text: "Dismiss", icon: "xmark.circle", color: DS.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(Color(hex: "#06B6D4").opacity(0.25))
        )
    }

    @ViewBuilder
    private func draftActionLabel(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }

    private func annotationTypeBadge(_ type: AnnotationType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.system(size: 9))
            Text(type.label)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(type.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(type.color.opacity(0.12), in: Capsule())
    }

    // MARK: - Section 3: AI Analysis

    @ViewBuilder
    private var aiAnalysisSection: some View {
        if isAnalyzing {
            loadingIndicator("Analyzing research...")
        } else if let analysis = analysis {
            aiAnalysisContent(analysis)
        } else {
            analyzeButton
        }
    }

    private var analyzeButton: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28))
                .foregroundColor(accentColor.opacity(0.5))

            Text("Run AI analysis to extract key arguments, contrarian takes, and actionable takeaways.")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)

            Button {
                Task { await runAnalysis() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("Analyze")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func aiAnalysisContent(_ analysis: ResearchAnalysis) -> some View {
        // Key Arguments
        if !analysis.keyArguments.isEmpty {
            analysisSubsection(title: "KEY ARGUMENTS", icon: "text.quote", color: Color(hex: "#3B82F6"))
            ForEach(analysis.keyArguments) { arg in
                analysisCard(title: arg.claim, detail: arg.evidence)
            }
        }

        // Contrarian Takes
        if !analysis.contrarianTakes.isEmpty {
            analysisSubsection(title: "CONTRARIAN TAKES", icon: "exclamationmark.triangle.fill", color: Color(hex: "#FFD700"))
            ForEach(analysis.contrarianTakes) { take in
                analysisCard(title: take.take, detail: take.reasoning, accentColor: Color(hex: "#FFD700"))
            }
        }

        // Actionable Takeaways
        if !analysis.actionableTakeaways.isEmpty {
            analysisSubsection(title: "ACTIONABLE TAKEAWAYS", icon: "checkmark.circle.fill", color: Color(hex: "#22C55E"))
            ForEach(analysis.actionableTakeaways) { takeaway in
                analysisCard(title: takeaway.action, detail: takeaway.relevance, accentColor: Color(hex: "#22C55E"))
            }
        }

        // Connection Suggestions
        if !analysis.connectionSuggestions.isEmpty {
            analysisSubsection(title: "CONNECTION SUGGESTIONS", icon: "link.circle.fill", color: Color(hex: "#8B5CF6"))
            ForEach(analysis.connectionSuggestions) { suggestion in
                connectionSuggestionCard(suggestion)
            }
        }

        // Re-analyze button
        Button {
            self.analysis = nil
            Task { await runAnalysis() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                Text("Re-analyze")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(DS.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DS.border, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    private func analysisSubsection(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(color)
        }
        .padding(.top, 8)
    }

    private func analysisCard(title: String, detail: String?, accentColor: Color = Color(hex: "#3B82F6")) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.text)

            if let detail = detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
    }

    private func connectionSuggestionCard(_ suggestion: ResearchAnalysis.ConnectionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#8B5CF6"))

                Text(suggestion.connectionTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.text)

                Spacer()

                if suggestion.existingConnectionUUID != nil {
                    Text("EXISTS")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Color(hex: "#22C55E"))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#22C55E").opacity(0.15), in: Capsule())
                }
            }

            Text(suggestion.reasoning)
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)
                .lineLimit(3)

            if let existingUUID = suggestion.existingConnectionUUID {
                Button {
                    Task { await linkToConnection(existingUUID) }
                } label: {
                    actionButtonLabel(text: "Link Research", icon: "link.badge.plus")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await createNewConnection(title: suggestion.connectionTitle, reasoning: suggestion.reasoning) }
                } label: {
                    actionButtonLabel(text: "Create Connection", icon: "plus.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Section 4: Linked Items

    @ViewBuilder
    private var linkedItemsSection: some View {
        // Connections this research feeds into
        if !linkedConnections.isEmpty {
            sectionLabel(title: "CONNECTIONS", icon: "link.circle.fill")
            ForEach(linkedConnections, id: \.uuid) { connection in
                linkedItemRow(connection, removable: true)
            }
        }

        // Content referencing this research
        if !linkedContent.isEmpty {
            sectionLabel(title: "CONTENT", icon: "doc.text.fill")
            ForEach(linkedContent, id: \.uuid) { content in
                linkedItemRow(content, removable: true)
            }
        }

        // Related research via shared connections
        if !linkedResearch.isEmpty {
            sectionLabel(title: "SHARED RESEARCH", icon: "magnifyingglass")
            ForEach(linkedResearch, id: \.uuid) { research in
                linkedItemRow(research, removable: false)
            }
        }

        if linkedConnections.isEmpty && linkedContent.isEmpty && linkedResearch.isEmpty {
            emptyState(
                icon: "link",
                message: "No linked items",
                detail: "Link this research to connections and content pieces"
            )
        }

        // Add link button
        addLinkButton
    }

    @ViewBuilder
    private func linkedItemRow(_ item: Atom, removable: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openBlockInFocusMode,
                    object: nil,
                    userInfo: ["atomUUID": item.uuid]
                )
            } label: {
                linkedItemRowLabel(item)
            }
            .buttonStyle(.plain)

            if removable {
                Button {
                    Task { await unlinkAtom(item.uuid) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func linkedItemRowLabel(_ item: Atom) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconForType(item.type))
                .font(.system(size: 10))
                .foregroundColor(colorForType(item.type))
                .frame(width: 16)

            Text(item.title ?? "Untitled")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.text)
                .lineLimit(1)

            Spacer()
        }
        .padding(8)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
    }

    private var addLinkButton: some View {
        Button {
            showConnectionPicker = true
            connectionPickerAnnotationID = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                Text("Add Link")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - Connection Picker Sheet

    private var connectionPickerSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Link to Connection")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.text)
                Spacer()
                Button("Cancel") { showConnectionPicker = false }
                    .buttonStyle(.plain)
                    .foregroundColor(DS.textSecondary)
            }

            if allConnections.isEmpty {
                Text("No connections found")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textMuted)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(allConnections, id: \.uuid) { connection in
                            connectionPickerRow(connection)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(DS.surfaceCard)
        .onAppear {
            Task { await loadAllConnections() }
        }
    }

    @ViewBuilder
    private func connectionPickerRow(_ connection: Atom) -> some View {
        Button {
            Task {
                await linkToConnection(connection.uuid)
                showConnectionPicker = false
            }
        } label: {
            connectionPickerRowLabel(connection)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func connectionPickerRowLabel(_ connection: Atom) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#8B5CF6"))

            Text(connection.title ?? "Untitled")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.text)
                .lineLimit(1)

            Spacer()

            if let score = connectionRelevanceScores[connection.uuid] {
                Text(String(format: "%.0f%%", score * 100))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textMuted)
            }
        }
        .padding(10)
        .background(DS.border, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Shared UI Components

    private func sectionLabel(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(DS.textMuted)
        }
    }

    private func loadingIndicator(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(accentColor)
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func emptyState(icon: String, message: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(DS.textMuted)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.textMuted)
            Text(detail)
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Data Loading

    private func loadInitialData() async {
        await refreshRelatedItems()
        await loadLinkedItems()
    }

    private func refreshRelatedItems() async {
        isLoadingRelated = true
        defer { isLoadingRelated = false }

        do {
            relatedItems = try await InsightExtractionEngine.shared.findRelatedItems(
                research: atom,
                sections: state.transcriptSections
            )
        } catch {
            print("ResearchSidebar: Failed to load related items: \(error)")
        }
    }

    private func loadLinkedItems() async {
        let links = atom.linksList
        linkedConnections = []
        linkedContent = []
        linkedResearch = []

        for link in links {
            guard let linkedAtom = try? await AtomRepository.shared.fetch(uuid: link.uuid) else { continue }
            switch linkedAtom.type {
            case .connection: linkedConnections.append(linkedAtom)
            case .content: linkedContent.append(linkedAtom)
            case .research:
                if linkedAtom.uuid != atom.uuid {
                    linkedResearch.append(linkedAtom)
                }
            default: break
            }
        }
    }

    private func loadAllConnections() async {
        do {
            allConnections = try await AtomRepository.shared.fetchByTypes([.connection])

            // Compute relevance scores
            let query = atom.title ?? ""
            guard !query.isEmpty else { return }

            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 50,
                entityTypes: [.connection]
            )

            for result in results {
                if let uuid = result.entityUUID {
                    connectionRelevanceScores[uuid] = result.combinedScore
                }
            }

            // Sort connections by relevance
            allConnections.sort { a, b in
                (connectionRelevanceScores[a.uuid] ?? 0) > (connectionRelevanceScores[b.uuid] ?? 0)
            }
        } catch {
            print("ResearchSidebar: Failed to load connections: \(error)")
        }
    }

    // MARK: - Actions

    private func runAnalysis() async {
        isAnalyzing = true
        isExtractingInsights = true
        defer {
            isAnalyzing = false
            isExtractingInsights = false
        }

        do {
            // Load existing connections for context
            let connections = try await AtomRepository.shared.fetchByTypes([.connection])
            let researchAtoms = try await AtomRepository.shared.fetchByTypes([.research])
            let researchTitles = researchAtoms
                .filter { $0.uuid != atom.uuid }
                .compactMap { $0.title }

            // Run full analysis
            analysis = try await InsightExtractionEngine.shared.analyzeResearch(
                research: atom,
                sections: state.transcriptSections,
                existingConnections: connections,
                existingResearchTitles: researchTitles
            )

            // Also extract draft insights
            let insights = try await InsightExtractionEngine.shared.extractInsights(
                research: atom,
                sections: state.transcriptSections
            )
            draftInsights = insights
        } catch {
            print("ResearchSidebar: Analysis failed: \(error)")
        }
    }

    private func acceptDraftInsight(_ draft: DraftInsightAtom) {
        guard let index = draftInsights.firstIndex(where: { $0.id == draft.id }) else { return }
        draftInsights[index].isAccepted = true

        // Create a real annotation in the state
        let annotation = ResearchAnnotation(
            type: draft.type,
            content: draft.content,
            timestamp: draft.suggestedTimestamp
        )

        if let sectionID = draft.suggestedSectionID {
            state.addAnnotation(annotation, toSection: sectionID)
        } else {
            state.addStandaloneAnnotation(annotation)
        }
        state.save()
    }

    private func dismissDraftInsight(_ draft: DraftInsightAtom) {
        guard let index = draftInsights.firstIndex(where: { $0.id == draft.id }) else { return }
        draftInsights[index].isDismissed = true
    }

    private func linkToConnection(_ connectionUUID: String) async {
        var updatedAtom = atom
        var links = updatedAtom.linksList
        let newLink = AtomLink(type: AtomLinkType.connection.rawValue, uuid: connectionUUID, entityType: AtomType.connection.rawValue)

        // Don't duplicate
        guard !links.contains(where: { $0.uuid == connectionUUID && $0.type == AtomLinkType.connection.rawValue }) else { return }
        links.append(newLink)

        if let linksData = try? JSONEncoder().encode(links),
           let linksString = String(data: linksData, encoding: .utf8) {
            updatedAtom.links = linksString
            updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
            updatedAtom.localVersion += 1
            try? await AtomRepository.shared.update(updatedAtom)
        }

        await loadLinkedItems()
    }

    private func unlinkAtom(_ targetUUID: String) async {
        var updatedAtom = atom
        var links = updatedAtom.linksList
        links.removeAll { $0.uuid == targetUUID }

        if let linksData = try? JSONEncoder().encode(links),
           let linksString = String(data: linksData, encoding: .utf8) {
            updatedAtom.links = linksString
            updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
            updatedAtom.localVersion += 1
            try? await AtomRepository.shared.update(updatedAtom)
        }

        await loadLinkedItems()
    }

    private func createConnectionFromAnnotation(_ annotation: ResearchAnnotation) async {
        let title = annotation.content.isEmpty
            ? "New Connection"
            : String(annotation.content.prefix(60))

        let connection = Atom.new(
            type: .connection,
            title: title,
            body: "Seeded from research: \(atom.title ?? "Untitled")\n\n\(annotation.content)"
        )

        guard let created = try? await AtomRepository.shared.create(connection) else { return }
        await linkToConnection(created.uuid)
    }

    private func createNewConnection(title: String, reasoning: String) async {
        let connection = Atom.new(
            type: .connection,
            title: title,
            body: "Suggested from research: \(atom.title ?? "Untitled")\n\nReasoning: \(reasoning)"
        )

        guard let created = try? await AtomRepository.shared.create(connection) else { return }
        await linkToConnection(created.uuid)
    }

    // MARK: - Section 5: Ambient Knowledge

    @ViewBuilder
    private var ambientSection: some View {
        if ambientEngine.isLoading {
            loadingIndicator("Surfacing related knowledge...")
        } else if ambientEngine.ambientResults.isEmpty {
            emptyState(
                icon: "sparkles",
                message: "No ambient results yet",
                detail: "Related knowledge will appear as you explore"
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ambientEngine.ambientResults) { result in
                    AmbientResultCard(
                        result: result,
                        onPull: {
                            ambientEngine.pullToCanvas(result: result, sourceBlockUUID: atom.uuid)
                        },
                        onDismiss: {
                            withAnimation(ProMotionSprings.snappy) {
                                ambientEngine.dismiss(uuid: result.id)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func iconForType(_ type: AtomType) -> String {
        switch type {
        case .connection: return "link.circle.fill"
        case .research: return "magnifyingglass"
        case .content: return "doc.text.fill"
        case .idea: return "lightbulb.fill"
        case .task: return "checkmark.circle.fill"
        case .note: return "note.text"
        default: return "doc.fill"
        }
    }

    private func colorForType(_ type: AtomType) -> Color {
        switch type {
        case .connection: return Color(hex: "#8B5CF6")
        case .research: return Color(hex: "#10B981")
        case .content: return Color(hex: "#3B82F6")
        case .idea: return Color(hex: "#818CF8")
        case .task: return Color(hex: "#22C55E")
        case .note: return Color(hex: "#F97316")
        default: return DS.textSecondary
        }
    }
}

// MARK: - Preview

#Preview("Research Sidebar View") {
    @Previewable @State var state = ResearchFocusModeState(atomUUID: "preview-atom-uuid")

    HStack(spacing: 0) {
        Color.black.opacity(0.5)
            .frame(width: 400)

        Divider().background(DS.border)

        ResearchSidebarView(
            atom: Atom.new(
                type: .research,
                title: "Sample Research: How to Build Better Habits",
                body: "Key insights about habit formation and behavior change."
            ),
            state: $state,
            isVisible: true
        )
    }
    .frame(width: 720, height: 600)
    .background(DS.bg)
}
