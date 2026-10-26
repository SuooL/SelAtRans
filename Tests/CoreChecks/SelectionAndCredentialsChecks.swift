import Foundation
import TranslationCore

private func require(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(condition, "Regression check failed", file: file, line: line)
}

private func rejects(_ operation: () throws -> Void) {
    do { try operation() } catch { return }
    fatalError("Expected safe rejection")
}

func runSelectionChecks() {
    let missing = NSRange?.none
    let empty = NSRange(location: 5, length: 0)
    let selected = NSRange(location: 5, length: 2)
    // An editor that omits AXSelectedTextRange is the reported stale-clipboard regression.
    require(SelectionCapturePolicy.route(range: missing, isTextInput: true, copy: .enabled) == .copySelection)
    require(SelectionCapturePolicy.route(range: missing, isTextInput: true, copy: .unknown) == .unavailable)
    require(SelectionCapturePolicy.route(range: selected, isTextInput: true, copy: .disabled) == .unavailable)
    require(SelectionCapturePolicy.route(range: empty, isTextInput: true, copy: .enabled) == .clipboard)
    require(SelectionCapturePolicy.route(range: empty, isTextInput: true, copy: .enabled,
                                             selectionReported: true) == .copySelection)
    require(SelectionCapturePolicy.route(range: missing, isTextInput: false, copy: .disabled) == .clipboard)
    require(SelectionCapturePolicy.route(range: missing, isTextInput: false, copy: .unknown) == .unavailable)
    require(SelectionCapturePolicy.route(range: missing, isTextInput: false, copy: .enabled) == .copySelection)
    // Copy must produce a new, nonempty value; an unchanged previous copy is never a selection.
    require(SelectionCapturePolicy.copiedSelection("previous copied text", clipboardChanged: false) == nil)
    require(SelectionCapturePolicy.copiedSelection(nil, clipboardChanged: true) == nil)
    require(SelectionCapturePolicy.copiedSelection("", clipboardChanged: true) == nil)
    require(SelectionCapturePolicy.copiedSelection("current selection", clipboardChanged: true) == "current selection")
    let full = "a你好🌍z"
    require(SelectionCapturePolicy.text(in: full, range: NSRange(location: 1, length: 4)) == "你好🌍")
    for range in [NSRange(location: NSNotFound, length: 2), NSRange(location: 0, length: Int.max),
                  NSRange(location: 2, length: 0), NSRange(location: 4, length: 1)] {
        require(SelectionCapturePolicy.text(in: full, range: range) == nil)
    }
    print("PASS: selection routing, unchanged-copy rejection, and UTF-16 range regression checks")
}

func runCredentialChecks() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent("selatrans-credential-tests-" + UUID().uuidString)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }
    let directory = temporary.appendingPathComponent("private/Credentials")
    let store = CredentialStore(directory: directory)
    let first = LLMProfile(configuration: .init(baseURL: "https://one.example.invalid"))
    let changed = LLMProfile(id: first.id, configuration: .init(baseURL: "https://two.example.invalid"))
    let other = LLMProfile(configuration: first.configuration)
    let account = try first.credentialAccount()
    require(try store.read(account: account) == nil)
    try store.delete(account: account)
    require(!manager.fileExists(atPath: directory.path))

    try store.save("synthetic-first", account: account)
    let originalFile = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)[0]
    let directoryMode = try manager.attributesOfItem(atPath: directory.path)[.posixPermissions] as! NSNumber
    let fileMode = try manager.attributesOfItem(atPath: originalFile.path)[.posixPermissions] as! NSNumber
    require(directoryMode.intValue == 0o700 && fileMode.intValue == 0o600)
    require(try store.read(account: account) == "synthetic-first")
    try store.save("synthetic-replacement", account: account)
    require(try store.read(account: account) == "synthetic-replacement")
    require(try manager.contentsOfDirectory(atPath: directory.path).count == 1)

    try manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)
    try manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: originalFile.path)
    _ = try store.read(account: account)
    require((try manager.attributesOfItem(atPath: directory.path)[.posixPermissions] as! NSNumber).intValue == 0o700)
    require((try manager.attributesOfItem(atPath: originalFile.path)[.posixPermissions] as! NSNumber).intValue == 0o600)

    try store.save("synthetic-second-origin", account: changed.credentialAccount())
    try store.save("synthetic-other-profile", account: other.credentialAccount())
    require(try store.read(account: account) == "synthetic-replacement")
    require(try store.read(account: changed.credentialAccount()) == "synthetic-second-origin")
    try store.delete(account: account)
    require(try store.read(account: account) == nil)
    try store.deleteProfile(id: first.id)
    require(try store.read(account: changed.credentialAccount()) == nil)
    require(try store.read(account: other.credentialAccount()) == "synthetic-other-profile")

    try store.save("synthetic-valid", account: account)
    let outside = temporary.appendingPathComponent("outside")
    try Data("synthetic-outside".utf8).write(to: outside)
    try manager.removeItem(at: originalFile)
    try manager.createSymbolicLink(at: originalFile, withDestinationURL: outside)
    rejects { _ = try store.read(account: account) }
    try store.save("synthetic-safe-replacement", account: account)
    require(try String(contentsOf: outside) == "synthetic-outside")
    require(try store.read(account: account) == "synthetic-safe-replacement")

    try manager.removeItem(at: originalFile)
    try manager.linkItem(at: outside, to: originalFile)
    rejects { _ = try store.read(account: account) }
    try manager.removeItem(at: originalFile)
    try store.save("synthetic-valid", account: account)
    try Data([0xff, 0xfe]).write(to: originalFile)
    rejects { _ = try store.read(account: account) }
    try Data(repeating: 65, count: 16_385).write(to: originalFile)
    rejects { _ = try store.read(account: account) }
    rejects { try store.save("", account: account) }
    rejects { try store.save(String(repeating: "a", count: 16_385), account: account) }
    rejects { try store.save("synthetic-key", account: "../../invalid") }

    let alias = temporary.appendingPathComponent("symlink-directory")
    try manager.createSymbolicLink(at: alias, withDestinationURL: directory)
    let aliasedStore = CredentialStore(directory: alias)
    rejects { _ = try aliasedStore.read(account: account) }
    rejects { try aliasedStore.save("synthetic-key", account: account) }
    print("PASS: local credential CRUD, origin/profile isolation, atomic overwrite, permissions, symlink/hardlink refusal, and corruption checks")
}
