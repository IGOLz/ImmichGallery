import AppKit
import UserNotifications
import SwiftUI

/// Requests permission only when a caller explicitly enables completion notifications.
@MainActor
enum SystemNotifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func completed(title: String, body: String) async {
        guard UserDefaults.standard.bool(forKey: "completionNotifications"), !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

struct MacNotificationPreference: View {
    @AppStorage("completionNotifications") private var enabled = false
    @State private var permissionDenied = false
    var body: some View {
        Section("Notifications") {
            Toggle("Notify When Background Work Finishes", isOn: Binding(get: { enabled }, set: { value in
                if value {
                    Task {
                        enabled = await SystemNotifier.requestPermission()
                        permissionDenied = !enabled
                    }
                } else { enabled = false }
            }))
            if permissionDenied {
                Text("Enable notifications for Immich Gallery in System Settings → Notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
