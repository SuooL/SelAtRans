import CryptoKit
import Darwin
import Foundation

public enum CredentialStoreError: Error, LocalizedError {
    case unavailable, invalidCredential
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "无法访问本地密钥文件，请检查当前用户的应用支持目录权限。"
        case .invalidCredential: return "密钥为空、过长或本地密钥文件无效，请重新填写。"
        }
    }
}

/// App-owned plaintext files, isolated by profile and origin. Never accesses Keychain.
public struct CredentialStore {
    public let directory: URL
    private static let maximumBytes = 16_384

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SelAtRans/Credentials", isDirectory: true)
    }

    private func filename(_ account: String) throws -> String {
        guard let prefix = account.split(separator: "|", maxSplits: 1).first,
              let id = UUID(uuidString: String(prefix)), account.contains("|") else {
            throw CredentialStoreError.invalidCredential
        }
        let digest = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        return id.uuidString + "-" + digest + ".credential"
    }

    private func openDirectory(create: Bool) throws -> Int32? {
        if create {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            } catch { throw CredentialStoreError.unavailable }
        }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0, errno == ENOENT, !create { return nil }
        guard fd >= 0 else { throw CredentialStoreError.unavailable }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              fchmod(fd, 0o700) == 0 else {
            close(fd)
            throw CredentialStoreError.unavailable
        }
        return fd
    }

    public func read(account: String) throws -> String? {
        let name = try filename(account)
        guard let root = try openDirectory(create: false) else { return nil }
        defer { close(root) }
        let fd = openat(root, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw CredentialStoreError.unavailable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, fchmod(fd, 0o600) == 0 else {
            throw CredentialStoreError.unavailable
        }
        guard info.st_size > 0, info.st_size <= Self.maximumBytes else { throw CredentialStoreError.invalidCredential }
        var bytes = [UInt8](repeating: 0, count: Self.maximumBytes + 1)
        var count = 0
        while count < bytes.count {
            let amount = bytes.withUnsafeMutableBytes {
                Darwin.read(fd, $0.baseAddress!.advanced(by: count), $0.count - count)
            }
            if amount < 0, errno == EINTR { continue }
            guard amount >= 0 else { throw CredentialStoreError.unavailable }
            if amount == 0 { break }
            count += amount
        }
        guard count > 0, count <= Self.maximumBytes,
              let key = String(bytes: bytes.prefix(count), encoding: .utf8), !key.isEmpty else {
            throw CredentialStoreError.invalidCredential
        }
        return key
    }

    public func save(_ key: String, account: String) throws {
        let data = Data(key.utf8)
        guard !data.isEmpty, data.count <= Self.maximumBytes else { throw CredentialStoreError.invalidCredential }
        let name = try filename(account)
        guard let root = try openDirectory(create: true) else { throw CredentialStoreError.unavailable }
        defer { close(root) }
        let temporary = ".pending-" + UUID().uuidString
        let fd = openat(root, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CredentialStoreError.unavailable }
        defer { close(fd); unlinkat(root, temporary, 0) }
        guard fchmod(fd, 0o600) == 0 else { throw CredentialStoreError.unavailable }
        var offset = 0
        while offset < data.count {
            let amount = data.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset)
            }
            if amount < 0, errno == EINTR { continue }
            guard amount > 0 else { throw CredentialStoreError.unavailable }
            offset += amount
        }
        guard fsync(fd) == 0, renameat(root, temporary, root, name) == 0 else {
            throw CredentialStoreError.unavailable
        }
    }

    public func delete(account: String) throws {
        let name = try filename(account)
        guard let root = try openDirectory(create: false) else { return }
        defer { close(root) }
        guard unlinkat(root, name, 0) == 0 || errno == ENOENT else { throw CredentialStoreError.unavailable }
    }

    public func deleteProfile(id: UUID) throws {
        guard let root = try openDirectory(create: false) else { return }
        defer { close(root) }
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: directory.path) }
        catch { throw CredentialStoreError.unavailable }
        for name in names where name.hasPrefix(id.uuidString + "-") && name.hasSuffix(".credential") {
            guard unlinkat(root, name, 0) == 0 || errno == ENOENT else { throw CredentialStoreError.unavailable }
        }
    }
}
