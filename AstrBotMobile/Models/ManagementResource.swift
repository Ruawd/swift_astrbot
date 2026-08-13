import SwiftUI

enum ResourceItemStyle: String {
    case enabled
    case disabled
    case warning
    case neutral
}

struct ResourceItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let style: ResourceItemStyle
    let raw: JSONValue
}

struct ManagementResource: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let path: String
    let method: HTTPMethod
    let category: String
    let supportsCreate: Bool
    let createPath: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        path: String,
        method: HTTPMethod = .get,
        category: String,
        supportsCreate: Bool = false,
        createPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.path = path
        self.method = method
        self.category = category
        self.supportsCreate = supportsCreate
        self.createPath = createPath
    }

    func parseItems(from value: JSONValue?) -> [ResourceItem] {
        guard let value else { return [] }
        let arrays: [[JSONValue]?] = [
            value.arrayValue,
            value["items"]?.arrayValue,
            value["list"]?.arrayValue,
            value["data"]?.arrayValue,
            value["plugins"]?.arrayValue,
            value["providers"]?.arrayValue,
            value["platforms"]?.arrayValue,
            value["jobs"]?.arrayValue,
            value["skills"]?.arrayValue,
            value["servers"]?.arrayValue,
            value["personas"]?.arrayValue,
            value["backups"]?.arrayValue,
            value["knowledge_bases"]?.arrayValue,
            value["sessions"]?.arrayValue,
            value["groups"]?.arrayValue,
            value["keys"]?.arrayValue,
        ]
        guard let array = arrays.compactMap({ $0 }).first else {
            if let object = value.objectValue {
                return object.sorted(by: { $0.key < $1.key }).map { key, raw in
                    ResourceItem(id: key, title: key, subtitle: raw.stringValue, style: .neutral, raw: raw)
                }
            }
            return []
        }
        return array.enumerated().map { index, raw in
            let object = raw.objectValue ?? [:]
            let identifier = Self.firstString(object, keys: [
                "id", "plugin_id", "provider_id", "bot_id", "session_id", "job_id", "kb_id",
                "persona_id", "name", "key_id", "umo", "filename", "handler_full_name",
            ]) ?? "\(index)"
            let title = Self.firstString(object, keys: [
                "name", "display_name", "title", "plugin_name", "provider_id", "bot_id",
                "persona_id", "session_id", "job_id", "kb_name", "filename", "umo", "handler_name", "key_id",
            ]) ?? identifier
            let subtitle = Self.firstString(object, keys: [
                "description", "desc", "type", "version", "provider_type", "platform_id",
                "cron_expression", "schedule", "source", "updated_at", "created_at", "status",
            ])
            let enabled = object["enabled"]?.stringValue ?? object["enable"]?.stringValue ?? object["is_enabled"]?.stringValue ?? object["activated"]?.stringValue ?? object["active"]?.stringValue
            let style: ResourceItemStyle = enabled == "false" ? .disabled : enabled == "true" ? .enabled : .neutral
            return ResourceItem(id: identifier, title: title, subtitle: subtitle, style: style, raw: raw)
        }
    }

    private static func firstString(_ object: [String: JSONValue], keys: [String]) -> String? {
        keys.lazy.compactMap { object[$0]?.stringValue }.first(where: { !$0.isEmpty })
    }
}

extension ManagementResource {
    static let bots = Self(id: "bots", title: "消息平台", subtitle: "QQ、Telegram、Discord 等", icon: "antenna.radiowaves.left.and.right", path: "/api/v1/bots", category: "核心配置", supportsCreate: true)
    static let providers = Self(id: "providers", title: "模型提供商", subtitle: "LLM、语音、Embedding 与 Rerank", icon: "brain.head.profile", path: "/api/v1/providers", category: "核心配置", supportsCreate: true)
    static let configProfiles = Self(id: "profiles", title: "配置", subtitle: "多套机器人配置与路由", icon: "gearshape.2", path: "/api/v1/config-profiles", category: "核心配置", supportsCreate: true)
    static let configRoutes = Self(id: "routes", title: "配置路由", subtitle: "按会话分配配置", icon: "arrow.triangle.branch", path: "/api/v1/config-routes", category: "核心配置")

    static let plugins = Self(id: "plugins", title: "插件", subtitle: "安装、更新与配置插件", icon: "puzzlepiece.extension", path: "/api/v1/plugins", category: "扩展能力")
    static let pluginMarket = Self(id: "market", title: "插件市场", subtitle: "浏览并安装社区插件", icon: "storefront", path: "/api/v1/plugins/market", category: "扩展能力")
    static let mcp = Self(id: "mcp", title: "MCP 服务器", subtitle: "连接、测试与启停 MCP", icon: "point.3.connected.trianglepath.dotted", path: "/api/v1/mcp/servers", category: "扩展能力", supportsCreate: true)
    static let skills = Self(id: "skills", title: "技能", subtitle: "上传、启停与编辑 Skill", icon: "wand.and.stars", path: "/api/v1/skills", category: "扩展能力")
    static let tools = Self(id: "tools", title: "工具与权限", subtitle: "内置、插件和 MCP 工具", icon: "wrench.and.screwdriver", path: "/api/v1/tools", category: "扩展能力")
    static let commands = Self(id: "commands", title: "指令", subtitle: "别名、冲突与权限", icon: "terminal", path: "/api/v1/commands", category: "扩展能力")

    static let knowledgeBases = Self(id: "knowledge", title: "知识库", subtitle: "文档、分块与检索测试", icon: "books.vertical", path: "/api/v1/knowledge-bases", category: "数据与自动化", supportsCreate: true)
    static let personas = Self(id: "personas", title: "人格", subtitle: "人格与文件夹管理", icon: "heart", path: "/api/v1/personas", category: "数据与自动化", supportsCreate: true)
    static let sessions = Self(id: "sessions", title: "会话管理", subtitle: "规则、分组与服务切换", icon: "rectangle.stack.person.crop", path: "/api/v1/sessions", category: "数据与自动化")
    static let conversations = Self(id: "conversations", title: "对话记录", subtitle: "查询、编辑、导出与删除", icon: "externaldrive", path: "/api/v1/conversations", category: "数据与自动化")
    static let cronJobs = Self(id: "cron", title: "定时任务", subtitle: "创建、运行和维护任务", icon: "clock", path: "/api/v1/cron/jobs", category: "数据与自动化", supportsCreate: true)
    static let subagents = Self(id: "subagents", title: "子 Agent", subtitle: "Agent 编排与工具分配", icon: "point.3.connected.trianglepath.dotted", path: "/api/v1/subagents/config", category: "数据与自动化")
    static let t2i = Self(id: "t2i", title: "文本转图片", subtitle: "HTML 模板与活动模板", icon: "photo.badge.plus", path: "/api/v1/t2i/templates", category: "扩展能力", supportsCreate: true)

    static let backups = Self(id: "backups", title: "备份与恢复", subtitle: "导出、导入与下载备份", icon: "externaldrive.badge.timemachine", path: "/api/v1/backups", category: "系统管理", supportsCreate: true)
    static let apiKeys = Self(id: "apiKeys", title: "API Keys", subtitle: "创建、吊销与删除访问密钥", icon: "key.horizontal", path: "/api/v1/api-keys", category: "系统管理", supportsCreate: true)
    static let updates = Self(id: "updates", title: "更新", subtitle: "检查核心与 WebUI 更新", icon: "arrow.down.circle", path: "/api/v1/updates/check", category: "系统管理")
    static let storage = Self(id: "storage", title: "存储空间", subtitle: "缓存、日志和临时文件", icon: "internaldrive", path: "/api/v1/stats/storage", category: "系统管理")
    static let logs = Self(id: "logs", title: "运行日志", subtitle: "历史日志与实时日志入口", icon: "doc.text.magnifyingglass", path: "/api/v1/logs/history", category: "系统管理")
    static let trace = Self(id: "trace", title: "链路追踪", subtitle: "追踪状态与设置", icon: "waveform.path.ecg", path: "/api/v1/trace/settings", category: "系统管理")
    static let systemConfig = Self(id: "systemConfig", title: "系统配置", subtitle: "完整配置树与运行时信息", icon: "gearshape.2", path: "/api/v1/system-config", category: "系统管理")

    static let all: [Self] = [
        .bots, .providers, .configProfiles, .configRoutes,
        .plugins, .pluginMarket, .mcp, .skills, .tools, .commands,
        .knowledgeBases, .personas, .sessions, .conversations, .cronJobs, .subagents, .t2i,
        .backups, .apiKeys, .updates, .storage, .logs, .trace, .systemConfig,
    ]
}
