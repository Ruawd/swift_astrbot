import Foundation

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case network
    case security
    case maintenance
    case openAPI
    case resources

    var id: String { return rawValue }

    var title: String {
        switch self {
        case .general: return "常规"
        case .appearance: return "外观"
        case .network: return "网络"
        case .security: return "安全"
        case .maintenance: return "维护"
        case .openAPI: return "OpenAPI"
        case .resources: return "资源"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintpalette"
        case .network: return "network"
        case .security: return "shield.lefthalf.filled"
        case .maintenance: return "wrench.and.screwdriver"
        case .openAPI: return "key.horizontal"
        case .resources: return "info.circle"
        }
    }
}

struct SystemSettingDefinition: Identifiable, Hashable {
    enum Kind: Hashable {
        case toggle
        case text
        case integer
        case decimal
        case choice([String])
        case stringList
    }

    let keyPath: String
    let title: String
    let subtitle: String
    let kind: Kind
    let section: SettingsSection
    let group: String
    let sensitive: Bool

    var id: String { return keyPath }

    init(
        _ keyPath: String,
        _ title: String,
        _ subtitle: String,
        kind: Kind,
        section: SettingsSection,
        group: String,
        sensitive: Bool = false
    ) {
        self.keyPath = keyPath
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.section = section
        self.group = group
        self.sensitive = sensitive
    }

    static let all: [Self] = [
        Self("timezone", "时区", "服务器日志、任务和展示时间使用的时区", kind: .text, section: .general, group: "运行时"),
        Self("callback_api_base", "回调 API 地址", "AstrBot 对外生成回调链接时使用的基础地址", kind: .text, section: .general, group: "运行时"),
        Self("log_level", "日志级别", "控制控制台输出的最低日志等级", kind: .choice(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]), section: .general, group: "日志"),
        Self("log_file_enable", "写入日志文件", "同时将运行日志保存到磁盘", kind: .toggle, section: .general, group: "日志"),
        Self("log_file_path", "日志文件路径", "相对于 AstrBot 工作目录", kind: .text, section: .general, group: "日志"),
        Self("log_file_max_mb", "日志文件上限", "单个日志文件最大 MB", kind: .integer, section: .general, group: "日志"),
        Self("trace_log_enable", "写入 Trace 日志", "将链路追踪信息保存到独立文件", kind: .toggle, section: .general, group: "日志"),
        Self("trace_log_path", "Trace 文件路径", "链路追踪日志保存位置", kind: .text, section: .general, group: "日志"),
        Self("trace_log_max_mb", "Trace 文件上限", "单个 Trace 日志最大 MB", kind: .integer, section: .general, group: "日志"),
        Self("temp_dir_max_size", "临时目录上限", "临时文件总量上限 MB", kind: .integer, section: .general, group: "临时存储"),

        Self("t2i_strategy", "文本转图片方式", "远程服务或本机渲染", kind: .choice(["remote", "local"]), section: .appearance, group: "文本转图片"),
        Self("t2i_endpoint", "T2I 服务地址", "远程文本转图片服务端点", kind: .text, section: .appearance, group: "文本转图片"),
        Self("t2i_active_template", "活动模板", "当前使用的图片渲染模板", kind: .text, section: .appearance, group: "文本转图片"),

        Self("http_proxy", "HTTP 代理", "GitHub、模型服务等出站请求使用的代理", kind: .text, section: .network, group: "代理"),
        Self("no_proxy", "不使用代理", "每行填写一个地址", kind: .stringList, section: .network, group: "代理"),
        Self("pip_install_arg", "Pip 安装参数", "插件安装依赖时附加给 Pip 的参数", kind: .text, section: .network, group: "Python 包"),
        Self("pypi_index_url", "PyPI 镜像", "Python 包索引地址", kind: .text, section: .network, group: "Python 包"),

        Self("dashboard.trust_proxy_headers", "信任代理请求头", "仅在可信反向代理之后启用", kind: .toggle, section: .security, group: "反向代理"),
        Self("dashboard.ssl.enable", "WebUI 内置 HTTPS", "直接由 AstrBot Dashboard 提供 TLS", kind: .toggle, section: .security, group: "HTTPS"),
        Self("dashboard.ssl.cert_file", "证书文件", "PEM 证书文件路径", kind: .text, section: .security, group: "HTTPS"),
        Self("dashboard.ssl.key_file", "私钥文件", "PEM 私钥文件路径", kind: .text, section: .security, group: "HTTPS", sensitive: true),
        Self("dashboard.ssl.ca_certs", "CA 证书", "可选 CA 证书文件路径", kind: .text, section: .security, group: "HTTPS"),
        Self("dashboard.auth_rate_limit.enable", "登录限流", "限制短时间内的登录尝试", kind: .toggle, section: .security, group: "登录保护"),
        Self("dashboard.auth_rate_limit.average_interval", "平均间隔", "登录限流平均时间间隔（秒）", kind: .decimal, section: .security, group: "登录保护"),
        Self("dashboard.auth_rate_limit.max_burst", "最大突发次数", "允许短时间连续尝试的次数", kind: .integer, section: .security, group: "登录保护"),
        Self("dashboard.totp.enable", "两步验证", "为 Dashboard 登录启用 TOTP", kind: .toggle, section: .security, group: "两步验证"),
    ]
}

extension JSONValue {
    func value(at keyPath: String) -> JSONValue? {
        var current: JSONValue? = self
        for component in keyPath.split(separator: ".").map(String.init) {
            current = current?[component]
        }
        return current
    }

    mutating func setValue(_ newValue: JSONValue, at keyPath: String) {
        var components = keyPath.split(separator: ".").map(String.init)
        guard !components.isEmpty else { self = newValue; return }
        let head = components.removeFirst()
        var object = objectValue ?? [:]
        if components.isEmpty {
            object[head] = newValue
        } else {
            var child = object[head] ?? .object([:])
            child.setValue(newValue, at: components.joined(separator: "."))
            object[head] = child
        }
        self = .object(object)
    }
}
