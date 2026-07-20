import Foundation

struct CosmoEditableOperationResult: Equatable, Sendable {
    var operationID: UUID
    var status: CosmoProposalStatus
    var message: String
}

@MainActor
protocol CosmoEditableSurfaceProvider: AnyObject {
    var surfaceID: String { get }

    /// The skill this surface permanently lives in (concept boards → concept).
    /// While non-nil, non-explicit turns always run this skill and passive
    /// skill auto-routing is disabled. Cheap to read — no snapshot render.
    var residentSkillID: String? { get }

    func editableSnapshot() -> CosmoEditableSourceSnapshot
    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult
    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult
}

extension CosmoEditableSurfaceProvider {
    var residentSkillID: String? { nil }
}

enum CosmoEditableSurfaceHasher {
    static func hash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
