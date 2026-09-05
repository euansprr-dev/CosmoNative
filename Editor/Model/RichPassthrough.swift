// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/Model and
// CosmoOS-iOS/CosmoCoreKit/Sources/Models. Verified by Tools/verify_twins.sh.
//
// Unknown-key passthrough for the rich document model. A block written by a
// newer build (a table, a section, a field we have not invented yet) must
// survive a decode → edit → encode round trip on an older build with every
// byte it does not understand intact. Without this, RichBlock's fixed
// CodingKeys silently dropped the payload of any unknown kind.

import Foundation

/// A JSON value we can carry without interpreting.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// A coding key made from any string — lets a decoder enumerate every key
/// present in a JSON object, known or not.
public struct AnyCodingKey: CodingKey, Hashable, Sendable {
    public var stringValue: String
    public var intValue: Int?

    public init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    public init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    public init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

public enum RichPassthrough {
    /// Every key in the object that is not one of `known`, decoded as an
    /// opaque JSON value. Decode failures on a single key are dropped rather
    /// than failing the whole object — passthrough must never make a
    /// document unreadable.
    public static func unknownKeys(
        from decoder: Decoder,
        known: Set<String>
    ) -> [String: JSONValue] {
        guard let container = try? decoder.container(keyedBy: AnyCodingKey.self) else { return [:] }
        var result: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            if let value = try? container.decode(JSONValue.self, forKey: key) {
                result[key.stringValue] = value
            }
        }
        return result
    }

    /// Re-emits passthrough values, never overwriting a known key.
    public static func encode(
        _ passthrough: [String: JSONValue],
        to encoder: Encoder,
        known: Set<String>
    ) throws {
        guard !passthrough.isEmpty else { return }
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in passthrough.sorted(by: { $0.key < $1.key }) where !known.contains(key) {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}
