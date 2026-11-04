import SwiftUI

struct AccountNotificationBell: View {
    let session: AccountServices
    @State private var showing = false
    // Owned here so an operation outlives a closed popover; only the popover reads its state.
    @State private var operation = AccountOperation()

    // On macOS 15 a toolbar item is rebuilt whenever its root view reads data that changes,
    // which dismisses its popover (e.g. right after the popover reloads notifications).
    // Changing data is therefore read only by the child views below.
    var body: some View {
        if session.notificationsAvailable {
            Button { showing.toggle() } label: { AccountNotificationBellLabel(session: session) }
                .popover(isPresented: $showing) { AccountNotificationsPopover(session: session, operation: operation) }
        }
    }
}

private struct AccountNotificationBellLabel: View {
    let session: AccountServices
    var body: some View {
        let unreadCount = session.notifications.filter { $0.readAt == nil }.count
        HStack(spacing: 4) {
            Image(systemName: unreadCount == 0 ? "bell" : "bell.badge")
            if unreadCount > 0 { Text(unreadCount.formatted()).monospacedDigit() }
        }
        .accessibilityLabel("Notifications, \(unreadCount) unread")
        .help("\(unreadCount) unread notifications")
    }
}

private struct AccountNotificationsPopover: View {
    let session: AccountServices
    let operation: AccountOperation
    private var notifications: [AccountNotification] { session.notifications }
    private var unread: [AccountNotification] { notifications.filter { $0.readAt == nil } }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Notifications").font(.headline)
                Spacer()
                Text("\(unread.count) unread").foregroundStyle(.secondary)
                Button("Refresh") { operation.run { try await reload() } }
                Button("Mark All Read") {
                    operation.run {
                        try await session.client.readAccountNotifications(unread.map(\.id))
                        try await reload()
                    }
                }.disabled(unread.isEmpty)
            }.padding()
            if notifications.isEmpty { ContentUnavailableView("No Notifications", systemImage: "bell") }
            else {
                List(notifications) { notification in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(notification.title, systemImage: notification.readAt == nil ? "circle.fill" : "circle")
                            .fontWeight(notification.readAt == nil ? .semibold : .regular)
                        if let description = notification.description { Text(description).foregroundStyle(.secondary) }
                        Text(accountDate(notification.createdAt)).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if notification.readAt == nil {
                                Button("Mark Read") {
                                    operation.run {
                                        try await session.client.readAccountNotifications([notification.id])
                                        try await reload()
                                    }
                                }
                            }
                            Button("Delete", role: .destructive) {
                                operation.run {
                                    try await session.client.deleteAccountNotification(notification.id)
                                    try await reload()
                                }
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
            if let error = session.notificationError { Text(error).foregroundStyle(.red).padding(.horizontal) }
            AccountOperationStatus(operation: operation).padding(.horizontal)
        }
        .frame(width: 500, height: 430)
        .modifier(BusyDisabled(busy: operation.busy))
        .task { operation.run { try await reload() } }
    }

    private func reload() async throws {
        try await session.reloadNotifications()
    }
}

/// Disables the popover while busy. Not on macOS 15: disabling the focused button while the
/// popover becomes key loops forever there; `operation.run` already ignores taps while busy.
private struct BusyDisabled: ViewModifier {
    let busy: Bool
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.disabled(busy) } else { content }
    }
}
