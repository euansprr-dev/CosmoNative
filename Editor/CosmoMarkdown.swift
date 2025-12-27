// CosmoOS/Editor/CosmoMarkdown.swift
// Shared utility for parsing and serializing markdown
// Handles Bold (**text**), Italic (*text*), and basic paragraph styling

import Foundation
import AppKit

struct CosmoMarkdown {
    
    // MARK: - Parse (Markdown -> NSAttributedString)

    static func parse(_ text: String, fontSize: CGFloat = 16) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor(CosmoColors.textPrimary),
                .paragraphStyle: CosmoTypography.bodyParagraphStyle()
            ]
        )

        // Headings: Parse line by line for # and ## prefixes
        let lines = text.components(separatedBy: .newlines)
        var currentLocation = 0

        for line in lines {
            let lineRange = NSRange(location: currentLocation, length: line.count)

            // Heading 1: "# "
            if line.hasPrefix("# ") && !line.hasPrefix("## ") {
                let headingStyle = NSMutableParagraphStyle()
                headingStyle.lineSpacing = 4
                headingStyle.paragraphSpacing = 12
                headingStyle.paragraphSpacingBefore = 16

                result.addAttributes([
                    .font: NSFont.systemFont(ofSize: 28, weight: .bold),
                    .foregroundColor: NSColor(CosmoColors.textPrimary),
                    .paragraphStyle: headingStyle
                ], range: lineRange)
            }
            // Heading 2: "## "
            else if line.hasPrefix("## ") {
                let headingStyle = NSMutableParagraphStyle()
                headingStyle.lineSpacing = 4
                headingStyle.paragraphSpacing = 12
                headingStyle.paragraphSpacingBefore = 16

                result.addAttributes([
                    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                    .foregroundColor: NSColor(CosmoColors.textPrimary),
                    .paragraphStyle: headingStyle
                ], range: lineRange)
            }
            // Heading 3: "### "
            else if line.hasPrefix("### ") {
                let headingStyle = NSMutableParagraphStyle()
                headingStyle.lineSpacing = 4
                headingStyle.paragraphSpacing = 10
                headingStyle.paragraphSpacingBefore = 12

                result.addAttributes([
                    .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                    .foregroundColor: NSColor(CosmoColors.textPrimary),
                    .paragraphStyle: headingStyle
                ], range: lineRange)
            }

            currentLocation += line.count + 1 // +1 for newline
        }

        // Bold (**text**)
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*") {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                result.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: fontSize), range: match.range)
            }
        }

        // Italic (*text*) - simplified regex to avoid nested bold conflict
        // Matches *text* but not **text**
        if let regex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)") {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                result.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize).italic(), range: match.range)
            }
        }

        return result
    }
    
    // MARK: - Serialize (NSAttributedString -> Markdown)
    
    static func serialize(_ attributedString: NSAttributedString) -> String {
        let string = attributedString.string
        // We can't easily reconstruct markdown from a mutable string that might have mixed attributes without careful iteration.
        // Simplified approach: Iterate through the string and rebuild it with markdown syntax based on attributes.
        // Note: This is complex for a robust editor. 
        // A safer approach for this iteration:
        // 1. We rely on the fact that `TextKitCoordinator` updates `plainText` whenever user types. 
        //    However, `plainText` from NSTextView doesn't include attributes if the user used Cmd+B on selected text.
        //    NSTextView.string returns just the characters.
        
        // So we MUST reconstruct the string with markdown symbols.
        
        var result = ""
        
        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { (attributes, range, stop) in
            let subString = (string as NSString).substring(with: range)
            var chunk = subString
            
            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                
                if traits.contains(.bold) {
                    // Check if it's already wrapped (if user typed **)
                    if !chunk.hasPrefix("**") && !chunk.hasSuffix("**") {
                        // Trim whitespace to avoid ** bold**
                        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            // Re-wrap non-whitespace content only - naive approach
                            // Better: Wrap the chunk. 
                            chunk = "**" + chunk + "**"
                        }
                    }
                } else if traits.contains(.italic) {
                     if !chunk.hasPrefix("*") && !chunk.hasSuffix("*") {
                         let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                         if !trimmed.isEmpty {
                             chunk = "*" + chunk + "*"
                         }
                     }
                }
            }
            
            result += chunk
        }
        
        return result
    }
}

// MARK: - Font Traits Helper
extension NSFont {
    func italic() -> NSFont {
        return NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    }
}
