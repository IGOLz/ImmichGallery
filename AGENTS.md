# Agent notes

- The app supports macOS 15 Sequoia and later (built with the latest SDK): when you add or change a feature, keep it working on macOS 15 from your own API knowledge, without VM testing. Wrap macOS 26+ APIs in `if #available(macOS 26, *)` with a fallback (helpers in `ImmichGallery/Views/MacIntegration/OSCompatibility.swift`) and avoid the SwiftUI pitfalls listed in `docs/MacIntegration.md`.
