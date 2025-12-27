// CosmoOS/Navigation/ProjectCreationModal.swift
// Modal for creating new projects from Ctrl+K

import SwiftUI

struct ProjectCreationModal: View {
    @Binding var isPresented: Bool
    let onProjectCreated: (Project) -> Void

    @State private var projectName = ""
    @State private var projectDescription = ""
    @State private var selectedIcon = "💼"
    @State private var selectedColorHex = "#A8CCE8"  // Pastel Sky Blue
    @FocusState private var isNameFocused: Bool

    private let atomRepo = AtomRepository.shared

    // Emoji picker options
    private let iconOptions = ["💼", "🎨", "🚀", "📊", "🎯", "🏠", "💡", "📝", "🔬", "🎭", "🌟", "🎪"]

    // Pastel color palette
    private let colorOptions = [
        "#A8CCE8",  // Pastel Sky Blue
        "#CAB8E8",  // Pastel Lavender
        "#F4AFA0",  // Soft Coral
        "#8FC7A2",  // Muted Emerald
        "#F5E6C8",  // Light Yellow
        "#E8B8A8",  // Soft Peach
        "#A8D8E8",  // Soft Cyan
        "#D8A8E8",  // Soft Purple
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
                .background(CosmoColors.glassGrey.opacity(0.4))
            
            formContent
            
            Divider()
                .background(CosmoColors.glassGrey.opacity(0.4))
            
            footer
        }
        .frame(width: 600, height: 580)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(CosmoColors.softWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(CosmoColors.glassGrey.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 30, y: 15)
        .onAppear {
            isNameFocused = true
        }
    }

    private var header: some View {
        HStack {
            Text("Create New Project")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CosmoColors.textPrimary)

            Spacer()

            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(CosmoColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                nameField
                iconPicker
                colorPicker
                descriptionField
            }
            .padding(24)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CosmoColors.textSecondary)

            ZStack(alignment: .leading) {
                if projectName.isEmpty {
                    Text("e.g., Michael Smith Consulting")
                        .font(.system(size: 15))
                        .foregroundColor(CosmoColors.textTertiary)
                        .padding(.leading, 12)
                }
                TextField("", text: $projectName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(CosmoColors.textPrimary)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CosmoColors.glassGrey.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isNameFocused ? CosmoColors.skyBlue.opacity(0.5) : CosmoColors.glassGrey.opacity(0.3), lineWidth: 1)
            )
            .focused($isNameFocused)
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon (optional)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CosmoColors.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                ForEach(iconOptions, id: \.self) { icon in
                    Button(action: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            selectedIcon = icon
                        }
                    }) {
                        Text(icon)
                            .font(.system(size: 20))
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(selectedIcon == icon ? Color(hex: selectedColorHex).opacity(0.2) : CosmoColors.glassGrey.opacity(0.1))
                            )
                            .overlay(
                                Circle()
                                    .stroke(selectedIcon == icon ? Color(hex: selectedColorHex) : Color.clear, lineWidth: 2)
                            )
                            .scaleEffect(selectedIcon == icon ? 1.1 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CosmoColors.textSecondary)

            HStack(spacing: 12) {
                ForEach(colorOptions, id: \.self) { colorHex in
                    Button(action: { selectedColorHex = colorHex }) {
                        Circle()
                            .fill(Color(hex: colorHex))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(selectedColorHex == colorHex ? CosmoColors.textPrimary : Color.clear, lineWidth: 2)
                            )
                            .scaleEffect(selectedColorHex == colorHex ? 1.1 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: selectedColorHex)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @FocusState private var isDescriptionFocused: Bool

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CosmoColors.textSecondary)

                Text("(required)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(CosmoColors.coral.opacity(0.8))
            }

            ZStack(alignment: .topLeading) {
                if projectDescription.isEmpty {
                    Text("Describe what this project is for - helps AI organize your captures")
                        .font(.system(size: 15))
                        .foregroundColor(CosmoColors.textTertiary)
                        .padding(.top, 12)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }

                TextField("", text: $projectDescription, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(2...4)
                    .padding(12)
                    .focused($isDescriptionFocused)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CosmoColors.glassGrey.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isDescriptionFocused ? CosmoColors.skyBlue.opacity(0.5) :
                        (projectDescription.count > 0 && projectDescription.count < 20 ? CosmoColors.coral.opacity(0.4) : CosmoColors.glassGrey.opacity(0.3)),
                        lineWidth: 1
                    )
            )

            // Character counter
            HStack {
                Text("\(projectDescription.count)/20 minimum")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(projectDescription.count >= 20 ? CosmoColors.emerald : CosmoColors.textTertiary)

                Spacer()

                if projectDescription.count >= 20 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(CosmoColors.emerald)
                }
            }
        }
    }

    private var isFormValid: Bool {
        !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        projectDescription.count >= 20
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(SecondaryButtonStyle())

            Button("Create Project") {
                createProject()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isFormValid)
            .opacity(isFormValid ? 1.0 : 0.5)
        }
        .padding(20)
    }

    private func createProject() {
        Task {
            let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isFormValid else { return }

            do {
                let atom = try await atomRepo.createProject(
                    title: trimmedName,
                    description: projectDescription,
                    color: selectedColorHex
                )
                print("✅ Project created: \(atom.title ?? trimmedName)")

                // Convert Atom to Project wrapper for callback compatibility
                let project = ProjectWrapper(atom: atom)
                isPresented = false
                onProjectCreated(project)
            } catch {
                print("❌ Failed to create project: \(error)")
            }
        }
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CosmoColors.skyBlue)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(CosmoColors.textSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CosmoColors.glassGrey.opacity(0.15))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
