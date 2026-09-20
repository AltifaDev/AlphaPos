import Foundation

enum BranchSyncPolicyTests {
    static func runAll() -> [TestResult] {
        [
            expectUpload(localIsSynced: false, existsRemotely: false, expected: true),
            expectUpload(localIsSynced: false, existsRemotely: true, expected: true),
            expectUpload(localIsSynced: true, existsRemotely: true, expected: false),
            expectUpload(localIsSynced: true, existsRemotely: false, expected: false),
            expectBootstrapPlaceholder(hasDependentRecords: false, expected: true),
            expectBootstrapPlaceholder(hasDependentRecords: true, expected: false)
        ]
    }

    private static func expectUpload(
        localIsSynced: Bool,
        existsRemotely: Bool,
        expected: Bool
    ) -> TestResult {
        let actual = BranchParentSyncPolicy.requiresUpload(
            localIsSynced: localIsSynced,
            existsRemotely: existsRemotely
        )
        let name = "\(#function)_synced_\(localIsSynced)_remote_\(existsRemotely)"
        return actual == expected
            ? .success(name)
            : .failure(name, "Expected upload=\(expected), got \(actual)")
    }


    private static func expectBootstrapPlaceholder(
        hasDependentRecords: Bool,
        expected: Bool
    ) -> TestResult {
        let actual = BranchParentSyncPolicy.isBootstrapPlaceholder(
            name: " main branch ",
            location: "Headquarters",
            phone: nil,
            hasDependentRecords: hasDependentRecords,
            matchingRemoteNameExists: true
        )
        let name = "\(#function)_dependent_\(hasDependentRecords)"
        return actual == expected
            ? .success(name)
            : .failure(name, "Expected placeholder=\(expected), got \(actual)")
    }
}
