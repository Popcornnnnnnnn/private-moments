import Foundation
import SwiftUI
import UIKit

struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    var onPasteImages: (([Data]) -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.text = text
        context.coordinator.textView = textView
        configureImagePasteHandler(for: textView, context: context)
        textView.font = MarkdownEditorStyler.bodyFont
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.smartInsertDeleteType = .default
        textView.inputAccessoryView = context.coordinator.makeAccessoryView()
        context.coordinator.applyMarkdownStyling(to: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onPasteImages = onPasteImages
        context.coordinator.textView = uiView
        configureImagePasteHandler(for: uiView, context: context)

        if uiView.text != text,
           !context.coordinator.hasMarkedText(in: uiView) {
            uiView.text = text
        }

        context.coordinator.applyMarkdownStyling(to: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onPasteImages: onPasteImages)
    }

    private func configureImagePasteHandler(for textView: UITextView, context: Context) {
        guard let textView = textView as? PasteAwareTextView else {
            return
        }

        guard onPasteImages != nil else {
            textView.pastedImageHandler = nil
            return
        }

        textView.pastedImageHandler = { pastedImages in
            context.coordinator.handlePastedImages(pastedImages)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var onPasteImages: (([Data]) -> Void)?
        weak var textView: UITextView?

        private var isApplyingMarkdownStyling = false

        init(text: Binding<String>, onPasteImages: (([Data]) -> Void)?) {
            self.text = text
            self.onPasteImages = onPasteImages
        }

        func makeAccessoryView() -> UIView {
            let toolbar = UIToolbar(frame: CGRect(origin: .zero, size: CGSize(width: 0, height: 44)))
            toolbar.isTranslucent = true

            let formatControl = UISegmentedControl(items: ["H1", "H2"])
            formatControl.selectedSegmentTintColor = UIColor.secondarySystemFill
            formatControl.backgroundColor = UIColor.tertiarySystemFill
            formatControl.setWidth(46, forSegmentAt: 0)
            formatControl.setWidth(46, forSegmentAt: 1)
            formatControl.setTitleTextAttributes(
                [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: UIColor.label
                ],
                for: .normal
            )
            formatControl.addTarget(self, action: #selector(formatControlChanged(_:)), for: .valueChanged)
            formatControl.accessibilityLabel = "Text format"

            toolbar.items = [
                UIBarButtonItem(customView: formatControl)
            ]

            toolbar.sizeToFit()
            return toolbar
        }

        func handlePastedImages(_ pastedImages: [Data]) -> Bool {
            guard let onPasteImages else {
                return false
            }

            onPasteImages(pastedImages)
            return true
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n" else {
                return true
            }

            guard let edit = PlainTextListContinuation.replacement(
                in: textView.text ?? "",
                selectedRange: range,
                replacementText: replacement
            ) else {
                return true
            }

            applyListContinuation(edit, to: textView)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingMarkdownStyling else {
                return
            }

            text.wrappedValue = textView.text ?? ""
            if !hasMarkedText(in: textView) {
                applyMarkdownStyling(to: textView)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingMarkdownStyling else {
                return
            }

            if !hasMarkedText(in: textView) {
                applyMarkdownStyling(to: textView)
            }
        }

        func applyMarkdownStyling(to textView: UITextView) {
            guard !hasMarkedText(in: textView) else {
                return
            }

            let currentText = textView.text ?? ""
            let selectedRange = clamped(range: textView.selectedRange, textLength: currentText.utf16.count)

            isApplyingMarkdownStyling = true
            let attributed = MarkdownEditorStyler.attributedText(
                for: currentText,
                selectedRange: selectedRange
            )
            textView.textStorage.setAttributedString(attributed)
            textView.selectedRange = selectedRange
            textView.typingAttributes = MarkdownEditorStyler.typingAttributes(
                for: currentText,
                selectedRange: selectedRange
            )
            isApplyingMarkdownStyling = false
        }

        @objc private func formatControlChanged(_ sender: UISegmentedControl) {
            switch sender.selectedSegmentIndex {
            case 0:
                toggle(.heading(level: 1))
            case 1:
                toggle(.heading(level: 2))
            default:
                break
            }

            sender.selectedSegmentIndex = UISegmentedControl.noSegment
        }

        private func toggle(_ style: MomentTextMarkdown.LineStyle) {
            guard let textView else {
                return
            }

            guard let edit = MomentTextMarkdown.togglingLineStyle(
                style,
                in: textView.text ?? "",
                selectedRange: textView.selectedRange
            ) else {
                return
            }

            apply(edit, to: textView)
            UISelectionFeedbackGenerator().selectionChanged()
        }

        private func apply(_ edit: MomentTextMarkdown.TextEdit, to textView: UITextView) {
            guard let currentText = textView.text,
                  let stringRange = Range(edit.replacementRange, in: currentText) else {
                return
            }

            let updatedText = currentText.replacingCharacters(in: stringRange, with: edit.replacementText)
            textView.text = updatedText
            text.wrappedValue = updatedText
            textView.selectedRange = clamped(range: edit.selectedRange, textLength: updatedText.utf16.count)
            applyMarkdownStyling(to: textView)
        }

        private func applyListContinuation(_ edit: PlainTextListContinuation.Edit, to textView: UITextView) {
            guard let currentText = textView.text,
                  let stringRange = Range(edit.replacementRange, in: currentText) else {
                return
            }

            let updatedText = currentText.replacingCharacters(in: stringRange, with: edit.replacementText)
            textView.text = updatedText
            text.wrappedValue = updatedText
            textView.selectedRange = clamped(range: edit.selectedRange, textLength: updatedText.utf16.count)
            applyMarkdownStyling(to: textView)
        }

        private func clamped(range: NSRange, textLength: Int) -> NSRange {
            let location = min(max(0, range.location), textLength)
            let maxLength = max(0, textLength - location)
            return NSRange(location: location, length: min(max(0, range.length), maxLength))
        }

        func hasMarkedText(in textView: UITextView) -> Bool {
            guard let markedRange = textView.markedTextRange else {
                return false
            }

            return textView.offset(from: markedRange.start, to: markedRange.end) > 0
        }
    }
}

private enum MarkdownEditorStyler {
    static var bodyFont: UIFont {
        UIFont.preferredFont(forTextStyle: .body)
    }

    static func attributedText(for text: String, selectedRange: NSRange) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes()
        )
        let nsText = text as NSString

        for line in styledLines(in: text) {
            if let heading = headingMarker(in: line.text) {
                let font = heading.level == 1 ? heading1Font : heading2Font
                attributed.addAttributes(
                    [
                        .font: font,
                        .foregroundColor: UIColor.label,
                        .paragraphStyle: headingParagraphStyle
                    ],
                    range: line.contentRange
                )

                let markerRange = NSRange(location: line.contentRange.location, length: heading.length)
                attributed.addAttributes(
                    line.contains(selectedRange.location)
                        ? headingMarkerAttributes(font: font)
                        : hiddenMarkerAttributes(),
                    range: markerRange
                )
                continue
            }

        }

        if nsText.length == 0 {
            attributed.addAttributes(baseAttributes(), range: NSRange(location: 0, length: 0))
        }

        return attributed
    }

    static func typingAttributes(for text: String, selectedRange: NSRange) -> [NSAttributedString.Key: Any] {
        guard let line = styledLines(in: text).first(where: { $0.contains(selectedRange.location) }),
              let heading = headingMarker(in: line.text) else {
            return baseAttributes()
        }

        return [
            .font: heading.level == 1 ? heading1Font : heading2Font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: headingParagraphStyle
        ]
    }

    private static var heading1Font: UIFont {
        scaledSystemFont(textStyle: .title2, weight: .semibold)
    }

    private static var heading2Font: UIFont {
        scaledSystemFont(textStyle: .title3, weight: .semibold)
    }

    private static var headingParagraphStyle: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 3
        return paragraph
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: UIColor.label
        ]
    }

    private static func headingMarkerAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
    }

    private static func hiddenMarkerAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 0.1),
            .foregroundColor: UIColor.clear,
            .kern: -1
        ]
    }

    private static func scaledSystemFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: textStyle)
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }

    private static func headingMarker(in line: String) -> (level: Int, length: Int)? {
        if line.hasPrefix("## ") {
            return (2, 3)
        }

        if line.hasPrefix("# ") {
            return (1, 2)
        }

        return nil
    }

    private static func styledLines(in text: String) -> [StyledLine] {
        let nsText = text as NSString
        guard nsText.length > 0 else {
            return []
        }

        var result: [StyledLine] = []
        var location = 0

        while location < nsText.length {
            let rawRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            var contentLength = rawRange.length
            let rawLine = nsText.substring(with: rawRange)

            if rawLine.hasSuffix("\r\n") {
                contentLength -= 2
            } else if rawLine.hasSuffix("\n") || rawLine.hasSuffix("\r") {
                contentLength -= 1
            }

            let contentRange = NSRange(location: rawRange.location, length: max(0, contentLength))
            result.append(StyledLine(contentRange: contentRange, text: nsText.substring(with: contentRange)))

            let nextLocation = NSMaxRange(rawRange)
            guard nextLocation > location else {
                break
            }
            location = nextLocation
        }

        return result
    }

    private struct StyledLine {
        let contentRange: NSRange
        let text: String

        func contains(_ location: Int) -> Bool {
            location >= contentRange.location && location <= NSMaxRange(contentRange)
        }
    }
}

struct PlainTextListEditor: UIViewRepresentable {
    @Binding var text: String
    var onPasteImages: (([Data]) -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.text = text
        configureImagePasteHandler(for: textView, context: context)
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.smartInsertDeleteType = .default
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onPasteImages = onPasteImages
        configureImagePasteHandler(for: uiView, context: context)

        if uiView.text != text {
            uiView.text = text
        }

        uiView.font = .preferredFont(forTextStyle: .body)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onPasteImages: onPasteImages)
    }

    private func configureImagePasteHandler(for textView: UITextView, context: Context) {
        guard let textView = textView as? PasteAwareTextView else {
            return
        }

        guard onPasteImages != nil else {
            textView.pastedImageHandler = nil
            return
        }

        textView.pastedImageHandler = { pastedImages in
            context.coordinator.handlePastedImages(pastedImages)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var onPasteImages: (([Data]) -> Void)?

        init(text: Binding<String>, onPasteImages: (([Data]) -> Void)?) {
            self.text = text
            self.onPasteImages = onPasteImages
        }

        func handlePastedImages(_ pastedImages: [Data]) -> Bool {
            guard let onPasteImages else {
                return false
            }

            onPasteImages(pastedImages)
            return true
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n" else {
                return true
            }

            guard let edit = PlainTextListContinuation.replacement(
                in: textView.text ?? "",
                selectedRange: range,
                replacementText: replacement
            ) else {
                return true
            }

            guard let currentText = textView.text,
                  let stringRange = Range(edit.replacementRange, in: currentText) else {
                return true
            }

            let updatedText = currentText.replacingCharacters(in: stringRange, with: edit.replacementText)
            textView.text = updatedText
            text.wrappedValue = updatedText
            textView.selectedRange = edit.selectedRange
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text ?? ""
        }
    }
}

private final class PasteAwareTextView: UITextView {
    var pastedImageHandler: (([Data]) -> Bool)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)),
           pastedImageHandler != nil,
           UIPasteboard.general.pmHasImages {
            return true
        }

        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pastedImages = UIPasteboard.general.pmImageData(limit: ComposerImageDraft.maxImageCount)

        if !pastedImages.isEmpty,
           let pastedImageHandler,
           pastedImageHandler(pastedImages) {
            return
        }

        super.paste(sender)
    }
}

private extension UIPasteboard {
    var pmHasImages: Bool {
        hasImages
    }

    func pmImageData(limit: Int) -> [Data] {
        let pastedImages = images ?? image.map { [$0] } ?? []
        return pastedImages
            .prefix(max(0, limit))
            .compactMap { image in
                image.jpegData(compressionQuality: 0.9) ?? image.pngData()
            }
    }
}

struct PlainTextListContinuation {
    struct Edit: Equatable {
        let replacementRange: NSRange
        let replacementText: String
        let selectedRange: NSRange
    }

    static func replacement(
        in text: String,
        selectedRange: NSRange,
        replacementText: String
    ) -> Edit? {
        guard replacementText == "\n",
              selectedRange.length >= 0,
              isValid(range: selectedRange, in: text) else {
            return nil
        }

        let nsText = text as NSString
        let cursorLocation = selectedRange.location
        let currentLineRange = nsText.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let lineEnd = min(cursorLocation, currentLineRange.location + currentLineRange.length)
        let linePrefixRange = NSRange(location: currentLineRange.location, length: lineEnd - currentLineRange.location)
        let linePrefix = nsText.substring(with: linePrefixRange)

        guard let marker = ListMarker(linePrefix: linePrefix) else {
            return nil
        }

        if marker.hasEmptyItemText {
            let replacementRange = NSRange(
                location: currentLineRange.location,
                length: linePrefixRange.length + selectedRange.length
            )
            let selectedLocation = currentLineRange.location + 1
            return Edit(
                replacementRange: replacementRange,
                replacementText: "\n",
                selectedRange: NSRange(location: selectedLocation, length: 0)
            )
        }

        guard let nextPrefix = marker.nextPrefix else {
            return nil
        }

        let customReplacement = "\n" + nextPrefix
        let selectedLocation = selectedRange.location + customReplacement.utf16.count
        return Edit(
            replacementRange: selectedRange,
            replacementText: customReplacement,
            selectedRange: NSRange(location: selectedLocation, length: 0)
        )
    }

    private static func isValid(range: NSRange, in text: String) -> Bool {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= text.utf16.count,
              range.location + range.length <= text.utf16.count else {
            return false
        }

        return Range(range, in: text) != nil
    }
}

private struct ListMarker {
    let nextPrefix: String?
    let hasEmptyItemText: Bool

    init?(linePrefix: String) {
        if linePrefix.hasPrefix("- ") {
            self.nextPrefix = "- "
            self.hasEmptyItemText = Self.isEmptyItemText(linePrefix.dropFirst(2))
            return
        }

        if linePrefix.hasPrefix("• ") {
            self.nextPrefix = "• "
            self.hasEmptyItemText = Self.isEmptyItemText(linePrefix.dropFirst(2))
            return
        }

        guard let numbered = Self.numberedPrefix(in: linePrefix) else {
            return nil
        }

        self.nextPrefix = numbered.nextPrefix
        self.hasEmptyItemText = Self.isEmptyItemText(linePrefix.dropFirst(numbered.prefixLength))
    }

    private static func isEmptyItemText(_ text: Substring) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func numberedPrefix(in linePrefix: String) -> (prefixLength: Int, nextPrefix: String?)? {
        var digits = ""
        var cursor = linePrefix.startIndex

        while cursor < linePrefix.endIndex, linePrefix[cursor].isNumber {
            digits.append(linePrefix[cursor])
            cursor = linePrefix.index(after: cursor)
        }

        guard !digits.isEmpty,
              cursor < linePrefix.endIndex,
              linePrefix[cursor] == "." else {
            return nil
        }

        cursor = linePrefix.index(after: cursor)

        guard cursor < linePrefix.endIndex,
              linePrefix[cursor] == " " else {
            return nil
        }

        let prefixLength = linePrefix.distance(from: linePrefix.startIndex, to: linePrefix.index(after: cursor))
        guard let number = Int(digits), number < Int.max else {
            return (prefixLength, nil)
        }

        return (prefixLength, "\(number + 1). ")
    }
}
