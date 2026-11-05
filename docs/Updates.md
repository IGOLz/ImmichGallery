# In-app updates

Immich Gallery updates itself with [Sparkle 2](https://sparkle-project.org), the standard updater
for Mac apps distributed outside the App Store. It is a Swift package of the app target.

## What the user sees

- **Immich Gallery › Check for Updates…** checks right away and shows the result.
- **Settings › Updates** has two options:
  - *Check for Updates Automatically* (on by default): a check when the app opens and once a day.
  - *Download and Install Updates Automatically* (off by default): the update is downloaded quietly
    and installed the next time the app quits.
- When a check finds a new version and automatic installs are off, a window shows the version and
  its release notes, with **Install Update**, **Remind Me Later** and **Skip This Version**. A check
  that runs while the app is in the background shows it as soon as the app comes to the front.
  *Remind Me Later* brings it back at the next launch.

`ImmichGallery/App/AppUpdater.swift` holds all of it: the Sparkle controller, the launch check, the
menu command and the Settings tab. Sparkle's windows are localized by Sparkle itself.

## How it works

- `Config/Info.plist`: `SUFeedURL` (from the `SPARKLE_FEED_URL` build setting), `SUPublicEDKey`,
  `SUEnableAutomaticChecks` (no "check automatically?" prompt on second launch) and
  `SUEnableInstallerLauncherService` (required by the sandbox).
- `Config/ImmichGallery.entitlements`: the `-spks` / `-spki` mach-lookup exceptions that let the
  sandboxed app talk to Sparkle's installer. The app already has `network.client`, so Sparkle's
  Downloader service is not used.
- The feed is `https://github.com/IGOLz/ImmichGallery/releases/latest/download/appcast.xml`: the
  `appcast.xml` file attached to the **latest** GitHub release. Pre-releases and drafts are never
  "latest", so they are not offered.
- Every update is the release's `.zip`, signed with an EdDSA key. Sparkle refuses an update whose
  signature doesn't match `SUPublicEDKey`, or whose Developer ID team differs from the installed app.
- Sparkle compares `CFBundleVersion` (`CURRENT_PROJECT_VERSION`), so **raise the build number on
  every release**, together with `MARKETING_VERSION`.

## Releasing

```sh
RELEASE_NOTES=path/to/notes.md scripts/release.sh   # build, sign, notarize, appcast.xml
scripts/publish.sh                                   # GitHub release with dmg, zip, appcast, sums
```

`release.sh` signs Sparkle's helpers with the Developer ID (they ship ad-hoc signed), downloads the
published `appcast.xml`, adds the new version with `generate_appcast` and writes it to
`build/release/appcast.xml`. Earlier entries stay in the feed, so if a future version requires a
newer macOS, older Macs are still offered the last version they can run. The Markdown release notes
appear in the update window; keep them about the changes (the update window has no use for
download instructions).

`publish.sh` creates the GitHub release as a draft, uploads everything and only then publishes it,
so installed apps never see a feed whose `.zip` isn't there yet. Use `--prerelease` for a test
release that installed apps must not get.

The Sparkle tools come from the resolved package (`build/SourcePackages/artifacts/sparkle/Sparkle/bin`),
so they always match the framework version in the app.

## The signing key

The private EdDSA key is in the login keychain of the release Mac (item "Private key for signing
Sparkle updates", account `ed25519`). The first time `generate_appcast` uses it, macOS asks for
access: choose **Always Allow**. After a Sparkle update, the new tool may ask once more.

**Back it up**: if it is lost, installed apps can no longer be updated in place, and users have to
download a new version by hand. Export it and keep the file in a password manager, not in the repo:

```sh
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
```

On another Mac, import it with `generate_keys -f sparkle-private-key.txt`. For CI, pass it on
standard input to `generate_appcast --ed-key-file -`.

## Testing an update locally

Building with `SPARKLE_FEED_URL=http://127.0.0.1:8765/appcast.xml` points a build at a local feed
(ATS already allows plain HTTP). To avoid touching your real data, give the test copy another bundle
ID and app group, and remove its widget. The flow tested for 0.3.2: an older Developer ID build with
a local feed found the newer `.zip`, verified its EdDSA signature, installed it in place when quit
(automatic mode) and, in the default mode, showed the update window when brought to the front.
