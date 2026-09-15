/// Tracks app switching, independently of payment status. Handles either order
/// of the URL completion callback and the scene becoming active again.
struct ExternalAppHandoff {
    private(set) var isPending = false
    private var opened = false
    private var leftApp = false
    private var isActive = true

    mutating func begin() {
        self = Self()
        isPending = true
    }

    mutating func didOpen(_ success: Bool) -> Bool {
        guard isPending else { return false }
        guard success else { self = Self(); return false }
        opened = true
        return consumeReturn()
    }

    mutating func activityChanged(isActive: Bool) -> Bool {
        guard isPending else { return false }
        self.isActive = isActive
        if !isActive { leftApp = true }
        return consumeReturn()
    }

    private mutating func consumeReturn() -> Bool {
        guard opened && leftApp && isActive else { return false }
        self = Self()
        return true
    }

    mutating func cancel() { self = Self() }
}
