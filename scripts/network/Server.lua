---@diagnostic disable: undefined-global
-- ============================================================================
-- Server.lua — 服务端：LLM + TTS + ASR + 对话记忆 + 主动说话 + 触摸 + 视觉
-- ============================================================================
-- 注意：服务端模式下 File API 完全屏蔽，对话历史仅在内存中维护。
--       如需持久化，请使用 serverCloud API。

local Config = require("config")

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

-- ======================== 对话历史管理（纯内存）========================
-- 服务端模式下 File API 被完全屏蔽，因此不做文件持久化。
-- 如需跨会话持久化，请改用 serverCloud API。

local chatHistories  = {}     -- { [connection] = { messages... } }
local sessionIds     = {}     -- { [connection] = "session_id" }
local lastActivity   = {}     -- { [connection] = timestamp }
local proactiveSent  = {}     -- { [connection] = timestamp }
local interruptFlags = {}     -- { [connection] = true }

-- 存储所有会话（内存中）
local allSessions    = {}     -- { [sessionId] = { messages... } }

local function GetHistory(connection)
    if not chatHistories[connection] then
        chatHistories[connection] = {}
    end
    return chatHistories[connection]
end

local function AppendHistory(connection, role, content)
    local history = GetHistory(connection)
    table.insert(history, {
        role      = role,
        content   = content,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    })
    while #history > Config.AI.MAX_HISTORY do
        table.remove(history, 1)
    end
end

-- ======================== 会话管理（内存版）========================

local function GetSessionId(connection)
    if not sessionIds[connection] then
        sessionIds[connection] = "session_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    end
    return sessionIds[connection]
end

local function SaveSessionToMemory(connection)
    if not Config.HISTORY.AUTO_SAVE then return end
    local sid = GetSessionId(connection)
    local history = GetHistory(connection)

    -- 深拷贝到 allSessions
    local copy = {}
    for _, msg in ipairs(history) do
        table.insert(copy, {
            role      = msg.role,
            content   = msg.content,
            timestamp = msg.timestamp,
        })
    end
    allSessions[sid] = copy
    print("[Server] Session saved to memory: " .. sid)
end

local function LoadSessionFromMemory(sessionId)
    return allSessions[sessionId]
end

local function ListAllSessions()
    local list = {}
    for sid, _ in pairs(allSessions) do
        table.insert(list, sid)
    end
    table.sort(list)
    return list
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

local function BuildMultimodalMessages(connection, userText, imageBase64)
    local msgs = {
        { role = "system", content = SYSTEM_PROMPT },
    }
    local history = GetHistory(connection)
    for _, msg in ipairs(history) do
        table.insert(msgs, { role = msg.role, content = msg.content })
    end
    local contentParts = {}
    if userText and #userText > 0 then
        table.insert(contentParts, { type = "text", text = userText })
    end
    if imageBase64 and #imageBase64 > 0 then
        table.insert(contentParts, {
            type = "image_url",
            image_url = { url = "data:image/png;base64," .. imageBase64 },
        })
    end
    table.insert(msgs, { role = "user", content = contentParts })
    return msgs
end

local function CallLLM(connection, userText, imageBase64)
    local messages
    local config = Config.LLM
    local model  = config.MODEL
    local apiUrl = config.API_URL
    local apiKey = config.API_KEY

    if imageBase64 and #imageBase64 > 0 and Config.VISION.ENABLED then
        messages = BuildMultimodalMessages(connection, userText, imageBase64)
        apiUrl = Config.VISION.API_URL
        apiKey = Config.VISION.API_KEY
        model  = Config.VISION.MODEL
    else
        messages = BuildMessages(connection, userText)
    end

    local requestBody = cjson.encode({
        model      = model,
        messages   = messages,
        max_tokens = config.MAX_TOKENS,
    })

    -- 通知客户端：AI 正在思考
    local typingData = VariantMap()
    connection:SendRemoteEvent(EVENTS.CHAT_TYPING, true, typingData)
    interruptFlags[connection] = false

    http:Create()
        :SetUrl(apiUrl)
        :SetMethod(HTTP_POST)
        :SetContentType("application/json")
        :AddHeader("Authorization", "Bearer " .. apiKey)
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

            if userText and #userText > 0 then
                AppendHistory(connection, "user", userText)
            end
            AppendHistory(connection, "assistant", cleanReply)
            SaveSessionToMemory(connection)

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

-- ======================== TTS 语音合成 ========================

function CallTTS(connection, text)
    if not text or #text == 0 then return end

    local requestBody = cjson.encode({
        text     = text,
        voice    = Config.TTS.VOICE,
        format   = Config.TTS.FORMAT,
        encoding = "base64",
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

            local ok, data = pcall(cjson.decode, response.dataAsString)
            if not ok then
                print("[Server] TTS response parse error")
                return
            end

            local audioBase64 = data.audio or data.data or ""
            if #audioBase64 > 0 then
                local audioData = VariantMap()
                audioData["audio"]  = Variant(audioBase64)
                audioData["format"] = Variant(Config.TTS.FORMAT)
                connection:SendRemoteEvent(EVENTS.AUDIO_PLAY, true, audioData)
                print("[Server] TTS audio sent to client")
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

-- 客户端握手
SubscribeToEvent(EVENTS.CLIENT_READY, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    lastActivity[connection] = os.time()
    proactiveSent[connection] = os.time()
    print("[Server] Client ready")
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
        SaveSessionToMemory(connection)
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

-- 加载历史会话
SubscribeToEvent(EVENTS.HISTORY_LOAD, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local sid = eventData["session_id"]:GetString()

    local messages = LoadSessionFromMemory(sid)
    if messages then
        chatHistories[connection] = messages
        sessionIds[connection] = sid
        print("[Server] Loaded history: " .. sid)

        local resData = VariantMap()
        resData["session_id"] = Variant(sid)
        resData["messages"]   = Variant(cjson.encode(messages))
        connection:SendRemoteEvent(EVENTS.HISTORY_DATA, true, resData)
    else
        local errData = VariantMap()
        errData["error"] = Variant("History not found: " .. sid)
        connection:SendRemoteEvent(EVENTS.CHAT_ERROR, true, errData)
    end
end)

-- 创建新对话
SubscribeToEvent(EVENTS.HISTORY_NEW, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")

    -- 保存当前会话
    SaveSessionToMemory(connection)

    -- 重置
    chatHistories[connection] = {}
    sessionIds[connection] = nil
    local newSid = GetSessionId(connection)
    print("[Server] New session: " .. newSid)

    local resData = VariantMap()
    resData["session_id"] = Variant(newSid)
    resData["messages"]   = Variant("[]")
    connection:SendRemoteEvent(EVENTS.HISTORY_DATA, true, resData)
end)

-- 获取历史列表
SubscribeToEvent(EVENTS.HISTORY_LIST, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local list = ListAllSessions()

    local resData = VariantMap()
    resData["sessions"] = Variant(cjson.encode(list))
    connection:SendRemoteEvent(EVENTS.HISTORY_LIST, true, resData)
end)

-- ======================== 主动说话定时器（Update 事件）========================

SubscribeToEvent("Update", function(eventType, eventData)
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
