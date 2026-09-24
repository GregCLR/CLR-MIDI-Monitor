import XCTest
@testable import MIDICore
final class SourceSelectionTests: XCTestCase {
    func testBulkSelectionPreservesOtherExclusions() {
        var selection = SourceSelection()
        selection.setEnabled(false, for: 99)
        selection.setEnabled(false, for: [1, 2, 3])
        XCTAssertTrue([1, 2, 3, 99].allSatisfy { !selection.isEnabled($0) })
        selection.setEnabled(true, for: [1, 2, 3])
        XCTAssertTrue([1, 2, 3].allSatisfy { selection.isEnabled($0) })
        XCTAssertFalse(selection.isEnabled(99))
        XCTAssertTrue(selection.isEnabled(4))
    }

    func testNewSourcesEnabledWithoutResettingExclusions() {
        var selection = SourceSelection()
        XCTAssertTrue(selection.isEnabled(100))
        selection.setEnabled(false, for: 100)
        XCTAssertFalse(selection.isEnabled(100))
        XCTAssertTrue(selection.isEnabled(200))
        // Reconnecting the same device retains its explicit exclusion.
        XCTAssertFalse(selection.isEnabled(100))
        selection.setEnabled(true, for: 100)
        XCTAssertTrue(selection.isEnabled(100))
    }
}
