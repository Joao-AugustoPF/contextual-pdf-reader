import CryptoKit
import Flutter
import Foundation
import UIKit
import UniformTypeIdentifiers

struct OriginalPdfFailure: LocalizedError {
  let code: String
  let message: String
  var errorDescription: String? { message }
}

// Bookmarks persistem a autorização do seletor, não caminhos privados de outros
// apps. Cada leitura/escrita adquire e libera o escopo e coordena o provedor.
final class OriginalPdfStore {
  private let defaults: UserDefaults
  private let key = "entrelinhas.original-pdf.bookmarks.v1"

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  private var bookmarks: [String: Data] {
    get { defaults.dictionary(forKey: key) as? [String: Data] ?? [:] }
    set { defaults.set(newValue, forKey: key) }
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func authorized<T>(_ url: URL, _ action: () throws -> T) throws -> T {
    let scoped = url.startAccessingSecurityScopedResource()
    let container = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/"
    guard scoped || url.resolvingSymlinksInPath().path.hasPrefix(container) else {
      throw OriginalPdfFailure(code: "PDF_ACCESS_LOST",
        message: "A autorização do PDF expirou. Selecione o original novamente em Arquivos.")
    }
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try action()
  }

  private func resolve(_ source: String) throws -> URL {
    guard source.hasPrefix("ios-pdf://"), let data = bookmarks[source] else {
      throw OriginalPdfFailure(code: "PDF_ACCESS_LOST",
        message: "Original indisponível. Selecione o PDF novamente em Arquivos.")
    }
    var stale = false
    let url = try URL(resolvingBookmarkData: data, options: [],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    if stale {
      try authorized(url) { try remember(url, source: source) }
    }
    return url
  }

  private func remember(_ url: URL, source: String) throws {
    let data = try url.bookmarkData(options: .minimalBookmark,
      includingResourceValuesForKeys: nil, relativeTo: nil)
    var saved = bookmarks
    saved[source] = data
    bookmarks = saved
  }

  func register(_ url: URL) throws -> String {
    try authorized(url) {
      // Reabrir a mesma URL conserva o documento e suas anotações no banco.
      let existing = bookmarks.first { _, data in
        var stale = false
        let previous = try? URL(resolvingBookmarkData: data, options: [],
          relativeTo: nil, bookmarkDataIsStale: &stale)
        return previous?.standardizedFileURL == url.standardizedFileURL
      }?.key
      let source = existing ?? "ios-pdf://\(UUID().uuidString)"
      try remember(url, source: source)
      return source
    }
  }

  func read(_ source: String) throws -> (name: String, bytes: Data) {
    let url = try resolve(source)
    return try authorized(url) {
      var coordinationError: NSError?
      var outcome: Result<Data, Error>?
      NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) {
        location in outcome = Result { try Data(contentsOf: location) }
      }
      if let error = coordinationError { throw error }
      guard let outcome = outcome else {
        throw OriginalPdfFailure(code: "PDF_READ_FAILED", message: "O provedor não permitiu ler o PDF.")
      }
      return (url.lastPathComponent, try outcome.get())
    }
  }

  func write(_ source: String, bytes: Data, expectedHash: String) throws {
    let url = try resolve(source)
    try authorized(url) {
      var coordinationError: NSError?
      var outcome: Result<Void, Error>?
      NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing,
        error: &coordinationError) { location in
        outcome = Result {
          // Conferência dentro da coordenação, depois da preparação no Dart.
          let current = try Data(contentsOf: location)
          guard Self.digest(current) == expectedHash else {
            throw OriginalPdfFailure(code: "PDF_CHANGED_EXTERNALLY",
              message: "O PDF mudou fora do aplicativo. Reabra-o antes de salvar.")
          }
          try bytes.write(to: location, options: .atomic)
        }
      }
      if let error = coordinationError { throw error }
      guard let outcome = outcome else {
        throw OriginalPdfFailure(code: "PDF_WRITE_FAILED", message: "O provedor não permitiu salvar o PDF original.")
      }
      try outcome.get()
      // A substituição pode alterar a identidade interna do arquivo.
      // Não transformar uma gravação já concluída em falha se o bookmark
      // não puder ser atualizado; a resolução seguinte detectará acesso perdido.
      try? remember(url, source: source)
    }
  }
}

final class OriginalPdfPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private weak var registrar: FlutterPluginRegistrar?
  private let store = OriginalPdfStore()
  private let queue = DispatchQueue(label: "br.com.estudos.reader.original-pdf")
  private var pendingPick: FlutterResult?

  init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "br.com.estudos.reader/original_pdf",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(OriginalPdfPlugin(registrar: registrar), channel: channel)
  }

  private func complete(_ result: @escaping FlutterResult, error: Error) {
    let failure = error as? OriginalPdfFailure
    result(FlutterError(code: failure?.code ?? "PDF_PROVIDER_ERROR",
      message: error.localizedDescription, details: nil))
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "pickPdf" {
      guard pendingPick == nil else {
        result(FlutterError(code: "PICKER_BUSY", message: "O seletor de PDFs já está aberto.", details: nil))
        return
      }
      guard var presenter = registrar?.viewController else {
        result(FlutterError(code: "NO_WINDOW", message: "Janela do leitor indisponível.", details: nil))
        return
      }
      while let presented = presenter.presentedViewController { presenter = presented }
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: false)
      picker.allowsMultipleSelection = false
      picker.delegate = self
      picker.modalPresentationStyle = .formSheet
      pendingPick = result
      presenter.present(picker, animated: true) {
        picker.presentationController?.delegate = self
      }
      return
    }
    guard call.method == "readPdf" || call.method == "writePdf" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let source = arguments["source"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "PDF original não informado.", details: nil))
      return
    }
    queue.async {
      do {
        if call.method == "readPdf" {
          let snapshot = try self.store.read(source)
          DispatchQueue.main.async {
            result(["name": snapshot.name, "bytes": FlutterStandardTypedData(bytes: snapshot.bytes)])
          }
        } else {
          guard let bytes = arguments["bytes"] as? FlutterStandardTypedData,
                let expectedHash = arguments["expectedHash"] as? String else {
            throw OriginalPdfFailure(code: "INVALID_ARGUMENT", message: "Conteúdo ou hash do PDF não informado.")
          }
          try self.store.write(source, bytes: bytes.data, expectedHash: expectedHash)
          DispatchQueue.main.async { result(nil) }
        }
      } catch {
        DispatchQueue.main.async { self.complete(result, error: error) }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pendingPick
    pendingPick = nil
    result?(nil)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    let result = pendingPick
    pendingPick = nil
    result?(nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pendingPick else { return }
    pendingPick = nil
    guard let url = urls.first else { result(nil); return }
    queue.async {
      do {
        let source = try self.store.register(url)
        DispatchQueue.main.async { result(source) }
      } catch {
        DispatchQueue.main.async { self.complete(result, error: error) }
      }
    }
  }
}
