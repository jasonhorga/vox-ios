import XCTest
@testable import VoxInput

final class RecordButtonPhaseTests: XCTestCase {
    func testRecordingStateMapping() {
        XCTAssertEqual(RecordButtonPhase(.idle), .idle)
        XCTAssertEqual(RecordButtonPhase(.recording), .recording)
        XCTAssertEqual(RecordButtonPhase(.processing), .processing)
    }
}
