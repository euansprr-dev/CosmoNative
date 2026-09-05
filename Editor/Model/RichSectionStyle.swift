// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/Model and
// CosmoOS-iOS/CosmoCoreKit/Sources/Models. Verified by Tools/verify_twins.sh.
//
// The Section block: a titled, tinted, collapsible container of blocks —
// the "Section 1 — Change begins with clarity" box. Title lives in the
// block's `inlines`, body in `children`, and this style rides `section`.

import Foundation

public struct RichSectionStyle: Codable, Equatable, Hashable, Sendable {
    public enum Appearance: String, Codable, Hashable, Sendable, CaseIterable {
        /// Tone wash fill + hairline (the Element look).
        case wash
        /// Hairline only.
        case outline
        /// A left bar in the tone ink, no fill, no hairline.
        case bar
    }

    /// The tone id that means "parchment, no tint".
    public static let noneToneID = "none"

    public var toneID: String
    public var appearance: Appearance
    /// SF Symbol name or a single emoji; nil = no icon seat.
    public var icon: String?
    public var isCollapsed: Bool
    public var passthrough: [String: JSONValue]

    public static let `default` = RichSectionStyle()

    public init(
        toneID: String = "moss",
        appearance: Appearance = .wash,
        icon: String? = nil,
        isCollapsed: Bool = false,
        passthrough: [String: JSONValue] = [:]
    ) {
        self.toneID = toneID
        self.appearance = appearance
        self.icon = icon
        self.isCollapsed = isCollapsed
        self.passthrough = passthrough
    }

    public var isTinted: Bool { toneID != Self.noneToneID }

    private enum CodingKeys: String, CodingKey {
        case toneID, appearance, icon, isCollapsed
        static var known: Set<String> { Set(["toneID", "appearance", "icon", "isCollapsed"]) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toneID = (try? container.decodeIfPresent(String.self, forKey: .toneID)) ?? Self.default.toneID
        appearance = (try? container.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .wash
        icon = try? container.decodeIfPresent(String.self, forKey: .icon)
        isCollapsed = (try? container.decodeIfPresent(Bool.self, forKey: .isCollapsed)) ?? false
        passthrough = RichPassthrough.unknownKeys(from: decoder, known: CodingKeys.known)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toneID, forKey: .toneID)
        try container.encode(appearance, forKey: .appearance)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(isCollapsed, forKey: .isCollapsed)
        try RichPassthrough.encode(passthrough, to: encoder, known: CodingKeys.known)
    }
}
