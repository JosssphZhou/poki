# Poki 菜单栏应用（macOS）

把 `poki` 这套 MCP 服务 + Agent 打成一个双击可用的菜单栏 App。App 内自带 Node 运行时、
原生桥接和 idevice 工具，不依赖系统里的 Node。

## 构建

```sh
# 先在仓库根目录完成原生构建
./bin/setup

# 再打包（会在 /tmp/poki-build 生成 Poki.app，并生成 DMG）
sh menubar/build.sh /absolute/path/to/poki
```

需要完整版 Xcode（`xcrun swiftc`）、Node 24+、Rust。

## App 做什么

- 随 App 启动 daemon（`127.0.0.1:47825`），退出时一并结束；强杀时 daemon 通过
  `POKI_PARENT_PID` 看门狗自行退出，不会留下孤儿进程
- 菜单栏：服务状态、启动/停止/重启、复制 MCP 配置（带内置 node 路径）、查看日志
- **设置窗口**：
  - 模型页：选供应商（42 个内置 provider）、选模型、OAuth 或 API Key、在终端登录
  - iMessage 页：填 BlueBubbles 地址/密码/发送者/GUID/设备，测试连接后保存
- iMessage 子菜单：启动/停止通道、检查连接、打开配置目录与日志

## 配置文件

| 路径 | 内容 | 权限 |
| --- | --- | --- |
| `~/.config/poki-agent/config.json` | provider / model / auth / serviceTier / baseUrl | 600 |
| `~/.config/poki-agent/env.json` | GUI 填入的 API Key（环境变量优先） | 600 |
| `~/.config/poki-agent/imessage/` | BlueBubbles 连接与通道配置 | 700 / 600 |
| `~/Library/Application Support/PokiMCP/mcp.json` | daemon 端点与令牌（运行时生成） | 600 |
| `~/Library/Logs/Poki/*.log` | daemon 与通道日志 | — |

## 签名

构建脚本使用 adhoc 签名（`codesign --force --sign -`），没有公证。分发给别人时首次打开
需要右键 →「打开」，或 `xattr -dr com.apple.quarantine /Applications/Poki.app`。
