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

    -- ==================== TTS 语音合成（百炼 DashScope CosyVoice）====================
    TTS = {
        ENABLED  = false,
        API_URL  = "https://dashscope.aliyuncs.com/compatible-mode/v1/audio/speech",
        API_KEY  = "sk-37f1402d9b4f46eeb3487a0227398a09",
        MODEL    = "cosyvoice-v3.5-flash",
        VOICE    = "Maia",
        FORMAT   = "wav",  -- wav / mp3 / pcm / opus
    },

    -- ==================== ASR 语音识别 ====================
    ASR = {
        ENABLED  = false,
        API_URL  = "https://openspeech.bytedance.com/api/v1/asr",
        API_KEY  = "YOUR_ASR_API_KEY_HERE",
    },

    -- ==================== 视觉模型（DashScope qwen3.5-flash 图片理解）====================
    -- 两步架构：DashScope 分析图片 → 文字描述 → 交给豆包 LLM 对话
    VISION = {
        ENABLED  = true,
        API_URL  = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        API_KEY  = "sk-37f1402d9b4f46eeb3487a0227398a09",
        MODEL    = "qwen3.5-flash",
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

    -- ==================== 历史持久化（serverCloud）====================
    HISTORY = {
        AUTO_SAVE    = true,       -- 自动持久化到 serverCloud
        MAX_SESSIONS = 50,         -- 保留最近 N 个会话的元数据
    },
}
