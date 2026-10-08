import Foundation
import Combine

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

final class OperationsAPI {
    static let baseURL = URL(string: "https://luggage-movement-log.tztm49pksy.chatgpt.site")!
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session = session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = .shared
            configuration.httpShouldSetCookies = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 25
            self.session = URLSession(configuration: configuration)
        }
    }

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                 multipart: Data? = nil, boundary: String? = nil) async throws -> Data {
        guard path.hasPrefix("/api/"), let url = URL(string: path, relativeTo: Self.baseURL)?.absoluteURL,
              url.host == Self.baseURL.host, url.scheme == "https" else {
            throw APIError(status: 0, message: "Invalid workspace request.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let multipart = multipart, let boundary = boundary {
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = multipart
        } else if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError(status: 0, message: "No response from Concieasy.") }
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw APIError(status: response.statusCode,
                           message: payload?["error"] as? String ?? "Concieasy returned an error (\(response.statusCode)). Please try again.")
        }
        return data
    }

    func list(_ path: String) async throws -> [OperationRecord] {
        try JSONDecoder().decode([OperationRecord].self, from: await request(path))
    }

    func completeLuggage(_ payload: [String: Any]) async throws {
        guard let id = payload["id"] as? String else { throw APIError(status: 400, message: "Select a task.") }
        struct Start: Decodable { let time: String }
        let response = try await request("/api/start", method: "POST", body: ["id": id])
        var completion = payload
        completion["time"] = try JSONDecoder().decode(Start.self, from: response).time
        _ = try await request("/api/complete", method: "POST", body: completion)
    }
}

@MainActor
final class OperationsStore: ObservableObject {
    let api: OperationsAPI
    @Published var area: OperationsArea = .concierge
    @Published var section: OperationsSection = .overview
    @Published private(set) var records: [OperationRecord] = []
    @Published private(set) var requests: [OperationRecord] = []
    @Published private(set) var movements: [OperationRecord] = []
    @Published private(set) var departed: [OperationRecord] = []
    @Published private(set) var alerts: [OperationRecord] = []
    @Published private(set) var counts: NotificationCounts?
    @Published private(set) var loading = false
    @Published private(set) var requiresSignIn = false
    @Published var error: String?
    @Published var notice: String?
    private var generation = UUID()

    init(api: OperationsAPI = OperationsAPI()) { self.api = api }

    func select(_ section: OperationsSection) {
        guard self.section != section else { return }
        generation = UUID()
        self.section = section
        records = []; requests = []; movements = []; departed = []
        error = nil; notice = nil; loading = false
    }

    func switchArea(_ area: OperationsArea) {
        guard self.area != area else { return }
        self.area = area
        alerts = []; counts = nil
        select(area == .ays ? .ays : .overview)
    }

    func refresh() async {
        guard !loading else { return }
        let token = generation, selected = section, selectedArea = area
        loading = true
        defer { if token == generation { loading = false } }
        do {
            var result: [OperationRecord] = [], vehicleRequests: [OperationRecord] = []
            var history: [OperationRecord] = [], departureRecords: [OperationRecord] = []
            switch selected {
            case .overview:
                struct Presence: Decodable { let users: [OperationRecord] }
                result = try JSONDecoder().decode(Presence.self, from: await api.request("/api/presence")).users
            case .luggage: result = try await api.list("/api/luggage")
            case .storage: result = try await api.list("/api/storage")
            case .valet:
                result = try await api.list("/api/valet")
                vehicleRequests = try await api.list("/api/valet/requests")
                history = try await api.list("/api/valet/movements")
                struct Departures: Decodable { let vehicles: [OperationRecord] }
                departureRecords = try JSONDecoder().decode(Departures.self, from: await api.request("/api/valet/departed")).vehicles
            case .reservations: result = try await api.list("/api/reservations")
            case .jobs: result = try await api.list("/api/ays?type=Other")
            case .handover: result = try await api.list("/api/handover")
            case .ays: result = try await api.list("/api/ays?view=backoffice")
            case .settings: break
            }
            guard token == generation else { return }
            records = result; requests = vehicleRequests; movements = history; departed = departureRecords
            error = nil; requiresSignIn = false
            if selectedArea == .concierge {
                // Secondary alerts must not hide successfully loaded task lists on failure.
                do {
                    let newCounts = try JSONDecoder().decode(NotificationCounts.self, from: await api.request("/api/notifications"))
                    let newAlerts = try await api.list("/api/front-desk")
                    guard token == generation else { return }
                    counts = newCounts; alerts = newAlerts
                } catch {
                    guard token == generation else { return }
                    counts = nil
                    self.error = "Tasks loaded, but alerts could not be refreshed. \(error.localizedDescription)"
                    if (error as? APIError)?.status == 401 { requiresSignIn = true; clearPrivateData() }
                }
            }
        } catch {
            guard token == generation else { return }
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { return }
            self.error = error.localizedDescription
            requiresSignIn = (error as? APIError)?.status == 401
            if requiresSignIn { clearPrivateData() }
        }
    }

    func signIn(username: String, password: String) async throws {
        _ = try await api.request("/api/auth", method: "POST", body: ["action": area == .ays ? "ays-login" : "login", "email": username, "password": password])
        generation = UUID(); loading = false
        clearPrivateData()
        requiresSignIn = false
        error = nil
        await refresh()
    }

    func signOut() async {
        do {
            _ = try await api.request("/api/auth", method: "POST", body: ["action": "logout"])
            generation = UUID(); loading = false; clearPrivateData()
            requiresSignIn = true
        } catch { self.error = error.localizedDescription }
    }

    func mutate(_ path: String, method: String = "POST", body: [String: Any]) async throws {
        _ = try await api.request(path, method: method, body: body)
        await didSave()
    }

    func didSave() async {
        notice = "Saved to Concieasy."
        // Invalidate an in-flight poll so a response from before the mutation cannot overwrite the new state.
        generation = UUID(); loading = false
        await refresh()
    }

    func dismissAlert(_ record: OperationRecord) async {
        do { try await mutate("/api/front-desk", method: "PATCH", body: ["id": record.id]) }
        catch { self.error = error.localizedDescription }
    }

    private func clearPrivateData() {
        records = []; requests = []; movements = []; departed = []; alerts = []; counts = nil
    }
}
