//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import XCTest

final class DocumentTestDiscoveryTests: XCTestCase {
  func testIndexBasedDocumentTests() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        1️⃣class MyTests: XCTestCase {
          2️⃣func testMyLibrary() {}3️⃣
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }4️⃣
        """,
        "Tests/MyLibraryTests/MoreTests.swift": """
        import XCTest

        class MoreTests: XCTestCase {
          func testSomeMore() {}
        }
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      build: true
    )

    let (uri, positions) = try project.openDocument("MyTests.swift")
    let tests = try await project.testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(uri: try project.uri(for: "MyTests.swift"), range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testSyntacticDocumentTestsSwift() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import XCTest

      1️⃣class MyTests: XCTestCase {
        2️⃣func testMyLibrary() {}3️⃣
        func testWithAnArgument(x: Int) {}
        func unrelatedFunc() {}
        var testVariable: Int = 0
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testDocumentTestsGetRefinedWithIndexedFile() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class LooksLikeTestCaseButIsNot {}

        1️⃣class MyTests: LooksLikeTestCaseButIsNot {
          2️⃣func testMyLibrary() {}3️⃣
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }4️⃣
        """
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """
    )

    let (uri, positions) = try project.openDocument("MyTests.swift")

    // Syntactically we can't tell that `LooksLikeTestCaseButIsNot` is not a subclass of `XCTestCase`.
    // We are thus conservative and report it as tests.
    let syntacticTests = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      syntacticTests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )

    try await SwiftPMTestProject.build(at: project.scratchDirectory)
    _ = try await project.testClient.send(PollIndexRequest())

    // After indexing, we know that `LooksLikeTestCaseButIsNot` does not inherit from `XCTestCase` and we don't report any tests.
    let indexBasedTests = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(indexBasedTests, [])
  }

  func testSwiftTestingDocumentTests() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testSwiftTestingDocumentTestsInIndexedProject() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      allowBuildFailure: true
    )

    let tests = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(project.fileURI))
    )
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: project.fileURI, range: project.positions["1️⃣"]..<project.positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: project.fileURI, range: project.positions["2️⃣"]..<project.positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testNestedSwiftTestingSuites() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣struct Inner {
          3️⃣@Test
          func oneIsTwo() {
            #expect(1 == 2)
          }4️⃣
        }5️⃣
      }6️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["6️⃣"]),
          children: [
            TestItem(
              id: "MyTests/Inner",
              label: "Inner",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["5️⃣"]),
              children: [
                TestItem(
                  id: "MyTests/Inner/oneIsTwo()",
                  label: "oneIsTwo()",
                  disabled: false,
                  style: TestStyle.swiftTesting,
                  location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"]),
                  children: [],
                  tags: []
                )
              ],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testParameterizedSwiftTestingTest() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test(arguments: [0, 1, 2])
        func numbersAreOne(x: Int) {
          #expect(x == 1)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/numbersAreOne(x:)",
              label: "numbersAreOne(x:)",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testSwiftTestingSuiteWithNoTests() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Suite
      struct MyTests {
      }2️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [],
          tags: []
        )
      ]
    )
  }

  func testSwiftTestingSuiteWithCustomName() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Suite("My tests")
      struct MyTests {
      }2️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "My tests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [],
          tags: []
        )
      ]
    )
  }

  func testSwiftTestingTestWithCustomName() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Test("One is two")
      func oneIsTwo() {
        #expect(1 == 2)
      }2️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "oneIsTwo()",
          label: "One is two",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [],
          tags: []
        )
      ]
    )
  }

  func testDisabledSwiftTestingTest() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Test("One is two", .disabled())
      func oneIsTwo() {
        #expect(1 == 2)
      }2️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "oneIsTwo()",
          label: "One is two",
          disabled: true,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [],
          tags: []
        )
      ]
    )
  }

  func testSwiftTestingTestInDisabledSuite() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Suite(.disabled())
      struct MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: true,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: true,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testHiddenSwiftTestingTest() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    testClient.openDocument(
      """
      import Testing

      @Test("One is two", .hidden)
      func oneIsTwo() {
        #expect(1 == 2)
      }
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      []
    )
  }

  func testSwiftTestingTestWithTags() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Suite(.tags("Suites"))
      struct MyTests {
        2️⃣@Test(.tags("one", "two"))
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: [TestTag(id: "one"), TestTag(id: "two")]
            )
          ],
          tags: [TestTag(id: "Suites")]
        )
      ]
    )
  }

  func testSwiftTestingTestsWithExtension() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣

      5️⃣extension MyTests {
        6️⃣@Test
        func twoIsThree() {
          #expect(2 == 3)
        }7️⃣
      }8️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        ),
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["5️⃣"]..<positions["8️⃣"]),
          children: [
            TestItem(
              id: "MyTests/twoIsThree()",
              label: "twoIsThree()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["6️⃣"]..<positions["7️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        ),
      ]
    )
  }

  func testSwiftTestingExtensionOfTypeInAnotherFile() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣extension MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testSwiftTestingExtensionOfNestedType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      struct MyTests {
        struct Inner {}
      }

      1️⃣extension MyTests.Inner {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests/Inner",
          label: "Inner",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/Inner/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testFullyQualifySwiftTestingTestAttribute() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Testing.Suite("My Tests")
      struct MyTests {
        2️⃣@Testing.Test("one is two")
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "My Tests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "one is two",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }
}
