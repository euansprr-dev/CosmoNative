// Run: swift scripts/generate_cosmo_symbols.swift
// Original Cosmo artwork. Edit the 24-unit drawings here, never generated SVGs.
// CoreGraphics expands strokes into filled paths for Apple's symbol importer.
import Foundation
import CoreGraphics

struct Drawing {
    let name: String
    let strokes: CGPath
}

func drawing(_ name: String, _ draw: (CGMutablePath) -> Void) -> Drawing {
    let path = CGMutablePath()
    draw(path)
    return Drawing(name: name, strokes: path)
}

extension CGMutablePath {
    func line(_ points: [(Double, Double)]) {
        guard let first = points.first else { return }
        move(to: CGPoint(x: first.0, y: first.1))
        for p in points.dropFirst() { addLine(to: CGPoint(x: p.0, y: p.1)) }
    }
    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double = 2) {
        addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r)
    }
    func circle(_ x: Double, _ y: Double, _ r: Double) {
        addEllipse(in: CGRect(x: x-r, y: y-r, width: 2*r, height: 2*r))
    }
}

let drawings = [
    drawing("space") { p in
        p.box(3, 4, 7, 16, 2)
        p.box(13, 4, 8, 6, 2)
        p.box(13, 13, 8, 7, 2)
    },
    drawing("command") { p in
        p.circle(12,12,9)
        p.line([(15.8,8.2), (13.5,13.5), (8.2,15.8), (10.5,10.5), (15.8,8.2)])
    },
    drawing("content") { p in
        p.move(to: CGPoint(x: 16, y: 3))
        p.addLine(to: CGPoint(x: 7, y: 3))
        p.addQuadCurve(to: CGPoint(x: 4.5, y: 5.5), control: CGPoint(x: 4.5, y: 3))
        p.addLine(to: CGPoint(x: 4.5, y: 18.5))
        p.addQuadCurve(to: CGPoint(x: 7, y: 21), control: CGPoint(x: 4.5, y: 21))
        p.addLine(to: CGPoint(x: 17, y: 21))
        p.addQuadCurve(to: CGPoint(x: 19.5, y: 18.5), control: CGPoint(x: 19.5, y: 21))
        p.line([(19.5,18.5), (19.5,6.5), (16,3), (16,7), (19.5,7)])
        p.line([(8,11), (15.5,11)])
        p.line([(8,15), (13,15)])
    },
    drawing("swipe") { p in
        p.line([(7,3), (18,3)])
        p.line([(5,6), (20,6)])
        p.box(3,9,18,12,2.5)
        p.line([(15,9), (15,15), (17,13.5), (19,15), (19,9)])
    },
    drawing("idea") { p in
        p.move(to: CGPoint(x: 8.5, y: 16.5))
        p.addCurve(to: CGPoint(x: 5.5, y: 9), control1: CGPoint(x: 8.5, y: 13), control2: CGPoint(x: 5.5, y: 13))
        p.addCurve(to: CGPoint(x: 12, y: 2.5), control1: CGPoint(x: 5.5, y: 5.3), control2: CGPoint(x: 8.3, y: 2.5))
        p.addCurve(to: CGPoint(x: 18.5, y: 9), control1: CGPoint(x: 15.7, y: 2.5), control2: CGPoint(x: 18.5, y: 5.3))
        p.addCurve(to: CGPoint(x: 15.5, y: 16.5), control1: CGPoint(x: 18.5, y: 13), control2: CGPoint(x: 15.5, y: 13))
        p.closeSubpath()
        p.line([(9,20), (15,20)])
        p.line([(12,16.5), (12,11)])
    },
    drawing("concept") { p in
        p.line([(10.1,7), (6.5,15)])
        p.line([(13.9,7), (17.5,15)])
        p.line([(8,18), (16,18)])
        p.circle(12,4.8,2.8)
        p.circle(5.2,18,2.8)
        p.circle(18.8,18,2.8)
    },
    drawing("research") { p in
        p.box(4,3,16,18,2.5)
        p.line([(8,3), (8,21)])
        p.line([(13,3), (13,10), (15.5,8), (18,10), (18,3)])
        p.line([(11.5,15), (16,15)])
    },
    drawing("pipeline") { p in
        p.box(2.5,4,5,16,1.8)
        p.box(9.5,4,5,11,1.8)
        p.box(16.5,4,5,6,1.8)
    }
]

func svgPath(_ path: CGPath) -> String {
    var commands: [String] = []
    func pt(_ p: CGPoint) -> String { String(format: "%.3f %.3f", locale: Locale(identifier: "en_US_POSIX"), p.x, p.y) }
    path.applyWithBlock { item in
        let e = item.pointee
        switch e.type {
        case .moveToPoint: commands.append("M" + pt(e.points[0]))
        case .addLineToPoint: commands.append("L" + pt(e.points[0]))
        case .addQuadCurveToPoint: commands.append("Q" + pt(e.points[0]) + " " + pt(e.points[1]))
        case .addCurveToPoint: commands.append("C" + pt(e.points[0]) + " " + pt(e.points[1]) + " " + pt(e.points[2]))
        case .closeSubpath: commands.append("Z")
        @unknown default: break
        }
    }
    return commands.joined(separator: " ")
}

let weights: [(String, CGFloat)] = [
    ("Ultralight", 0.85), ("Thin", 1.05), ("Light", 1.3),
    ("Regular", 1.65), ("Medium", 1.85), ("Semibold", 2.05),
    ("Bold", 2.3), ("Heavy", 2.5), ("Black", 2.7)
]
let scales: [(String, CGFloat, CGFloat)] = [("S", 4.25, 696), ("M", 5.0, 1126), ("L", 5.75, 1556)]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Resources/Assets.xcassets/CosmoSymbols")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try "{\"info\":{\"author\":\"xcode\",\"version\":1}}\n".write(to: assets.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

for drawing in drawings {
    var guides = ""
    var symbols = ""
    for (scaleName, scale, baseline) in scales {
        for (name, y) in [("Baseline", baseline), ("Capline", baseline-70.459)] {
            guides += "<line id=\"\(name)-\(scaleName)\" x1=\"263\" x2=\"3036\" y1=\"\(y)\" y2=\"\(y)\"/>"
        }
        for (index, weight) in weights.enumerated() {
            let x = CGFloat(520 + index*296)
            let width = 24*scale
            let outline = drawing.strokes.copy(strokingWithWidth: weight.1, lineCap: .round, lineJoin: .round, miterLimit: 4)
            var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: -35.2295-12*scale)
            let transformed = outline.copy(using: &transform)!
            let id = "\(weight.0)-\(scaleName)"
            guides += "<line id=\"left-margin-\(id)\" x1=\"\(x)\" x2=\"\(x)\" y1=\"\(baseline-100)\" y2=\"\(baseline+30)\"/>"
            guides += "<line id=\"right-margin-\(id)\" x1=\"\(x+width)\" x2=\"\(x+width)\" y1=\"\(baseline-100)\" y2=\"\(baseline+30)\"/>"
            symbols += "<g id=\"\(id)\" transform=\"translate(\(x) \(baseline))\"><path d=\"\(svgPath(transformed))\"/></g>\n"
        }
    }
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="3300" height="2200">
    <!-- Original CosmoOS symbol; generated from scripts/generate_cosmo_symbols.swift. -->
    <g id="Notes"><text id="template-version" x="263" y="1933">Template v.2.0</text></g>
    <g id="Guides" fill="none" stroke="#27AAE1" stroke-width="0.5">\(guides)</g>
    <g id="Symbols" fill="black">\(symbols)</g>
    </svg>
    """
    let folder = assets.appendingPathComponent("cosmo.\(drawing.name).symbolset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try svg.write(to: folder.appendingPathComponent("symbol.svg"), atomically: true, encoding: .utf8)
    try "{\"info\":{\"author\":\"xcode\",\"version\":1},\"symbols\":[{\"filename\":\"symbol.svg\",\"idiom\":\"universal\"}]}\n".write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("Generated cosmo.\(drawing.name) — 9 weights × 3 scales")
}
