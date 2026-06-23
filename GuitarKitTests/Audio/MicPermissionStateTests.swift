//
//  MicPermissionStateTests.swift
//  GuitarKitTests
//
//  Tests for the pure mapping from Apple's `AVAudioApplication.recordPermission`
//  onto GuitarKit's friendlier `MicPermissionState`. No audio hardware needed —
//  we just feed the raw enum cases and assert the translation.
//

import XCTest
import AVFoundation
@testable import GuitarKit

final class MicPermissionStateTests: XCTestCase {

    func test_undetermined_mapsToUndetermined() {
        XCTAssertEqual(MicPermissionState.from(.undetermined), .undetermined)
    }

    func test_granted_mapsToGranted() {
        XCTAssertEqual(MicPermissionState.from(.granted), .granted)
    }

    func test_denied_mapsToDenied() {
        XCTAssertEqual(MicPermissionState.from(.denied), .denied)
    }

    func test_states_areDistinct() {
        // Sanity: the three cases are not accidentally equal to each other.
        XCTAssertNotEqual(MicPermissionState.undetermined, .granted)
        XCTAssertNotEqual(MicPermissionState.granted, .denied)
        XCTAssertNotEqual(MicPermissionState.denied, .undetermined)
    }
}
