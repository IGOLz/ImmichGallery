import SwiftUI

struct AccountNotificationBell: View {
    let session: LibrarySession
    @Environment(\.scenePhase) private var scenePhase
    @State private var notifications: [AccountNotification] = []
    @State private var showing = false
    @State private var operation = AccountOperation()
    @State private var available = true
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
                    AccountOperationStatus(operation: operation).padding(.horizontal)
                }.frame(width: 500, height: 430).disabled(operation.busy)
                    .task { operation.run { try await reload() } }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                var retryDelay = 60
                while !Task.isCancelled && available {
                    do {
                        try await reload()
                        retryDelay = 60
                        try await Task.sleep(for: .seconds(60))
                    } catch is CancellationError { return }
                    catch ImmichError.http(404, _) { available = false; return }
                    catch ImmichError.http(403, _) { available = false; return }
                    catch {
                        operation.error = error.localizedDescription
                        retryDelay = min(retryDelay * 2, 900)
                        do { try await Task.sleep(for: .seconds(retryDelay)) } catch { return }
                    }
                }
            }
        }
    }

    private func reload() async throws {
        notifications = try await session.client.accountNotifications().sorted { $0.createdAt > $1.createdAt }
    }
}
