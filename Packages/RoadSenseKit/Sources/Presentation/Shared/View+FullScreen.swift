import SwiftUI

extension View {
    /// Full screen on iOS. macOS has no full-screen cover, so the package (built there for editors) uses a sheet.
    func fullScreen<Item: Identifiable>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> some View,
    ) -> some View {
        #if os(iOS)
            fullScreenCover(item: item, content: content)
        #else
            sheet(item: item, content: content)
        #endif
    }
}
