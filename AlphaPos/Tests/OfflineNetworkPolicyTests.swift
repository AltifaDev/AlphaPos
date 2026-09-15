#if canImport(XCTest)
import XCTest

final class OfflineNetworkPolicyTests: XCTestCase {
    private final class FailOnRequestURLProtocol: URLProtocol, @unchecked Sendable {
        static let lock = NSLock()
        static var requestCount = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.requestCount += 1
            Self.lock.unlock()
            XCTFail("Offline-only mode created a URLSession task: \(request.url?.absoluteString ?? "unknown")")
            client?.urlProtocol(self, didFailWithError: NetworkPolicyError.offlineModeProhibited(.cloudData))
        }

        override func stopLoading() {}
    }

    override func tearDown() {
        BackupNetworkAuthorization.shared.end()
        NetworkPolicy.shared.setModeOverrideForTesting(nil)
        super.tearDown()
    }

    func testOfflineOnlyRejectsBeforeURLProtocolSeesRequest() async {
        NetworkPolicy.shared.setModeOverrideForTesting(.offlineOnly)
        FailOnRequestURLProtocol.lock.lock()
        FailOnRequestURLProtocol.requestCount = 0
        FailOnRequestURLProtocol.lock.unlock()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailOnRequestURLProtocol.self]
        let transport = LiveNetworkTransport(session: URLSession(configuration: configuration))
        let request = URLRequest(url: URL(string: "https://example.invalid/offline-test")!)

        do {
            _ = try await transport.data(for: request, purpose: .cloudData)
            XCTFail("Expected offlineModeProhibited")
        } catch let error as NetworkPolicyError {
            XCTAssertEqual(error, .offlineModeProhibited(.cloudData))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        FailOnRequestURLProtocol.lock.lock()
        let requestCount = FailOnRequestURLProtocol.requestCount
        FailOnRequestURLProtocol.lock.unlock()
        XCTAssertEqual(requestCount, 0, "No URLProtocol, DNS, TCP, or HTTP work may start")
    }

    func testAuthenticationRequiredAllowsOnlyLoginAndActivation() {
        NetworkPolicy.shared.setModeOverrideForTesting(.authenticationRequired)
        XCTAssertTrue(NetworkPolicy.shared.allows(.interactiveAuthentication))
        XCTAssertTrue(NetworkPolicy.shared.allows(.licensingActivation))
        XCTAssertFalse(NetworkPolicy.shared.allows(.cloudData))
        XCTAssertFalse(NetworkPolicy.shared.allows(.authRefresh))
        XCTAssertFalse(NetworkPolicy.shared.allows(.realtime))
    }

    func testOfflineRecordsReportCloudDisabledNotPending() {
        NetworkPolicy.shared.setModeOverrideForTesting(.offlineOnly)
        XCTAssertEqual(PersistenceStateResolver.localState, .committed)
        XCTAssertEqual(PersistenceStateResolver.cloudState(isSynced: false), .disabled)
    }

    func testOfflineBackupAuthorizationAllowsOnlyBackupAndRefresh() {
        NetworkPolicy.shared.setModeOverrideForTesting(.offlineOnly)
        BackupNetworkAuthorization.shared.begin(duration: 30)
        XCTAssertTrue(NetworkPolicy.shared.allows(.backupTransfer))
        XCTAssertTrue(NetworkPolicy.shared.allows(.authRefresh))
        XCTAssertTrue(NetworkPolicy.shared.allows(.interactiveAuthentication))
        XCTAssertFalse(NetworkPolicy.shared.allows(.cloudData))
        XCTAssertFalse(NetworkPolicy.shared.allows(.realtime))
        XCTAssertFalse(NetworkPolicy.shared.allows(.remoteMedia))
        BackupNetworkAuthorization.shared.end()
        XCTAssertFalse(NetworkPolicy.shared.allows(.backupTransfer))
    }
}
#endif
