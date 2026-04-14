-- ============================================================================
-- Shared.lua — 客户端与服务端共享的事件名定义
-- ============================================================================

EVENTS = {
    -- 聊天核心
    CHAT_SEND       = "ChatSend",        -- Client → Server: 发送用户消息
    CHAT_REPLY      = "ChatReply",       -- Server → Client: AI 回复（text + expression）
    CHAT_TYPING     = "ChatTyping",      -- Server → Client: AI 正在思考
    CHAT_ERROR      = "ChatError",       -- Server → Client: 请求失败
    CLIENT_READY    = "ClientReady",     -- Client → Server: 握手

    -- TTS 语音合成
    AUDIO_PLAY      = "AudioPlay",       -- Server → Client: TTS 音频数据
    AUDIO_DONE      = "AudioDone",       -- Client → Server: 音频播放完毕

    -- ASR 语音识别
    AUDIO_SEND      = "AudioSend",       -- Client → Server: 麦克风录音数据
    ASR_RESULT      = "ASRResult",       -- Server → Client: 识别出的文字

    -- 打断
    INTERRUPT       = "InterruptSignal", -- Client → Server: 打断当前回复

    -- 触摸互动
    TOUCH_EVENT     = "TouchEvent",      -- Client → Server: 触摸角色

    -- 视觉感知
    IMAGE_SEND      = "ImageSend",       -- Client → Server: 截图/图片数据

    -- 对话历史
    HISTORY_LIST    = "HistoryList",     -- Server → Client: 历史列表
    HISTORY_LOAD    = "HistoryLoad",     -- Client → Server: 加载指定历史
    HISTORY_NEW     = "HistoryNew",      -- Client → Server: 创建新对话
    HISTORY_DATA    = "HistoryData",     -- Server → Client: 历史消息数据
}

for _, name in pairs(EVENTS) do
    network:RegisterRemoteEvent(name)
end
