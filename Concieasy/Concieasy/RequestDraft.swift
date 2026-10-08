import Foundation

enum EditorKind: String, Identifiable {
    case luggage, ays, storage, vehicle, vehicleRequest, reservation, handover
    case luggageProgress, luggageComplete, jobProgress, jobComplete, vehicleMove, requestProgress, requestComplete, storageCollect
    var id: String { rawValue }
    var title: String {
        switch self {
        case .luggage: return "Luggage task"
        case .ays: return "AYS request"
        case .storage: return "Stored items"
        case .vehicle: return "Valet vehicle"
        case .vehicleRequest: return "Request a vehicle"
        case .reservation: return "Reservation"
        case .handover: return "Handover note"
        case .luggageProgress, .jobProgress, .requestProgress: return "Start task"
        case .luggageComplete, .jobComplete: return "Complete task"
        case .vehicleMove: return "Move vehicle"
        case .requestComplete: return "Vehicle collection"
        case .storageCollect: return "Collect stored items"
        }
    }
}

struct EditorSelection: Identifiable {
    let id = UUID()
    let kind: EditorKind
    var record: OperationRecord?
    var initialType: String?
    var initialConciergeType: String?
}

struct RequestDraft {
    let requestID = UUID().uuidString
    var type = "Bags up"
    var guest = ""
    var room = ""
    var newRoom = ""
    var rooms: [String] = []
    var currentRooms: [String] = []
    var bags = 1
    var location = "Front desk"
    var notes = ""
    var details = ""
    var collectKeys = false
    var conciergeType = "Assist Guest"
    var mode = "now"
    var scheduledAt = Date().addingTimeInterval(3600)
    var plate = ""
    var ticket = ""
    var charge = ""
    var hasRequestTime = false
    var porter = ""
    var activityType = "dining"
    var restaurant = ""
    var transport = ""
    var from = ""
    var to = ""
    var tour = ""
    var title = ""
    var outcome = "ready"

    init(kind: EditorKind, record: OperationRecord? = nil) {
        if kind == .vehicle || kind == .vehicleMove { location = "FC" }
        if kind == .storage { location = "Luggage room" }
        guard let record = record else { return }
        guest = record.guest
        if guest == "Guest not provided" || guest == "Name not provided" { guest = "" }
        room = record.text("room")
        if kind == .reservation { room = record.text("room_number") }
        if kind == .storage { room = record.text("previous_room") }
        type = record.taskType.isEmpty ? "Bags up" : record.taskType
        rooms = record.rooms(); currentRooms = record.rooms("current_rooms")
        bags = max(1, record.integer(kind == .storage ? "item_count" : kind == .reservation ? "pax" : "bags"))
        if !record.text("location").isEmpty { location = record.text("location") }
        if kind == .storage { location = record.text("storage_location") }
        notes = record.text("notes")
        if kind == .luggage { notes = record.text("comments") }
        if kind == .storage { notes = record.text("storage_comments") }
        if kind == .reservation { notes = record.text("comments") }
        details = record.text("description")
        collectKeys = record.text("instructions").contains("Yes") || details.contains("Collect keys from reception: Yes")
        if kind == .ays {
            let parts = details.components(separatedBy: " · ")
            newRoom = parts.first(where: { $0.hasPrefix("New room: ") })?.replacingOccurrences(of: "New room: ", with: "") ?? ""
            if let bagPart = parts.first(where: { $0.hasPrefix("Bags: ") }) {
                bags = Int(bagPart.replacingOccurrences(of: "Bags: ", with: "")) ?? 1
            }
            notes = parts.first(where: { $0.hasPrefix("Notes: ") })?.replacingOccurrences(of: "Notes: ", with: "") ?? ""
        }
        ticket = record.text("ticket_number"); plate = record.text("plate")
        if case .number? = record.fields["valet_charge_cents"] {
            charge = String(format: "%.2f", Double(record.integer("valet_charge_cents")) / 100)
        }
        porter = record.text("assigned_porter")
        activityType = record.text("activity_type").isEmpty ? "dining" : record.text("activity_type")
        restaurant = record.text("restaurant_name"); transport = record.text("transport_company")
        from = record.text("from_location"); to = record.text("to_location"); tour = record.text("tour_company")
        title = record.text("title")
        if kind == .handover { details = record.text("details") }
        for key in ["reservation_at", "pickup_at", "due_at", "requested_at"] {
            if let date = AucklandTime.parse(record.text(key)) { scheduledAt = date; break }
        }
        hasRequestTime = !record.text("requested_at").isEmpty
        if kind == .handover, !record.text("due_date").isEmpty {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = AucklandTime.zone
            scheduledAt = formatter.date(from: record.text("due_date")) ?? scheduledAt
        }
    }

    func payload(kind: EditorKind, record: OperationRecord?) throws -> [String: Any] {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw APIError(status: 400, message: message) }
        }
        let guest = guest.trimmingCharacters(in: .whitespacesAndNewlines)
        let room = room.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = AucklandTime.components(scheduledAt)
        let id = record?.id ?? requestID
        switch kind {
        case .luggage:
            try require(type == "Room move" || !guest.isEmpty, "Enter the guest name.")
            try require(bags >= 1 && bags <= 999, "Choose 1–999 bags.")
            if type == "Room move" {
                try require(!rooms.isEmpty && !currentRooms.isEmpty && Set(rooms).isDisjoint(with: currentRooms), "Enter different current and destination rooms.")
            } else {
                try require((type == "Bags up" || !rooms.isEmpty) && rooms.allSatisfy(ReferenceOptions.validRoom), "Choose rooms on floors 3–10, numbered 01–42.")
            }
            return ["id": id, "guest": guest, "bags": bags, "taskType": type, "rooms": rooms,
                    "currentRooms": type == "Room move" ? currentRooms : [], "location": location, "collectKeys": collectKeys]
        case .ays:
            let frontDesk = type == "Other" && conciergeType == "Assist at Front Desk"
            try require(!room.isEmpty || frontDesk, "Enter a room number.")
            try require(!["Bags up", "Bags down", "Bag collection"].contains(type) || (1...10).contains(bags), "Choose 1–10 bags.")
            try require(type != "Room move" || !newRoom.trimmingCharacters(in: .whitespaces).isEmpty, "Enter the new room number.")
            try require(record != nil || type != "Other" || frontDesk || !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Describe the guest assistance.")
            if record != nil {
                var description = [String]()
                if type == "Other" { description.append(details) }
                if type == "Room move" { description += ["New room: \(newRoom)", "Collect keys from reception: \(collectKeys ? "Yes" : "No")"] }
                if ["Bags up", "Bags down", "Bag collection"].contains(type) { description.append("Bags: \(bags)") }
                if type == "Car down", let existingSchedule = record?.text("description").components(separatedBy: " · ").first(where: { $0.hasPrefix("Vehicle needed:") }) { description.append(existingSchedule) }
                if !notes.isEmpty { description.append("Notes: \(notes)") }
                return ["id": id, "action": "edit", "room": room, "jobType": type, "name": guest,
                        "description": description.joined(separator: " · "), "newRoom": newRoom]
            }
            return ["id": id, "room": room, "jobType": type, "name": guest, "bags": bags,
                    "description": details, "conciergeType": conciergeType, "newRoom": newRoom, "collectKeys": collectKeys,
                    "notes": notes, "ticketNumber": ticket, "location": location, "mode": mode, "date": date.date, "time": date.time]
        case .storage:
            try require(!guest.isEmpty || !room.isEmpty, "Enter a guest name or previous room.")
            try require(room.isEmpty || ReferenceOptions.validRoom(room), "Choose a valid previous room.")
            return ["id": id, "name": guest, "previousRoom": room, "itemCount": String(bags), "storageLocation": location,
                    "ticketNumber": ticket, "storageComments": notes, "pickupDate": date.date, "pickupTime": date.time]
        case .vehicle:
            try require(!guest.isEmpty && !plate.trimmingCharacters(in: .whitespaces).isEmpty && !ticket.trimmingCharacters(in: .whitespaces).isEmpty, "Enter the guest, plate and ticket number.")
            var body: [String: Any] = ["id": id, "name": guest, "plate": plate, "ticketNumber": ticket, "location": location,
                                      "room": room, "valetCharge": charge, "notes": notes]
            if record != nil {
                body["action"] = "edit"
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                body["requestedAt"] = hasRequestTime ? formatter.string(from: scheduledAt) : ""
            } else { body["requestTime"] = hasRequestTime ? date.date + "T" + date.time : "" }
            return body
        case .vehicleRequest:
            try require(!guest.isEmpty && ReferenceOptions.validRoom(room) && !ticket.isEmpty, "Enter the reservation name, ticket and valid room.")
            return ["name": guest, "room": room, "ticketNumber": ticket, "mode": mode, "date": date.date, "time": date.time]
        case .reservation:
            try require(!guest.isEmpty && (1...100).contains(bags), "Enter the guest and party size (1–100).")
            try require(room.isEmpty || ReferenceOptions.validRoom(room), "Enter a valid room, or leave it blank.")
            try require(activityType != "dining" || !restaurant.isEmpty, "Enter the restaurant name.")
            try require(activityType != "transport" || (!transport.isEmpty && !from.isEmpty && !to.isEmpty), "Enter the transport company and locations.")
            try require(activityType != "tour" || !tour.isEmpty, "Enter the tour company.")
            return ["id": id, "name": guest, "roomNumber": room, "pax": bags, "activityType": activityType,
                    "date": date.date, "time": date.time, "restaurantName": restaurant, "transportCompany": transport,
                    "fromLocation": from, "toLocation": to, "tourCompany": tour, "comments": notes]
        case .handover:
            try require(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Enter a title.")
            return ["id": id, "title": title, "details": details, "dueDate": date.date]
        case .luggageProgress, .jobProgress, .jobComplete, .requestProgress, .storageCollect, .luggageComplete:
            try require(record != nil && !porter.trimmingCharacters(in: .whitespaces).isEmpty, "Select the staff member.")
            if kind == .luggageComplete {
                try require(!room.isEmpty || !(record?.text("stored_bag_id").isEmpty ?? true), "Enter the completed room number.")
            }
            return ["id": id, "porter": porter, "driver": porter, "staff": porter, "room": room, "comments": notes,
                    "action": kind == .jobComplete ? "complete" : "start"]
        case .vehicleMove, .requestComplete:
            try require(ReferenceOptions.drivers.contains(porter), "Select the driver.")
            return ["id": id, "driver": porter, "location": location, "outcome": outcome, "legacy": record?.flag("legacy") ?? false]
        }
    }

    static func multipart(fields: [String: Any], boundary: String, image: Data? = nil, mimeType: String = "image/jpeg") -> Data {
        var data = Data()
        func append(_ value: String) { data.append(Data(value.utf8)) }
        for key in fields.keys.sorted() {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key]!)\r\n")
        }
        if let image = image {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"stored-item\"\r\nContent-Type: \(mimeType)\r\n\r\n")
            data.append(image); append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return data
    }
}
