// Offline checks for the real tag picker. No app, account or server access.
import Foundation
import SwiftUI

@main struct ExploreTagPickerChecks {
    @MainActor static func main() {
        let tags = [
            ExploreTag(id: "a", name: "Città", value: "Viaggi/Città"),
            ExploreTag(id: "b", name: "Mare", value: "Viaggi/Mare"),
            ExploreTag(id: "c", name: "Città", value: "Casa/Città")
        ]
        for removing in [true, false] {
            func matches(_ query: String) -> [String] {
                ExploreTagPicker(tags: tags, removing: removing, apply: { _ in }, query: query).matchingTags.map(\.id)
            }
            precondition(matches("") == ["a", "b", "c"])
            precondition(matches(" \n ") == ["a", "b", "c"])
            precondition(matches("viaggi") == ["a", "b"])
            precondition(matches(" CITTA ") == ["a", "c"])
            precondition(matches("Casa/Città") == ["c"])
            precondition(matches("absent").isEmpty)
        }
        // Guard the actual regression: opening the menu must not enumerate the tag catalog.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try! String(contentsOf: root.appendingPathComponent("ImmichGallery/Views/Explore/ExploreTagsView.swift"), encoding: .utf8)
        let actions = source.components(separatedBy: "struct ExploreAssetActions: View {")[1]
        precondition(!actions.contains("ForEach"), "Context-menu tag actions must have constant size")
        precondition(actions.range(of: #"session\.exploreTags\b"#, options: .regularExpression) == nil,
                     "The tag catalog belongs in the picker, not the context menu")
        print("Tag picker checks passed: full-path filtering, case/diacritics, whitespace, empty results and bounded context-menu construction")
    }
}
