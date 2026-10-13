import SwiftUI

extension Font {
    static var weatherLargeTitle: Font {
        .custom("Verdana", size: 32, relativeTo: .largeTitle).weight(.bold)
    }

    static var weatherHeadline: Font {
        .custom("Verdana", size: 15, relativeTo: .headline).weight(.bold)
    }

    static var weatherBody: Font {
        .custom("Verdana", size: 15, relativeTo: .body)
    }

    static var weatherSubheadline: Font {
        .custom("Verdana", size: 13, relativeTo: .subheadline)
    }

    static var weatherFootnote: Font {
        .custom("Verdana", size: 11, relativeTo: .footnote)
    }
}

extension View {
    @ViewBuilder
    func weatherInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func weatherCityTextInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}

@main
struct MyWeatherApp: App {
    @StateObject private var store = WeatherStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .font(.weatherBody)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(minWidth: 320, minHeight: 300)
                #endif
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        #endif
    }
}
