import SwiftUI
import PhotosUI
import UIKit

struct RequestEditor: View {
    @ObservedObject var store: OperationsStore
    let selection: EditorSelection
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RequestDraft
    @State private var saving = false
    @State private var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var loadingPhoto = false

    init(store: OperationsStore, selection: EditorSelection) {
        self.store = store; self.selection = selection
        var draft = RequestDraft(kind: selection.kind, record: selection.record)
        if let type = selection.initialType { draft.type = type }
        if let type = selection.initialConciergeType { draft.conciergeType = type }
        if selection.kind == .luggageComplete, draft.room.isEmpty {
            draft.room = selection.record?.rooms().joined(separator: ", ") ?? ""
        }
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let record = selection.record {
                    Section {
                        Text(record.guest).font(.headline)
                        if !record.taskType.isEmpty { Text(record.taskType).foregroundStyle(ConciergeStyle.muted) }
                    }
                }
                fields
                if let error = error {
                    Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                }
                Section {
                    Text("Dates and times use Auckland time. Changes are saved to the existing Concieasy workspace.")
                        .font(.caption).foregroundStyle(ConciergeStyle.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ConciergeStyle.background)
            .environment(\.timeZone, AucklandTime.zone)
            .disabled(saving)
            .navigationTitle(selection.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Text("Save").bold() }
                    }.disabled(saving || loadingPhoto)
                }
            }
            .interactiveDismissDisabled(saving)
            .onChange(of: photo) { item in
                guard let item = item else { return }
                loadingPhoto = true
                Task {
                    defer { loadingPhoto = false }
                    do {
                        guard let original = try await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: original), let jpeg = image.jpegData(compressionQuality: 0.8),
                              jpeg.count <= 5 * 1024 * 1024 else {
                            throw APIError(status: 400, message: "Choose an image that can be uploaded as a JPG under 5 MB.")
                        }
                        imageData = jpeg; error = nil
                    } catch { self.error = error.localizedDescription }
                }
            }
        }
        .tint(ConciergeStyle.teal)
    }

    @ViewBuilder private var fields: some View {
        switch selection.kind {
        case .luggage:
            Section("Task details") {
                choices("Task type", value: $draft.type, options: ReferenceOptions.luggageTypes)
                text("Guest name", value: $draft.guest)
                if draft.type != "Room move" { Stepper("Bags: \(draft.bags)", value: $draft.bags, in: 1...999) }
                if draft.type == "Room move" {
                    commaRooms("Current rooms", rooms: $draft.currentRooms)
                    commaRooms("Destination rooms", rooms: $draft.rooms)
                    Toggle("Collect keys from reception", isOn: $draft.collectKeys)
                } else {
                    NavigationLink { RoomSelection(rooms: $draft.rooms) } label: {
                        LabeledContent("Rooms", value: draft.rooms.isEmpty ? "Room not ready" : draft.rooms.joined(separator: ", "))
                    }
                    choices("Bags location", value: $draft.location, options: ReferenceOptions.luggageLocations)
                }
            }
        case .ays:
            Section("Request") {
                choices("Job type", value: $draft.type, options: ReferenceOptions.aysTypes)
                if draft.type == "Other", selection.record == nil {
                    choices("Concierge task", value: $draft.conciergeType, options: ["Assist Guest", "Assist at Front Desk"])
                }
                if draft.type != "Other" || draft.conciergeType != "Assist at Front Desk" || selection.record != nil {
                    text("Room number", value: $draft.room)
                }
                text("Guest name (optional)", value: $draft.guest)
                if ["Bags up", "Bags down", "Bag collection"].contains(draft.type) {
                    Stepper("Bags: \(draft.bags)", value: $draft.bags, in: 1...10)
                }
                if draft.type == "Bags up", selection.record == nil {
                    choices("Bags waiting at", value: $draft.location, options: ReferenceOptions.aysLocations)
                }
                if draft.type == "Room move" {
                    text("New room number", value: $draft.newRoom)
                    Toggle("Collect keys from reception", isOn: $draft.collectKeys)
                }
                if draft.type == "Other", draft.conciergeType != "Assist at Front Desk" || selection.record != nil {
                    text("Task details", value: $draft.details, multiline: true)
                }
                if draft.type == "Car down", selection.record == nil { schedule }
                text("Notes (optional)", value: $draft.notes, multiline: true)
            }
        case .storage:
            Section("Stored items") {
                text("Guest name", value: $draft.guest)
                text("Previous room (optional)", value: $draft.room)
                text("Ticket number (optional)", value: $draft.ticket)
                Stepper("Items: \(draft.bags)", value: $draft.bags, in: 1...999)
                choices("Storage location", value: $draft.location, options: ReferenceOptions.storageLocations)
                DatePicker("Pickup · Auckland", selection: $draft.scheduledAt)
                text("Storage comments", value: $draft.notes, multiline: true)
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(imageData == nil ? "Add item photo" : "Replace item photo", systemImage: "photo")
                }
                if loadingPhoto { ProgressView("Preparing photo…") }
                if let imageData = imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                    Button("Remove selected photo", role: .destructive) { self.imageData = nil; photo = nil }
                }
                if selection.record?.flag("has_image") == true && imageData == nil {
                    Text("The existing photo will be kept.").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .vehicle:
            Section("Vehicle details") {
                text("Reservation name", value: $draft.guest)
                text("Number plate", value: $draft.plate)
                text("Ticket number", value: $draft.ticket)
                text("Room (optional)", value: $draft.room)
                choices("Location", value: $draft.location, options: Array(ReferenceOptions.vehicleLocations.dropLast()))
                text("Valet charge · NZD (optional)", value: $draft.charge).keyboardType(.decimalPad)
                Toggle("Set time vehicle is needed", isOn: $draft.hasRequestTime)
                if draft.hasRequestTime { DatePicker("Needed · Auckland", selection: $draft.scheduledAt) }
                text("Notes", value: $draft.notes, multiline: true)
                if selection.record != nil {
                    Text("Use Move vehicle to record a driver and a movement in the audit trail.").font(.caption)
                }
            }
        case .vehicleRequest:
            Section("Collection request") {
                text("Reservation name", value: $draft.guest)
                text("Room number", value: $draft.room)
                text("Ticket number", value: $draft.ticket)
                schedule
            }
        case .reservation:
            Section("Guest & activity") {
                text("Guest name", value: $draft.guest)
                text("Room (optional)", value: $draft.room)
                Stepper("Party size: \(draft.bags)", value: $draft.bags, in: 1...100)
                choices("Activity", value: $draft.activityType, options: ["dining", "transport", "tour", "other"])
                DatePicker("Reservation · Auckland", selection: $draft.scheduledAt)
                if draft.activityType == "dining" { text("Restaurant", value: $draft.restaurant) }
                if draft.activityType == "transport" {
                    text("Transport company", value: $draft.transport)
                    text("From", value: $draft.from); text("To", value: $draft.to)
                }
                if draft.activityType == "tour" { text("Tour company", value: $draft.tour) }
                text("Comments", value: $draft.notes, multiline: true)
            }
        case .handover:
            Section("Handover / FYI") {
                text("Title", value: $draft.title)
                text("Details", value: $draft.details, multiline: true)
                DatePicker("Due date · Auckland", selection: $draft.scheduledAt, displayedComponents: .date)
            }
        case .luggageProgress, .luggageComplete, .jobProgress, .jobComplete, .storageCollect:
            Section("Staff & completion") {
                choices("Porter", value: $draft.porter, options: [""] + ReferenceOptions.porters)
                text("Staff name", value: $draft.porter)
                if selection.kind == .luggageComplete { text("Completed room(s)", value: $draft.room) }
                if selection.kind == .luggageComplete || selection.kind == .storageCollect {
                    text("Comments", value: $draft.notes, multiline: true)
                }
            }
        case .vehicleMove, .requestProgress, .requestComplete:
            Section("Vehicle action") {
                choices("Driver", value: $draft.porter, options: [""] + ReferenceOptions.drivers)
                if selection.kind == .vehicleMove {
                    choices("Destination", value: $draft.location, options: ReferenceOptions.vehicleLocations)
                }
                if selection.kind == .requestComplete {
                    Picker("Outcome", selection: $draft.outcome) {
                        Text("Ready at forecourt").tag("ready")
                        Text("Gone, be back").tag("returning")
                        Text("Departed").tag("departed")
                    }
                }
            }
        }
    }

    private var schedule: some View {
        Group {
            Picker("When needed", selection: $draft.mode) { Text("Now").tag("now"); Text("Later").tag("later") }
                .pickerStyle(.segmented)
            if draft.mode == "later" { DatePicker("Collection · Auckland", selection: $draft.scheduledAt) }
        }
    }

    private func text(_ label: String, value: Binding<String>, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(ConciergeStyle.muted)
            TextField(label, text: value, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 3...6 : 1...1)
                .accessibilityLabel(label)
        }.padding(.vertical, 4)
    }

    private func choices(_ label: String, value: Binding<String>, options: [String]) -> some View {
        Picker(label, selection: value) {
            // Preserve an existing custom staff/location value instead of silently changing it.
            if !options.contains(value.wrappedValue) { Text(value.wrappedValue).tag(value.wrappedValue) }
            ForEach(options, id: \.self) { Text($0.isEmpty ? "Choose…" : $0).tag($0) }
        }
    }

    private func commaRooms(_ label: String, rooms: Binding<[String]>) -> some View {
        text(label + " (comma separated)", value: Binding(get: { rooms.wrappedValue.joined(separator: ", ") }, set: {
            var seen = Set<String>()
            rooms.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        }))
    }

    @MainActor private func save() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            let payload = try draft.payload(kind: selection.kind, record: selection.record)
            let editing = selection.record != nil
            let path: String
            var method = "POST"
            switch selection.kind {
            case .luggage: path = "/api/luggage"; method = editing ? "PATCH" : "POST"
            case .ays: path = "/api/ays"; method = editing ? "PATCH" : "POST"
            case .vehicle: path = "/api/valet"; method = editing ? "PATCH" : "POST"
            case .vehicleRequest: path = "/api/valet/requests"
            case .reservation: path = "/api/reservations"; method = editing ? "PATCH" : "POST"
            case .handover: path = "/api/handover"; method = editing ? "PATCH" : "POST"
            case .luggageProgress: path = "/api/luggage/progress"
            case .luggageComplete:
                try await store.api.completeLuggage(payload)
                await store.didSave(); dismiss(); return
            case .jobProgress, .jobComplete: path = "/api/ays"; method = "PATCH"
            case .vehicleMove: path = "/api/valet/move"
            case .requestProgress, .requestComplete: path = "/api/valet/requests"; method = "PATCH"
            case .storageCollect: path = "/api/storage/collect"
            case .storage:
                let boundary = "Concieasy-" + UUID().uuidString
                _ = try await store.api.request("/api/storage", method: editing ? "PATCH" : "POST",
                                                multipart: RequestDraft.multipart(fields: payload, boundary: boundary, image: imageData), boundary: boundary)
                await store.didSave(); dismiss(); return
            }
            try await store.mutate(path, method: method, body: payload)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct RoomSelection: View {
    @Binding var rooms: [String]
    var body: some View {
        List {
            Section { Button("Room not ready / clear selection") { rooms = [] } }
            ForEach(3...10, id: \.self) { floor in
                Section("Floor \(floor)") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                        ForEach(1...42, id: \.self) { number in
                            let room = "\(floor)" + String(format: "%02d", number)
                            Button {
                                if rooms.contains(room) { rooms.removeAll { $0 == room } }
                                else { rooms.append(room) }
                            } label: {
                                Text(room).font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(rooms.contains(room) ? ConciergeStyle.teal : ConciergeStyle.background, in: RoundedRectangle(cornerRadius: 7))
                                    .foregroundStyle(rooms.contains(room) ? .white : ConciergeStyle.teal)
                            }.buttonStyle(.plain)
                            .accessibilityAddTraits(rooms.contains(room) ? .isSelected : [])
                        }
                    }.padding(.vertical, 8)
                }
            }
        }.navigationTitle("Choose rooms")
    }
}
