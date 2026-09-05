// The Greenhouse cast, drawn in a 100-point studio. Shared verbatim with iPhone.
// Broad silhouettes survive at 24pt; folds, veins and tiny highlights reward a closer look.
import SwiftUI

struct CompanionPortrait: View {
    let companion: Companion
    var growth: CompanionGrowth = .beginning
    var size: CGFloat = 120
    var isDelighted = false
    var expression: CompanionExpression = .resting

    var body: some View {
        Canvas { context, canvasSize in
            context.scaleBy(x: canvasSize.width / 100, y: canvasSize.height / 100)
            CompanionIllustration.draw(companion, growth: growth, expression: isDelighted ? .celebrating : expression, in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private enum CompanionIllustration {
    // Art pigments belong to the cast, independent of the app's chrome palette.
    static let cream = Color(hex: "FFF4D9")
    static let ink = Color(hex: "293D36")
    static let blush = Color(hex: "EDAD97")
    static let mint = Color(hex: "BFE4AD")
    static let green = Color(hex: "4A9368")
    static let deepGreen = Color(hex: "28634B")
    static let amber = Color(hex: "E9B85E")
    static let terra = Color(hex: "C77961")
    static let lavender = Color(hex: "A5A9DB")
    static let blue = Color(hex: "89B9D1")

    static func draw(_ c: Companion, growth: CompanionGrowth, expression: CompanionExpression, in ctx: inout GraphicsContext) {
        let level = growth.rawValue
        ctx.fill(ellipse(25, 84, 50, 6), with: .color(c.shade.opacity(0.10)))
        switch c {
        case .sprout: sprout(&ctx, level, expression)
        case .fern: fern(&ctx, level, expression)
        case .monstera: monstera(&ctx, level, expression)
        case .cactus: cactus(&ctx, level, expression)
        case .mushroom: mushroom(&ctx, level, expression)
        case .snail: snail(&ctx, level, expression)
        case .bee: bee(&ctx, level, expression)
        case .moth: moth(&ctx, level, expression)
        case .sun: sun(&ctx, level, expression)
        case .moon: moon(&ctx, level, expression)
        case .wateringCan: wateringCan(&ctx, level, expression)
        case .paperPlane: paperPlane(&ctx, level, expression)
        }
        if level == 3 {
            sparkle(&ctx, 17, 28, 3, amber)
            sparkle(&ctx, 84, 49, 2, c.tint)
        }
    }

    static func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
    }
    static func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }
    static func shape(_ points: [CGPoint]) -> Path {
        Path { path in path.addLines(points); path.closeSubpath() }
    }
    static func sculpt(_ ctx: inout GraphicsContext, _ path: Path, _ light: Color, _ dark: Color) {
        let b = path.boundingRect
        ctx.fill(path, with: .linearGradient(Gradient(stops: [
            .init(color: light, location: 0), .init(color: light, location: 0.18),
            .init(color: dark, location: 1)
        ]), startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
        ctx.drawLayer { rim in
            rim.clip(to: path)
            rim.fill(path, with: .radialGradient(Gradient(colors: [cream.opacity(0.22), .clear]), center: CGPoint(x: b.minX + b.width * 0.25, y: b.minY + b.height * 0.15), startRadius: 0, endRadius: max(b.width, b.height) * 0.65))
        }
        ctx.stroke(path, with: .color(dark.opacity(0.22)), lineWidth: 0.65)
    }
    static func stroke(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color, _ width: CGFloat = 2) {
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
    static func curve(_ a: CGPoint, _ b: CGPoint, _ control: CGPoint) -> Path {
        Path { $0.move(to: a); $0.addQuadCurve(to: b, control: control) }
    }
    static func leaf(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, width: CGFloat, light: Color = mint, dark: Color = green) {
        let mid = CGPoint(x: (a.x+b.x)/2, y: (a.y+b.y)/2)
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let nx = -dy / length, ny = dx / length
        let p = Path { p in
            p.move(to: a)
            p.addQuadCurve(to: b, control: CGPoint(x: mid.x + nx * width, y: mid.y + ny * width))
            p.addQuadCurve(to: a, control: CGPoint(x: mid.x - nx * width, y: mid.y - ny * width))
        }
        sculpt(&ctx, p, light, dark)
        stroke(&ctx, curve(a, b, mid), cream.opacity(0.35), 0.8)
    }
    static func face(_ ctx: inout GraphicsContext, x: CGFloat = 50, y: CGFloat = 61, spread: CGFloat = 8, expression: CompanionExpression) {
        for side: CGFloat in [-1, 1] {
            let eyeX = x + side * spread
            if expression == .celebrating || expression == .restingFocus {
                stroke(&ctx, curve(CGPoint(x: eyeX-2, y: y), CGPoint(x: eyeX+2, y: y), CGPoint(x: eyeX, y: y-3)), ink, 1.8)
            } else {
                let gaze: CGFloat = expression == .working ? 1.2 : expression == .attentive ? -0.5 : 0
                let eyeHeight: CGFloat = expression == .working ? 4 : 5.5
                ctx.fill(ellipse(eyeX - 1.7 + gaze, y - 3, 3.4, eyeHeight), with: .color(ink))
                ctx.fill(ellipse(eyeX - 0.8 + gaze, y - 2.4, 1, 1.5), with: .color(cream))
                if expression == .reviewing {
                    stroke(&ctx, curve(CGPoint(x: eyeX - 2.5, y: y - 6), CGPoint(x: eyeX + 2, y: y - 7), CGPoint(x: eyeX, y: y - 8)), ink.opacity(0.65), 1)
                }
            }
            ctx.fill(ellipse(eyeX-4, y+4, 7, 3), with: .color(blush.opacity(0.52)))
        }
        if expression == .speaking {
            sculpt(&ctx, ellipse(x - 2.4, y + 4, 4.8, 5.5), ink, ink)
        } else {
            stroke(&ctx, curve(CGPoint(x: x-2, y: y+5), CGPoint(x: x+2, y: y+5), CGPoint(x: x, y: y+8)), ink.opacity(0.7), 1.1)
        }
    }
    static func feet(_ ctx: inout GraphicsContext, _ color: Color = deepGreen) {
        sculpt(&ctx, ellipse(35, 79, 12, 7), color, color.opacity(0.7))
        sculpt(&ctx, ellipse(54, 79, 12, 7), color, color.opacity(0.7))
    }
    static func flower(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color = blush) {
        for i in 0..<5 {
            let angle = Double(i) * .pi * 2 / 5 - .pi/2
            ctx.fill(ellipse(x+cos(angle)*r*0.6-r*0.5, y+sin(angle)*r*0.6-r*0.5, r, r), with: .color(color))
        }
        ctx.fill(ellipse(x-r*0.28, y-r*0.28, r*0.56, r*0.56), with: .color(cream))
    }
    static func sparkle(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
        ctx.fill(shape([CGPoint(x:x,y:y-r),CGPoint(x:x+r*0.3,y:y-r*0.3),CGPoint(x:x+r,y:y),CGPoint(x:x+r*0.3,y:y+r*0.3),CGPoint(x:x,y:y+r),CGPoint(x:x-r*0.3,y:y+r*0.3),CGPoint(x:x-r,y:y),CGPoint(x:x-r*0.3,y:y-r*0.3)]), with: .color(color))
    }

    static func sprout(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        feet(&ctx)
        sculpt(&ctx, round(29, 49, 43, 34, 16), cream, Color(hex: "DBCAA0"))
        stroke(&ctx, curve(CGPoint(x:50,y:54), CGPoint(x:51,y:28), CGPoint(x:44,y:36)), deepGreen, 3)
        leaf(&ctx, from: CGPoint(x:50,y:41), to: CGPoint(x:27,y:25), width: 14)
        leaf(&ctx, from: CGPoint(x:50,y:34), to: CGPoint(x:76,y:15), width: 16)
        if level >= 1 { leaf(&ctx, from: CGPoint(x:48,y:46), to: CGPoint(x:76,y:40), width: 10, light: mint, dark: deepGreen) }
        if level >= 2 { leaf(&ctx, from: CGPoint(x:49,y:30), to: CGPoint(x:39,y:10), width: 9) }
        if level == 3 { flower(&ctx, 51, 24, 8) }
        stroke(&ctx, curve(CGPoint(x:35,y:54), CGPoint(x:65,y:54), CGPoint(x:50,y:60)), cream.opacity(0.8), 2)
        face(&ctx, y: 65, expression: expression)
    }
    static func fern(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        feet(&ctx)
        sculpt(&ctx, ellipse(31, 51, 40, 33), mint, green)
        stroke(&ctx, curve(CGPoint(x:49,y:58), CGPoint(x:58,y:22), CGPoint(x:35,y:29)), deepGreen, 4)
        var curl = Path()
        for i in 0...60 {
            let t = Double(i)/60
            let a = t * .pi * 3
            let r = 12 * (1-t) + 1
            let point = CGPoint(x:58+cos(a)*r,y:22+sin(a)*r)
            if i == 0 { curl.move(to: point) } else { curl.addLine(to: point) }
        }
        stroke(&ctx, curl, green, 5)
        for i in 0..<(2+level) {
            let y = CGFloat(48-i*7)
            let direction: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            leaf(&ctx, from: CGPoint(x:47,y:y), to: CGPoint(x:47+direction*21,y:y-8), width: 8)
        }
        if level >= 2 { flower(&ctx, 68, 49, 5, amber) }
        face(&ctx, y: 67, expression: expression)
    }
    static func monstera(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        feet(&ctx)
        let blade = Path { p in
            p.move(to: CGPoint(x:50,y:26))
            p.addCurve(to: CGPoint(x:80,y:43), control1: CGPoint(x:68,y:4), control2: CGPoint(x:83,y:19))
            p.addCurve(to: CGPoint(x:50,y:83), control1: CGPoint(x:79,y:64), control2: CGPoint(x:68,y:77))
            p.addCurve(to: CGPoint(x:20,y:43), control1: CGPoint(x:31,y:77), control2: CGPoint(x:21,y:64))
            p.addCurve(to: CGPoint(x:50,y:26), control1: CGPoint(x:16,y:19), control2: CGPoint(x:33,y:5))
        }
        ctx.drawLayer { layer in
            sculpt(&layer, blade, mint, deepGreen)
            layer.blendMode = .destinationOut
            for side: CGFloat in [-1, 1] {
                for i in 0..<(2+level) {
                    let y = CGFloat(34+i*8)
                    stroke(&layer, curve(CGPoint(x:50+side*32,y:y), CGPoint(x:50+side*17,y:y+7), CGPoint(x:50+side*23,y:y+6)), .black, 3)
                }
            }
        }
        stroke(&ctx, curve(CGPoint(x:50,y:30), CGPoint(x:50,y:76), CGPoint(x:47,y:52)), cream.opacity(0.42), 1.2)
        if level >= 2 { leaf(&ctx, from: CGPoint(x:52,y:25), to: CGPoint(x:64,y:9), width: 7) }
        face(&ctx, y: 55, expression: expression)
    }
    static func cactus(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        sculpt(&ctx, round(19, 42, 15, 22, 7), mint, green)
        sculpt(&ctx, round(67, 35, 14, 27, 7), mint, green)
        sculpt(&ctx, round(32, 23, 38, 54, 19), mint, deepGreen)
        for x: CGFloat in [42, 58] { stroke(&ctx, curve(CGPoint(x:x,y:31),CGPoint(x:x,y:68),CGPoint(x:x-4,y:47)), cream.opacity(0.3), 1) }
        sculpt(&ctx, round(30, 69, 42, 16, 6), Color(hex:"EDB599"), terra)
        sculpt(&ctx, round(27, 67, 48, 6, 3), Color(hex:"F0C6A8"), terra)
        for i in 0...level { flower(&ctx, CGFloat(43+i*7), CGFloat(23-abs(i-1)*3), CGFloat(4+level), i.isMultiple(of:2) ? blush : cream) }
        face(&ctx, y: 49, expression: expression)
    }
    static func mushroom(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        feet(&ctx, terra)
        sculpt(&ctx, round(35, 44, 32, 39, 14), cream, Color(hex:"DDCAA6"))
        let cap = Path { p in
            p.move(to: CGPoint(x:15,y:47))
            p.addCurve(to: CGPoint(x:50,y:14),control1:CGPoint(x:17,y:29),control2:CGPoint(x:34,y:12))
            p.addCurve(to: CGPoint(x:85,y:47),control1:CGPoint(x:70,y:12),control2:CGPoint(x:84,y:31))
            p.addCurve(to: CGPoint(x:15,y:47),control1:CGPoint(x:78,y:62),control2:CGPoint(x:21,y:62))
        }
        sculpt(&ctx, cap, Color(hex:"F0B59B"), terra)
        ctx.fill(ellipse(25,45,51,9), with:.color(Color(hex:"974E45").opacity(0.24)))
        for point in [CGPoint(x:33,y:32),CGPoint(x:51,y:23),CGPoint(x:65,y:35)] {
            sculpt(&ctx, ellipse(point.x-4,point.y-3,8,6), cream, Color(hex:"EFDBC2"))
        }
        if level >= 1 { ctx.fill(ellipse(45,40,5,4),with:.color(cream.opacity(0.85))) }
        if level >= 2 { leaf(&ctx,from:CGPoint(x:51,y:16),to:CGPoint(x:66,y:6),width:7) }
        if level == 3 { flower(&ctx,40,14,6) }
        face(&ctx, y: 66, spread: 7, expression: expression)
    }
    static func snail(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        sculpt(&ctx, round(19,63,66,20,10), cream, Color(hex:"CDB889"))
        sculpt(&ctx, round(18,43,23,36,11), cream, Color(hex:"D6C197"))
        for x: CGFloat in [24,35] {
            stroke(&ctx,curve(CGPoint(x:x,y:47),CGPoint(x:x-2,y:35),CGPoint(x:x-2,y:40)),Color(hex:"BBA377"),2)
            ctx.fill(ellipse(x-4,32,4,5),with:.color(ink))
        }
        sculpt(&ctx, ellipse(39,30,44,46),Color(hex:"ECC99C"),Color(hex:"B98A63"))
        var spiral = Path()
        for i in 0...80 {
            let t = Double(i)/80, a = t * .pi * 4.5, r = 18*(1-t)+1
            let p = CGPoint(x:61+cos(a)*r,y:53+sin(a)*r)
            if i == 0 { spiral.move(to:p) } else { spiral.addLine(to:p) }
        }
        stroke(&ctx,spiral,Color(hex:"8E674D").opacity(0.68),2)
        if level >= 1 { leaf(&ctx,from:CGPoint(x:61,y:32),to:CGPoint(x:76,y:20),width:7) }
        if level >= 2 { flower(&ctx,58,29,6,blush) }
        if level == 3 { flower(&ctx,72,29,4,cream) }
        face(&ctx,x:29,y:58,spread:5,expression:expression)
    }
    static func bee(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        let wing = CGFloat(21+level*3)
        sculpt(&ctx,ellipse(15,27,wing,32),cream,blue.opacity(0.65))
        sculpt(&ctx,ellipse(62,23,wing,34),cream,blue.opacity(0.65))
        sculpt(&ctx,ellipse(29,35,43,46),Color(hex:"FFE3A0"),amber)
        ctx.drawLayer { layer in
            layer.clip(to:ellipse(29,35,43,46))
            for y: CGFloat in [62,73] {
                stroke(&layer,curve(CGPoint(x:27,y:y),CGPoint(x:75,y:y),CGPoint(x:51,y:y+9)),ink.opacity(0.80),5)
            }
        }
        for side: CGFloat in [-1,1] {
            stroke(&ctx,curve(CGPoint(x:50+side*9,y:38),CGPoint(x:50+side*14,y:27),CGPoint(x:50+side*9,y:28)),ink,1.8)
            ctx.fill(ellipse(48+side*14,24,4,4),with:.color(ink))
        }
        if level >= 2 { flower(&ctx,74,66,6,cream) }
        if level == 3 { sparkle(&ctx,23,60,4,amber) }
        face(&ctx,y:50,expression:expression)
    }
    static func moth(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        for side: CGFloat in [-1,1] {
            let wing = Path { p in
                p.move(to:CGPoint(x:50,y:43))
                p.addCurve(to:CGPoint(x:50+side*35,y:22),control1:CGPoint(x:50+side*16,y:17),control2:CGPoint(x:50+side*32,y:10))
                p.addCurve(to:CGPoint(x:50+side*26,y:67),control1:CGPoint(x:50+side*48,y:47),control2:CGPoint(x:50+side*27,y:50))
                p.addQuadCurve(to:CGPoint(x:50,y:58),control:CGPoint(x:50+side*31,y:94))
            }
            sculpt(&ctx,wing,Color(hex:"DFE7CC"),level >= 2 ? lavender : green.opacity(0.75))
            sculpt(&ctx,ellipse(50+side*23-6,35,12,16),cream,amber.opacity(0.7))
            ctx.fill(ellipse(50+side*23-2,39,4,8),with:.color(deepGreen.opacity(0.7)))
            if level >= 1 { sparkle(&ctx,50+side*23,63,4,cream) }
            stroke(&ctx,curve(CGPoint(x:50+side*3,y:42),CGPoint(x:50+side*10,y:27),CGPoint(x:50+side*2,y:29)),ink,1.5)
        }
        sculpt(&ctx,round(43,39,14,35,7),cream,Color(hex:"B7C49B"))
        face(&ctx,y:48,spread:4,expression:expression)
    }
    static func sun(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        let rays = 8+level*2
        for i in 0..<rays {
            let a = Double(i)*2 * .pi/Double(rays)
            stroke(&ctx,curve(CGPoint(x:50+cos(a)*31,y:49+sin(a)*31),CGPoint(x:50+cos(a)*38,y:49+sin(a)*38),CGPoint(x:50+cos(a)*35,y:49+sin(a)*35)),amber,4)
        }
        sculpt(&ctx,ellipse(24,23,52,52),Color(hex:"FFE9AD"),Color(hex:"ECAE51"))
        ctx.fill(ellipse(34,30,20,5),with:.color(cream.opacity(0.55)))
        if level >= 2 { sculpt(&ctx,ellipse(59,72,18,8),cream,Color(hex:"DFD9CB")) }
        face(&ctx,y:49,expression:expression)
    }
    static func moon(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        let crescent = Path { p in
            p.move(to:CGPoint(x:62,y:16))
            p.addCurve(to:CGPoint(x:74,y:73),control1:CGPoint(x:12,y:7),control2:CGPoint(x:10,y:86))
            p.addCurve(to:CGPoint(x:62,y:16),control1:CGPoint(x:46,y:78),control2:CGPoint(x:36,y:35))
        }
        sculpt(&ctx,crescent,Color(hex:"D7DCF1"),Color(hex:"8993C2"))
        for i in 0...level {
            let x = CGFloat(66+(i%2)*12), y = CGFloat(28+i*12)
            sparkle(&ctx,x,y,i == 0 ? 5 : 3,amber)
        }
        ctx.fill(ellipse(31,37,6,7),with:.color(cream.opacity(0.25)))
        ctx.fill(ellipse(28,55,4,4),with:.color(cream.opacity(0.2)))
        face(&ctx,x:41,y:59,spread:5,expression:expression)
    }
    static func wateringCan(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        stroke(&ctx,Path(ellipseIn:CGRect(x:57,y:36,width:25,height:29)),blue,6)
        let spout = shape([CGPoint(x:33,y:55),CGPoint(x:16,y:40),CGPoint(x:12,y:44),CGPoint(x:27,y:71),CGPoint(x:38,y:65)])
        sculpt(&ctx,spout,Color(hex:"B8D7DE"),Color(hex:"6399AD"))
        sculpt(&ctx,round(30,42,40,40,12),Color(hex:"C8E0DE"),Color(hex:"709DA6"))
        sculpt(&ctx,ellipse(30,37,40,12),Color(hex:"8FB8BB"),Color(hex:"4D7E85"))
        leaf(&ctx,from:CGPoint(x:48,y:41),to:CGPoint(x:39,y:23),width:9)
        if level >= 1 { leaf(&ctx,from:CGPoint(x:49,y:41),to:CGPoint(x:67,y:25),width:9) }
        if level >= 2 { flower(&ctx,50,23,6,blush) }
        if level == 3 { leaf(&ctx,from:CGPoint(x:50,y:34),to:CGPoint(x:56,y:12),width:7) }
        sculpt(&ctx,ellipse(9,50,3,5),cream,blue)
        face(&ctx,y:62,expression:expression)
    }
    static func paperPlane(_ ctx: inout GraphicsContext, _ level: Int, _ expression: CompanionExpression) {
        let tip = CGPoint(x:86,y:20)
        sculpt(&ctx,shape([CGPoint(x:14,y:40),tip,CGPoint(x:40,y:57)]),cream,Color(hex:"B5CFDE"))
        sculpt(&ctx,shape([CGPoint(x:40,y:57),tip,CGPoint(x:55,y:80)]),Color(hex:"C7DEE7"),Color(hex:"7FA8C6"))
        ctx.fill(shape([CGPoint(x:40,y:57),CGPoint(x:43,y:72),CGPoint(x:55,y:62),tip]),with:.color(Color(hex:"5A86A8")))
        sculpt(&ctx,shape([CGPoint(x:45,y:55),tip,CGPoint(x:55,y:80)]),Color(hex:"E8F0ED"),Color(hex:"97BED5"))
        stroke(&ctx,curve(CGPoint(x:15,y:69),CGPoint(x:34,y:62),CGPoint(x:27,y:75)),blue.opacity(0.7),1.5)
        if level >= 1 { stroke(&ctx,curve(CGPoint(x:9,y:76),CGPoint(x:31,y:77),CGPoint(x:21,y:84)),blue.opacity(0.4),1) }
        if level >= 2 { leaf(&ctx,from:CGPoint(x:29,y:51),to:CGPoint(x:16,y:56),width:4,light:cream,dark:amber) }
        if level == 3 { sparkle(&ctx,70,13,4,amber) }
        face(&ctx,x:56,y:50,spread:5,expression:expression)
    }
}
