// Run from the repository root:
// swiftc -parse-as-library ImmichGallery/API/Models.swift ImmichGallery/API/ImmichClient.swift \
//   ImmichGallery/API/ImmichClient+MacIntegration.swift scripts/verify-mac-integration.swift \
//   -o build/verify-mac-integration && build/verify-mac-integration
// Read-only demo checks. The newly created login session is logged out on success.
import Foundation
@main struct Live {
 static func main() async throws {
  let base = URL(string: "https://demo.immich.app")!
  let anonymous = ImmichClient(serverURL: base, apiURL: base.appendingPathComponent("api"), credential: nil)
  let login = try await anonymous.login(email: "demo@immich.app", password: "demo")
  let client = anonymous.with(credential: .accessToken(login.accessToken))
  let version = try await client.serverVersion()
  let albums = try await client.albums()
  let results = try await client.metadataSearch(page: .init(page: 1), size: 1)
  guard let first = results.items.first else { fatalError("No demo assets") }
  let detail = try await client.asset(first.id)
  let file = try await client.macIntegrationOriginal(first.id)
  assert(FileManager.default.fileExists(atPath: file.path))
  print("Decoded server \(version), \(albums.count) albums, search and asset DTOs; downloaded \(detail.originalFileName), \((try FileManager.default.attributesOfItem(atPath: file.path)[.size]) ?? 0) bytes")
  try FileManager.default.removeItem(at: file.deletingLastPathComponent())
  let smart = try await client.smartSearch("mountains", page: 1, size: 1)
  print("Decoded smart search: \(smart.items.count) result")
  try await client.logout()
 }
}
