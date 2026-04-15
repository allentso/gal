# AI 女友项目 — 功能实现状况与技术边界

> 最后更新: 2026-04-15

---

## 项目架构

| 项目 | 值 |
|------|-----|
| 引擎 | UrhoX（WASM 运行时） |
| 运行模式 | 多人 C/S 架构（Persistent World） |
| 客户端入口 | `main.lua` |
| 服务端入口 | `network/Server.lua` |
| 最大玩家数 | 2 |

## 文件结构

```
scripts/
├── main.lua              # 客户端 UI + 角色动画 + 截图
├── config.lua            # 集中配置（API / 角色 / 行为 / 开关）
├── network/
│   ├── Shared.lua        # 18 个远程事件定义（客户端+服务端共用）
│   ├── Client.lua        # 客户端网络模块（发送/接收）
│   └── Server.lua        # 服务端逻辑（LLM/TTS/Vision/历史）
└── utils/
    └── base64.lua        # 纯 Lua Base64 编解码
```

---

## 功能状态一览

| 功能 | 状态 | 说明 |
|------|------|------|
| **LLM 对话** | ✅ 可用 | 火山引擎豆包 API（ARK），流式对话 |
| **表情系统** | ✅ 可用 | 5 种表情（normal/happy/shy/sad/surprised），LLM 回复末尾 `[表情]` 标签驱动切换 |
| **Live2D 动画** | ✅ 可用 | 呼吸 + 身体摇摆 + 弹跳反应（图片层动画模拟） |
| **粒子特效** | ✅ 可用 | 表情切换时生成 emoji 粒子（✨/❤️/💕/💧/❗） |
| **触摸互动** | ✅ 可用 | 三个热区（头部/脸颊/身体），触发表情+粒子+LLM 反应 |
| **快捷回复** | ✅ 可用 | 6 个预设按钮，横向滚动 |
| **好感度系统** | ✅ 可用 | 发消息 +1，顶栏进度条显示（纯客户端，不持久化） |
| **离线 fallback** | ✅ 可用 | 服务端断连时本地回复池按关键词分类回复 |
| **AI 主动说话** | ✅ 可用 | 用户沉默超时后 LLM 主动发起对话 |
| **打断机制** | ✅ 可用 | AI 说话时显示 ⏹ 按钮，服务端丢弃被打断的响应 |
| **对话历史持久化** | ✅ 可用 | serverCloud API，scores 存会话元数据 + list 存消息，跨会话保留 |
| **视觉感知（Vision）** | ⚠️ 受限 | 代码已实现，API 已配置。**但截图在 WASM 平台无法工作**（见下方技术边界） |
| **TTS 语音合成** | ⚠️ 受限 | 代码已实现（百炼 CosyVoice）。**但 TTS 接口不在服务端 HTTP 白名单内**（见下方技术边界） |
| **ASR 语音识别** | ❌ 不可用 | 引擎无麦克风录音 API，无法采集音频 |

---

## 关键技术细节

### 网络通信

- C/S 架构：服务端直接加载 `Server.lua`（不经过 `main.lua`），需显式 `require("network/Shared")`
- 所有 `SendRemoteEvent` 使用 `VariantMap()` + `Variant()` 封装数据
- 客户端通过 `network:GetServerConnection()` 发送
- 服务端通过 `eventData["Connection"]:GetPtr("Connection")` 获取连接

### LLM 调用链

```
客户端输入
  → ChatSend 事件 → 服务端 CallLLM()
  → HTTP 调用火山引擎 ARK API
  → 解析回复，提取 [表情] 标签
  → ChatReply 事件 → 客户端显示气泡 + 切换表情 + 粒子特效
```

### 视觉模型调用链（两步架构）

```
客户端截图 → Base64 编码 → ImageSend 事件 → 服务端
  → 步骤1: DashScope qwen3.5-flash 分析图片内容（生成文字描述）
  → 步骤2: 将"[图片描述：xxx] + 用户文字"交给豆包 LLM 生成角色化回复
  → ChatReply 事件 → 客户端显示
  → 降级: 步骤1 失败时直接用纯文字走步骤2
```

### config.lua 配置开关

| 开关 | 当前值 | 作用 |
|------|--------|------|
| `LLM.*` | 已配置 | 火山引擎豆包对话模型 |
| `TTS.ENABLED` | `false` | TTS 语音合成（接口被白名单阻止） |
| `ASR.ENABLED` | `false` | ASR 语音识别（无麦克风 API） |
| `VISION.ENABLED` | `true` | 视觉模型（截图获取受限） |
| `TOUCH.ENABLED` | `true` | 触摸互动 |
| `AI.PROACTIVE_ENABLED` | `true` | AI 主动说话 |
| `HISTORY.AUTO_SAVE` | `true` | serverCloud 自动持久化 |

---

## 技术边界（平台限制）

### 一、WASM 平台限制（客户端）

UrhoX 游戏运行在 WASM（WebAssembly）环境中，以下能力受到根本性限制：

| 能力 | 状态 | 原因 |
|------|------|------|
| **屏幕截图** | ❌ 不可用 | `graphics:TakeScreenShot()` 在 WASM 返回 false。WebGL 默认帧缓冲区不保留绘制内容（`preserveDrawingBuffer=false`），导致 `glReadPixels` 无法读取。当前已实现 render-to-texture 备选方案（`Texture2D` + `GetImage()`），但只能捕获 3D 场景层，**无法捕获 UI 层**（NanoVG / UI 库渲染在独立的绘制流程中） |
| **本地文件选择** | ❌ 不可用 | 引擎无原生文件选择器 API。`UI.FileUpload` 组件仅是 UI 模拟，点击后添加假数据，不会触发浏览器的 `<input type="file">` |
| **设备相机** | ❌ 不可用 | 引擎无 WebRTC / MediaDevices API 封装，无法调用手机摄像头 |
| **麦克风录音** | ❌ 不可用 | 引擎无音频采集 API（`getUserMedia` 等未暴露到 Lua 层） |
| **剪贴板图片** | ❌ 不可用 | 剪贴板 API 仅支持纯文本（`GetClipboardText` / `SetClipboardText`），不支持读取图片数据 |

**总结**：在 WASM 平台上，**没有任何可用途径将外部图片数据传入游戏运行时**。这意味着视觉感知功能（Vision）虽然服务端代码完整可用，但客户端无法提供图片输入。

### 二、服务端 HTTP 白名单限制

服务端的出站 HTTP 请求受平台白名单管控，只有白名单内的 URL 可以访问：

| 接口 | URL | 白名单 | 状态 |
|------|-----|--------|------|
| 豆包 LLM | `ark.cn-beijing.volces.com/api/v3/chat/completions` | ✅ 在白名单 | 正常可用 |
| DashScope 视觉/对话 | `dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` | ✅ 在白名单 | 正常可用 |
| DashScope TTS | `dashscope.aliyuncs.com/compatible-mode/v1/audio/speech` | ❌ 不在白名单 | **请求被拦截** |
| ASR 语音识别 | `openspeech.bytedance.com/api/v1/asr` | ❌ 不在白名单 | 请求被拦截 |

**影响**：
- TTS（`cosyvoice-v3.5-flash`）代码已完整实现，但服务端无法访问 `/audio/speech` 端点，语音合成不可用
- 如平台后续将 TTS 端点加入白名单，只需将 `config.lua` 中 `TTS.ENABLED` 改为 `true` 即可立即生效

### 三、可以做 vs 不能做

#### ✅ 现在可以做的

| 功能 | 说明 |
|------|------|
| 文字聊天 | 完整可用，支持对话历史持久化 |
| 表情/动画/粒子 | 完整可用，LLM 驱动 |
| 触摸互动 | 完整可用，三热区触发 |
| AI 主动对话 | 完整可用，沉默超时触发 |
| 打断 AI | 完整可用 |
| 对话历史跨会话保存 | 完整可用，serverCloud 持久化 |
| 好感度显示 | 可用（不持久化） |
| 快捷回复 | 完整可用 |
| 离线模式 | 可用，本地回复池兜底 |

#### ⚠️ 代码已实现，等条件解除即可启用

| 功能 | 阻塞条件 | 解除方式 |
|------|----------|----------|
| TTS 语音合成 | 服务端 HTTP 白名单不含 `/audio/speech` | 平台将该端点加入白名单后，改 `TTS.ENABLED = true` |
| 视觉感知 | 客户端无法获取图片数据（截图/上传/相机均不可用） | 引擎支持文件选择器 或 `TakeScreenShot` 修复 WASM 兼容性 |

#### ❌ 引擎能力不支持，无法实现

| 功能 | 原因 |
|------|------|
| 语音输入（ASR） | 无麦克风录音 API |
| 从相册选图 | 无原生文件选择器 |
| 拍照 | 无相机 API |
| 屏幕截图 | `TakeScreenShot` 在 WASM 返回 false，render-to-texture 无法覆盖 UI 层 |
| 剪贴板粘贴图片 | 剪贴板仅支持文本 |

---

## 后续可改进方向

1. **好感度持久化** — 使用 `clientCloud` 或 `serverCloud` 存储好感度数值
2. **TTS 启用** — 等待白名单放开 `/audio/speech` 端点
3. **视觉感知备选方案** — 如引擎后续暴露 JS 互操作层（Emscripten `ccall`/`cwrap`），可通过浏览器原生 `<input type="file">` 实现图片选择
4. **更多表情/动作** — 增加表情图素材即可扩展，代码结构已支持
5. **多会话管理 UI** — 服务端已支持多会话存储，可增加客户端会话切换界面
