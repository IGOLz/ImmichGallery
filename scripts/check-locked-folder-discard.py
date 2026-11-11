#!/usr/bin/env python3
"""Run the real discarded-unlock cleanup branch from an already-cancelled task, without an app or server."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
source = (repo / "ImmichGallery/Views/Explore/ExploreLockedView.swift").read_text()
start = source.index("guard isCurrent(attempt, services) else", source.index("// Left the Locked Folder, locked, or signed out while unlocking."))
brace = source.index("{", start)
end, depth = brace + 1, 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
branch = source[start:end]
harness = r'''import Foundation
import Synchronization

final class Probe: URLProtocol, @unchecked Sendable {
    static let count = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.count.withLock { $0 += 1 }
        client!.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client!.urlProtocolDidFinishLoading(self)
    }
}
struct Account: Sendable {
    let session: URLSession
    func exploreLock() async throws {
        _ = try await session.data(from: URL(string: "https://fixture.invalid/lock")!)
    }
}
actor Gate {
    var continuation: CheckedContinuation<Void, Never>?
    var arrived: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
@main struct Check {
    static func isCurrent(_ attempt: Int, _ services: Int) -> Bool { false }
    static func uncached<T>(_ account: Account, _ action: (Account) async throws -> T) async throws -> T { try await action(account) }
    static func discard(_ account: Account) async {
        let attempt = 0, services = 0
        __BRANCH__
    }
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Probe.self]
        let account = Account(session: URLSession(configuration: configuration))
        let gate = Gate()
        let task = Task { await gate.wait(); await discard(account) }
        while !(await gate.arrived) { await Task.yield() }
        task.cancel()
        await gate.release()
        await task.value
        for _ in 0..<100 {
            if Probe.count.withLock({ $0 }) == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(Probe.count.withLock { $0 } == 1, "Discarded unlock must send exactly one relock even when its task is cancelled")
        account.session.invalidateAndCancel()
        print("PASS discarded unlock sends relock from a cancelled parent")
    }
}
'''.replace("__BRANCH__", branch)
with tempfile.TemporaryDirectory(prefix="immich-discard-") as directory:
    swift = Path(directory) / "main.swift"
    binary = Path(directory) / "check"
    swift.write_text(harness)
    subprocess.run(["swiftc", "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
