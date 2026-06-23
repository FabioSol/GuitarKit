//
//  SmokeTests.swift
//  GuitarKitTests
//
//  The very first test in the project. Its only job is to prove that:
//    1. the `GuitarKitTests` target compiles,
//    2. it links against the app target (the "host"),
//    3. the test runner can discover and execute a test, and
//    4. assertions work.
//
//  Future domain slices (music model, tuning state machine, harmony,
//  fretboard engine, metronome scheduling, pitch detector) will drop their
//  own `XCTestCase` files into this same `GuitarKitTests/` folder. Because
//  the folder is wired into Xcode as a "file-system-synchronized group",
//  any `.swift` file added here is picked up automatically — no need to edit
//  `project.pbxproj` again.
//

// `XCTest` is Apple's built-in unit-testing framework. Importing it gives us
// `XCTestCase` (the base class every test class inherits from) and the family
// of `XCTAssert...` functions used to make assertions.
import XCTest

// `@testable import` pulls in the app module *with access to its internal
// symbols* (not just `public` ones). We don't use any app symbols yet, but
// importing it here verifies the test target is correctly linked to the app
// and gives future tests immediate access to the app's types.
@testable import GuitarKit

// A test case is a `class` (reference type) that subclasses `XCTestCase`.
// The test runner instantiates it and runs every method whose name starts
// with `test`. We mark it `final` because there's no reason to subclass it,
// and `final` lets the compiler optimize a little and signals intent.
final class SmokeTests: XCTestCase {

    // Any method named `test...` with no parameters is auto-discovered and
    // executed by the runner. This one simply asserts a truth, proving the
    // whole test pipeline is alive.
    func testTestTargetRunsAndCanAssert() {
        // `XCTAssertTrue` fails the test if its argument is `false`.
        // The trailing string is the message shown on failure.
        XCTAssertTrue(true, "If this fails, the universe is broken.")

        // A second, slightly less trivial assertion: basic arithmetic works,
        // which confirms real code is executing (not just being skipped).
        XCTAssertEqual(2 + 2, 4, "Math should still work inside a test.")
    }
}
