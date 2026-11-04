import Foundation

struct AdminUser: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let email: String
    let isAdmin: Bool
    var deletedAt: String?
    var status: String?
    var quotaSizeInBytes: Int64?
    var quotaUsageInBytes: Int64?
    var shouldChangePassword: Bool?
    var isDeleted: Bool { deletedAt != nil || status == "deleted" || status == "removing" }
}

struct AdminUserInput: Encodable {
    var name: String
    var email: String
    var isAdmin: Bool
    var password: String?
    var shouldChangePassword: Bool
    var quotaSizeInBytes: Int64?

    // A null quota removes the limit; omitting it would leave the previous quota unchanged.
    enum CodingKeys: String, CodingKey { case name, email, isAdmin, password, shouldChangePassword, quotaSizeInBytes }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(email, forKey: .email)
        try c.encode(isAdmin, forKey: .isAdmin)
        try c.encodeIfPresent(password, forKey: .password)
        try c.encode(shouldChangePassword, forKey: .shouldChangePassword)
        try c.encode(quotaSizeInBytes, forKey: .quotaSizeInBytes)
    }
}

struct AdminLibrary: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let ownerId: String
    let assetCount: Int
    let importPaths: [String]
    let exclusionPatterns: [String]
}

struct AdminLibraryInput: Encodable {
    var name: String
    var ownerId: String?
    var importPaths: [String]
    var exclusionPatterns: [String]
}

struct AdminQueue: Decodable, Identifiable, Sendable {
    let name: String
    let isPaused: Bool
    let statistics: Statistics
    var id: String { name }
    struct Statistics: Decodable, Sendable {
        let active: Int
        let completed: Int
        let delayed: Int
        let failed: Int
        let paused: Int
        let waiting: Int
    }
    // Same order and manageable queues as the v3.3.5 web QueuePanel.
    static let managedNames = ["thumbnailGeneration", "metadataExtraction", "library", "sidecar",
                               "smartSearch", "duplicateDetection", "faceDetection", "facialRecognition",
                               "ocr", "videoConversion", "storageTemplateMigration", "migration"]
    var title: String {
        ["thumbnailGeneration": "Generate Thumbnails", "metadataExtraction": "Extract Metadata",
         "library": "External Libraries", "sidecar": "Sidecar Metadata", "smartSearch": "Smart Search",
         "duplicateDetection": "Duplicate Detection", "faceDetection": "Face Detection",
         "facialRecognition": "Facial Recognition", "ocr": "OCR", "videoConversion": "Transcode Videos",
         "storageTemplateMigration": "Storage Template Migration", "migration": "Migration"][name] ?? name
    }
    var startTitle: String {
        switch name {
        case "library": "Rescan Libraries"
        case "sidecar": "Discover Sidecars"
        case "migration", "storageTemplateMigration": "Start"
        default: "Start Missing Jobs"
        }
    }
    var allTitle: String {
        switch name {
        case "sidecar": "Sync Sidecars…"
        case "faceDetection", "facialRecognition": "Reset Faces…"
        default: "Process All Assets…"
        }
    }
    var canStart: Bool { Self.managedNames.contains(name) }
    var canStartAll: Bool {
        canStart && !["storageTemplateMigration", "migration", "library"].contains(name)
    }
}

/// Configuration is intentionally read-only. Preserve unknown fields across server versions.
indirect enum AdminValue: Codable, Sendable {
    case object([String: AdminValue]), array([AdminValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: AdminValue].self) { self = .object(v) }
        else { self = .array(try c.decode([AdminValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> AdminValue? {
        if case .object(let fields) = self { fields[key] } else { nil }
    }
    var boolValue: Bool { if case .bool(let value) = self { value } else { false } }
    func display(forKey key: String) -> String {
        if case .string = self, ["password", "clientSecret", "apiKey", "secret"].contains(key) { return "Hidden" }
        if case .number(let bytes) = self,
           (key.hasPrefix("usage") || key.hasSuffix("Raw")), bytes.isFinite,
           bytes >= Double(Int64.min), bytes < Double(Int64.max) {
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        return display
    }

    var display: String {
        switch self {
        case .object, .array: ""
        case .string(let v): v.isEmpty ? "Empty" : v
        case .number(let v): v.formatted(.number.grouping(.never))
        case .bool(let v): v ? "Yes" : "No"
        case .null: "Not set"
        }
    }
}

// Immich quotas are bytes on the wire and GiB in the editor.
enum AdminQuota {
    static let bytesPerGiB = 1_073_741_824.0
    static func bytes(from text: String) -> Int64? {
        guard let gib = Double(text), gib.isFinite, gib >= 0,
              gib * bytesPerGiB <= 9_007_199_254_740_991 else { return nil }
        return Int64(gib * bytesPerGiB)
    }
    static func text(from bytes: Int64?) -> String {
        bytes.map { String(Double($0) / bytesPerGiB) } ?? ""
    }
}
