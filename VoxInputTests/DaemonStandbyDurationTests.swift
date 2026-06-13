import XCTest
@testable import VoxInput

final class DaemonStandbyDurationTests: XCTestCase {
    func testSeconds() {
        XCTAssertEqual(DaemonStandbyDuration.minutes3.seconds, 180)
        XCTAssertEqual(DaemonStandbyDuration.minutes10.seconds, 600)
        XCTAssertNil(DaemonStandbyDuration.never.seconds)   // never = 永不休眠（保持常驻）
    }
    func testDisplayNamesNonEmpty() {
        for d in DaemonStandbyDuration.allCases {
            XCTAssertFalse(d.displayName.isEmpty)
        }
    }
    func testRawValuesStable() {
        // 持久化兼容：rawValue 不能变
        XCTAssertEqual(DaemonStandbyDuration.minutes3.rawValue, "3m")
        XCTAssertEqual(DaemonStandbyDuration.minutes10.rawValue, "10m")
        XCTAssertEqual(DaemonStandbyDuration.never.rawValue, "never")
    }
}
