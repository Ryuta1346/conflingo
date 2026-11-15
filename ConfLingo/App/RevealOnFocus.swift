import SwiftUI

struct RevealOnFocus: ViewModifier {
    let proxy: ScrollViewProxy?
    @Namespace private var target
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .id(target)
            .focused($focused)
            .onChange(of: focused) { _, value in
                if value { proxy?.scrollTo(target, anchor: .center) }
            }
    }
}
