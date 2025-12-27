// CosmoOS/Canvas/Components/EditableConnectionSection.swift
// Inline editable section card for Connection floating blocks
// Auto-saves on text change with debouncing

import SwiftUI

/// Editable section card that appears when a section is selected in the floating block.
/// Features auto-focus, real-time saving, and keyboard navigation.
struct EditableConnectionSection: View {
    let section: MentalModelSection
    @Binding var content: String
    let onSave: () -> Void
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
    let onClose: () -> Void
    
    @FocusState private var isFocused: Bool
    @State private var localContent: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var justSaved = false
    
    private let saveDelay: TimeInterval = 1.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with section info and controls
            sectionHeader
            
            // Editable content area
            ZStack(alignment: .topLeading) {
                // Placeholder
                if localContent.isEmpty && !isFocused {
                    Text(section.placeholder)
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textTertiary.opacity(0.6))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                
                // Text editor
                TextEditor(text: $localContent)
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 100, maxHeight: 200)
            }
            
            // Footer with character count and save status
            sectionFooter
        }
        .padding(16)
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(sectionBorder)
        .shadow(color: section.color.opacity(0.1), radius: 8, y: 4)
        .onAppear {
            localContent = content
            // Auto-focus after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onChange(of: localContent) { _, newValue in
            triggerAutoSave(newValue)
        }
        .onDisappear {
            // Force save on disappear
            saveTask?.cancel()
            if localContent != content {
                content = localContent
                onSave()
            }
        }
    }
    
    // MARK: - Header
    
    private var sectionHeader: some View {
        HStack {
            // Section icon and name
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(section.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.name)
                        .font(CosmoTypography.titleSmall)
                        .foregroundColor(CosmoColors.textPrimary)
                    
                    Text(section.subtitle)
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.textTertiary)
                }
            }
            
            Spacer()
            
            // Navigation and close buttons
            HStack(spacing: 8) {
                // Previous section
                if let onPrevious = onPrevious {
                    Button(action: onPrevious) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(CosmoColors.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(CosmoColors.glassGrey.opacity(0.3), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("[", modifiers: .command)
                }
                
                // Next section
                if let onNext = onNext {
                    Button(action: onNext) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(CosmoColors.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(CosmoColors.glassGrey.opacity(0.3), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("]", modifiers: .command)
                }
                
                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CosmoColors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(CosmoColors.glassGrey.opacity(0.3), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
        }
    }
    
    // MARK: - Footer
    
    private var sectionFooter: some View {
        HStack {
            // Character count
            Text("\(localContent.count) characters")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)
            
            Spacer()
            
            // Save status
            if isSaving {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Saving...")
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.textTertiary)
                }
            } else if justSaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(CosmoColors.emerald)
                    Text("Saved")
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.emerald)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }
    
    // MARK: - Background & Border
    
    private var sectionBackground: some View {
        ZStack {
            CosmoColors.softWhite
            section.color.opacity(0.03)
        }
    }
    
    private var sectionBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                LinearGradient(
                    colors: [section.color.opacity(0.4), section.color.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
    }
    
    // MARK: - Auto-save
    
    private func triggerAutoSave(_ newValue: String) {
        saveTask?.cancel()
        
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(saveDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    isSaving = true
                }
                
                // Small delay to show saving state
                try await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    content = newValue
                    onSave()
                    isSaving = false
                    justSaved = true
                }
                
                // Hide "Saved" indicator after 2 seconds
                try await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    justSaved = false
                }
            } catch {
                // Task was cancelled
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Compact Editable Section (For collapsed mode)

/// More compact version for inline editing in smaller blocks
struct CompactEditableSection: View {
    let section: MentalModelSection
    @Binding var content: String
    let onSave: () -> Void
    
    @FocusState private var isFocused: Bool
    @State private var localContent: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Minimal header
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(section.color)
                
                Text(section.name)
                    .font(CosmoTypography.label)
                    .foregroundColor(CosmoColors.textPrimary)
                
                Spacer()
            }
            
            // Text field
            ZStack(alignment: .topLeading) {
                if localContent.isEmpty {
                    Text(section.placeholder)
                        .font(CosmoTypography.bodySmall)
                        .foregroundColor(CosmoColors.textTertiary.opacity(0.5))
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $localContent)
                    .font(CosmoTypography.bodySmall)
                    .foregroundColor(CosmoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 60, maxHeight: 120)
            }
            .padding(8)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? section.color.opacity(0.5) : CosmoColors.glassGrey, lineWidth: 1)
            )
        }
        .padding(12)
        .background(section.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            localContent = content
        }
        .onChange(of: localContent) { _, newValue in
            // Debounced save
            content = newValue
            onSave()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct EditableConnectionSection_Previews: PreviewProvider {
    @State static var content = "This is some sample content for the section."
    
    static var previews: some View {
        VStack(spacing: 30) {
            EditableConnectionSection(
                section: MentalModelSection.allSections[0],
                content: $content,
                onSave: { print("Saved!") },
                onPrevious: { print("Previous") },
                onNext: { print("Next") },
                onClose: { print("Close") }
            )
            
            CompactEditableSection(
                section: MentalModelSection.allSections[1],
                content: $content,
                onSave: { print("Saved!") }
            )
        }
        .padding(30)
        .frame(width: 400)
        .background(CosmoColors.softWhite)
    }
}
#endif
