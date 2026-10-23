import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testOriginalIsReplacedAndBookmarkSurvivesStoreRecreation() throws {
    try withStore { store, url, defaults in
      let initial = Data("PDF inicial".utf8)
      try initial.write(to: url)
      let source = try store.register(url)
      XCTAssertTrue(source.hasPrefix("ios-pdf://"))
      XCTAssertEqual(try store.register(url), source)
      XCTAssertEqual(try store.read(source).bytes, initial)
      let edited = Data("PDF com anotacoes".utf8)
      try store.write(source, bytes: edited, expectedHash: OriginalPdfStore.digest(initial))
      XCTAssertEqual(try Data(contentsOf: url), edited)
      XCTAssertEqual(try OriginalPdfStore(defaults: defaults).read(source).bytes, edited)
      let children = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(),
        includingPropertiesForKeys: nil)
      XCTAssertEqual(children.map { $0.lastPathComponent }, ["livro.pdf"])
    }
  }

  func testExternalChangeIsPreservedInsideCoordinatedWrite() throws {
    try withStore { store, url, _ in
      let initial = Data("PDF inicial".utf8)
      try initial.write(to: url)
      let source = try store.register(url)
      let external = Data("Alteracao feita em outro aplicativo".utf8)
      try external.write(to: url, options: .atomic)
      XCTAssertThrowsError(try store.write(source, bytes: Data("Nao substituir".utf8),
        expectedHash: OriginalPdfStore.digest(initial))) { error in
        XCTAssertEqual((error as? OriginalPdfFailure)?.code, "PDF_CHANGED_EXTERNALLY")
      }
      XCTAssertEqual(try Data(contentsOf: url), external)
    }
  }

  func testMissingAuthorizationDoesNotCreateAnyFile() throws {
    try withStore { store, url, _ in
      XCTAssertThrowsError(try store.read("ios-pdf://unknown"))
      XCTAssertThrowsError(try store.write("ios-pdf://unknown", bytes: Data(), expectedHash: ""))
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
  }

  private func withStore(_ test: (OriginalPdfStore, URL, UserDefaults) throws -> Void) throws {
    let name = "entrelinhas-tests-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: name)!
    defer {
      defaults.removePersistentDomain(forName: name)
      try? FileManager.default.removeItem(at: directory)
    }
    try test(OriginalPdfStore(defaults: defaults), directory.appendingPathComponent("livro.pdf"), defaults)
  }

}
