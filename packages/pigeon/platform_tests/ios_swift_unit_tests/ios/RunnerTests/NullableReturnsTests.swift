// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import XCTest
@testable import Runner

class MockNullableArgHostApi: NullableArgHostApi {
  var didCall: Bool = false
  var x: Int32?
  
  func doit(x: Int32?) -> Int32 {
    didCall = true
    self.x = x
    return x ?? 0
  }
}

class NullableReturnsTests: XCTestCase {
  func testNullableParameterWithFlutterApi() {
    let binaryMessenger = EchoBinaryMessenger(codec: NullableArgFlutterApiCodec.shared)
    binaryMessenger.defaultReturn = 99
    let api = NullableArgFlutterApi(binaryMessenger: binaryMessenger)
    
    let expectation = XCTestExpectation(description: "callback")
    api.doit(x: nil) { result in
      XCTAssertEqual(99, result)
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1.0)
  }
  
  func testNullableParameterWithHostApi() {
    let api = MockNullableArgHostApi()
    let binaryMessenger = MockBinaryMessenger<Int32?>(codec: NullableArgHostApiCodec.shared)
    let channel = "dev.flutter.pigeon.NullableArgHostApi.doit"
    
    NullableArgHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: api)
    XCTAssertNotNil(binaryMessenger.handlers[channel])
    
    let inputEncoded = binaryMessenger.codec.encode([nil])
    
    let expectation = XCTestExpectation(description: "callback")
    binaryMessenger.handlers[channel]?(inputEncoded) { _ in
      expectation.fulfill()
    }
    
    XCTAssertTrue(api.didCall)
    XCTAssertNil(api.x)
    wait(for: [expectation], timeout: 1.0)
    
  }
}
