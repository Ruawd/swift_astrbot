# AstrBot Mobile

原生 SwiftUI AstrBot 管理端，面向 iOS 26，并使用系统 Liquid Glass 组件。项目不依赖第三方运行库。

## 功能范围

- 账号密码、TOTP 与 API Key 登录，凭据存入 iOS Keychain
- 原生统计概览、运行状态和 Token 数据
- WebChat 会话、历史记录与 SSE 流式回复
- 平台、模型提供商、配置路由和配置档案
- 插件、插件市场、MCP、Skills、Tools、Commands
- 知识库、人格、会话规则、对话记录、Cron、Sub-agent、T2I
- 备份、API Key、更新、存储、日志、Trace 和系统配置
- 原生实时控制台：先载入历史日志，再通过 SSE 持续接收日志，支持等级筛选、搜索、自动滚动和断线重连
- 设置结构和保存逻辑与 WebUI 对齐，覆盖常规、外观、网络、安全、维护、OpenAPI 与资源
- OpenAPI 浏览器保留在设置中的高级工具入口，不作为主要管理界面
- iOS 26 `glassEffect`，并为较低系统提供 Material 降级
- 深色/浅色模式、Dynamic Type、VoiceOver 标签、减少动态效果和 iPad 布局

## 打开和运行

1. 使用 Xcode 26 打开 `AstrBotMobile.xcodeproj`。
2. 在 Target > Signing & Capabilities 选择你的个人 Team。
3. 修改 Bundle Identifier（如发生冲突）。
4. 选择 iPhone 或模拟器运行。

项目的最低部署版本为 iOS 17，以便旧设备安装；真正的 Liquid Glass 会在 iOS 26 自动启用。

## 自签安装

没有付费 Apple Developer 账号时，可以使用 Xcode 的 Personal Team 安装到自己的 iPhone。个人签名通常需要每 7 天重新签名。也可在 Mac 上 Archive 后交给 AltStore/SideStore 等自签工具。

## GitHub Release IPA

仓库包含 `.github/workflows/release-ipa.yml`：

- 推送 `v*` Tag 会在 GitHub macOS Runner 上构建未签名 IPA，并自动创建 Release。
- 也可以在 Actions 页面手动运行 `Build unsigned IPA release`。
- Release 中的 `*-unsigned.ipa` 必须先由 AltStore、SideStore、TrollStore 或其他工具签名后才能安装。

发布示例：

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 网络要求

- 推荐 AstrBot 使用 HTTPS。
- 局域网 HTTP 可连接；`Info.plist` 只开放了 Local Networking，没有全局关闭 ATS。
- 若使用公网域名，证书必须受 iOS 信任。

## 管理界面策略

底部导航按“概览、聊天、管理、日志、设置”组织。常用管理功能使用原生卡片、列表、状态、开关和表单呈现；OpenAPI 仅作为服务器新增能力尚未适配时的高级备用工具。
