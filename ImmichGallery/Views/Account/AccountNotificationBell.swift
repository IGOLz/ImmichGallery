import SwiftUI

struct AccountNotificationBell: View {
    let session: AccountServices
    private var notifications: [AccountNotification] { session.notifications }
    @State private var showing = false
    @State private var operation = AccountOperation()
    private var available: Bool { session.notificationsAvailable }
    private var unread: [AccountNotification] { notifications.filter { $0.readAt == nil } }

    var body: some View {
        if available {
            Button {
                showing.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: unread.isEmpty ? "bell" : "bell.badge")
                    if !unread.isEmpty { Text(unread.count.formatted()).monospacedDigit() }
                }
                .accessibilityLabel("Notifications, \(unread.count) unread")
            }
            .help("\(unread.count) unread notifications")
            .popover(isPresented: $showing) {
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
                }.frame(width: 500, height: 430).disabled(operation.busy)
                    .task { operation.run { try await reload() } }
            }

        }
    }

    private func reload() async throws {
        try await session.reloadNotifications()
    }
}
