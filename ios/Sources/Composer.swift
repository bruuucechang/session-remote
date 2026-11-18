import SwiftUI

/// 底部的輸入框。用 UITextView（TextEditor 的文字元件）而不是 vertical TextField：
/// 後者超過 lineLimit 之後不會捲到游標，打多行時新打的字直接掉到框外看不到。
/// 高度跟著內容長，長到 maxHeight 就固定、改成框內捲動（UITextView 會自己跟著游標）。
struct Composer: View {
    @Binding var text: String
    let placeholder: String
    let sending: Bool
    /// 不轉圈、只是現在不給送（例如畫面上開著沒有打字選項的選單）
    var blocked = false
    var focus: Binding<Bool>
    let onSend: () -> Void

    @State private var editor = ComposerInput()
    @State private var contentHeight: CGFloat = 0
    private let minHeight: CGFloat = 38
    private let maxHeight: CGFloat = 160

    private var canSend: Bool {
        !sending && !blocked && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ComposerTextView(text: $text, focus: focus, input: editor)
                .frame(height: min(max(contentHeight, minHeight), maxHeight))
                // 捲到框外的行不要畫出來（UITextView 預設不裁切，會疊到上面的內容）
                .clipped()
                // 用一份看不見的 Text 量內容高度（跟 UITextView 的內距一致：左右 5、上下 8）
                .background(alignment: .topLeading) {
                    Text(measureText)
                        .font(.body)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(GeometryReader { g in
                            Color.clear.preference(key: HeightKey.self, value: g.size.height)
                        })
                }
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
                .padding(.horizontal, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 19, style: .continuous))

            Button {
                // 先結束中文組字，把 UITextView 裡最後的字同步回 binding，再交給送出流程。
                text = editor.finishEditing() ?? text
                onSend()
                editor.clear()
            } label: {
                ZStack {
                    // 不能送時用淡底＋灰箭頭：深色模式下 systemGray4 配白箭頭看起來還是可以按
                    Circle().fill(canSend || sending ? Color.accentColor : Color(.tertiarySystemFill))
                    if sending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up").font(.body.weight(.bold))
                            .foregroundStyle(canSend ? Color.white : Color(.tertiaryLabel))
                    }
                }
                .frame(width: 38, height: 38)
            }
            .disabled(!canSend)
            .accessibilityLabel("送出")
        }
    }

    /// 結尾是換行時 Text 不算最後那個空行，補一個字元讓高度先長出來
    private var measureText: String {
        text.isEmpty ? " " : (text.hasSuffix("\n") ? text + " " : text)
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 保留 UITextView 的多行、游標捲動；送出時能同步結束 marked text 並確實清空。
private final class ComposerInput {
    weak var view: UITextView?

    func finishEditing() -> String? {
        view?.unmarkText()
        let text = view?.text
        view?.resignFirstResponder()
        return text
    }

    func clear() {
        view?.unmarkText()
        view?.text = ""
    }
}

private struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    var focus: Binding<Bool>
    let input: ComposerInput

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 5
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        input.view = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text, view.markedTextRange == nil { view.text = text }
        if focus.wrappedValue, !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !focus.wrappedValue, view.isFirstResponder {
            view.resignFirstResponder()
        }
        #if DEBUG
        // 用真正的 marked text 重現中文組字，不依賴模擬器當時裝哪種鍵盤。
        if view.isFirstResponder, !context.coordinator.seededMarkedText,
           let marked = ProcessInfo.processInfo.environment["SR_MARKED_TEXT"] {
            context.coordinator.seededMarkedText = true
            view.setMarkedText(marked, selectedRange: NSRange(location: marked.utf16.count, length: 0))
            DispatchQueue.main.async { self.text = view.text }
        }
        #endif
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        var seededMarkedText = false
        init(_ parent: ComposerTextView) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) { parent.text = view.text }
        func textViewDidBeginEditing(_ view: UITextView) {
            if !parent.focus.wrappedValue { parent.focus.wrappedValue = true }
        }
        func textViewDidEndEditing(_ view: UITextView) {
            if parent.focus.wrappedValue { parent.focus.wrappedValue = false }
        }
    }
}
