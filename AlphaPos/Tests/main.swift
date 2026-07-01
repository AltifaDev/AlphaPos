import Foundation

#if TEST_RUNNER
let allPassed = TestRunner.runAll()
exit(allPassed ? 0 : 1)
#endif
