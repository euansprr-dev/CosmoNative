// CosmoOS/Editor/Components/ConnectionComponents.swift

import SwiftUI

// MARK: - Connections Design System
struct ConnectionDesign {
    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 20
    
    // Smooth shadows
    static func cardShadow() -> some View {
        Color.black.opacity(0.05)
            .blur(radius: 10)
            .offset(y: 4)
    }
    
    // Glass effect for section headers
    static func glassHeader() -> some View {
        VisualEffectBlur(material: NSVisualEffectView.Material.headerView, blendingMode: .withinWindow)
            .opacity(0.8)
    }
}

// MARK: - Premium Section Card
struct PremiumSectionCard: View {
    let title: String
    let subtitle: String?
    let placeholder: String
    @Binding var content: String
    let accentColor: Color
    
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(CosmoTypography.titleSmall) // 15pt bold
                    .foregroundColor(CosmoColors.textPrimary)
                
                Spacer()
                
                // Status Indicator
                Circle()
                    .fill(content.isEmpty ? Color.clear : accentColor)
                    .frame(width: 6, height: 6)
                    .background(
                        Circle()
                            .stroke(content.isEmpty ? CosmoColors.glassGrey : accentColor.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Subtitle (Helper text)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
                    .lineLimit(2)
            }
            
            // Editor
            ZStack(alignment: .topLeading) {
                if content.isEmpty && !isFocused {
                    Text(placeholder)
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textTertiary.opacity(0.5))
                        .padding(.top, 8) // Match TextEditor internal padding
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $content)
                    .font(CosmoTypography.body) // 15pt regular
                    .foregroundColor(CosmoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 120)
            }
        }
        .padding(24)
        .background(
            ZStack {
                CosmoColors.cardBackground // Pure white or slight off-white
                
                // Subtle tint based on accent color
                accentColor.opacity(0.03)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: ConnectionDesign.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ConnectionDesign.cornerRadius)
                .stroke(
                    isFocused ? accentColor.opacity(0.5) : 
                    (isHovered ? CosmoColors.glassGrey : Color.clear),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(isFocused ? 0.08 : 0.04), radius: 12, x: 0, y: 6)
        .scaleEffect(isHovered && !isFocused ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Core Idea Hero Section
struct CoreIdeaHero: View {
    @Binding var content: String
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Core Idea", systemImage: "sparkles")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoMentionColors.connection)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(CosmoMentionColors.connection.opacity(0.1), in: Capsule())
            
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("What is the central concept? Describe the essence of this connection...")
                        .font(CosmoTypography.displaySmall) // 24pt
                        .foregroundColor(CosmoColors.textTertiary.opacity(0.5))
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $content)
                    .font(CosmoTypography.displaySmall)
                    .foregroundColor(CosmoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 100)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(
                    colors: [
                        CosmoColors.softWhite,
                        CosmoMentionColors.connection.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(CosmoMentionColors.connection.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: CosmoMentionColors.connection.opacity(0.1), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Masonry Grid Layout
// Simple 2-column masonry for SwiftUI
struct MasonryVStack<Content: View>: View {
    let columns: Int
    let spacing: CGFloat
    let content: () -> Content
    
    init(columns: Int = 2, spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            // This is a naive implementation; for dynamic/unknown content counts 
            // a custom Layout protocol or two VStacks with pre-split data is better.
            // For Connections, we have a fixed set of sections, so we can hardcode the split in the parent view.
            content() 
        }
    }
}

// MARK: - References Section
struct ReferencesSection: View {
    let references: [ConnectionReference]
    let onAdd: () -> Void
    let onRemove: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("References")
                    .font(CosmoTypography.titleSmall)
                    .foregroundColor(CosmoColors.textPrimary)
                
                Spacer()
                
                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("Add")
                            .font(CosmoTypography.labelSmall)
                    }
                    .foregroundColor(CosmoColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            
            if references.isEmpty {
                Button(action: onAdd) {
                    Text("Add research, ideas, or other connections...")
                        .font(CosmoTypography.bodySmall)
                        .foregroundColor(CosmoColors.textTertiary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(CosmoColors.glassGrey.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundColor(CosmoColors.textTertiary.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(references.enumerated()), id: \.offset) { index, ref in
                        ReferenceCard(reference: ref, onRemove: { onRemove(index) })
                    }
                }
            }
        }
        .padding(20)
        .background(CosmoColors.glassGrey.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// Helper FlowLayout (Simple horizontal wrapping)
fileprivate struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        if rows.isEmpty { return .zero }
        return CGSize(width: proposal.width ?? 0, height: rows.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        for row in rows {
            for element in row.elements {
                element.subview.place(at: CGPoint(x: bounds.minX + element.x, y: bounds.minY + row.minY), proposal: proposal)
            }
        }
    }
    
    struct Row {
        var elements: [Element] = []
        var minY: CGFloat = 0
        var maxY: CGFloat = 0
    }
    
    struct Element {
        var subview: LayoutSubview
        var x: CGFloat
    }
    
    func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        
        let maxWidth = proposal.width ?? .infinity
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > maxWidth && !currentRow.elements.isEmpty {
                // New row
                currentRow.minY = y
                currentRow.maxY = y + maxHeight
                rows.append(currentRow)
                currentRow = Row()
                x = 0
                y += maxHeight + spacing
                maxHeight = 0
            }
            
            currentRow.elements.append(Element(subview: subview, x: x))
            x += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
        
        if !currentRow.elements.isEmpty {
            currentRow.minY = y
            currentRow.maxY = y + maxHeight
            rows.append(currentRow)
        }
        
        return rows
    }
}
