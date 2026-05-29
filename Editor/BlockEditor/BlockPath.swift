import Foundation

struct BlockPath: Codable, Equatable, Hashable, Sendable {
    let indices: [Int]

    init?(indices: [Int]) {
        guard !indices.isEmpty, indices.allSatisfy({ $0 >= 0 }) else {
            return nil
        }
        self.indices = indices
    }

    static func root(index: Int) -> BlockPath {
        guard let path = BlockPath(indices: [index]) else {
            preconditionFailure("Root block index must be non-negative")
        }
        return path
    }

    var depth: Int {
        indices.count - 1
    }

    var parent: BlockPath? {
        guard indices.count > 1 else { return nil }
        return BlockPath(indices: Array(indices.dropLast()))
    }

    var indexInParent: Int {
        indices[indices.count - 1]
    }

    func appendingChild(index: Int) -> BlockPath {
        guard let path = BlockPath(indices: indices + [index]) else {
            preconditionFailure("Child block index must be non-negative")
        }
        return path
    }
}
