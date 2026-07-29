// CosmoOS/SwipeFile/Artifacts/SwipePageSlicer.swift
// Turning a captured page's DOM geometry into the slices a Page swipe is made
// of. Pure and deterministic — no WebKit, no images — so the boundaries a
// sales page gets cut on are testable without rendering anything.
//
// WHY DOM-GUIDED CUTS: an arbitrary grid (every 800px, say) would slice a
// testimonial in half and glue the back of one section to the front of the
// next, which makes both the image and the role assignment nonsense. The
// page already tells us where its sections are; we cut where it says.

import Foundation

// MARK: - Probe results

/// One block the DOM probe identified as a section, in CSS pixels.
struct SwipePageSection: Equatable, Sendable {
    var top: Int
    var height: Int
    var text: String

    var bottom: Int { top + height }
}

/// Cheap structural signals read alongside the sections. Feeds lens inference
/// in step 9 — a page with a pricing table and four testimonials is craft
/// reference; fifteen paragraphs and no CTA is something to read.
struct SwipePageShape: Equatable, Sendable {
    var ctaCount: Int = 0
    var hasPricingTable: Bool = false
    var testimonialCount: Int = 0
    var paragraphCount: Int = 0
}

/// A resolved cut, in CAPTURE pixels (CSS pixels × the snapshot scale).
struct SwipePageSlice: Equatable, Sendable {
    var index: Int
    var top: Int
    var height: Int
    var text: String

    var bottom: Int { top + height }
}

// MARK: - Slicer

enum SwipePageSlicer {

    /// A page with more sections than this is a wall, and forty images is
    /// already more than anyone studies. The tail merges into the last slice
    /// rather than being dropped — the bottom of a sales page is where the
    /// offer lives.
    static let maxSlices = 40

    /// Below this a "section" is a divider, a spacer, or a stray badge —
    /// not something worth its own image and its own role. It merges upward.
    static let minSectionHeight = 120

    /// WebKit will render a very tall webview, but not an unbounded one, and
    /// a single snapshot past this starts failing outright.
    static let maxSingleCaptureHeight = 20_000

    /// Height of each pass when a page is taller than one capture can hold.
    static let tileHeight = 12_000

    /// Resolve DOM sections into ordered, non-overlapping slices in capture
    /// pixels.
    ///
    /// - Sections are sorted and clamped into `[0, contentHeight)`.
    /// - Anything shorter than `minSectionHeight` merges into the slice above
    ///   it (or the one below, when it is the first).
    /// - Gaps between sections are absorbed by the preceding slice, so the
    ///   slices tile the page with no missing bands — a reader scrolling the
    ///   stage must never hit a hole where a divider used to be.
    /// - Past `maxSlices` everything remaining merges into the final slice.
    static func slices(
        from sections: [SwipePageSection],
        contentHeight: Int,
        scale: Double = 1
    ) -> [SwipePageSlice] {
        guard contentHeight > 0 else { return [] }

        // Clamp, drop empties, sort.
        var ordered = sections
            .map { section -> SwipePageSection in
                let top = max(0, min(section.top, contentHeight))
                let bottom = max(top, min(section.bottom, contentHeight))
                return SwipePageSection(top: top, height: bottom - top, text: section.text)
            }
            .filter { $0.height > 0 }
            .sorted { $0.top < $1.top }

        // No usable geometry — the whole page is one slice rather than none.
        if ordered.isEmpty {
            ordered = [SwipePageSection(top: 0, height: contentHeight, text: "")]
        }

        // Merge short sections upward, and absorb gaps.
        var merged: [SwipePageSection] = []
        for section in ordered {
            guard var last = merged.last else {
                merged.append(section)
                continue
            }
            // Overlapping or too-short → fold into the previous.
            if section.height < minSectionHeight || section.top < last.bottom {
                last.height = max(last.height, section.bottom - last.top)
                last.text = joined(last.text, section.text)
                merged[merged.count - 1] = last
                continue
            }
            // A gap between them belongs to the previous slice, so the page
            // stays fully tiled.
            if section.top > last.bottom {
                last.height = section.top - last.top
                merged[merged.count - 1] = last
            }
            merged.append(section)
        }

        // The first slice always starts at the top of the page — a hero that
        // begins 40px down still owns those 40px.
        if var first = merged.first, first.top > 0 {
            first.height += first.top
            first.top = 0
            merged[0] = first
        }
        // The last slice always runs to the bottom.
        if var last = merged.last, last.bottom < contentHeight {
            last.height = contentHeight - last.top
            merged[merged.count - 1] = last
        }

        // Cap: fold the tail into the final kept slice.
        if merged.count > maxSlices {
            let kept = Array(merged.prefix(maxSlices - 1))
            let tail = merged.suffix(from: maxSlices - 1)
            var last = SwipePageSection(
                top: tail.first?.top ?? 0,
                height: contentHeight - (tail.first?.top ?? 0),
                text: tail.map(\.text).reduce("") { joined($0, $1) }
            )
            last.height = max(last.height, 1)
            merged = kept + [last]
        }

        return merged.enumerated().map { index, section in
            SwipePageSlice(
                index: index,
                top: Int((Double(section.top) * scale).rounded()),
                height: max(1, Int((Double(section.height) * scale).rounded())),
                text: section.text
            )
        }
    }

    /// Y-offsets for the capture passes needed to cover `height`.
    ///
    /// One pass for anything WebKit will render in a single snapshot; beyond
    /// that, `tileHeight` chunks. The final tile is short rather than
    /// overhanging, so the stitched image is exactly `height` tall.
    static func tileOffsets(forHeight height: Int) -> [Int] {
        guard height > maxSingleCaptureHeight else { return [0] }
        return stride(from: 0, to: height, by: tileHeight).map { $0 }
    }

    /// Height of the tile starting at `offset`.
    static func tileHeight(at offset: Int, totalHeight: Int) -> Int {
        guard totalHeight > maxSingleCaptureHeight else { return totalHeight }
        return min(tileHeight, max(0, totalHeight - offset))
    }

    private static func joined(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + "\n\n" + right
    }
}
