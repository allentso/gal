-- ============================================================================
-- config.lua — 所有 API 与功能配置集中管理
-- ============================================================================

return {
    -- ==================== LLM 大语言模型 ====================
    LLM = {
        API_URL    = "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
        API_KEY    = "44738533-488b-49a2-86a2-5d5f06968699",
        MODEL      = "ep-20260413224319-t7qkj",
        MAX_TOKENS = 512,
    },

    -- ==================== TTS 语音合成 ====================
    TTS = {
        ENABLED  = false,
        API_URL  = "https://openspeech.bytedance.com/api/v1/tts",
        API_KEY  = "YOUR_TTS_API_KEY_HERE",
        VOICE    = "zh_female_cancan",
        FORMAT   = "wav",  -- wav / ogg (Urho3D 支持的格式)
    },

    -- ==================== ASR 语音识别 ====================
    ASR = {
        ENABLED  = false,
        API_URL  = "https://openspeech.bytedance.com/api/v1/asr",
        API_KEY  = "YOUR_ASR_API_KEY_HERE",
    },

    -- ==================== 视觉模型（多模态 LLM）====================
    VISION = {
        ENABLED  = false,
        API_URL  = "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
        API_KEY  = "YOUR_API_KEY_HERE",
        MODEL    = "YOUR_VISION_MODEL_ID_HERE",
    },

    -- ==================== AI 行为 ====================
    AI = {
        MAX_HISTORY         = 20,
        PROACTIVE_ENABLED   = true,
        PROACTIVE_TIMEOUT   = 60,    -- 用户沉默多少秒后 AI 主动说话
        PROACTIVE_COOLDOWN  = 120,   -- 主动说话后至少间隔多少秒再次触发
        EXPR_REVERT_DELAY   = 5.0,   -- 表情切换后多少秒回归 normal
    },

    -- ==================== 角色 ====================
    CHARACTER = {
        NAME   = "小雪",
        AGE    = "20",
        SIGN   = "天秤座",
        HOBBY  = "画画、听音乐、看日落",
        BIO    = "喜欢安静的午后，和你在一起的每一刻都是最好的时光。",
        AVATAR = "image/girlfriend_avatar_20260413152437.png",
    },

    -- ==================== 触摸互动 ====================
    TOUCH = {
        ENABLED = true,
        AREAS = {
            head = { label = "头部", prompt_prefix = "[用户摸了摸你的头]" },
            face = { label = "脸颊", prompt_prefix = "[用户戳了戳你的脸]" },
            body = { label = "身体", prompt_prefix = "[用户拍了拍你的肩]" },
        },
    },

    -- ==================== 历史持久化 ====================
    HISTORY = {
        SAVE_DIR    = "data/chat_history",
        AUTO_SAVE   = true,
    },
}
