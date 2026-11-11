import AppKit

/// Renders a paginated, typographically clean A4 PDF of a summary using the system text stack.
@MainActor
enum PDFRenderer {
    static func render(title: String, meta: String, summary: VideoSummary, to url: URL) throws {
        let text = attributedSummary(title: title, meta: meta, summary: summary)

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595, height: 842)
        printInfo.topMargin = 56; printInfo.bottomMargin = 56
        printInfo.leftMargin = 60; printInfo.rightMargin = 60
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.backgroundColor = .white
        textView.textStorage?.setAttributedString(text)
        textView.isVerticallyResizable = true
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.sizeToFit()

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func attributedSummary(title: String, meta: String, summary: VideoSummary) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let ink = NSColor(white: 0.1, alpha: 1)
        let muted = NSColor(white: 0.45, alpha: 1)

        func paragraph(spacingBefore: CGFloat = 0, after: CGFloat = 6, indent: CGFloat = 0, lineHeight: CGFloat = 1.25) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = spacingBefore
            p.paragraphSpacing = after
            p.lineHeightMultiple = lineHeight
            p.headIndent = indent
            p.firstLineHeadIndent = indent > 0 ? indent - 12 : 0
            if indent > 0 { p.tabStops = [NSTextTab(textAlignment: .left, location: indent)] }
            return p
        }
        func add(_ s: String, font: NSFont, color: NSColor = ink, style: NSParagraphStyle) {
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        }
        func heading(_ s: String) {
            add(s, font: .systemFont(ofSize: 13, weight: .semibold), style: paragraph(spacingBefore: 16, after: 6))
        }
        func bullets(_ items: [String], empty: String? = nil) {
            if items.isEmpty, let empty {
                add(empty, font: .systemFont(ofSize: 11), color: muted, style: paragraph())
            }
            for item in items {
                add("•\t\(item)", font: .systemFont(ofSize: 11), style: paragraph(after: 4, indent: 14))
            }
        }

        add(title, font: .systemFont(ofSize: 22, weight: .bold), style: paragraph(after: 4, lineHeight: 1.1))
        add(meta, font: .systemFont(ofSize: 10), color: muted, style: paragraph(after: 10))

        heading(tr("Visão geral"))
        add(summary.overview, font: .systemFont(ofSize: 11), style: paragraph(after: 4, lineHeight: 1.35))

        if !summary.chapters.isEmpty {
            heading(tr("Capítulos"))
            for c in summary.chapters {
                let line = NSMutableAttributedString(string: TimeFormat.clock(c.start) + "\t",
                    attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium), .foregroundColor: muted])
                line.append(NSAttributedString(string: c.title + "\n", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: ink]))
                let p = NSMutableParagraphStyle(); p.tabStops = [NSTextTab(textAlignment: .left, location: 56)]; p.headIndent = 56; p.paragraphSpacing = 3
                line.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: line.length))
                out.append(line)
            }
        }
        if !summary.topics.isEmpty { heading(tr("Principais tópicos")); bullets(summary.topics) }
        if !summary.keyPoints.isEmpty { heading(tr("Pontos importantes")); bullets(summary.keyPoints) }
        heading(tr("Decisões e conclusões")); bullets(summary.decisions, empty: tr("Nenhuma decisão identificada no conteúdo."))
        heading(tr("Ações e próximos passos")); bullets(summary.actionItems, empty: tr("Nenhuma ação mencionada no conteúdo."))

        add("", font: .systemFont(ofSize: 8), style: paragraph(spacingBefore: 12))
        add(TranscriptRenderer.disclaimer(summary), font: .systemFont(ofSize: 9), color: muted, style: paragraph())
        return out
    }
}
