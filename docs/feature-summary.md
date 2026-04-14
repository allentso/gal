# AI 女友项目 — 功能实现状况（当前版本）

> 最后更新: 2026-04-14

---

## 项目架构

| 项目 | 值 |
|------|-----|
| 运行模式 | 多人 C/S 架构（Persistent World） |
| 客户端/服务端入口 | 均为 `main.lua`（通过 `IsServerMode()` 分流） |
| 最大玩家数 | 2 |

## 文件结构

```
scripts/
├── main.lua              # 客户端 UI + 入口分流
├── config.lua            # 集中配置（API / 角色 / 行为 / 开关）
├── network/
│   ├── Shared.lua        # 18 个远程事件定义
│   ├── Client.lua        # 客户端网络模块（发送/接收）
│   └── Server.lua        # 服务端逻辑（LLM/TTS/ASR/历史）
└── utils/
    └── base64.lua        # 纯 Lua Base64 编解码
```

---

## 功能状态一览

| 功能 | 状态 | 说明 |
|------|------|------|
| **LLM 对话** | ✅ 已实现 | 火山引擎 ARK API，API Key 已配置 |
| **表情系统** | ✅ 已实现 | 5 种表情（normal/happy/shy/sad/surprised），LLM 回复末尾 `[表情]` 标签驱动切换，N 秒后自动回归 normal |
| **Live2D 动画** | ✅ 已实现 | 呼吸动画 + 身体摇摆 + 弹跳反应（伪 Live2D，实际是图片层动画） |
| **粒子特效** | ✅ 已实现 | 表情切换时生成 emoji 粒子（✨/❤️/💕/💧/❗） |
| **触摸互动** | ✅ 已实现 | 三个热区（头部 25%/脸颊 20%/身体 55%），点击后触发表情+粒子+发送给 LLM 生成反应 |
| **快捷回复** | ✅ 已实现 | 6 个预设快捷按钮，横向滚动 |
| **好感度系统** | ✅ 已实现 | 发消息 +1，顶栏显示数值和进度条（纯客户端，不持久化） |
| **离线 fallback** | ✅ 已实现 | 服务端无法连接时，使用本地回复池按关键词匹配分类回复 |
| **AI 主动说话** | ✅ 已实现 | 服务端 Update 事件定时检测，用户沉默超时后 LLM 主动发起对话 |
| **打断机制** | ✅ 已实现 | AI 说话时显示 ⏹ 按钮，服务端丢弃被打断的 LLM/TTS 响应 |
| **对话历史（内存）** | ✅ 已实现 | 服务端内存中维护多会话，支持列表/加载/新建。**不持久化**——服务端重启后丢失 |
| **多模态视觉** | ⚠️ 代码已写，未启用 | `VISION.ENABLED = false`，截图按钮存在但视觉 LLM API Key 未配置 |
| **截图发送** | ⚠️ 部分可用 | 截图按钮 📷 存在，调用 `graphics:TakeScreenShot()` → Base64 → 发送服务端。依赖视觉模型开启 |
| **TTS 语音合成** | ❌ 已禁用 | `TTS.ENABLED = false`，API Key 未配置。代码流程完整（服务端调 API → base64 音频 → 客户端解码播放），但字节跳动 TTS API 的请求格式未经验证 |
| **ASR 语音识别** | ❌ 不可用 | `ASR.ENABLED = false`。**根本限制**：UrhoX 引擎无内置麦克风录音 API，客户端无法采集音频 |
| **对话历史持久化** | ❌ 不可用 | 原设计用 `io.open` 写 JSON 文件，但服务端 File API 被完全屏蔽。当前改为纯内存，重启丢失。需改用 `serverCloud` API 才能持久化 |

---

## 关键技术细节

### 网络通信

- 所有 `SendRemoteEvent` 使用 `VariantMap()` + `Variant()` 封装数据
- 客户端通过 `network:GetServerConnection()` 发送
- 服务端通过 `eventData["Connection"]:GetPtr("Connection")` 获取连接对象
- `ClientNet.Init()` 直接检查已有连接（UrhoX 多人架构中连接在 `Start()` 前建立）

### LLM 调用链

```
客户端输入 → ChatSend 事件 → 服务端 CallLLM()
  → http:Create() 链式调用火山引擎 API
  → 解析回复，提取 [表情] 标签
  → ChatReply 事件 → 客户端显示气泡 + 切换表情 + 粒子特效
```

### config.lua 配置开关

| 开关 | 当前值 | 作用 |
|------|--------|------|
| `TTS.ENABLED` | `false` | TTS 语音合成 |
| `ASR.ENABLED` | `false` | ASR 语音识别 |
| `VISION.ENABLED` | `false` | 多模态视觉 LLM |
| `TOUCH.ENABLED` | `true` | 触摸互动 |
| `AI.PROACTIVE_ENABLED` | `true` | AI 主动说话 |
| `HISTORY.AUTO_SAVE` | `true` | 自动保存历史（仅内存） |

---

## 需要后续解决的问题

1. **对话历史持久化** — 改用 `serverCloud` API 替代内存存储，实现跨会话保存
2. **TTS** — 需提供 API Key 并验证字节跳动 API 请求格式是否匹配
3. **ASR** — 引擎层面不支持麦克风录音，无法实现
4. **好感度持久化** — 当前纯客户端变量，刷新后重置，可用 `clientCloud` 持久化
5. **视觉感知** — 需配置视觉 LLM 的 API Key 和模型 ID
