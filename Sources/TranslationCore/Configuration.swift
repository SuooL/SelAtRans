import Foundation

public struct APIConfiguration: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var effort: ReasoningEffort

    public init(baseURL: String = "https://api.deepseek.com", model: String = "deepseek-flash", effort: ReasoningEffort = .providerDefault) {
        self.baseURL = baseURL
        self.model = model
        self.effort = effort
    }

    public func endpoint() throws -> URL {
        guard let components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let base = components.url else { throw TranslationError.invalidEndpoint }
        if base.path.hasSuffix("/chat/completions") { return base }
        return base.appendingPathComponent("chat/completions")
    }

    public func credentialAccount() throws -> String {
        let url = try endpoint()
        return "https://\(url.host!.lowercased()):\(url.port ?? 443)"
    }

    public func validate() throws {
        _ = try endpoint()
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.missingModel
        }
    }
}

public enum ReasoningEffort: String, Codable, CaseIterable, Sendable {
    case providerDefault, none, minimal, low, medium, high, xhigh, max
    public var label: String { self == .providerDefault ? "服务默认" : rawValue }
    public static func supported(for baseURL: String) -> [Self] {
        URL(string: baseURL)?.host?.lowercased() == "api.deepseek.com"
            ? [.providerDefault, .none, .low, .high, .max] : allCases
    }
}

public struct LLMProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var configuration: APIConfiguration
    public init(id: UUID = UUID(), name: String = "DeepSeek", configuration: APIConfiguration = .init()) {
        self.id = id; self.name = name; self.configuration = configuration
    }
    public func credentialAccount() throws -> String {
        "\(id.uuidString)|\(try configuration.credentialAccount())"
    }
}

public struct ProfileCollection: Codable, Equatable, Sendable {
    public var profiles: [LLMProfile]
    public var activeID: UUID?
    public var active: LLMProfile? { profiles.first { $0.id == activeID } }
    public init(profiles: [LLMProfile], activeID: UUID?) { self.profiles = profiles; self.activeID = activeID }
    public static func initial() -> Self {
        let profile = LLMProfile()
        return .init(profiles: [profile], activeID: profile.id)
    }
    public mutating func remove(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeID == id { activeID = nil }
    }
}

public enum TranslationError: Error, LocalizedError, Equatable {
    case invalidEndpoint, missingModel, missingKey, emptyInput, inputTooLong
    case invalidResponse, emptyResponse, incompleteResponse, outputTooLong, http(Int), network

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "请填写有效的 HTTPS API 地址，不含用户名、密码、查询参数或片段。"
        case .missingModel: return "请先在设置中填写模型名称。"
        case .missingKey: return "请先在设置中保存当前服务的 API Key。"
        case .emptyInput: return "没有可翻译的文字。"
        case .inputTooLong: return "本次文字过长，请缩小选区后重试（最多 30,000 个 UTF-16 字符）。"
        case .invalidResponse: return "API 返回了无法识别的结果，请检查模型和服务地址。"
        case .emptyResponse: return "API 没有返回译文，原文已保留。"
        case .incompleteResponse: return "API 返回的译文不完整，原文已保留。"
        case .outputTooLong: return "译文超出长度限制，原文和剪贴板已保留。"
        case .http(401), .http(403): return "API 认证失败，请检查当前服务的密钥和权限。"
        case .http(429): return "API 请求受限或额度不足，请稍后重试。"
        case .http(let code): return "API 请求失败（HTTP \(code)），原文已保留。"
        case .network: return "网络请求失败或超时，原文已保留。"
        }
    }
}
