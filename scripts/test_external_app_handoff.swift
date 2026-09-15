// Run with ExternalAppHandoff.swift; exercises lifecycle ordering without UIKit.
@main
enum ExternalAppHandoffChecks {
    static func main() {
        var flow = ExternalAppHandoff()
        assert(!flow.activityChanged(isActive: false))
        assert(!flow.activityChanged(isActive: true))

        flow.begin()
        assert(!flow.didOpen(true)) // Opening alone must not show confirmation.
        assert(!flow.activityChanged(isActive: false))
        assert(flow.activityChanged(isActive: true))
        assert(!flow.isPending)
        assert(!flow.activityChanged(isActive: true)) // Consume only once.

        flow.begin()
        assert(!flow.activityChanged(isActive: false))
        assert(!flow.activityChanged(isActive: true))
        assert(flow.didOpen(true)) // Delayed callback after returning.

        flow.begin()
        assert(!flow.activityChanged(isActive: false))
        assert(!flow.didOpen(false))
        assert(!flow.isPending)
        assert(!flow.activityChanged(isActive: true))

        flow.begin()
        flow.cancel()
        assert(!flow.didOpen(true))
        assert(!flow.activityChanged(isActive: true))
        print("PASS: app return, delayed callback, failure, cancellation, single presentation")
    }
}
