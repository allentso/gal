---@diagnostic disable: undefined-global
-- ============================================================================
-- Server.lua — 服务端：LLM + TTS + ASR + 对话记忆 + 主动说话 + 触摸 + 视觉
-- ============================================================================
-- 对话历史通过 serverCloud API 持久化存储，支持跨会话保留。
-- 存储方案：
--   scores["chat_meta"]       → 会话元数据 { sessions: [{id, title, updatedAt}], activeSession }
--   list["chat_{sessionId}"]  → 该会话的消息列表 [{role, content, timestamp}]

require("network/Shared")       -- EVENTS 定义（服务端独立入口，需显式加载）
local Config = require("config")
local Base64 = require("utils/base64")

-- ======================== System Prompt（强化表情引导）========================

local SYSTEM_PROMPT = [[
你是]] .. Config.CHARACTER.NAME .. [[，一个]] .. Config.CHARACTER.AGE .. [[岁的女孩，]] .. Config.CHARACTER.SIGN .. [[。
你喜欢]] .. Config.CHARACTER.HOBBY .. [[。
]] .. Config.CHARACTER.BIO .. [[

你的说话风格：
- 温暖亲密，偶尔撒娇
- 每次回复保持简短自然（1-3句话），不要长篇大论
- 可以用一些可爱的语气词和表情符号
- 不要包含动作描述或括号内容，直接说话就好

【表情标签规则】
你必须在每次回复的**最末尾**添加一个表情标签，格式为 [表情名]。
可用的表情标签及其适用场景：
- [normal]    — 日常对话、平静叙述、思考、中性回答
- [happy]     — 开心、兴奋、收到夸赞、聊到喜欢的事物、有趣的话题
- [shy]       — 被夸好看、收到表白、亲密话题、害羞尴尬
- [sad]       — 对方心情不好、离别、难过共情、失望
- [surprised] — 意外消息、惊讶、震惊、不可思议的事

每条回复只使用一个标签，放在最后。
示例：嗨~ 今天天气真好呀！😊 [happy]

当用户沉默较久后你主动发言时，可以说一些日常关心的话，如"在忙什么呀？"、"想你了~"等。
当用户触摸你时（系统消息以 [用户...] 开头），请根据部位给出自然的反应。
]]

-- ======================== 表情提取 ========================

local VALID_EXPRESSIONS = {
    normal = true, happy = true, shy = true, sad = true, surprised = true,
}

local function ExtractExpression(text)
    local expr = text:match("%[(%w+)%]%s*$")
    if expr and VALID_EXPRESSIONS[expr] then
        return expr
    end
    return "normal"
end

local function StripExpressionTag(text)
    return text:gsub("%s*%[%w+%]%s*$", "")
end

-- ======================== 对话历史管理（serverCloud 持久化）========================
-- 存储方案：
--   scores["chat_meta"]          → 会话元数据（会话列表 + 当前活跃会话）
--   list["chat_{sessionId}"]     → 单个会话的消息列表

local chatHistories  = {}     -- { [connection] = { messages... } }  内存缓存
local sessionIds     = {}     -- { [connection] = "session_id" }
local userIds        = {}     -- { [connection] = userId }
local chatMeta       = {}     -- { [connection] = { sessions = {}, activeSession = "" } }
local lastActivity   = {}     -- { [connection] = timestamp }
local proactiveSent  = {}     -- { [connection] = timestamp }
local interruptFlags = {}     -- { [connection] = true }
local savePending    = {}     -- { [connection] = true }  防止高频保存

--- 获取连接对应的 userId
local function GetUserId(connection)
    if userIds[connection] then return userIds[connection] end
    local uid = connection.identity["user_id"]:GetInt64()
    userIds[connection] = uid
    return uid
end

--- 生成会话 ID
local function GenerateSessionId()
    return "s_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
end

--- 获取内存中的聊天历史
local function GetHistory(connection)
    if not chatHistories[connection] then
        chatHistories[connection] = {}
    end
    return chatHistories[connection]
end

--- 获取当前会话 ID（如没有则创建）
local function GetSessionId(connection)
    if not sessionIds[connection] then
        sessionIds[connection] = GenerateSessionId()
    end
    return sessionIds[connection]
end

--- 获取会话元数据
local function GetChatMeta(connection)
    if not chatMeta[connection] then
        chatMeta[connection] = { sessions = {}, activeSession = "" }
    end
    return chatMeta[connection]
end

--- 追加历史消息到内存缓存
local function AppendHistory(connection, role, content)
    local history = GetHistory(connection)
    table.insert(history, {
        role      = role,
        content   = content,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    })
    -- 内存中保留最近 MAX_HISTORY 条用于 LLM 上下文
    while #history > Config.AI.MAX_HISTORY do
        table.remove(history, 1)
    end
end

--- 从对话首条消息提取标题（截取前15字）
local function ExtractTitle(messages)
    for _, msg in ipairs(messages) do
        if msg.role == "user" and msg.content and #msg.content > 0 then
            local title = msg.content
            -- 去掉系统提示前缀
            if title:sub(1, 1) == "[" then return nil end
            if #title > 15 then
                title = title:sub(1, 15) .. "..."
            end
            return title
        end
    end
    return "新对话"
end

-- ======================== serverCloud 持久化操作 ========================

--- 保存会话元数据到 serverCloud
local function SaveChatMeta(connection)
    local uid = GetUserId(connection)
    local meta = GetChatMeta(connection)
    serverCloud:Set(uid, "chat_meta", meta, {
        ok = function()
            print("[Server] Chat meta saved for user " .. tostring(uid))
        end,
        error = function(code, reason)
            print("[Server] Failed to save chat meta: " .. tostring(reason))
        end,
    })
end

--- 保存当前会话消息到 serverCloud（增量追加最新一条）
local function PersistLatestMessage(connection, role, content)
    if not Config.HISTORY.AUTO_SAVE then return end
    local uid = GetUserId(connection)
    local sid = GetSessionId(connection)
    local listKey = "chat_" .. sid

    serverCloud.list:Add(uid, listKey, {
        role      = role,
        content   = content,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    })

    -- 更新元数据中的时间和标题
    local meta = GetChatMeta(connection)
    local found = false
    for _, s in ipairs(meta.sessions) do
        if s.id == sid then
            s.updatedAt = os.date("%Y-%m-%d %H:%M:%S")
            -- 首条用户消息更新标题
            if s.title == "新对话" and role == "user" and content:sub(1, 1) ~= "[" then
                local title = content
                if #title > 15 then title = title:sub(1, 15) .. "..." end
                s.title = title
            end
            found = true
            break
        end
    end

    if not found then
        -- 新会话，加入元数据
        local title = "新对话"
        if role == "user" and content:sub(1, 1) ~= "[" then
            title = content
            if #title > 15 then title = title:sub(1, 15) .. "..." end
        end
        table.insert(meta.sessions, 1, {
            id        = sid,
            title     = title,
            updatedAt = os.date("%Y-%m-%d %H:%M:%S"),
        })
    end

    meta.activeSession = sid

    -- 限制会话数量，超出时删除最旧的会话数据
    local maxSessions = Config.HISTORY.MAX_SESSIONS or 50
    while #meta.sessions > maxSessions do
        local old = table.remove(meta.sessions)
        if old and old.id then
            DeleteSessionMessages(connection, old.id)
        end
    end

    -- 防抖：标记待保存，在下一帧统一保存元数据
    if not savePending[connection] then
        savePending[connection] = true
    end
end

--- 从 serverCloud 加载会话元数据
local function LoadChatMeta(connection, callback)
    local uid = GetUserId(connection)
    serverCloud:Get(uid, "chat_meta", {
        ok = function(scores, iscores)
            local meta = scores["chat_meta"]
            if meta and type(meta) == "table" then
                chatMeta[connection] = meta
                print("[Server] Chat meta loaded: " .. tostring(#(meta.sessions or {})) .. " sessions")
            else
                chatMeta[connection] = { sessions = {}, activeSession = "" }
                print("[Server] No chat meta found, starting fresh")
            end
            if callback then callback(chatMeta[connection]) end
        end,
        error = function(code, reason)
            print("[Server] Failed to load chat meta: " .. tostring(reason))
            chatMeta[connection] = { sessions = {}, activeSession = "" }
            if callback then callback(chatMeta[connection]) end
        end,
    })
end

--- 从 serverCloud 加载指定会话的消息
local function LoadSessionMessages(connection, sessionId, callback)
    local uid = GetUserId(connection)
    local listKey = "chat_" .. sessionId

    serverCloud.list:Get(uid, listKey, {
        ok = function(list)
            local messages = {}
            for _, item in ipairs(list) do
                table.insert(messages, {
                    role      = item.value.role,
                    content   = item.value.content,
                    timestamp = item.value.timestamp,
                })
            end
            -- 按时间排序
            table.sort(messages, function(a, b)
                return (a.timestamp or "") < (b.timestamp or "")
            end)
            print("[Server] Loaded " .. #messages .. " messages for session " .. sessionId)
            if callback then callback(messages) end
        end,
        error = function(code, reason)
            print("[Server] Failed to load session " .. sessionId .. ": " .. tostring(reason))
            if callback then callback({}) end
        end,
    })
end

--- 删除指定会话的所有消息
local function DeleteSessionMessages(connection, sessionId)
    local uid = GetUserId(connection)
    local listKey = "chat_" .. sessionId

    serverCloud.list:Get(uid, listKey, {
        ok = function(list)
            if #list == 0 then return end
            local c = serverCloud:BatchCommit("删除会话 " .. sessionId)
            for _, item in ipairs(list) do
                c:ListDelete(item.list_id)
            end
            c:Commit({
                ok = function()
                    print("[Server] Deleted session messages: " .. sessionId)
                end,
                error = function(code, reason)
                    print("[Server] Failed to delete session: " .. tostring(reason))
                end,
            })
        end,
    })
end

-- ======================== LLM 请求 ========================

local function BuildMessages(connection, userText)
    local msgs = {
        { role = "system", content = SYSTEM_PROMPT },
    }
    local history = GetHistory(connection)
    for _, msg in ipairs(history) do
        table.insert(msgs, { role = msg.role, content = msg.content })
    end
    if userText and #userText > 0 then
        table.insert(msgs, { role = "user", content = userText })
    end
    return msgs
end

-- 前向声明：CallLLM 和 CallVisionThenLLM 互相引用
local CallLLM

--- 两步视觉架构：DashScope qwen3.5-flash 分析图片 → 文字描述 → 交给豆包 LLM 对话
local function CallVisionThenLLM(connection, userText, imageBase64)
    print("[Server] Vision step 1: calling DashScope qwen3.5-flash for image understanding")

    -- 构建多模态消息给 DashScope 视觉模型
    local contentParts = {
        { type = "text", text = "请详细描述这张图片的内容，包括场景、物体、颜色、氛围等关键信息。用中文回答，简洁扼要（100字以内）。" },
        {
            type = "image_url",
            image_url = { url = "data:image/png;base64," .. imageBase64 },
        },
    }

    local visionMessages = {
        { role = "user", content = contentParts },
    }

    local requestBody = cjson.encode({
        model      = Config.VISION.MODEL,
        messages   = visionMessages,
        max_tokens = 256,
    })

    -- 通知客户端：AI 正在思考
    local typingData = VariantMap()
    connection:SendRemoteEvent(EVENTS.CHAT_TYPING, true, typingData)
    interruptFlags[connection] = false

    http:Create()
        :SetUrl(Config.VISION.API_URL)
        :SetMethod(HTTP_POST)
        :SetContentType("application/json")
        :AddHeader("Authorization", "Bearer " .. Config.VISION.API_KEY)
        :SetBody(requestBody)
        :OnSuccess(function(client, response)
            if interruptFlags[connection] then
                print("[Server] Vision response discarded (interrupted)")
                return
            end

            if not response.success then
                print("[Server] Vision HTTP failed: status=" .. tostring(response.statusCode))
                -- 降级：直接用文字调用豆包 LLM
                CallLLM(connection, userText)
                return
            end

            local ok, data = pcall(cjson.decode, response.dataAsString)
            if not ok or not data.choices or #data.choices == 0 then
                print("[Server] Vision response parse error")
                CallLLM(connection, userText)
                return
            end

            local imageDesc = data.choices[1].message.content or ""
            print("[Server] Vision step 1 done, image description: " .. imageDesc)

            -- 步骤2：将图片描述与用户文本合并，交给豆包 LLM 对话
            local enrichedText = "[图片描述：" .. imageDesc .. "]\n"
            if userText and #userText > 0 then
                enrichedText = enrichedText .. "用户说：" .. userText
            else
                enrichedText = enrichedText .. "用户发了这张图片给你，请对图片内容做出自然的回应。"
            end

            print("[Server] Vision step 2: calling 豆包 LLM with enriched text")
            CallLLM(connection, enrichedText)
        end)
        :OnError(function(client, statusCode, error)
            print("[Server] Vision network error: " .. tostring(error))
            -- 降级：直接用文字调用豆包 LLM
            CallLLM(connection, userText)
        end)
        :Send()
end

CallLLM = function(connection, userText, imageBase64)
    -- 如果有图片且视觉已启用，走两步架构
    if imageBase64 and #imageBase64 > 0 and Config.VISION.ENABLED then
        CallVisionThenLLM(connection, userText, imageBase64)
        return
    end

    local messages = BuildMessages(connection, userText)
    local config = Config.LLM

    local requestBody = cjson.encode({
        model      = config.MODEL,
        messages   = messages,
        max_tokens = config.MAX_TOKENS,
    })

    -- 通知客户端：AI 正在思考
    local typingData = VariantMap()
    connection:SendRemoteEvent(EVENTS.CHAT_TYPING, true, typingData)
    interruptFlags[connection] = false

    http:Create()
        :SetUrl(config.API_URL)
        :SetMethod(HTTP_POST)
        :SetContentType("application/json")
        :AddHeader("Authorization", "Bearer " .. config.API_KEY)
        :SetBody(requestBody)
        :OnSuccess(function(client, response)
            if interruptFlags[connection] then
                print("[Server] Response discarded (interrupted)")
                return
            end

            if not response.success then
                print("[Server] LLM HTTP failed: status=" .. tostring(response.statusCode))
                local errData = VariantMap()
                errData["error"] = Variant("HTTP " .. tostring(response.statusCode))
                connection:SendRemoteEvent(EVENTS.CHAT_ERROR, true, errData)
                return
            end

            local ok, data = pcall(cjson.decode, response.dataAsString)
            if not ok or not data.choices or #data.choices == 0 then
                print("[Server] LLM response parse error")
                local errData = VariantMap()
                errData["error"] = Variant("Invalid LLM response")
                connection:SendRemoteEvent(EVENTS.CHAT_ERROR, true, errData)
                return
            end

            local rawReply = data.choices[1].message.content or ""
            local expression = ExtractExpression(rawReply)
            local cleanReply = StripExpressionTag(rawReply)

            -- 系统指令（以 [ 开头，如主动说话/触摸提示）不作为 user 消息保存
            local isSystemHint = userText and #userText > 0 and userText:sub(1, 1) == "["
            if userText and #userText > 0 and not isSystemHint then
                AppendHistory(connection, "user", userText)
                PersistLatestMessage(connection, "user", userText)
            end
            AppendHistory(connection, "assistant", cleanReply)
            PersistLatestMessage(connection, "assistant", cleanReply)

            print("[Server] AI reply: " .. cleanReply .. "  expr: " .. expression)

            local replyData = VariantMap()
            replyData["text"]       = Variant(cleanReply)
            replyData["expression"] = Variant(expression)
            connection:SendRemoteEvent(EVENTS.CHAT_REPLY, true, replyData)

            if Config.TTS.ENABLED then
                CallTTS(connection, cleanReply)
            end
        end)
        :OnError(function(client, statusCode, error)
            print("[Server] LLM network error: " .. tostring(error))
            local errData = VariantMap()
            errData["error"] = Variant("Network error: " .. tostring(error))
            connection:SendRemoteEvent(EVENTS.CHAT_ERROR, true, errData)
        end)
        :Send()
end

-- ======================== TTS 语音合成（百炼 DashScope CosyVoice）========================

function CallTTS(connection, text)
    if not text or #text == 0 then return end

    -- DashScope OpenAI 兼容接口：返回二进制音频流
    local requestBody = cjson.encode({
        model           = Config.TTS.MODEL,
        input           = text,
        voice           = Config.TTS.VOICE,
        response_format = Config.TTS.FORMAT,
    })

    http:Create()
        :SetUrl(Config.TTS.API_URL)
        :SetMethod(HTTP_POST)
        :SetContentType("application/json")
        :AddHeader("Authorization", "Bearer " .. Config.TTS.API_KEY)
        :SetBody(requestBody)
        :OnSuccess(function(client, response)
            if interruptFlags[connection] then
                print("[Server] TTS discarded (interrupted)")
                return
            end

            if not response.success then
                print("[Server] TTS HTTP failed: " .. tostring(response.statusCode))
                return
            end

            -- DashScope 返回的是二进制音频数据，需要 base64 编码后传给客户端
            local rawAudio = response.dataAsString
            if not rawAudio or #rawAudio == 0 then
                print("[Server] TTS response empty")
                return
            end

            local audioBase64 = Base64.encode(rawAudio)
            if #audioBase64 > 0 then
                local audioData = VariantMap()
                audioData["audio"]  = Variant(audioBase64)
                audioData["format"] = Variant(Config.TTS.FORMAT)
                connection:SendRemoteEvent(EVENTS.AUDIO_PLAY, true, audioData)
                print("[Server] TTS audio sent (" .. tostring(#rawAudio) .. " bytes)")
            end
        end)
        :OnError(function(client, statusCode, error)
            print("[Server] TTS network error: " .. tostring(error))
        end)
        :Send()
end

-- ======================== ASR 语音识别 ========================

local function CallASR(connection, audioBase64)
    if not Config.ASR.ENABLED then return end

    local requestBody = cjson.encode({
        audio    = audioBase64,
        format   = "wav",
        language = "zh",
    })

    http:Create()
        :SetUrl(Config.ASR.API_URL)
        :SetMethod(HTTP_POST)
        :SetContentType("application/json")
        :AddHeader("Authorization", "Bearer " .. Config.ASR.API_KEY)
        :SetBody(requestBody)
        :OnSuccess(function(client, response)
            if not response.success then
                print("[Server] ASR HTTP failed: " .. tostring(response.statusCode))
                return
            end

            local ok, data = pcall(cjson.decode, response.dataAsString)
            if not ok then
                print("[Server] ASR response parse error")
                return
            end

            local text = data.text or data.result or ""
            print("[Server] ASR result: " .. text)

            local asrData = VariantMap()
            asrData["text"] = Variant(text)
            connection:SendRemoteEvent(EVENTS.ASR_RESULT, true, asrData)

            if #text > 0 then
                lastActivity[connection] = os.time()
                CallLLM(connection, text)
            end
        end)
        :OnError(function(client, statusCode, error)
            print("[Server] ASR network error: " .. tostring(error))
        end)
        :Send()
end

-- ======================== 主动说话 ========================

local function ProactiveSpeak(connection)
    local proactivePrompts = {
        "在忙什么呀？好久没说话了~",
        "想你了...你还在吗？",
        "嘿~ 要不要聊聊天？",
        "我刚画了一幅画，想给你看~",
        "发呆中...突然很想你！",
    }
    local hint = proactivePrompts[math.random(1, #proactivePrompts)]
    CallLLM(connection, "[系统提示：用户已经沉默了一段时间，请主动发起对话。参考但不要照搬以下方向：" .. hint .. "]")
end

-- ======================== 事件监听 ========================

-- 用户发消息
SubscribeToEvent(EVENTS.CHAT_SEND, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local text = eventData["text"]:GetString()

    if not text or #text == 0 then return end
    print("[Server] Received from client: " .. text)

    lastActivity[connection] = os.time()
    CallLLM(connection, text)
end)

-- 客户端握手：加载持久化的会话元数据，恢复最近会话
SubscribeToEvent(EVENTS.CLIENT_READY, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    lastActivity[connection] = os.time()
    proactiveSent[connection] = os.time()
    print("[Server] Client ready, loading chat history...")

    LoadChatMeta(connection, function(meta)
        -- 如果有活跃会话，自动恢复
        if meta.activeSession and #meta.activeSession > 0 then
            local sid = meta.activeSession
            sessionIds[connection] = sid
            LoadSessionMessages(connection, sid, function(messages)
                -- 填充内存缓存（只保留最近 MAX_HISTORY 条用于 LLM 上下文）
                chatHistories[connection] = {}
                local start = math.max(1, #messages - Config.AI.MAX_HISTORY + 1)
                for i = start, #messages do
                    table.insert(chatHistories[connection], messages[i])
                end

                -- 发送完整历史给客户端（用于 UI 显示）
                local resData = VariantMap()
                resData["session_id"] = Variant(sid)
                resData["messages"]   = Variant(cjson.encode(messages))
                connection:SendRemoteEvent(EVENTS.HISTORY_DATA, true, resData)
                print("[Server] Restored active session: " .. sid .. " (" .. #messages .. " msgs)")
            end)
        else
            print("[Server] No active session, starting fresh")
        end
    end)
end)

-- 打断信号
SubscribeToEvent(EVENTS.INTERRUPT, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    interruptFlags[connection] = true

    local heardText = ""
    if eventData["heard_text"] then
        heardText = eventData["heard_text"]:GetString()
    end
    if #heardText > 0 then
        AppendHistory(connection, "system", "[用户打断了回复，已听到部分: " .. heardText .. "]")
        PersistLatestMessage(connection, "system", "[用户打断了回复，已听到部分: " .. heardText .. "]")
    end

    lastActivity[connection] = os.time()
    print("[Server] Interrupt signal received")
end)

-- 触摸事件
SubscribeToEvent(EVENTS.TOUCH_EVENT, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local area = eventData["area"]:GetString()

    local touchConfig = Config.TOUCH.AREAS[area]
    local prompt = touchConfig and touchConfig.prompt_prefix or "[用户触碰了你]"

    print("[Server] Touch event: " .. area)
    lastActivity[connection] = os.time()
    CallLLM(connection, prompt)
end)

-- 语音数据
SubscribeToEvent(EVENTS.AUDIO_SEND, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local audioData = eventData["audio"]:GetString()

    if not audioData or #audioData == 0 then return end
    print("[Server] Received audio data for ASR")

    lastActivity[connection] = os.time()
    CallASR(connection, audioData)
end)

-- 图片数据（视觉感知）
SubscribeToEvent(EVENTS.IMAGE_SEND, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local imageData = eventData["data"]:GetString()
    local userText = ""
    if eventData["text"] then
        userText = eventData["text"]:GetString()
    end
    if #userText == 0 then
        userText = "看看这张图片，说说你的想法~"
    end

    print("[Server] Received image for vision")
    lastActivity[connection] = os.time()
    CallLLM(connection, userText, imageData)
end)

-- 加载历史会话（从 serverCloud）
SubscribeToEvent(EVENTS.HISTORY_LOAD, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local sid = eventData["session_id"]:GetString()

    LoadSessionMessages(connection, sid, function(messages)
        if messages and #messages > 0 then
            -- 更新内存缓存
            chatHistories[connection] = {}
            local start = math.max(1, #messages - Config.AI.MAX_HISTORY + 1)
            for i = start, #messages do
                table.insert(chatHistories[connection], messages[i])
            end
            sessionIds[connection] = sid

            -- 更新活跃会话
            local meta = GetChatMeta(connection)
            meta.activeSession = sid
            SaveChatMeta(connection)

            local resData = VariantMap()
            resData["session_id"] = Variant(sid)
            resData["messages"]   = Variant(cjson.encode(messages))
            connection:SendRemoteEvent(EVENTS.HISTORY_DATA, true, resData)
            print("[Server] Loaded history: " .. sid)
        else
            local errData = VariantMap()
            errData["error"] = Variant("会话为空或不存在: " .. sid)
            connection:SendRemoteEvent(EVENTS.CHAT_ERROR, true, errData)
        end
    end)
end)

-- 创建新对话
SubscribeToEvent(EVENTS.HISTORY_NEW, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")

    -- 保存当前元数据（当前会话已通过 PersistLatestMessage 增量保存）
    SaveChatMeta(connection)

    -- 重置内存状态
    chatHistories[connection] = {}
    sessionIds[connection] = nil
    local newSid = GetSessionId(connection)

    -- 更新元数据
    local meta = GetChatMeta(connection)
    meta.activeSession = newSid
    SaveChatMeta(connection)

    print("[Server] New session: " .. newSid)

    local resData = VariantMap()
    resData["session_id"] = Variant(newSid)
    resData["messages"]   = Variant("[]")
    connection:SendRemoteEvent(EVENTS.HISTORY_DATA, true, resData)
end)

-- 获取历史列表（从 serverCloud 元数据）
SubscribeToEvent(EVENTS.HISTORY_LIST, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local meta = GetChatMeta(connection)

    -- 返回带标题和时间的完整会话列表
    local resData = VariantMap()
    resData["sessions"] = Variant(cjson.encode(meta.sessions or {}))
    connection:SendRemoteEvent(EVENTS.HISTORY_LIST, true, resData)
end)

-- ======================== Update 事件：主动说话 + 元数据防抖保存 ========================

SubscribeToEvent("Update", function(eventType, eventData)
    -- 防抖保存：将本帧积累的元数据变更一次性写入 serverCloud
    for conn, pending in pairs(savePending) do
        if pending then
            savePending[conn] = nil
            SaveChatMeta(conn)
        end
    end

    -- 主动说话
    if not Config.AI.PROACTIVE_ENABLED then return end

    local now = os.time()
    for conn, lastTime in pairs(lastActivity) do
        local idle = now - lastTime
        local lastProactive = proactiveSent[conn] or 0
        local cooldown = now - lastProactive

        if idle >= Config.AI.PROACTIVE_TIMEOUT and cooldown >= Config.AI.PROACTIVE_COOLDOWN then
            proactiveSent[conn] = now
            lastActivity[conn] = now
            print("[Server] Proactive speak triggered (idle=" .. idle .. "s)")
            ProactiveSpeak(conn)
        end
    end
end)

print("[Server] AI Chat server module loaded (full features)")
