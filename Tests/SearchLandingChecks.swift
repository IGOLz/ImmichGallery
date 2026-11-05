// Offline presentation check with hidden windows. No app, credentials or live server.
import AppKit
import SwiftUI

private final class OfflineThumbnails: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@main private struct SearchLandingChecks {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineThumbnails.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://example.invalid/api")!
        let pipeline = ImagePipeline(client: ImmichClient(serverURL: url, apiURL: url, credential: nil, session: session))
        let asset = try JSONDecoder().decode(AssetResponse.self, from: Data(#"{"id":"fixture","type":"IMAGE","originalFileName":"fixture.jpg","fileCreatedAt":"2026-01-01T00:00:00Z","localDateTime":"2026-01-01T00:00:00Z","isFavorite":false,"isTrashed":false}"#.utf8))
        let places = ["Bergamo", "Brussels", "Burano", "Berlin", "Chicago", "A place with a longer name"].map {
            SearchExploreGroup.Item(value: $0, data: asset)
        }
        var scene = SearchQuery(); scene.text = "Blue sky"
        var filtered = SearchQuery(); filtered.favorites = true; filtered.city = "Bergamo"
        let output = URL(fileURLWithPath: "build/search-design", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            for width: CGFloat in [380, 980] {
                for populated in [false, true] {
                    let content = SearchLandingView(
                        pipeline: pipeline, query: SearchQuery(),
                        recent: populated ? [scene, filtered] : [], places: populated ? places : [],
                        controls: HStack {
                            Text("Search by").foregroundStyle(.secondary)
                            Text("Context").frame(width: 170)
                            Button("Filters") {}
                        }, select: { _ in }, clearHistory: {})
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .background(Color(nsColor: .windowBackgroundColor))
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 820),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
                    let host = NSHostingView(rootView: content)
                    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.contentView = host
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                    host.layoutSubtreeIfNeeded()
                    func checkScroll(_ view: NSView) {
                        if let scroll = view as? NSScrollView, let document = scroll.documentView {
                            precondition(document.frame.width <= scroll.bounds.width + 1,
                                         "Search landing must fit the viewport without horizontal scrolling")
                        }
                        for child in view.subviews { checkScroll(child) }
                    }
                    checkScroll(host)
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let filename = "\(dark ? "dark" : "light")-\(Int(width))-\(populated ? "places" : "empty").png"
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
                    window.orderOut(nil)
                }
            }
        }
        print("Search landing checks passed: light/dark, narrow/wide, recent and place suggestions, offline rendering")
    }
}
