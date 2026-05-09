import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            inlineText(content)
                .font(headingFont(for: level))
                .padding(.top, 4)
        case .paragraph(let content):
            inlineText(content)
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        bullet(for: item, index: idx)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 14, alignment: .leading)
                        inlineText(item.text)
                    }
                }
            }
        case .codeBlock(let content):
            Text(content)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 6))
        case .quote(let content):
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(.secondary).frame(width: 3)
                inlineText(content).foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }

    @ViewBuilder
    private func bullet(for item: MarkdownListItem, index: Int) -> some View {
        switch item.kind {
        case .unordered: Text("•")
        case .ordered: Text("\(index + 1).")
        case .unchecked: Image(systemName: "square")
        case .checked: Image(systemName: "checkmark.square.fill").foregroundStyle(.tint)
        }
    }

    private func inlineText(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(s)
    }
}

enum MarkdownBlock {
    case heading(level: Int, content: String)
    case paragraph(String)
    case list([MarkdownListItem])
    case codeBlock(String)
    case quote(String)
    case rule
}

struct MarkdownListItem {
    enum Kind { case unordered, ordered, unchecked, checked }
    let text: String
    let kind: Kind
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                i += 1
                continue
            }

            if line.hasPrefix("```") {
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.codeBlock(code.joined(separator: "\n")))
                continue
            }

            if line == "---" || line == "***" {
                blocks.append(.rule)
                i += 1
                continue
            }

            if let (level, content) = headingComponents(line) {
                blocks.append(.heading(level: level, content: content))
                i += 1
                continue
            }

            if let item = listItem(from: line) {
                var items: [MarkdownListItem] = [item]
                i += 1
                while i < lines.count, let next = listItem(from: lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    i += 1
                }
                blocks.append(.list(items))
                continue
            }

            if line.hasPrefix(">") {
                var quote: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    let body = l.drop(while: { $0 == ">" }).drop(while: { $0 == " " })
                    quote.append(String(body))
                    i += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }

            // Paragraph — gather consecutive non-blank, non-block lines
            var para: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty { break }
                if isBlockStart(next) { break }
                para.append(next)
                i += 1
            }
            blocks.append(.paragraph(para.joined(separator: " ")))
        }

        return blocks
    }

    private static func headingComponents(_ line: String) -> (Int, String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level > 0, idx < line.endIndex, line[idx] == " " else { return nil }
        let content = String(line[line.index(after: idx)...])
        return (level, content)
    }

    private static func listItem(from line: String) -> MarkdownListItem? {
        // Task list: "- [ ] text" or "- [x] text"
        if line.hasPrefix("- [ ] ") {
            return MarkdownListItem(text: String(line.dropFirst(6)), kind: .unchecked)
        }
        if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
            return MarkdownListItem(text: String(line.dropFirst(6)), kind: .checked)
        }
        // Unordered: "- text" or "* text"
        if line.hasPrefix("- ") {
            return MarkdownListItem(text: String(line.dropFirst(2)), kind: .unordered)
        }
        if line.hasPrefix("* ") {
            return MarkdownListItem(text: String(line.dropFirst(2)), kind: .unordered)
        }
        // Ordered: "1. text", "12. text" etc
        var idx = line.startIndex
        var digitCount = 0
        while idx < line.endIndex, line[idx].isNumber {
            digitCount += 1
            idx = line.index(after: idx)
        }
        if digitCount > 0,
           idx < line.endIndex, line[idx] == ".",
           line.index(after: idx) < line.endIndex,
           line[line.index(after: idx)] == " " {
            let textStart = line.index(idx, offsetBy: 2)
            return MarkdownListItem(text: String(line[textStart...]), kind: .ordered)
        }
        return nil
    }

    private static func isBlockStart(_ line: String) -> Bool {
        if line.hasPrefix("#"), line.contains(" ") { return true }
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return true }
        if line.hasPrefix("```") { return true }
        if line.hasPrefix(">") { return true }
        if line == "---" || line == "***" { return true }
        return false
    }
}

#Preview {
    ScrollView {
        MarkdownView(text: """
        # Heading 1
        ## Heading 2
        ### Heading 3

        A regular paragraph with **bold** and *italic* and `code` and a [link](https://apple.com).

        - Bullet one
        - Bullet two with **emphasis**

        1. First
        2. Second

        - [ ] Open task
        - [x] Closed task

        > A quote.
        > With two lines.

        ```
        let x = 42
        print(x)
        ```

        ---

        Final paragraph.
        """)
        .padding()
    }
}
