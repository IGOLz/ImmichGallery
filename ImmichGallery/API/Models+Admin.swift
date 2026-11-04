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
    // Only these queues support manually scheduling assets in the official web client.
    var canStart: Bool {
        ["thumbnailGeneration", "metadataExtraction", "videoConversion", "faceDetection",
         "facialRecognition", "smartSearch", "duplicateDetection", "storageTemplateMigration",
         "migration", "sidecar", "library", "ocr"].contains(name)
    }
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
