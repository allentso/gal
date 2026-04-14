-- ============================================================================
-- Client.lua — 客户端网络模块：聊天收发 + TTS 播放 + ASR + 打断 + 触摸 + 视觉
-- ============================================================================

local ClientNet = {}

-- ======================== 回调函数（由 main.lua 注册）========================

ClientNet.onReply       = nil   -- function(text, expression)
ClientNet.onTyping      = nil   -- function()
ClientNet.onError       = nil   -- function(errorMsg)
ClientNet.onAudioPlay   = nil   -- function(audioBase64, format)
ClientNet.onASRResult   = nil   -- function(text)
ClientNet.onHistoryList = nil   -- function(sessions)  -- sessions: table
ClientNet.onHistoryData = nil   -- function(sessionId, messages) -- messages: table

local connected_ = false

-- ======================== 发送：聊天消息 ========================

function ClientNet.SendChat(text)
    if not text or #text == 0 then return end
    if not connected_ then
        print("[Client] Not connected to server, cannot send")
        if ClientNet.onError then ClientNet.onError("未连接到服务器") end
        return
    end
    network:SendRemoteEvent(EVENTS.CHAT_SEND, true, { text = text })
    print("[Client] Sent to server: " .. text)
end

-- ======================== 发送：打断信号 ========================

function ClientNet.SendInterrupt(heardText)
    if not connected_ then return end
    network:SendRemoteEvent(EVENTS.INTERRUPT, true, {
        heard_text = heardText or "",
    })
    print("[Client] Interrupt sent")
end

-- ======================== 发送：触摸事件 ========================

function ClientNet.SendTouch(area)
    if not connected_ then return end
    network:SendRemoteEvent(EVENTS.TOUCH_EVENT, true, { area = area })
    print("[Client] Touch sent: " .. area)
end

-- ======================== 发送：语音数据 ========================

function ClientNet.SendAudio(audioBase64)
    if not connected_ then return end
    if not audioBase64 or #audioBase64 == 0 then return end
    network:SendRemoteEvent(EVENTS.AUDIO_SEND, true, { audio = audioBase64 })
    print("[Client] Audio sent for ASR")
end

-- ======================== 发送：图片数据 ========================

function ClientNet.SendImage(imageBase64, text)
    if not connected_ then return end
    if not imageBase64 or #imageBase64 == 0 then return end
    network:SendRemoteEvent(EVENTS.IMAGE_SEND, true, {
        data = imageBase64,
        text = text or "",
    })
    print("[Client] Image sent for vision")
end

-- ======================== 发送：历史操作 ========================

function ClientNet.RequestHistoryList()
    if not connected_ then return end
    network:SendRemoteEvent(EVENTS.HISTORY_LIST, true, {})
end

function ClientNet.LoadHistory(sessionId)
    if not connected_ then return end
    network:SendRemoteEvent(EVENTS.HISTORY_LOAD, true, { session_id = sessionId })
end

function ClientNet.NewHistory()
    if not connected_ then return end
    network:SendRemoteEvent(EVENTS.HISTORY_NEW, true, {})
end

-- ======================== 接收事件 ========================

SubscribeToEvent(EVENTS.CHAT_REPLY, function(eventType, eventData)
    local text = eventData["text"]:GetString()
    local expression = eventData["expression"]:GetString()
    print("[Client] AI reply: " .. text .. "  expr: " .. expression)
    if ClientNet.onReply then ClientNet.onReply(text, expression) end
end)

SubscribeToEvent(EVENTS.CHAT_TYPING, function(eventType, eventData)
    print("[Client] AI is thinking...")
    if ClientNet.onTyping then ClientNet.onTyping() end
end)

SubscribeToEvent(EVENTS.CHAT_ERROR, function(eventType, eventData)
    local err = eventData["error"]:GetString()
    print("[Client] Error: " .. err)
    if ClientNet.onError then ClientNet.onError(err) end
end)

SubscribeToEvent(EVENTS.AUDIO_PLAY, function(eventType, eventData)
    local audioData = eventData["audio"]:GetString()
    local format = eventData["format"]:GetString()
    print("[Client] TTS audio received (" .. format .. ")")
    if ClientNet.onAudioPlay then ClientNet.onAudioPlay(audioData, format) end
end)

SubscribeToEvent(EVENTS.ASR_RESULT, function(eventType, eventData)
    local text = eventData["text"]:GetString()
    print("[Client] ASR result: " .. text)
    if ClientNet.onASRResult then ClientNet.onASRResult(text) end
end)

SubscribeToEvent(EVENTS.HISTORY_LIST, function(eventType, eventData)
    local raw = eventData["sessions"]:GetString()
    local ok, sessions = pcall(cjson.decode, raw)
    if ok and ClientNet.onHistoryList then
        ClientNet.onHistoryList(sessions)
    end
end)

SubscribeToEvent(EVENTS.HISTORY_DATA, function(eventType, eventData)
    local sid = eventData["session_id"]:GetString()
    local raw = eventData["messages"]:GetString()
    local ok, messages = pcall(cjson.decode, raw)
    if ok and ClientNet.onHistoryData then
        ClientNet.onHistoryData(sid, messages)
    end
end)

-- ======================== 连接管理 ========================

function ClientNet.Init()
    if network.serverRunning then
        connected_ = true
        print("[Client] Running in same process as server, connected")
        return
    end

    SubscribeToEvent("ServerConnected", function()
        connected_ = true
        print("[Client] Connected to server")
        network:SendRemoteEvent(EVENTS.CLIENT_READY, true, {})
    end)

    SubscribeToEvent("ServerDisconnected", function()
        connected_ = false
        print("[Client] Disconnected from server")
    end)
end

function ClientNet.IsConnected()
    return connected_
end

print("[Client] AI Chat client module loaded (full features)")

return ClientNet
