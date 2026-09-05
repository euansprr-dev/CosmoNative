import Foundation
import AppKit

struct SwipeLabVisualEvidence: Sendable {
    var reference: String
    var jpeg: Data
    var kind: String
}

enum SwipeLabVisualLoader {
    /// Only original still images. A video thumbnail does not establish motion,
    /// delivery or sound. Those remain explicit limitations in the study.
    @MainActor
    static func load(source: SwipeLabSource, units: [SwipeLabUnit]) async -> [SwipeLabVisualEvidence] {
        var result: [SwipeLabVisualEvidence] = []
        for unit in units where unit.hasVisual {
            if Task.isCancelled { break }
            let url: URL?
            if unit.anchor.kind == .artifact,
               let id = source.atom.swipeArtifactUnits.first(where: { $0.id == unit.anchor.unitID })?.attachmentUUID,
               let attachment = try? await MediaAttachmentRepository.shared.fetch(uuid: id),
               !attachment.isDeleted,
               [.image, .screenshot, .pageScan].contains(attachment.kind) {
                url = await AttachmentCloudStore.shared.localOriginalURL(for: attachment)
            } else if let number = unit.anchor.slideNumber {
                let items = source.atom.richContent?.instagramData?.carouselItems ?? []
                let item = items.sorted { $0.index < $1.index }.dropFirst(max(0, number - 1)).first
                url = item?.mediaType == .image ? item?.mediaURL : nil
            } else { url = nil }
            guard let url else { continue }
            let data: Data?
            if url.isFileURL {
                data = await Task.detached { try? Data(contentsOf: url) }.value
            } else if url.scheme == "https" {
                var request = URLRequest(url: url); request.timeoutInterval = 20
                if let (bytes, response) = try? await URLSession.shared.data(for: request),
                   let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                   bytes.count <= 25_000_000 { data = bytes }
                else { data = nil }
            } else { data = nil }
            guard let data, let base64 = SwipeFrameAnalyzer.downscaledJPEGBase64(data),
                  let jpeg = Data(base64Encoded: base64) else { continue }
            result.append(.init(reference: SwipeLabEngine.reference(unit.anchor), jpeg: jpeg, kind: "original still image"))
        }
        return result
    }
}
