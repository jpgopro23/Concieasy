import Foundation

enum OperationsArea: String, CaseIterable, Identifiable {
    case concierge, ays
    var id: String { rawValue }
    var title: String { self == .ays ? "AYS" : "Concierge" }
    var sections: [OperationsSection] {
        self == .ays ? [.ays, .storage, .settings] : [.overview, .luggage, .storage, .valet, .reservations, .jobs, .handover, .settings]
    }
}

enum OperationsSection: String, CaseIterable, Identifiable {
    case overview, luggage, storage, valet, reservations, jobs, handover, ays, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .luggage: return "Luggage Log"
        case .storage: return "Stored items"
        case .valet: return "Valet Log"
        case .reservations: return "Reservations"
        case .jobs: return "Miscellaneous tasks"
        case .handover: return "Handover / FYI"
        case .ays: return "AYS requests"
        case .settings: return "Advanced settings"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "Your team and today’s work queues."
        case .luggage: return "Bags up, bags down, collection and room moves."
        case .storage: return "Items held by the hotel and scheduled pickups."
        case .valet: return "Vehicles, collection requests and movements."
        case .reservations: return "Dining, transport, tours and guest activities."
        case .jobs: return "Guest assistance and Concierge requests."
        case .handover: return "Notes and tasks for the next shift."
        case .ays: return "Raise requests and track the operations team."
        case .settings: return "Account access and workspace information."
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .luggage: return "suitcase.rolling"
        case .storage: return "archivebox"
        case .valet: return "car"
        case .reservations: return "calendar"
        case .jobs: return "checklist"
        case .handover: return "note.text"
        case .ays: return "clipboard"
        case .settings: return "gearshape"
        }
    }
    var path: String {
        switch self {
        case .overview: return "/"
        case .luggage: return "/luggage"
        case .storage: return "/luggage"
        case .valet: return "/valet"
        case .reservations: return "/reservations"
        case .jobs: return "/jobs"
        case .handover: return "/handover"
        case .ays: return "/ays"
        case .settings: return "/settings"
        }
    }
}

enum TaskState: String, CaseIterable {
    case pending = "Pending", inProgress = "In progress", completed = "Completed", archived = "Archived"
}

// Keep the exported API's field names intact, including JSON-encoded room lists.
// Each list endpoint has a different shape; no client-generated task state is persisted.
struct OperationRecord: Decodable, Identifiable, Equatable {
    let id: String
    let fields: [String: JSONValue]

    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: JSONValue].self)
        guard case let .string(id)? = fields["id"], !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing record ID"))
        }
        self.id = id
    }
    func text(_ key: String) -> String {
        if case let .string(value)? = fields[key] { return value }
        return ""
    }
    func integer(_ key: String) -> Int {
        if case let .number(value)? = fields[key], value.isFinite, value < Double(Int.max), value > Double(Int.min) { return Int(value) }
        return 0
    }
    func flag(_ key: String) -> Bool {
        if case let .bool(value)? = fields[key] { return value }
        return integer(key) == 1
    }
    func rooms(_ key: String = "rooms") -> [String] {
        guard let data = text(key).data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    var state: TaskState {
        if !text("archived_at").isEmpty { return .archived }
        if !text("completed_at").isEmpty || !text("collected_at").isEmpty { return .completed }
        if !text("progress_started_at").isEmpty || !text("started_at").isEmpty { return .inProgress }
        return .pending
    }
    var guest: String {
        for key in ["guest", "name", "guest_name", "title", "display_name"] where !text(key).isEmpty { return text(key) }
        return "Guest not provided"
    }
    var taskType: String {
        !text("task_type").isEmpty ? text("task_type") : text("job_type")
    }
}

indirect enum JSONValue: Decodable, Equatable {
    case string(String), number(Double), bool(Bool), null, array([JSONValue]), object([String: JSONValue])
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
}

struct NotificationCounts: Decodable {
    let luggage: Int
    let valet: Int
    let misc: Int
    func count(for section: OperationsSection) -> Int {
        switch section {
        case .luggage: return luggage
        case .valet: return valet
        case .jobs: return misc
        default: return 0
        }
    }
}

enum AucklandTime {
    static let zone = TimeZone(identifier: "Pacific/Auckland")!
    static func components(_ date: Date) -> (date: String, time: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_NZ")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH:mm"
        return (day, formatter.string(from: date))
    }
    static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    static func display(_ text: String) -> String {
        guard let date = parse(text) else { return text }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_NZ")
        formatter.timeZone = zone
        formatter.dateFormat = "d MMM · h:mm a"
        return formatter.string(from: date)
    }
}

enum ReferenceOptions {
    static let porters = ["Jamie", "Ken", "Leo", "Lori", "Ryota", "Jing", "Lily", "Manan", "Milano", "Shiv"]
    static let drivers = ["Jamie", "Ryota", "Ken", "Leo", "Lori", "Jing", "Manan", "Milano"]
    static let luggageTypes = ["Bags up", "Bags down", "Bag collection", "Room move"]
    static let aysTypes = luggageTypes + ["Car down", "Other"]
    static let luggageLocations = ["Porter bay", "Concierge desk", "Concierge", "Front desk", "Luggage room"]
    static let aysLocations = ["Front desk", "Luggage room", "Unknown"]
    static let storageLocations = ["Luggage room", "Porters bay", "Concierge desk", "Front desk", "HK", "DM Safe", "Trivet Fridge", "Trivet Freezer"]
    static let vehicleLocations = ["FC", "UPSTAIRS", "WILSON CARPARK", "GONE BE BACK", "DEPARTED"]
    static func validRoom(_ room: String) -> Bool {
        room.range(of: "^(?:[3-9]|10)(?:0[1-9]|[1-3][0-9]|4[0-2])$", options: .regularExpression) != nil
    }
}
