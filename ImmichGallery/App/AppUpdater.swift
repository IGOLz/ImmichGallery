import Observation
import Sparkle
import SwiftUI

/// In-app updates with Sparkle. The feed URL and the public signing key are in Info.plist;
/// releases publish a signed appcast next to the ZIP (see docs/Updates.md).
@MainActor @Observable
final class AppUpdater {
    static let shared = AppUpdater()
    static let isDevelopment = Bundle.main.bundleIdentifier == "dev.igol.ImmichGallery.Dev"

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: !AppUpdater.isDevelopment, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    private var updater: SPUUpdater { controller.updater }

    private(set) var canCheckForUpdates = false

    /// Checks when the app opens and once a day.
    var automaticallyChecks = false {
        didSet {
            if updater.automaticallyChecksForUpdates != automaticallyChecks {
                updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }

    /// Downloads updates silently and installs them when the app quits, instead of asking first.
    var automaticallyDownloads = false {
        didSet {
            if updater.automaticallyDownloadsUpdates != automaticallyDownloads {
                updater.automaticallyDownloadsUpdates = automaticallyDownloads
            }
        }
    }

    var allowsAutomaticDownloads: Bool { updater.allowsAutomaticUpdates }

    var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private init() {
        guard !Self.isDevelopment else { return }
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        refresh()
    }

    /// Re-reads the preferences, which Sparkle's update window can also change.
    func refresh() {
        guard !Self.isDevelopment else { return }
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
    }

    /// Shows the progress and the result, including "You're up to date".
    func checkForUpdates() { if !Self.isDevelopment { updater.checkForUpdates() } }

    /// Called once at launch. Unless updates install automatically, a new version opens
    /// Sparkle's window with the release notes and Install / Remind Me Later / Skip.
    /// With automatic updates, it is downloaded quietly and installed when the app quits.
    func checkAtLaunch() {
        guard !Self.isDevelopment, updater.automaticallyChecksForUpdates else { return }
        Task {
            // Let the library window appear first.
            try? await Task.sleep(for: .seconds(3))
            if !updater.sessionInProgress { updater.checkForUpdatesInBackground() }
        }
    }
}

struct UpdateCommands: Commands {
    let updater: AppUpdater
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

struct UpdateSettingsView: View {
    @Bindable private var updater = AppUpdater.shared

    var body: some View {
        Form {
            Section {
                Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecks)
                    .disabled(AppUpdater.isDevelopment)
                if updater.allowsAutomaticDownloads {
                    Toggle("Download and Install Updates Automatically", isOn: $updater.automaticallyDownloads)
                        .disabled(!updater.automaticallyChecks)
                }
            } footer: {
                if AppUpdater.isDevelopment {
                    Text("Development builds update automatically from the local source code.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Immich Gallery looks for a new version when it opens and once a day. Unless updates install automatically, it asks you before updating. Automatic updates are installed the next time you quit the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Current Version", value: updater.versionDescription)
                HStack {
                    Spacer()
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { updater.refresh() }
    }
}
