import XCTest
@testable import Concieasy

final class ConcieasyTests: XCTestCase {
    private func record(_ json: String) throws -> OperationRecord {
        try JSONDecoder().decode(OperationRecord.self, from: Data(json.utf8))
    }

    func testTaskStateComesFromServerTimestamps() throws {
        XCTAssertEqual(try record(#"{"id":"1","completed_at":null}"#).state, .pending)
        XCTAssertEqual(try record(#"{"id":"1","progress_started_at":"2026-10-08T00:00:00Z"}"#).state, .inProgress)
        XCTAssertEqual(try record(#"{"id":"1","started_at":"2026-10-08T00:00:00Z","completed_at":"2026-10-08T00:01:00Z"}"#).state, .completed)
        XCTAssertEqual(try record(#"{"id":"1","completed_at":"2026-10-08T00:01:00Z","archived_at":"2026-10-08T00:02:00Z"}"#).state, .archived)
    }

    func testLuggageRoomListsDecodeTheExportedWireFormat() throws {
        let task = try record(#"{"id":"1","rooms":"[\"301\",\"1042\"]","current_rooms":"[\"401\"]","bags":2}"#)
        XCTAssertEqual(task.rooms(), ["301", "1042"])
        XCTAssertEqual(task.rooms("current_rooms"), ["401"])
        XCTAssertEqual(task.integer("bags"), 2)
    }

    func testRoomValidationMatchesHotelFloors() {
        for room in ["301", "342", "901", "1001", "1042"] { XCTAssertTrue(ReferenceOptions.validRoom(room), room) }
        for room in ["201", "300", "343", "1043", "1101", "301x", " 301"] { XCTAssertFalse(ReferenceOptions.validRoom(room), room) }
    }

    func testRoomMoveRejectsOverlappingRooms() throws {
        var draft = RequestDraft(kind: .luggage)
        draft.type = "Room move"; draft.currentRooms = ["301"]; draft.rooms = ["301"]
        XCTAssertThrowsError(try draft.payload(kind: .luggage, record: nil))
        draft.rooms = ["401"]
        let payload = try draft.payload(kind: .luggage, record: nil)
        XCTAssertEqual(payload["currentRooms"] as? [String], ["301"])
        XCTAssertEqual(payload["rooms"] as? [String], ["401"])
    }

    func testBagsUpAllowsRoomNotReadyButCollectionRequiresARoom() throws {
        var draft = RequestDraft(kind: .luggage)
        draft.guest = "Guest"
        XCTAssertNoThrow(try draft.payload(kind: .luggage, record: nil))
        draft.type = "Bag collection"
        XCTAssertThrowsError(try draft.payload(kind: .luggage, record: nil))
    }

    func testAysSubmissionKeepsItsIdOnRetry() throws {
        var draft = RequestDraft(kind: .ays)
        draft.room = "301"
        let first = try draft.payload(kind: .ays, record: nil)
        let retry = try draft.payload(kind: .ays, record: nil)
        XCTAssertEqual(first["id"] as? String, retry["id"] as? String)
        XCTAssertNotNil(UUID(uuidString: first["id"] as! String))
    }

    func testFrontDeskAlertDoesNotRequireARoom() throws {
        var draft = RequestDraft(kind: .ays)
        draft.type = "Other"; draft.conciergeType = "Assist at Front Desk"; draft.notes = "Reception needs help"
        let payload = try draft.payload(kind: .ays, record: nil)
        XCTAssertEqual(payload["conciergeType"] as? String, "Assist at Front Desk")
        XCTAssertEqual(payload["notes"] as? String, "Reception needs help")
    }

    func testAysBagLimitMatchesBackend() {
        var draft = RequestDraft(kind: .ays)
        draft.room = "301"; draft.bags = 11
        XCTAssertThrowsError(try draft.payload(kind: .ays, record: nil))
    }

    func testVehicleRequestRequiresTicketAndValidRoom() {
        var draft = RequestDraft(kind: .vehicleRequest)
        draft.guest = "Guest"; draft.room = "301"
        XCTAssertThrowsError(try draft.payload(kind: .vehicleRequest, record: nil))
        draft.ticket = "V123"
        XCTAssertNoThrow(try draft.payload(kind: .vehicleRequest, record: nil))
    }

    func testVehicleEditPreservesScheduledCollectionAndCharge() throws {
        let vehicle = try record(#"{"id":"1","name":"Guest","plate":"ABC123","ticket_number":"V123","location":"FC","valet_charge_cents":4250,"requested_at":"2026-10-08T01:30:00.000Z"}"#)
        let draft = RequestDraft(kind: .vehicle, record: vehicle)
        let payload = try draft.payload(kind: .vehicle, record: vehicle)
        XCTAssertEqual(payload["valetCharge"] as? String, "42.50")
        XCTAssertEqual(payload["requestedAt"] as? String, "2026-10-08T01:30:00.000Z")
    }

    func testReservationRequiresActivitySpecificDetails() {
        var draft = RequestDraft(kind: .reservation)
        draft.guest = "Guest"; draft.activityType = "transport"
        XCTAssertThrowsError(try draft.payload(kind: .reservation, record: nil))
        draft.transport = "Taxi"; draft.from = "Hotel"; draft.to = "Airport"
        XCTAssertNoThrow(try draft.payload(kind: .reservation, record: nil))
    }

    func testAucklandSchedulingIsIndependentOfDeviceTimeZone() throws {
        let date = try XCTUnwrap(AucklandTime.parse("2026-10-07T23:00:00.000Z"))
        let components = AucklandTime.components(date)
        XCTAssertEqual(components.date, "2026-10-08")
        XCTAssertEqual(components.time, "12:00")
        let winter = try XCTUnwrap(AucklandTime.parse("2026-07-01T00:00:00.000Z"))
        XCTAssertEqual(AucklandTime.components(winter).time, "12:00")
    }

    func testStorageMultipartIncludesImageAndClosingBoundary() throws {
        let data = RequestDraft.multipart(fields: ["name": "Guest", "itemCount": "2"], boundary: "test-boundary", image: Data([1, 2, 3]))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"itemCount\"\r\n\r\n2\r\n"))
        XCTAssertTrue(text.contains("name=\"image\"; filename=\"stored-item\""))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(text.hasSuffix("--test-boundary--\r\n"))
    }

    func testCompletionUsesServerIssuedTimestamp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOperationsProtocol.self]
        let api = OperationsAPI(session: URLSession(configuration: config))
        var paths = [String]()
        MockOperationsProtocol.handler = { request in
            let path = request.url!.path
            paths.append(path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), OperationsAPI.baseURL.absoluteString)
            let json = try JSONSerialization.jsonObject(with: request.httpBody ?? request.bodyStreamData()) as! [String: Any]
            XCTAssertEqual(json["id"] as? String, "task-1")
            if path == "/api/start" { return (200, Data(#"{"time":"server-completion-token"}"#.utf8)) }
            XCTAssertEqual(json["time"] as? String, "server-completion-token")
            XCTAssertEqual(json["staff"] as? String, "Jamie")
            return (200, Data(#"{"ok":true}"#.utf8))
        }
        defer { MockOperationsProtocol.handler = nil }
        try await api.completeLuggage(["id": "task-1", "staff": "Jamie", "room": "301", "comments": ""])
        XCTAssertEqual(paths, ["/api/start", "/api/complete"])
    }

    func testApiPreservesConflictErrorInsteadOfReportingSuccess() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOperationsProtocol.self]
        let api = OperationsAPI(session: URLSession(configuration: config))
        MockOperationsProtocol.handler = { _ in (409, Data(#"{"error":"Task changed. Refresh."}"#.utf8)) }
        defer { MockOperationsProtocol.handler = nil }
        do {
            _ = try await api.request("/api/complete", method: "POST", body: ["id": "task"])
            XCTFail("A conflict must not be accepted as success.")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 409)
            XCTAssertEqual(error.message, "Task changed. Refresh.")
        }
    }
}

private final class MockOperationsProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private extension URLRequest {
    func bodyStreamData() -> Data {
        guard let stream = httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
