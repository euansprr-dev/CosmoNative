// CosmoOS/UI/FocusMode/FocusFloatingBlocksManager.swift
// Manages persistent floating blocks stored in atom metadata
// February 2026 - Floating blocks travel with the atom

import SwiftUI
import Combine

// MARK: - Focus Floating Blocks Manager

/// Manages floating blocks for a focus mode, persisting them in the atom's metadata.
/// Unlike FloatingPanelManager (which uses UserDefaults), these blocks are PART OF the atom
/// and travel with it when moving between thinkspaces.
@MainActor
class FocusFloatingBlocksManager: ObservableObject {
    // MARK: - Published State

    /// All floating blocks on the canvas
    @Published private(set) var blocks: [FocusFloatingBlock] = []

    /// Content loaded for each block (keyed by block ID)
    @Published private(set) var blockContents: [String: FloatingPanelContent] = [:]

    // MARK: - Properties

    /// The atom whose metadata stores these blocks
    private let ownerAtomUUID: String

    /// Debounce save timer
    private var saveTask: Task<Void, Never>?

    /// Save delay in seconds
    private let saveDebounceDelay: TimeInterval = 0.5

    // MARK: - Initialization

    init(ownerAtomUUID: String) {
        self.ownerAtomUUID = ownerAtomUUID
        loadBlocks()
    }

    // MARK: - Block Management

    /// Add a floating block referencing an existing atom
    @discardableResult
    func addBlock(
        linkedAtomUUID: String,
        linkedAtomType: AtomType,
        title: String,
        position: CGPoint,
        displayState: String = "standard"
    ) -> FocusFloatingBlock? {
        // Prevent duplicates
        guard !blocks.contains(where: { $0.linkedAtomUUID == linkedAtomUUID }) else {
            return blocks.first(where: { $0.linkedAtomUUID == linkedAtomUUID })
        }

        // Prevent adding the owner atom as its own floating block
        guard linkedAtomUUID != ownerAtomUUID else { return nil }

        let size = Self.defaultSize(for: linkedAtomType, displayState: displayState)

        let block = FocusFloatingBlock(
            linkedAtomUUID: linkedAtomUUID,
            linkedAtomType: linkedAtomType.rawValue,
            title: title,
            positionX: position.x,
            positionY: position.y,
            width: size.width,
            height: size.height,
            displayState: displayState
        )

        withAnimation(ProMotionSprings.snappy) {
            blocks.append(block)
        }

        // Load content
        Task {
            await loadContent(for: block)
        }

        debouncedSave()
        return block
    }

    /// Remove a floating block by ID
    func removeBlock(id: String) {
        withAnimation(ProMotionSprings.snappy) {
            blocks.removeAll { $0.id == id }
            blockContents.removeValue(forKey: id)
        }
        debouncedSave()
    }

    /// Remove a floating block by linked atom UUID
    func removeBlock(linkedAtomUUID: String) {
        if let block = blocks.first(where: { $0.linkedAtomUUID == linkedAtomUUID }) {
            removeBlock(id: block.id)
        }
    }

    /// Update a block's position
    func updatePosition(_ id: String, position: CGPoint) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].positionX = position.x
            blocks[index].positionY = position.y
            debouncedSave()
        }
    }

    /// Update a block's display state
    func updateDisplayState(_ id: String, displayState: String) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].displayState = displayState
            if let atomType = blocks[index].atomType {
                let size = Self.defaultSize(for: atomType, displayState: displayState)
                blocks[index].width = size.width
                blocks[index].height = size.height
            }
            debouncedSave()
        }
    }

    /// Check if a block already exists for a given atom
    func hasBlock(for atomUUID: String) -> Bool {
        blocks.contains { $0.linkedAtomUUID == atomUUID }
    }

    /// Remove all blocks
    func removeAllBlocks() {
        withAnimation(ProMotionSprings.snappy) {
            blocks.removeAll()
            blockContents.removeAll()
        }
        debouncedSave()
    }

    // MARK: - Content Loading

    /// Load content for a specific block
    func loadContent(for block: FocusFloatingBlock) async {
        guard blockContents[block.id] == nil else { return }

        // Set placeholder
        blockContents[block.id] = .placeholder

        do {
            guard let atom = try await AtomRepository.shared.fetch(uuid: block.linkedAtomUUID) else {
                // Stale reference - atom was deleted
                removeBlock(id: block.id)
                return
            }

            let content = FloatingPanelContent(
                title: atom.title ?? "Untitled",
                preview: atom.body?.prefix(200).description,
                thumbnailURL: nil,
                metadata: FloatingPanelContent.PanelMetadata(
                    author: nil,
                    duration: nil,
                    platform: nil,
                    sourceType: nil
                ),
                annotationCount: 0,
                linkedCount: atom.linksList.count,
                updatedAt: ISO8601DateFormatter().date(from: atom.updatedAt) ?? Date()
            )

            await MainActor.run {
                blockContents[block.id] = content
                // Also update cached title if it changed
                if let index = blocks.firstIndex(where: { $0.id == block.id }),
                   blocks[index].title != (atom.title ?? "Untitled") {
                    blocks[index].title = atom.title ?? "Untitled"
                    debouncedSave()
                }
            }
        } catch {
            print("FocusFloatingBlocksManager: Failed to load content for \(block.linkedAtomUUID): \(error)")
        }
    }

    /// Load content for all blocks
    func loadAllContent() async {
        await withTaskGroup(of: Void.self) { group in
            for block in blocks {
                group.addTask {
                    await self.loadContent(for: block)
                }
            }
        }
    }

    /// Get content for a block
    func content(for blockID: String) -> FloatingPanelContent {
        blockContents[blockID] ?? .placeholder
    }

    // MARK: - Persistence (Atom Metadata)

    /// Load blocks from the owner atom's metadata
    private func loadBlocks() {
        Task {
            do {
                guard let atom = try await AtomRepository.shared.fetch(uuid: ownerAtomUUID) else {
                    return
                }
                let loaded = atom.focusFloatingBlocks
                await MainActor.run {
                    blocks = loaded
                }
                // Load content for all blocks
                await loadAllContent()
            } catch {
                print("FocusFloatingBlocksManager: Failed to load blocks: \(error)")
            }
        }
    }

    /// Save blocks to the owner atom's metadata (debounced)
    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(saveDebounceDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await saveBlocks()
            } catch {
                // Cancelled - expected during rapid updates
            }
        }
    }

    /// Force an immediate save (call on disappear)
    func saveImmediately() {
        saveTask?.cancel()
        Task {
            await saveBlocks()
        }
    }

    /// Persist blocks to atom metadata
    private func saveBlocks() async {
        do {
            guard var atom = try await AtomRepository.shared.fetch(uuid: ownerAtomUUID) else {
                return
            }

            let currentBlocks = blocks
            atom = atom.withFocusFloatingBlocks(currentBlocks)
            _ = try await AtomRepository.shared.update(atom)
        } catch {
            print("FocusFloatingBlocksManager: Failed to save blocks: \(error)")
        }
    }

    // MARK: - Helpers

    /// Default size for a given atom type and display state
    static func defaultSize(for atomType: AtomType, displayState: String = "standard") -> CGSize {
        switch displayState {
        case "collapsed":
            return CGSize(width: 200, height: 60)
        case "expanded":
            return CGSize(width: 380, height: 280)
        default: // "standard"
            switch atomType {
            case .research:
                return CGSize(width: 280, height: 160)
            case .connection:
                return CGSize(width: 280, height: 160)
            case .content:
                return CGSize(width: 280, height: 140)
            default:
                return CGSize(width: 280, height: 140)
            }
        }
    }
}
