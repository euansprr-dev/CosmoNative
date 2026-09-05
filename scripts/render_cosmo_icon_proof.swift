// Native SwiftUI optical proof. Compile alongside Core/CosmoIcon.swift.
// Arguments: a compiled app/asset bundle, output directory.
// This is an offline specimen, not a screenshot of the full application.
import SwiftUI
import AppKit

private let identities: [(String, CosmoIcon)] = [
    ("Spaces", .space), ("Command", .command), ("Content", .content),
    ("Swipe File", .swipe), ("Idea", .idea), ("Concept", .concept),
    ("Research", .research), ("Pipeline", .pipeline)
]

private struct IconProof: View {
    let bundle: Bundle
    let dark: Bool
    private var ink: Color { dark ? Color(red: 0.9, green: 0.91, blue: 0.88) : Color(red: 0.16, green: 0.18, blue: 0.16) }
    private var accent: Color { dark ? Color(red: 0.53, green: 0.77, blue: 0.63) : Color(red: 0.18, green: 0.42, blue: 0.31) }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cosmo / A quieter vocabulary").font(.system(size: 32, weight: .semibold))
                Text("Original identity symbols · native controls · consistent at every size")
                    .font(.system(size: 15)).opacity(0.65)
            }
            HStack(alignment: .top, spacing: 40) {
                sidebar
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("SYMBOL").frame(width: 110, alignment: .leading)
                        Text("12").frame(width: 50)
                        Text("16").frame(width: 50)
                        Text("20").frame(width: 50)
                        Text("32").frame(width: 62)
                        Text("SEMIBOLD").frame(width: 90)
                        Text("SELECTED").frame(width: 90)
                    }.font(.system(size: 10, weight: .medium)).opacity(0.55).padding(.bottom, 14)
                    ForEach(identities, id: \.0) { name, icon in
                        HStack {
                            Text(name).font(.system(size: 14)).frame(width: 110, alignment: .leading)
                            ForEach([12,16,20,32], id: \.self) { size in
                                symbol(icon).font(.system(size: CGFloat(size)))
                                    .frame(width: size == 32 ? 62 : 50)
                            }
                            symbol(icon).font(.system(size: 20, weight: .semibold)).frame(width: 90)
                            symbol(icon).font(.system(size: 20)).foregroundStyle(accent).frame(width: 90)
                        }.frame(height: 56)
                    }
                    Divider().padding(.vertical, 20)
                    HStack(spacing: 24) {
                        ForEach(["magnifyingglass", "plus", "xmark", "square.and.arrow.up", "gearshape", "trash"], id: \.self) { name in
                            Image(systemName: name).font(.system(size: 16))
                        }
                    }
                    Text("Familiar tools keep their familiar symbols.")
                        .font(.system(size: 12)).opacity(0.6).padding(.top, 12)
                }
            }
            Text("Native symbol render · \(dark ? "dark" : "light") appearance · offline design specimen")
                .font(.system(size: 11)).opacity(0.5)
        }
        .padding(40)
        .foregroundStyle(ink)
        .background(dark ? Color(red: 0.085, green: 0.10, blue: 0.09) : Color(red: 0.974, green: 0.969, blue: 0.957))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "sidebar.left").font(.system(size: 14)).padding(.bottom, 16)
            ForEach(Array(identities.prefix(4)), id: \.0) { name, icon in row(name, icon: icon) }
            row("Inbox", icon: .inbox)
            Text("STUDIO").font(.system(size: 10, weight: .medium)).opacity(0.55).padding(.top, 24).padding(.bottom, 8)
            row("Ideas", icon: .idea)
            row("Pipeline", icon: .pipeline, selected: true)
            row("Calendar", icon: .calendar)
            row("Clients", icon: .clients)
            Spacer(minLength: 80)
            HStack { Text("Your work, clearly placed."); Spacer(); Image(systemName: "gearshape") }
                .font(.system(size: 12)).opacity(0.6)
        }
        .padding(16)
        .frame(width: 240)
        .background(ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
    }

    private func row(_ title: String, icon: CosmoIcon, selected: Bool = false) -> some View {
        HStack(spacing: 8) {
            symbol(icon).font(.system(size: 16)).frame(width: 20)
            Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
            Spacer()
        }
        .foregroundStyle(selected ? accent : ink.opacity(0.75))
        .padding(.horizontal, 8).frame(height: 30)
        .background(selected ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func symbol(_ icon: CosmoIcon) -> Image {
        if let name = icon.assetName { return Image(name, bundle: bundle) }
        return Image(systemName: icon.systemName)
    }
}

@main struct RenderIconProof {
    @MainActor static func main() throws {
        let bundle = Bundle(path: CommandLine.arguments[1])!
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (_, icon) in identities {
            let loaded = NSImage(symbolName: icon.assetName!, bundle: bundle, variableValue: 0)
            precondition(loaded != nil, "Missing native symbol: \(icon.assetName!)")
        }
        let nativeIcons: [CosmoIcon] = [
            .inbox, .today, .upcoming, .anytime, .someday, .logbook, .habits,
            .reports, .calendar, .clients, .creators, .discover, .boards,
            .captureLanes, .commands, .task, .project, .area, .note, .library
        ]
        for icon in nativeIcons + identities.map(\.1) {
            precondition(NSImage(systemSymbolName: icon.systemName, accessibilityDescription: nil) != nil,
                         "Invalid native representation: \(icon.systemName)")
        }
        for dark in [false, true] {
            let renderer = ImageRenderer(content: IconProof(bundle: bundle, dark: dark))
            renderer.scale = 2
            let image = renderer.cgImage!
            let rep = NSBitmapImageRep(cgImage: image)
            let data = rep.representation(using: .png, properties: [:])!
            let url = output.appendingPathComponent("CosmoIcons-\(dark ? "dark" : "light").png")
            try data.write(to: url)
            print(url.path)
        }
    }
}
