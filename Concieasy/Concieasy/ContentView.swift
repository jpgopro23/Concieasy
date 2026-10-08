import SwiftUI
import UIKit

enum ConciergeStyle {
    static let navy = Color(red: 16 / 255, green: 41 / 255, blue: 54 / 255)
    static let teal = Color(red: 23 / 255, green: 63 / 255, blue: 81 / 255)
    static let gold = Color(red: 246 / 255, green: 191 / 255, blue: 80 / 255)
    static let background = Color(red: 243 / 255, green: 246 / 255, blue: 248 / 255)
    static let border = Color(red: 220 / 255, green: 229 / 255, blue: 235 / 255)
    static let muted = Color(red: 99 / 255, green: 122 / 255, blue: 136 / 255)
    static let green = Color(red: 35 / 255, green: 99 / 255, blue: 76 / 255)
}

private struct ConfirmedAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let path: String
    let method: String
    let payload: [String: Any]
}

struct ContentView: View {
    @StateObject private var store = OperationsStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: EditorSelection?
    @State private var showingSignIn = false
    @State private var confirmingSignOut = false
    @State private var confirmation: ConfirmedAction?
    @State private var mutationBusy = false
    @State private var filter = "Pending"
    @State private var search = ""
    @State private var showAllHandover = true
    @State private var handoverDate = Date()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heading
                        messages
                        if !store.alerts.isEmpty { frontDeskAlerts }
                        if store.section == .overview { overview }
                        else if store.section == .settings { settings }
                        else { operationList }
                        footer
                    }
                    .padding(20)
                    .frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
                }
                .background(ConciergeStyle.background)
                .refreshable { await store.refresh() }
                .navigationTitle("Concieasy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(ConciergeStyle.navy, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 9) {
                            Image(systemName: "bell.fill").foregroundStyle(ConciergeStyle.gold)
                            Text("Concieasy").font(.headline).tracking(1.5).foregroundStyle(.white)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button { showingSignIn = true } label: { Label("Sign in", systemImage: "person.crop.circle") }
                            Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                            Divider()
                            Button("Sign out", role: .destructive) { confirmingSignOut = true }
                        } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.white) }
                        .accessibilityLabel("Account and workspace actions")
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(ConciergeStyle.teal)
        .preferredColorScheme(.light)
        .sheet(item: $editor) { RequestEditor(store: store, selection: $0) }
        .sheet(isPresented: $showingSignIn) { SignInView(store: store) }
        .confirmationDialog("Sign out of Concieasy?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await store.signOut() } }
        }
        .alert(confirmation?.title ?? "Confirm", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("Cancel", role: .cancel) { confirmation = nil }
            Button("Confirm", role: .destructive) {
                if let action = confirmation { Task { await perform(action) } }
                confirmation = nil
            }
        } message: { Text(confirmation?.message ?? "") }
        .task(id: store.section) { await store.refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                if !mutationBusy && editor == nil && !showingSignIn { await store.refresh() }
            }
        }
        .onChange(of: store.section) { section in
            filter = section == .valet ? "Vehicles" : section == .reservations ? "All" : "Pending"
            search = ""
        }
    }

    private var sidebar: some View {
        List(selection: Binding<OperationsSection?>(get: { store.section }, set: {
            if let section = $0 { store.select(section) }
        })) {
            Section {
                Picker("Workspace", selection: Binding(get: { store.area }, set: { store.switchArea($0) })) {
                    ForEach(OperationsArea.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                .accessibilityIdentifier("workspacePicker")
            }
            Section(store.area == .ays ? "AYS BACK OFFICE" : "CONCIERGE OPERATIONS") {
                ForEach(store.area.sections) { section in
                    NavigationLink(value: section) {
                        HStack {
                            Label(section.title, systemImage: section.symbol)
                            Spacer(minLength: 4)
                            if let count = store.counts?.count(for: section), count > 0 {
                                Text(count > 99 ? "99+" : String(count))
                                    .font(.caption2.bold()).padding(6)
                                    .background(ConciergeStyle.gold, in: Capsule())
                                    .foregroundStyle(ConciergeStyle.navy)
                                    .accessibilityLabel("\(count) requests need action")
                            }
                        }
                    }
                    .accessibilityIdentifier("section-\(section.rawValue)")
                }
            }
            Section {
                Label("Concierge · Auckland", systemImage: "location")
                    .font(.caption).foregroundStyle(ConciergeStyle.muted)
                Button { showingSignIn = true } label: { Label("Sign in", systemImage: "person.crop.circle") }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Workspace")
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.area == .ays ? "AYS · BACK OFFICE" : "CONCIERGE OPERATIONS")
                .font(.caption2.weight(.bold)).tracking(1.8).foregroundStyle(ConciergeStyle.muted)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.section.title).font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(ConciergeStyle.navy).accessibilityAddTraits(.isHeader)
                    Text(store.section.subtitle).font(.subheadline).foregroundStyle(ConciergeStyle.muted)
                }
                Spacer(minLength: 8)
                if store.loading { ProgressView().padding(.top, 8) }
            }
            if let kind = createKind {
                Button { editor = EditorSelection(kind: kind) } label: {
                    Label(createLabel, systemImage: "plus").font(.subheadline.weight(.bold))
                        .padding(.horizontal, 18).padding(.vertical, 13)
                        .foregroundStyle(.white).background(ConciergeStyle.teal, in: RoundedRectangle(cornerRadius: 8))
                }.disabled(mutationBusy || store.requiresSignIn)
                .accessibilityIdentifier("createRequest")
            }
        }
    }

    @ViewBuilder private var messages: some View {
        if let error = store.error {
            VStack(alignment: .leading, spacing: 12) {
                Label(error, systemImage: "exclamationmark.circle").font(.subheadline)
                HStack {
                    if store.requiresSignIn { Button("Sign in") { showingSignIn = true }.bold() }
                    else { Button("Try again") { Task { await store.refresh() } }.bold() }
                    Spacer()
                }
            }
            .padding(16).foregroundStyle(Color(red: 0.6, green: 0.22, blue: 0.16))
            .background(Color(red: 1, green: 0.94, blue: 0.93), in: RoundedRectangle(cornerRadius: 9))
        }
        if let notice = store.notice {
            HStack {
                Label(notice, systemImage: "checkmark.circle")
                Spacer()
                Button { store.notice = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss confirmation")
            }.font(.subheadline).padding(14).foregroundStyle(ConciergeStyle.green)
                .background(ConciergeStyle.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var frontDeskAlerts: some View {
        VStack(spacing: 10) {
            ForEach(store.alerts) { alert in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(ConciergeStyle.gold)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(alert.text("message")).font(.subheadline.bold())
                        if !alert.text("notes").isEmpty { Text(alert.text("notes")).font(.subheadline) }
                        Text(AucklandTime.display(alert.text("created_at"))).font(.caption)
                    }
                    Spacer()
                    Button { Task { await store.dismissAlert(alert) } } label: { Image(systemName: "xmark") }
                        .disabled(mutationBusy).accessibilityLabel("Dismiss front desk alert")
                }.padding(16).foregroundStyle(.white)
                    .background(ConciergeStyle.navy, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 14) {
                ForEach([OperationsSection.luggage, .valet, .jobs]) { section in
                    Button { store.select(section) } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            Label(section.title, systemImage: section.symbol).font(.caption.weight(.semibold))
                            Text(store.counts.map { String($0.count(for: section)) } ?? "—")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("Open work queue").font(.caption)
                        }.foregroundStyle(ConciergeStyle.teal).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ConciergeStyle.border))
                    }.buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("TEAM SESSIONS").font(.caption2.bold()).tracking(1.5).foregroundStyle(ConciergeStyle.muted)
                Text("Signed-in team").font(.title3.bold()).foregroundStyle(ConciergeStyle.navy)
                if store.records.isEmpty {
                    Text(store.error == nil && !store.loading ? "No team sessions to display." : "Team sessions will appear after the workspace loads.")
                        .foregroundStyle(ConciergeStyle.muted).font(.subheadline)
                } else {
                    ForEach(store.records) { user in
                        Label(user.text("display_name"), systemImage: "person.crop.circle.fill")
                            .foregroundStyle(ConciergeStyle.teal)
                    }
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 12) {
                Text("WORK QUEUES").font(.caption2.bold()).tracking(1.5).foregroundStyle(ConciergeStyle.muted)
                Text("Stay on top of today’s requests").font(.title3.bold())
                Text("Open Luggage Log, Valet Log or Miscellaneous tasks from Workspace. New requests and alerts refresh while the app is active.")
                    .font(.subheadline).foregroundStyle(ConciergeStyle.muted)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var operationList: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.section == .ays { aysShortcuts }
            filters
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(ConciergeStyle.muted)
                TextField("Search guests, rooms, tickets or notes", text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ConciergeStyle.border))
            if visibleRecords.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: store.section.symbol).font(.largeTitle).foregroundStyle(ConciergeStyle.muted)
                    Text(store.loading ? "Loading workspace…" : store.error != nil ? "Current data could not be loaded" : "Nothing in this view")
                        .font(.headline).foregroundStyle(ConciergeStyle.navy)
                    Text(store.error != nil ? "Try again to retrieve the latest records." : "Requests matching your selected filters will appear here.")
                        .font(.subheadline).foregroundStyle(ConciergeStyle.muted).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 45)
                    .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .top)], spacing: 16) {
                    ForEach(visibleRecords) { record in recordCard(record) }
                }
            }
        }
    }

    private var aysShortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                metric("Awaiting action", value: store.records.filter { $0.state == .pending || $0.state == .inProgress }.count)
                metric("Ready to archive", value: store.records.filter { $0.state == .completed }.count)
            }
            Text("QUICK REQUESTS").font(.caption2.bold()).tracking(1.5).foregroundStyle(ConciergeStyle.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                ForEach(ReferenceOptions.aysTypes, id: \.self) { type in
                    Button {
                        editor = EditorSelection(kind: .ays, initialType: type)
                    } label: {
                        Label(type == "Other" ? "Assist guest" : type, systemImage: type == "Car down" ? "car" : "plus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(OperationButtonStyle()).disabled(mutationBusy || store.requiresSignIn)
                }
                Button {
                    editor = EditorSelection(kind: .ays, initialType: "Other", initialConciergeType: "Assist at Front Desk")
                } label: {
                    Label("Front desk", systemImage: "bell.badge").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(OperationButtonStyle()).disabled(mutationBusy || store.requiresSignIn)
            }
            if store.records.contains(where: { $0.state == .completed }) {
                Button {
                    confirm("Archive completed tasks?", message: "Completed requests will move to the AYS audit history.", path: "/api/ays", method: "PATCH", body: ["action": "archive-all"])
                } label: { Label("Archive all completed tasks", systemImage: "archivebox") }
                .disabled(mutationBusy)
            }
        }
    }

    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(ConciergeStyle.muted)
            Text(store.error == nil && !store.loading ? String(value) : "—").font(.title.bold()).foregroundStyle(ConciergeStyle.navy)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var filters: some View {
        if store.section == .valet {
            filterChips(["Vehicles", "Requests", "Movements", "Departed"])
            Button { editor = EditorSelection(kind: .vehicleRequest) } label: { Label("Request a vehicle", systemImage: "car") }
        } else if store.section == .ays { filterChips(["Pending", "In progress", "Completed", "Archived"]) }
        else if store.section == .luggage { filterChips(["Pending", "In progress", "Completed"]) }
        else if store.section == .reservations { filterChips(["All", "Dining", "Transport", "Tour", "Other"]) }
        else if store.section == .handover {
            Toggle("Show all dates", isOn: $showAllHandover)
            if !showAllHandover {
                DatePicker("Shift date", selection: $handoverDate, displayedComponents: .date)
                    .environment(\.timeZone, AucklandTime.zone)
            }
        }
    }

    private func filterChips(_ choices: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    Button { filter = choice } label: {
                        Text(choice).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .foregroundStyle(filter == choice ? .white : ConciergeStyle.teal)
                            .background(filter == choice ? ConciergeStyle.teal : .white, in: RoundedRectangle(cornerRadius: 8))
                    }.accessibilityAddTraits(filter == choice ? .isSelected : [])
                }
            }
        }
    }

    private var visibleRecords: [OperationRecord] {
        var records = store.records
        if store.section == .valet {
            switch filter {
            case "Requests": records = store.requests
            case "Movements": records = store.movements
            case "Departed": records = store.departed
            default: break
            }
        } else if store.section == .luggage || store.section == .ays {
            records = records.filter {
                filter == "Pending" ? $0.state == .pending || $0.state == .inProgress : $0.state.rawValue == filter
            }
        } else if store.section == .reservations, filter != "All" {
            records = records.filter { $0.text("activity_type") == filter.lowercased() }
        } else if store.section == .handover, !showAllHandover {
            records = records.filter { $0.text("due_date") == AucklandTime.components(handoverDate).date }
        }
        if !search.isEmpty {
            records = records.filter { record in
                record.fields.values.contains { value in
                    if case let .string(text) = value { return text.localizedCaseInsensitiveContains(search) }
                    return false
                }
            }
        }
        return records
    }

    private func recordCard(_ record: OperationRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text(cardBadge(record)).font(.caption2.bold()).tracking(0.7)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(cardAccent(record).opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(cardAccent(record))
                Spacer(minLength: 4)
                if [.luggage, .ays, .jobs].contains(store.section) {
                    Text(record.state.rawValue).font(.caption.weight(.semibold)).foregroundStyle(ConciergeStyle.muted)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: store.section.symbol).font(.title2)
                    .frame(width: 48, height: 52).foregroundStyle(cardAccent(record))
                    .background(cardAccent(record).opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 7) {
                    Text(record.guest).font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(ConciergeStyle.navy)
                    cardDetails(record)
                }
            }
            if store.section == .storage, record.flag("has_image") {
                StoredItemPhoto(api: store.api, recordID: record.id)
            }
            Divider()
            cardActions(record)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(cardAccent(record).opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ConciergeStyle.border))
        .overlay(alignment: .leading) {
            UnevenAccent(color: cardAccent(record))
        }
    }

    @ViewBuilder private func cardDetails(_ record: OperationRecord) -> some View {
        let room = record.text("room")
        switch store.section {
        case .luggage:
            detail("\(record.integer("bags")) bags · \(record.text("location"))")
            detail("Rooms: \(record.rooms().isEmpty ? "Room not ready" : record.rooms().joined(separator: ", "))")
            if !record.rooms("current_rooms").isEmpty { detail("From: \(record.rooms("current_rooms").joined(separator: ", "))") }
            detail(record.text("instructions")); detail(record.text("comments"))
        case .storage:
            detail("\(record.integer("item_count")) items · \(record.text("storage_location"))")
            detail("Previous room: \(record.text("previous_room")) · Ticket: \(record.text("ticket_number"))")
            detail("Pickup: \(AucklandTime.display(record.text("pickup_at")))")
            detail(record.text("storage_comments"))
        case .valet:
            detail("\(record.text("plate")) · Ticket \(record.text("ticket_number"))")
            if !room.isEmpty { detail("Room \(room)") }
            if filter == "Movements" {
                detail("\(record.text("from_location")) → \(record.text("to_location"))")
                detail("\(record.text("driver")) · \(AucklandTime.display(record.text("moved_at")))")
            } else {
                detail(record.text("location"))
                if !record.text("due_at").isEmpty { detail("Needed: \(AucklandTime.display(record.text("due_at")))") }
                if !record.text("departed_at").isEmpty { detail("Departed: \(AucklandTime.display(record.text("departed_at")))") }
                detail(record.text("notes"))
            }
        case .reservations:
            detail("\(record.integer("pax")) guests\(record.text("room_number").isEmpty ? "" : " · Room " + record.text("room_number"))")
            detail(AucklandTime.display(record.text("reservation_at")))
            detail(record.text("restaurant_name")); detail(record.text("transport_company")); detail(record.text("tour_company"))
            if !record.text("from_location").isEmpty { detail("\(record.text("from_location")) → \(record.text("to_location"))") }
            detail(record.text("comments"))
        case .handover:
            detail(record.text("details")); detail("Due: \(record.text("due_date"))")
        case .ays, .jobs:
            if !room.isEmpty { detail("Room \(room)") }
            detail(record.text("description"))
        default: EmptyView()
        }
        if !record.text("assigned_porter").isEmpty { detail("Assigned: \(record.text("assigned_porter"))") }
        if !record.text("completed_at").isEmpty {
            detail("Completed: \(AucklandTime.display(record.text("completed_at")))")
        } else if !record.text("created_at").isEmpty { detail(AucklandTime.display(record.text("created_at"))) }
    }

    @ViewBuilder private func detail(_ value: String) -> some View {
        if !value.isEmpty { Text(value).font(.subheadline).foregroundStyle(ConciergeStyle.muted).fixedSize(horizontal: false, vertical: true) }
    }

    @ViewBuilder private func cardActions(_ record: OperationRecord) -> some View {
        let actionable = record.state == .pending || record.state == .inProgress
        VStack(alignment: .leading, spacing: 10) {
            switch store.section {
            case .luggage:
                if actionable {
                    HStack { action("Start", icon: "play", kind: .luggageProgress, record: record); action("Complete", icon: "checkmark", kind: .luggageComplete, record: record) }
                    if record.text("stored_bag_id").isEmpty {
                        HStack {
                            action("Edit", icon: "pencil", kind: .luggage, record: record)
                            deleteButton(record, path: "/api/luggage", method: "DELETE", body: ["id": record.id])
                        }
                    }
                } else { detail("Completed by \(record.text("staff"))") }
            case .storage:
                HStack { action("Edit", icon: "pencil", kind: .storage, record: record); action("Collect", icon: "checkmark", kind: .storageCollect, record: record) }
            case .ays:
                if actionable {
                    HStack {
                        action("Edit", icon: "pencil", kind: .ays, record: record)
                        Button {
                            confirm("Dismiss this request?", message: record.guest, path: "/api/ays", method: "PATCH", body: ["id": record.id, "action": "dismiss"])
                        } label: { Label("Dismiss", systemImage: "xmark") }
                        .buttonStyle(OperationButtonStyle()).disabled(mutationBusy)
                    }
                } else if record.state == .completed {
                    Button {
                        Task { await perform(ConfirmedAction(title: "", message: "", path: "/api/ays", method: "PATCH", payload: ["id": record.id, "action": "archive"])) }
                    } label: { Label("Archive", systemImage: "archivebox") }
                    .buttonStyle(OperationButtonStyle()).disabled(mutationBusy)
                } else { detail("Archived: \(AucklandTime.display(record.text("archived_at")))") }
            case .jobs:
                HStack { action("Start", icon: "play", kind: .jobProgress, record: record); action("Complete", icon: "checkmark", kind: .jobComplete, record: record) }
            case .valet:
                if filter == "Vehicles" {
                    HStack { action("Edit", icon: "pencil", kind: .vehicle, record: record); action("Move", icon: "arrow.right", kind: .vehicleMove, record: record) }
                    deleteButton(record, path: "/api/valet", method: "PATCH", body: ["id": record.id, "action": "delete"])
                } else if filter == "Requests" {
                    HStack {
                        if !record.text("ays_job_id").isEmpty { action("Start", icon: "play", kind: .requestProgress, record: record) }
                        action("Record collection", icon: "checkmark", kind: .requestComplete, record: record)
                    }
                    Button {
                        confirm("Dismiss vehicle request?", message: record.guest, path: "/api/valet/requests", method: "PATCH", body: ["id": record.id, "action": "dismiss", "legacy": record.flag("legacy")])
                    } label: { Label("Dismiss request", systemImage: "xmark") }
                    .buttonStyle(OperationButtonStyle()).disabled(mutationBusy)
                }
            case .reservations:
                HStack {
                    action("Edit", icon: "pencil", kind: .reservation, record: record)
                    Button {
                        confirm("Cancel reservation?", message: record.guest, path: "/api/reservations", method: "DELETE", body: ["id": record.id])
                    } label: { Label("Cancel reservation", systemImage: "xmark") }
                    .buttonStyle(OperationButtonStyle()).disabled(mutationBusy)
                }
            case .handover:
                HStack {
                    action("Edit", icon: "pencil", kind: .handover, record: record)
                    let encoded = record.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? record.id
                    deleteButton(record, path: "/api/handover?id=\(encoded)", method: "DELETE", body: [:])
                }
            default: EmptyView()
            }
        }
    }

    private func action(_ title: String, icon: String, kind: EditorKind, record: OperationRecord) -> some View {
        Button { editor = EditorSelection(kind: kind, record: record) } label: { Label(title, systemImage: icon) }
            .buttonStyle(OperationButtonStyle()).disabled(mutationBusy)
    }

    private func deleteButton(_ record: OperationRecord, path: String, method: String, body: [String: Any]) -> some View {
        Button {
            confirm("Delete this entry?", message: "\(record.guest). This action cannot be undone.", path: path, method: method, body: body)
        } label: { Label("Delete", systemImage: "trash") }
        .buttonStyle(OperationButtonStyle()).disabled(mutationBusy)
    }

    private func confirm(_ title: String, message: String, path: String, method: String, body: [String: Any]) {
        confirmation = ConfirmedAction(title: title, message: message, path: path, method: method, payload: body)
    }

    @MainActor private func perform(_ action: ConfirmedAction) async {
        guard !mutationBusy else { return }
        mutationBusy = true; defer { mutationBusy = false }
        do { try await store.mutate(action.path, method: action.method, body: action.payload) }
        catch { store.error = error.localizedDescription }
    }

    private func cardBadge(_ record: OperationRecord) -> String {
        if store.section == .valet { return filter == "Requests" ? "VEHICLE REQUEST" : filter.uppercased() }
        if store.section == .reservations { return record.text("activity_type").uppercased() }
        if store.section == .storage { return "STORED ITEMS" }
        if store.section == .handover { return "HANDOVER / FYI" }
        return record.taskType.uppercased()
    }

    private func cardAccent(_ record: OperationRecord) -> Color {
        if record.state == .completed || record.taskType == "Bags up" { return ConciergeStyle.green }
        if record.taskType == "Bags down" || record.taskType == "Car down" { return Color(red: 0.67, green: 0.47, blue: 0.10) }
        if record.taskType == "Room move" { return Color(red: 0.70, green: 0.28, blue: 0.25) }
        return ConciergeStyle.teal
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Existing Concieasy workspace").font(.title3.bold())
            Text("This app uses the same live backend as the web app. Sign in with your existing Concierge or AYS account. Account permissions are enforced by the server.")
                .font(.subheadline).foregroundStyle(ConciergeStyle.muted)
            Button { showingSignIn = true } label: { Label("Sign in", systemImage: "person.crop.circle") }
                .buttonStyle(OperationButtonStyle())
            Link(destination: URL(string: "/settings", relativeTo: OperationsAPI.baseURL)!) {
                Label("Manage users on the web", systemImage: "arrow.up.right.square")
            }
            Text("User administration and password recovery remain available on the web. Safari may ask you to sign in separately.")
                .font(.caption).foregroundStyle(ConciergeStyle.muted)
            LabeledContent("Time zone", value: "Pacific/Auckland")
            LabeledContent("Workspace", value: store.area.title)
        }.padding(22).background(.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private var createKind: EditorKind? {
        switch store.section {
        case .luggage: return .luggage
        case .storage: return .storage
        case .valet: return .vehicle
        case .reservations: return .reservation
        case .handover: return .handover
        case .ays: return .ays
        default: return nil
        }
    }
    private var createLabel: String {
        switch createKind {
        case .storage: return "Add stored items"
        case .vehicle: return "Check in vehicle"
        case .reservation: return "New reservation"
        case .handover: return "Add handover note"
        default: return "New request"
        }
    }

    private var footer: some View {
        HStack {
            Text("CONCIEASY").font(.caption2.bold()).tracking(1.5)
            Spacer()
            Text("Concierge · Auckland").font(.caption)
        }.foregroundStyle(ConciergeStyle.muted).padding(.top, 20)
    }
}

private struct UnevenAccent: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4).padding(.vertical, 10)
    }
}

struct OperationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 11)
            .foregroundStyle(ConciergeStyle.teal)
            .background(ConciergeStyle.teal.opacity(configuration.isPressed ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct StoredItemPhoto: View {
    let api: OperationsAPI
    let recordID: String
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image = image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 8)) }
            else if failed { Label("Photo could not be loaded", systemImage: "photo").font(.caption).foregroundStyle(ConciergeStyle.muted) }
            else { ProgressView("Loading photo…").font(.caption) }
        }.task(id: recordID) {
            do {
                let data = try await api.request("/api/storage/image?id=\(recordID)")
                guard let image = UIImage(data: data) else { failed = true; return }
                self.image = image
            } catch { failed = true }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
