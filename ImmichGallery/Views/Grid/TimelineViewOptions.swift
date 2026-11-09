import SwiftUI

/// Timeline pages: the View Options menu (TimelineArrangement). Takes only stable inputs: on macOS 15
/// a toolbar item whose inputs change is rebuilt, which closes its menu.
struct TimelineViewOptions: View {
    let page: TimelinePage
    let dateAddedAvailable: Bool
    @AppStorage private var show: TimelineShow
    @AppStorage private var sortBy: TimelineSortBy
    @AppStorage private var order: TimelineOrder

    init(page: TimelinePage, dateAddedAvailable: Bool) {
        self.page = page
        self.dateAddedAvailable = dateAddedAvailable
        _show = AppStorage(wrappedValue: .all, page.key("show"))
        _sortBy = AppStorage(wrappedValue: .dateTaken, page.key("sortBy"))
        _order = AppStorage(wrappedValue: .newestFirst, page.key("order"))
    }

    var body: some View {
        Menu {
            if page.offersFavoritesFilter {
                Picker("Show", selection: $show) {
                    ForEach(TimelineShow.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            Picker("Sort By", selection: Binding(get: { dateAddedAvailable ? sortBy : .dateTaken }, set: { sortBy = $0 })) {
                ForEach(TimelineSortBy.allCases) { option in
                    Text(option.title).tag(option).disabled(option == .dateAdded && !dateAddedAvailable)
                }
            }
            .pickerStyle(.inline)
            Picker("Order", selection: $order) {
                ForEach(TimelineOrder.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("View Options", systemImage: page.offersFavoritesFilter && show != .all
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help(dateAddedAvailable ? "View Options" : "View Options. Sorting by Date Added needs Immich v3.0 or later.")
    }
}

/// Reloads a timeline grid when its page's view options change, in this window or another.
struct TimelineViewOptionsReloader: ViewModifier {
    let model: AssetGridModel
    @AppStorage private var show: TimelineShow
    @AppStorage private var sortBy: TimelineSortBy
    @AppStorage private var order: TimelineOrder

    init(page: TimelinePage, model: AssetGridModel) {
        self.model = model
        _show = AppStorage(wrappedValue: .all, page.key("show"))
        _sortBy = AppStorage(wrappedValue: .dateTaken, page.key("sortBy"))
        _order = AppStorage(wrappedValue: .newestFirst, page.key("order"))
    }

    func body(content: Content) -> some View {
        content.onChange(of: TimelineArrangement(show: show, sortBy: sortBy, order: order)) {
            Task { await model.reload() }
        }
    }
}

extension View {
    @ViewBuilder
    func timelineViewOptionsReloader(_ model: AssetGridModel) -> some View {
        if let page = model.source.timelinePage {
            modifier(TimelineViewOptionsReloader(page: page, model: model))
        } else {
            self
        }
    }
}
