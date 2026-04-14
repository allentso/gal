-- ============================================================================
-- Server.lua — 服务端：LLM + TTS + ASR + 记忆持久化 + 主动说话 + 触摸 + 视觉
-- ============================================================================

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

-- ======================== 对话历史管理 ========================

local chatHistories = {}     -- { [connection] = { messages... } }
local sessionIds    = {}     -- { [connection] = "session_id" }
local lastActivity  = {}     -- { [connection] = timestamp }
local proactiveSent = {}     -- { [connection] = timestamp }
local interruptFlags = {}    -- { [connection] = true }

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

-- ======================== 持久化：SaveHistory / LoadHistory ========================

local function EnsureDir(path)
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
end

local function GetSessionId(connection)
    if not sessionIds[connection] then
        sessionIds[connection] = "session_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    end
    return sessionIds[connection]
end

local function GetHistoryPath(sessionId)
    return Config.HISTORY.SAVE_DIR .. "/" .. sessionId .. ".json"
end

local function SaveHistory(connection)
    if not Config.HISTORY.AUTO_SAVE then return end

    local sid = GetSessionId(connection)
    local history = GetHistory(connection)

    EnsureDir(Config.HISTORY.SAVE_DIR)

    local data = cjson.encode({
        session_id = sid,
        updated_at = os.date("%Y-%m-%d %H:%M:%S"),
        messages   = history,
    })

    local f = io.open(GetHistoryPath(sid), "w")
    if f then
        f:write(data)
        f:close()
        print("[Server] History saved: " .. sid)
    else
        print("[Server] Failed to save history: " .. sid)
    end
end

local function LoadHistory(sessionId)
    local path = GetHistoryPath(sessionId)
    local f = io.open(path, "r")
    if not f then return nil end

    local raw = f:read("*a")
    f:close()

    local ok, data = pcall(cjson.decode, raw)
    if ok and data and data.messages then
        return data.messages
    end
    return nil
end

local function ListHistories()
    local list = {}
    local dir = Config.HISTORY.SAVE_DIR
    local handle = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul')
    if handle then
        for line in handle:lines() do
            local sid = line:match("^(.+)%.json$")
            if sid then
                table.insert(list, sid)
            end
        end
        handle:close()
    end
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

    connection:SendRemoteEvent(EVENTS.CHAT_TYPING, true, {})
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
                connection:SendRemoteEvent(EVENTS.CHAT_ERROR, true, {
                    error = "HTTP " .. tostring(response.statusCode),
                })
                return
            end

            local ok, data = pcall(cjson.decode, response.dataAsString)
            if not ok or not data.choices or #data.choices == 0 then
                print("[Server] LLM response parse error")
                connection:SendRemoteEvent(EVENTS.CHAT_ERROR, true, {
                    error = "Invalid LLM response",
                })
                return
            end

            local rawReply = data.choices[1].message.content or ""
            local expression = ExtractExpression(rawReply)
            local cleanReply = StripExpressionTag(rawReply)

            if userText and #userText > 0 then
                AppendHistory(connection, "user", userText)
            end
            AppendHistory(connection, "assistant", cleanReply)
            SaveHistory(connection)

            print("[Server] AI reply: " .. cleanReply .. "  expr: " .. expression)

            connection:SendRemoteEvent(EVENTS.CHAT_REPLY, true, {
                text       = cleanReply,
                expression = expression,
            })

            if Config.TTS.ENABLED then
                CallTTS(connection, cleanReply)
            end
        end)
        :OnError(function(client, statusCode, error)
            print("[Server] LLM network error: " .. tostring(error))
            connection:SendRemoteEvent(EVENTS.CHAT_ERROR, true, {
                error = "Network error: " .. tostring(error),
            })
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
                connection:SendRemoteEvent(EVENTS.AUDIO_PLAY, true, {
                    audio  = audioBase64,
                    format = Config.TTS.FORMAT,
                })
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

            connection:SendRemoteEvent(EVENTS.ASR_RESULT, true, {
                text = text,
            })

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
    connection.scene = scene_
    lastActivity[connection] = os.time()
    proactiveSent[connection] = os.time()
    print("[Server] Client ready, scene assigned")
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
        SaveHistory(connection)
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

-- 历史操作
SubscribeToEvent(EVENTS.HISTORY_LOAD, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local sid = eventData["session_id"]:GetString()

    local messages = LoadHistory(sid)
    if messages then
        chatHistories[connection] = messages
        sessionIds[connection] = sid
        print("[Server] Loaded history: " .. sid)
        connection:SendRemoteEvent(EVENTS.HISTORY_DATA, true, {
            session_id = sid,
            messages   = cjson.encode(messages),
        })
    else
        connection:SendRemoteEvent(EVENTS.CHAT_ERROR, true, {
            error = "History not found: " .. sid,
        })
    end
end)

SubscribeToEvent(EVENTS.HISTORY_NEW, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    SaveHistory(connection)
    chatHistories[connection] = {}
    sessionIds[connection] = nil
    local newSid = GetSessionId(connection)
    print("[Server] New session: " .. newSid)

    connection:SendRemoteEvent(EVENTS.HISTORY_DATA, true, {
        session_id = newSid,
        messages   = "[]",
    })
end)

SubscribeToEvent(EVENTS.HISTORY_LIST, function(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local list = ListHistories()
    connection:SendRemoteEvent(EVENTS.HISTORY_LIST, true, {
        sessions = cjson.encode(list),
    })
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
