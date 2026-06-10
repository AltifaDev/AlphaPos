// ThreadSafetyTests.swift
// AlphaPos — Phase 4: Thread Safety Tests
//
// Tests that shared state access is properly synchronized:
//   - SyncEngine alert times
//   - Concurrent read/write safety

import Foundation

#if TEST_RUNNER
class SyncEngine {
    private static let alertTimesLock = NSLock()
    private static var _lastAlertTimes: [UUID: Date] = [:]
    
    static func getAlertTime(_ key: UUID) -> Date? {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        return _lastAlertTimes[key]
    }
    static func setAlertTime(_ key: UUID, _ value: Date) {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        _lastAlertTimes[key] = value
    }
    static func removeAlertTime(_ key: UUID) {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        _lastAlertTimes.removeValue(forKey: key)
    }
}
#endif

enum ThreadSafetyTests {

    static func runAll() -> [TestResult] {
        [
            test_alertTimesConcurrentAccess(),
            test_alertTimesIsolation()
        ]
    }

    /// Simulates concurrent access to SyncEngine.lastAlertTimes
    private static func test_alertTimesConcurrentAccess() -> TestResult {
        let name = #function
        let iterations = 100
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        
        var accessErrors = 0
        let lock = NSLock()
        
        for i in 0..<iterations {
            group.enter()
            queue.async {
                let uuid = UUID()
                SyncEngine.setAlertTime(uuid, Date())
                let retrieved = SyncEngine.getAlertTime(uuid)
                
                if retrieved == nil {
                    lock.lock()
                    accessErrors += 1
                    lock.unlock()
                }
                
                SyncEngine.removeAlertTime(uuid)
                group.leave()
            }
        }
        
        group.wait()
        
        return accessErrors == 0
            ? .success(name)
            : .failure(name, "\(accessErrors) concurrent access errors detected")
    }

    /// Verifies alert times are isolated between different UUIDs
    private static func test_alertTimesIsolation() -> TestResult {
        let name = #function
        let id1 = UUID()
        let id2 = UUID()
        
        SyncEngine.setAlertTime(id1, Date())
        SyncEngine.setAlertTime(id2, Date().addingTimeInterval(100))
        
        let time1 = SyncEngine.getAlertTime(id1)
        let time2 = SyncEngine.getAlertTime(id2)
        
        SyncEngine.removeAlertTime(id1)
        SyncEngine.removeAlertTime(id2)
        
        guard let t1 = time1, let t2 = time2 else {
            return .failure(name, "Failed to retrieve alert times")
        }
        
        return t1 != t2
            ? .success(name)
            : .failure(name, "Alert times should be different for different UUIDs")
    }
}
