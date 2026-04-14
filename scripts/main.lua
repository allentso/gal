-- ============================================================================
-- AI 女友 — 视觉小说风格 · 仿 Live2D 角色动画
-- 功能: LLM 对话 · TTS 语音 · ASR 语音输入 · 对话记忆 · 打断机制
--       LLM 驱动表情 · AI 主动说话 · 触摸互动 · 视觉感知（截图）
-- ============================================================================

local UI = require("urhox-libs/UI")

require("network/Shared")
local ClientNet = require("network/Client")
local Config    = require("config")

local AI_ENABLED = true

-- ============================================================================
-- 1. 角色与表情配置
-- ============================================================================

local GF = Config.CHARACTER

local EXPR_IMAGES = {
    normal    = "image/gf_normal_20260413153652.png",
    happy     = "image/gf_happy_20260413153548.png",
    shy       = "image/gf_shy_20260413153559.png",
    sad       = "image/gf_sad_20260413153546.png",
    surprised = "image/gf_surprised_20260413153810.png",
}

local BG_IMAGE = "image/scene_bg_20260413153659.png"

local EXPR_PARTICLES = {
    happy     = { emoji = "✨", count = 5 },
    shy       = { emoji = "❤️", count = 4 },
    love      = { emoji = "💕", count = 6 },
    sad       = { emoji = "💧", count = 3 },
    surprised = { emoji = "❗", count = 3 },
}

-- ============================================================================
-- 2. 本地回复系统（离线 fallback）
-- ============================================================================

local REPLY_POOL = {
    greeting = {
        replies = {
            "嗨~ 今天过得怎么样呀？😊",
            "你来啦！我一直在等你呢~",
            "见到你好开心！今天想聊什么？",
        },
        expr = "happy",
    },
    love = {
        replies = {
            "我也喜欢你呀~ 💕",
            "说这种话...人家会害羞的啦！",
            "每次听你这么说，心都砰砰跳~",
            "你是我最重要的人！❤️",
        },
        expr = "shy",
    },
    mood = {
        replies = {
            "有你在身边，我每天都很开心呢~",
            "今天画了一幅画，想给你看！🎨",
            "刚听了一首很好听的歌，想分享给你~",
        },
        expr = "happy",
    },
    food = {
        replies = {
            "说到吃的我就开心！你想吃什么？🍰",
            "我最近在学做甜点呢，下次做给你吃~",
            "好饿呀...一起去吃好吃的吧！",
        },
        expr = "happy",
    },
    night = {
        replies = {
            "晚安，做个好梦哦~ 梦里见！🌙",
            "这么晚了，早点休息嘛~",
            "睡前想对你说...今天也辛苦了！",
        },
        expr = "normal",
    },
    sad_talk = {
        replies = {
            "别难过了...我陪着你呢~",
            "抱抱你...一切都会好起来的 🫂",
            "有什么不开心的事可以跟我说哦~",
        },
        expr = "sad",
    },
    surprise = {
        replies = {
            "真的吗？！太厉害了吧！",
            "哇！这也太棒了！😮",
            "不会吧！快跟我说说细节！",
        },
        expr = "surprised",
    },
    default = {
        replies = {
            "嗯嗯，我在听呢~",
            "然后呢？快跟我说说！",
            "哈哈，你说的好有趣~",
            "真的吗？告诉我更多嘛~",
            "嗯...让我想想该怎么回答你~",
            "你今天真的好温柔哦~",
            "和你聊天总是这么开心！",
        },
        expr = "normal",
    },
}

local function MatchCategory(text)
    local t = string.lower(text)
    if string.find(t, "你好") or string.find(t, "嗨") or string.find(t, "hi")
       or string.find(t, "hello") or string.find(t, "早上好") or string.find(t, "早") then
        return "greeting"
    elseif string.find(t, "喜欢你") or string.find(t, "爱你") or string.find(t, "love")
       or string.find(t, "想你") or string.find(t, "亲") or string.find(t, "抱") then
        return "love"
    elseif string.find(t, "难过") or string.find(t, "伤心") or string.find(t, "不开心")
       or string.find(t, "哭") or string.find(t, "累") then
        return "sad_talk"
    elseif string.find(t, "天哪") or string.find(t, "不会吧") or string.find(t, "真的假的")
       or string.find(t, "厉害") or string.find(t, "哇") then
        return "surprise"
    elseif string.find(t, "心情") or string.find(t, "开心") or string.find(t, "画")
       or string.find(t, "歌") then
        return "mood"
    elseif string.find(t, "吃") or string.find(t, "饿") or string.find(t, "甜")
       or string.find(t, "饭") or string.find(t, "蛋糕") then
        return "food"
    elseif string.find(t, "晚安") or string.find(t, "睡") or string.find(t, "梦") then
        return "night"
    end
    return "default"
end

local function GenerateLocalReply(userText)
    local cat = MatchCategory(userText)
    local pool = REPLY_POOL[cat]
    local text = pool.replies[math.random(1, #pool.replies)]
    return text, pool.expr, cat
end

-- ============================================================================
-- 3. 配色
-- ============================================================================

local C = {
    chatBg       = { 15, 15, 30, 210 },
    chatBgSolid  = { 20, 22, 35, 250 },
    inputBg      = { 35, 38, 55, 255 },
    bubbleSelf   = { 255, 105, 145, 230 },
    bubbleOther  = { 45, 50, 72, 240 },
    accent       = { 255, 120, 160, 255 },
    accentFrom   = { 255, 100, 150, 255 },
    accentTo     = { 200, 100, 255, 255 },
    text         = { 240, 240, 250, 255 },
    textSec      = { 160, 165, 185, 255 },
    textMuted    = { 100, 105, 130, 255 },
    online       = { 80, 220, 120, 255 },
    divider      = { 60, 65, 90, 80 },
    topBarBg     = { 10, 10, 25, 200 },
    danger       = { 255, 80, 80, 255 },
}

-- ============================================================================
-- 4. 全局状态
-- ============================================================================

local uiRoot_          = nil
local exprPanels_      = {}
local currentExpr_     = "normal"
local characterSway_   = nil
local characterBreath_ = nil
local particleLayer_   = nil
local chatContainer_   = nil
local chatScroll_      = nil
local inputField_      = nil
local typingLabel_     = nil
local affection_       = 72
local messages_        = {}
local replyTimer_      = nil   -- { elapsed, delay, text, expr, cat }

-- 表情回归计时器
local exprRevertTimer_ = nil   -- { elapsed, delay }

-- TTS / 打断
local aiSpeaking_      = false
local currentReplyText_= ""
local interruptBtn_    = nil
local sendBtn_         = nil

-- ASR
local isRecording_     = false
local voiceBtn_        = nil

-- ============================================================================
-- 5. 时间工具
-- ============================================================================

local function TimeStr()
    local t = os.date("*t")
    return string.format("%02d:%02d", t.hour, t.min)
end

-- ============================================================================
-- 6. 表情切换系统（带回归计时器）
-- ============================================================================

local function SwitchExpression(newExpr)
    if newExpr == currentExpr_ then return end
    if exprPanels_[currentExpr_] then
        exprPanels_[currentExpr_]:SetStyle({ opacity = 0 })
    end
    if exprPanels_[newExpr] then
        exprPanels_[newExpr]:SetStyle({ opacity = 1 })
    end
    currentExpr_ = newExpr

    if newExpr ~= "normal" then
        exprRevertTimer_ = {
            elapsed = 0,
            delay   = Config.AI.EXPR_REVERT_DELAY,
        }
    else
        exprRevertTimer_ = nil
    end
end

-- ============================================================================
-- 7. 粒子特效
-- ============================================================================

local function SpawnParticle(parent, emoji, offsetX, startY)
    local p = UI.Label {
        text = emoji,
        fontSize = math.random(18, 30),
        pointerEvents = "none",
        opacity = 0,
    }
    parent:AddChild(p)

    local endY = startY - math.random(80, 180)
    p:Animate({
        keyframes = {
            [0]    = { opacity = 0, translateX = offsetX, translateY = startY, scale = 0.3 },
            [0.15] = { opacity = 1, translateX = offsetX + math.random(-10, 10),
                       translateY = startY - 30, scale = 1.1 },
            [0.7]  = { opacity = 0.7, translateX = offsetX + math.random(-20, 20),
                       translateY = endY + 30, scale = 0.9 },
            [1]    = { opacity = 0, translateX = offsetX + math.random(-15, 15),
                       translateY = endY, scale = 0.5 },
        },
        duration = 1.8 + math.random() * 0.8,
        easing = "easeOut",
        fillMode = "forwards",
        onComplete = function()
            p:Destroy()
        end,
    })
end

local function SpawnParticlesForExpr(exprOrCat)
    if not particleLayer_ then return end
    local info = EXPR_PARTICLES[exprOrCat]
    if not info then return end
    for i = 1, info.count do
        local ox = math.random(-90, 90)
        local sy = math.random(-20, 60)
        SpawnParticle(particleLayer_, info.emoji, ox, sy)
    end
end

-- ============================================================================
-- 8. 角色弹跳反应
-- ============================================================================

local function BounceCharacter()
    if not characterBreath_ then return end
    characterBreath_:StopAnimation()
    characterBreath_:Animate({
        keyframes = {
            [0]   = { scale = 1.0, translateY = 0 },
            [0.3] = { scale = 1.04, translateY = -8 },
            [0.6] = { scale = 0.98, translateY = 2 },
            [1]   = { scale = 1.0, translateY = 0 },
        },
        duration = 0.55,
        easing = "easeOutBack",
        fillMode = "forwards",
        onComplete = function()
            StartBreathingAnimation()
        end,
    })
end

-- ============================================================================
-- 9. Live2D 动画系统
-- ============================================================================

function StartBreathingAnimation()
    if not characterBreath_ then return end
    characterBreath_:Animate({
        keyframes = {
            [0]   = { translateY = 0, scale = 1.0 },
            [0.5] = { translateY = -4, scale = 1.012 },
            [1]   = { translateY = 0, scale = 1.0 },
        },
        duration = 3.5,
        easing = "easeInOut",
        loop = true,
    })
end

local function StartSwayAnimation()
    if not characterSway_ then return end
    characterSway_:Animate({
        keyframes = {
            [0]    = { rotate = 0 },
            [0.25] = { rotate = 0.6 },
            [0.5]  = { rotate = 0 },
            [0.75] = { rotate = -0.6 },
            [1]    = { rotate = 0 },
        },
        duration = 6.0,
        easing = "easeInOut",
        loop = true,
    })
end

-- ============================================================================
-- 10. TTS 音频播放 + 打断
-- ============================================================================

local function SetSpeakingState(speaking)
    aiSpeaking_ = speaking
    if interruptBtn_ then
        interruptBtn_:SetVisible(speaking)
    end
    if sendBtn_ then
        sendBtn_:SetVisible(not speaking)
    end
end

local function StopSpeaking()
    if not aiSpeaking_ then return end
    SetSpeakingState(false)
    -- 通知服务端打断
    ClientNet.SendInterrupt(currentReplyText_)
    currentReplyText_ = ""
end

local function PlayTTSAudio(audioBase64, format)
    if not audioBase64 or #audioBase64 == 0 then return end

    SetSpeakingState(true)

    -- Urho3D: decode base64 -> write temp file -> play via SoundSource
    -- 实际实现取决于 Urhox 引擎能力；此处提供框架
    local tempPath = "data/temp_tts." .. (format or "wav")
    local decoded = nil

    -- 尝试用引擎内置 base64 解码（若可用）
    if _G.Base64Decode then
        decoded = Base64Decode(audioBase64)
    end

    if decoded then
        local f = io.open(tempPath, "wb")
        if f then
            f:write(decoded)
            f:close()
        end

        -- Urho3D 播放
        if _G.SoundSource and _G.Sound then
            local sound = cache:GetResource("Sound", tempPath)
            if sound then
                local source = scene_:CreateComponent("SoundSource")
                source:Play(sound)
                source.autoRemoveMode = REMOVE_COMPONENT
            end
        end
    else
        print("[Client] Base64 decode not available, TTS audio skipped")
    end

    -- 模拟播放时长后恢复（粗略估算：每字 0.3 秒）
    local estimatedDuration = math.max(2.0, #currentReplyText_ * 0.3)
    replyTimer_ = {
        elapsed = 0,
        delay   = estimatedDuration,
        text    = nil,
        expr    = "normal",
        cat     = "default",
        isTTSDone = true,
    }
end

-- ============================================================================
-- 11. 聊天系统
-- ============================================================================

local function CreateBubble(msg)
    local isSelf = msg.isSelf
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = isSelf and "flex-end" or "flex-start",
        paddingHorizontal = 14,
        marginBottom = 3,
        children = {
            UI.Panel {
                maxWidth = "72%",
                paddingHorizontal = 14,
                paddingVertical = 9,
                backgroundColor = isSelf and C.bubbleSelf or C.bubbleOther,
                borderRadius = isSelf and { 16, 16, 4, 16 } or { 16, 16, 16, 4 },
                boxShadow = {
                    { x = 0, y = 2, blur = 8, spread = 0, color = { 0, 0, 0, 30 } },
                },
                children = {
                    UI.Label {
                        text = msg.text,
                        fontSize = 13,
                        fontColor = isSelf and { 255, 255, 255, 255 } or C.text,
                        whiteSpace = "normal",
                        lineHeight = 1.5,
                    },
                    UI.Label {
                        text = msg.time,
                        fontSize = 9,
                        fontColor = isSelf and { 255, 255, 255, 130 } or C.textMuted,
                        textAlign = "right",
                        marginTop = 3,
                    },
                },
            },
        },
    }
end

local function AddMessage(text, isSelf)
    local msg = { text = text, isSelf = isSelf, time = TimeStr() }
    table.insert(messages_, msg)
    if chatContainer_ then
        chatContainer_:AddChild(CreateBubble(msg))
    end
    if chatScroll_ then
        chatScroll_:ScrollToBottom()
    end
end

local function ShowTyping(show)
    if typingLabel_ then
        typingLabel_:SetVisible(show)
    end
end

local function ReceiveAIReply(replyText, expr)
    ShowTyping(false)
    SwitchExpression(expr)
    AddMessage(replyText, false)
    BounceCharacter()
    SpawnParticlesForExpr(expr)
    currentReplyText_ = replyText
end

local function SendMessage(text)
    if not text or #text == 0 then return end

    if aiSpeaking_ then
        StopSpeaking()
    end

    AddMessage(text, true)
    affection_ = math.min(100, affection_ + 1)

    if AI_ENABLED and ClientNet.IsConnected() then
        ShowTyping(true)
        ClientNet.SendChat(text)
    else
        local replyText, expr, cat = GenerateLocalReply(text)
        local delay = 0.8 + math.random() * 1.0
        ShowTyping(true)
        replyTimer_ = {
            elapsed = 0,
            delay   = delay,
            text    = replyText,
            expr    = expr,
            cat     = cat,
        }
    end
end

-- ============================================================================
-- 12. UI 构建
-- ============================================================================

local function BuildBackground()
    return UI.Panel {
        id = "bg",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundImage = BG_IMAGE,
        backgroundFit = "cover",
        pointerEvents = "none",
        children = {
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundGradient = {
                    type = "linear",
                    direction = "to-bottom",
                    from = { 0, 0, 0, 0 },
                    to   = { 15, 15, 30, 220 },
                },
                pointerEvents = "none",
            },
        },
    }
end

--- 角色层：支持触摸热区（头部 / 脸颊 / 身体）
local function BuildCharacter()
    local exprChildren = {}
    local order = { "normal", "happy", "shy", "sad", "surprised" }
    for _, id in ipairs(order) do
        local path = EXPR_IMAGES[id]
        local panel = UI.Panel {
            id = "expr_" .. id,
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundImage = path,
            backgroundFit = "contain",
            opacity = (id == "normal") and 1.0 or 0.0,
            transition = "opacity 0.5s easeInOut",
            pointerEvents = "none",
        }
        exprPanels_[id] = panel
        table.insert(exprChildren, panel)
    end

    characterBreath_ = UI.Panel {
        id = "breath",
        width = "100%",
        height = "100%",
        transformOrigin = "bottom",
        children = exprChildren,
    }

    characterSway_ = UI.Panel {
        id = "sway",
        width = "100%",
        height = "100%",
        transformOrigin = "bottom",
        children = { characterBreath_ },
    }

    particleLayer_ = UI.Panel {
        id = "particles",
        position = "absolute",
        top = "20%",
        left = 0, right = 0,
        height = "50%",
        alignItems = "center",
        justifyContent = "center",
        pointerEvents = "none",
    }

    local function MakeTouchZone(id, area, top, height)
        return UI.Panel {
            id = id,
            position = "absolute",
            top = top,
            left = 0, right = 0,
            height = height,
            pointerEvents = "auto",
            onClick = function(self)
                BounceCharacter()
                local reactions = { "happy", "shy", "surprised" }
                local r = reactions[math.random(1, #reactions)]
                SwitchExpression(r)
                SpawnParticlesForExpr(r)

                if Config.TOUCH.ENABLED and AI_ENABLED and ClientNet.IsConnected() then
                    ClientNet.SendTouch(area)
                end
            end,
        }
    end

    return UI.Panel {
        id = "characterArea",
        position = "absolute",
        top = 0, left = 0, right = 0,
        height = "68%",
        alignItems = "center",
        justifyContent = "flex-end",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                width = "75%",
                maxWidth = 420,
                height = "95%",
                pointerEvents = "auto",
                children = {
                    characterSway_,
                    MakeTouchZone("touchHead", "head", 0, "25%"),
                    MakeTouchZone("touchFace", "face", "25%", "20%"),
                    MakeTouchZone("touchBody", "body", "45%", "55%"),
                },
            },
            UI.Panel {
                width = 160,
                height = 12,
                borderRadius = 80,
                backgroundColor = { 0, 0, 0, 40 },
                marginBottom = 4,
                pointerEvents = "none",
            },
            particleLayer_,
        },
    }
end

local function BuildTopBar()
    return UI.Panel {
        id = "topBar",
        position = "absolute",
        top = 0, left = 0, right = 0,
        height = 56,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 14,
        gap = 10,
        backgroundColor = C.topBarBg,
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = 38, height = 38,
                borderRadius = 19,
                overflow = "hidden",
                borderWidth = 2,
                borderColor = C.accent,
                children = {
                    UI.Panel {
                        width = "100%", height = "100%",
                        backgroundImage = GF.AVATAR,
                        backgroundFit = "cover",
                    },
                },
            },
            UI.Panel {
                flexGrow = 1, gap = 2,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label {
                                text = GF.NAME,
                                fontSize = 15,
                                fontColor = C.text,
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                width = 7, height = 7,
                                borderRadius = 4,
                                backgroundColor = C.online,
                            },
                        },
                    },
                    UI.Label {
                        text = "在线 · 等你来聊天~",
                        fontSize = 11,
                        fontColor = C.textSec,
                    },
                },
            },
            -- 截图按钮（视觉感知）
            UI.Button {
                text = "📷",
                width = 34, height = 34,
                borderRadius = 17,
                fontSize = 15,
                backgroundColor = { 45, 48, 65, 200 },
                hoverBackgroundColor = { 255, 120, 160, 80 },
                onClick = function(self)
                    print("[Client] Screenshot requested")
                    local tempScreenshot = "data/screenshot_temp.png"
                    -- Urho3D 截图
                    if graphics and graphics.TakeScreenShot then
                        local image = Image()
                        graphics:TakeScreenShot(image)
                        image:SavePNG(tempScreenshot)

                        local f = io.open(tempScreenshot, "rb")
                        if f then
                            local raw = f:read("*a")
                            f:close()
                            if _G.Base64Encode then
                                local b64 = Base64Encode(raw)
                                ClientNet.SendImage(b64, "看看我的屏幕~")
                                AddMessage("[发送了截图]", true)
                                ShowTyping(true)
                            else
                                AddMessage("(截图功能暂不可用)", false)
                            end
                        end
                    else
                        AddMessage("(截图功能暂不可用)", false)
                    end
                end,
            },
            -- 好感度
            UI.Panel {
                alignItems = "flex-end", gap = 3,
                children = {
                    UI.Label {
                        text = "💖 " .. tostring(affection_),
                        fontSize = 12,
                        fontColor = C.accent,
                    },
                    UI.ProgressBar {
                        id = "affBar",
                        value = affection_ / 100,
                        width = 70, height = 5,
                        borderRadius = 3,
                        backgroundColor = { 60, 60, 85, 255 },
                        fillGradient = {
                            direction = "to-right",
                            from = "#FF6EA0",
                            to = "#C864FF",
                        },
                        transition = "value 0.5s easeOut",
                    },
                },
            },
        },
    }
end

local function BuildChatPanel()
    typingLabel_ = UI.Panel {
        id = "typing",
        visible = false,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 14,
        paddingVertical = 4,
        gap = 3,
        children = {
            UI.Label { text = GF.NAME .. " 正在思考", fontSize = 11, fontColor = C.textMuted },
            UI.Label { text = "···", fontSize = 11, fontColor = C.accent },
        },
    }

    chatContainer_ = UI.Panel {
        id = "msgs",
        width = "100%",
        paddingTop = 8,
        paddingBottom = 4,
        gap = 2,
    }

    local welcome = {
        { text = "你终于来啦！我等你好久了~ 😊", isSelf = false, time = "09:00" },
        { text = "今天天气好好，想和你一起出去走走~", isSelf = false, time = "09:01" },
    }
    for _, m in ipairs(welcome) do
        table.insert(messages_, m)
        chatContainer_:AddChild(CreateBubble(m))
    end

    chatScroll_ = UI.ScrollView {
        id = "chatScroll",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        showScrollbar = false,
        bounces = true,
        children = { chatContainer_, typingLabel_ },
    }

    -- 快捷回复
    local quickReplies = {
        { t = "🌅 早上好~" },
        { t = "💕 想你了" },
        { t = "🍚 吃饭了吗？" },
        { t = "🌙 晚安~" },
        { t = "🥰 你好可爱" },
        { t = "😮 天哪！" },
    }
    local qrBtns = {}
    for _, qr in ipairs(quickReplies) do
        table.insert(qrBtns, UI.Button {
            text = qr.t,
            height = 30, fontSize = 11,
            borderRadius = 15,
            paddingHorizontal = 12,
            backgroundColor = { 45, 48, 65, 220 },
            hoverBackgroundColor = { 255, 120, 160, 60 },
            textColor = C.textSec,
            transition = "backgroundColor 0.2s easeOut",
            onClick = function(self)
                local pure = string.sub(qr.t, string.find(qr.t, " ") + 1)
                SendMessage(pure)
            end,
        })
    end

    local quickBar = UI.ScrollView {
        width = "100%", height = 40,
        scrollX = true, scrollY = false,
        showScrollbar = false,
        children = {
            UI.Panel {
                flexDirection = "row", gap = 7,
                height = 34, alignItems = "center",
                paddingHorizontal = 12,
                children = qrBtns,
            },
        },
    }

    -- 输入栏
    inputField_ = UI.TextField {
        id = "input",
        flexGrow = 1, height = 38,
        placeholder = "说点什么吧...",
        fontSize = 13,
        borderRadius = 19,
        backgroundColor = C.inputBg,
        borderColor = C.divider,
        borderWidth = 1,
        paddingHorizontal = 16,
        onSubmit = function(self, text)
            SendMessage(text)
            self:Clear()
        end,
    }

    -- 语音按钮（ASR）
    voiceBtn_ = UI.Button {
        text = "🎤",
        width = 40, height = 40,
        borderRadius = 20, fontSize = 17,
        backgroundColor = { 45, 48, 65, 220 },
        hoverBackgroundColor = { 255, 120, 160, 80 },
        transition = "backgroundColor 0.15s easeOut",
        onClick = function(self)
            if not Config.ASR.ENABLED then
                AddMessage("(语音识别未启用)", false)
                return
            end
            if isRecording_ then
                -- 结束录音
                isRecording_ = false
                self:SetStyle({ backgroundColor = { 45, 48, 65, 220 } })
                print("[Client] Recording stopped")

                -- 读取录音文件并发送
                local tempAudio = "data/temp_recording.wav"
                local f = io.open(tempAudio, "rb")
                if f then
                    local raw = f:read("*a")
                    f:close()
                    if _G.Base64Encode then
                        local b64 = Base64Encode(raw)
                        ClientNet.SendAudio(b64)
                        ShowTyping(true)
                        AddMessage("[语音消息]", true)
                    end
                else
                    AddMessage("(录音失败)", false)
                end
            else
                -- 开始录音
                isRecording_ = true
                self:SetStyle({ backgroundColor = C.danger })
                print("[Client] Recording started")
                -- 实际录音实现依赖引擎/OS能力
                -- 若引擎不支持原生录音，可使用 os.execute 调 ffmpeg
                -- os.execute('start /b ffmpeg -f dshow -i audio="Microphone" -t 10 data/temp_recording.wav -y')
            end
        end,
    }

    -- 发送按钮
    sendBtn_ = UI.Button {
        text = "💌",
        width = 40, height = 40,
        borderRadius = 20, fontSize = 17,
        backgroundGradient = {
            type = "linear", direction = "to-right",
            from = C.accentFrom, to = C.accentTo,
        },
        transition = "scale 0.12s easeOut",
        onClick = function(self)
            local text = inputField_:GetValue()
            SendMessage(text)
            inputField_:Clear()
        end,
    }

    -- 打断按钮（AI 说话时替换发送按钮）
    interruptBtn_ = UI.Button {
        text = "⏹",
        width = 40, height = 40,
        borderRadius = 20, fontSize = 17,
        visible = false,
        backgroundColor = C.danger,
        transition = "scale 0.12s easeOut",
        onClick = function(self)
            StopSpeaking()
        end,
    }

    local inputBar = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 12,
        paddingTop = 4,
        paddingBottom = 10,
        gap = 8,
        children = {
            voiceBtn_,
            inputField_,
            sendBtn_,
            interruptBtn_,
        },
    }

    return UI.Panel {
        id = "chatPanel",
        position = "absolute",
        left = 0, right = 0, bottom = 0,
        height = "38%",
        minHeight = 200,
        flexDirection = "column",
        backgroundColor = C.chatBg,
        borderRadiusTopLeft = 20,
        borderRadiusTopRight = 20,
        borderWidth = { 1, 0, 0, 0 },
        borderColor = { 255, 255, 255, 15 },
        backdropBlur = 10,
        children = {
            UI.Panel {
                width = "100%", alignItems = "center",
                paddingVertical = 8, pointerEvents = "none",
                children = {
                    UI.Panel {
                        width = 36, height = 4,
                        borderRadius = 2,
                        backgroundColor = { 255, 255, 255, 40 },
                    },
                },
            },
            chatScroll_,
            UI.Divider { color = C.divider, thickness = 1 },
            quickBar,
            inputBar,
        },
    }
end

-- ============================================================================
-- 13. 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "AI女友 - " .. GF.NAME

    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    uiRoot_ = UI.Panel {
        id = "root",
        width = "100%", height = "100%",
        backgroundColor = { 10, 10, 20, 255 },
        children = {
            BuildBackground(),
            BuildCharacter(),
            BuildTopBar(),
            BuildChatPanel(),
        },
    }

    UI.SetRoot(uiRoot_)

    StartBreathingAnimation()
    StartSwayAnimation()

    -- 网络回调
    ClientNet.Init()

    ClientNet.onReply = function(text, expression)
        ReceiveAIReply(text, expression)
    end

    ClientNet.onTyping = function()
        ShowTyping(true)
    end

    ClientNet.onError = function(errorMsg)
        ShowTyping(false)
        AddMessage("(连接异常: " .. errorMsg .. ")", false)
    end

    ClientNet.onAudioPlay = function(audioBase64, format)
        PlayTTSAudio(audioBase64, format)
    end

    ClientNet.onASRResult = function(text)
        if text and #text > 0 then
            if inputField_ then
                inputField_:SetValue(text)
            end
        end
    end

    ClientNet.onHistoryData = function(sessionId, messages)
        if chatContainer_ then
            chatContainer_:RemoveAllChildren()
        end
        messages_ = {}
        if messages then
            for _, msg in ipairs(messages) do
                local isSelf = (msg.role == "user")
                AddMessage(msg.content, isSelf)
            end
        end
        print("[Client] History loaded: " .. sessionId)
    end

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print("=== AI女友 · " .. GF.NAME .. " 已上线 ===")
    if AI_ENABLED then
        print("AI 模式: 已启用（服务端 → LLM API）")
        print("TTS:  " .. (Config.TTS.ENABLED and "已启用" or "已禁用"))
        print("ASR:  " .. (Config.ASR.ENABLED and "已启用" or "已禁用"))
        print("触摸: " .. (Config.TOUCH.ENABLED and "已启用" or "已禁用"))
        print("视觉: " .. (Config.VISION.ENABLED and "已启用" or "已禁用"))
    else
        print("AI 模式: 离线（本地回复池）")
    end
    print("点击角色可以互动，输入文字或使用快捷回复聊天~")
end

function Stop()
    UI.Shutdown()
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 回复计时器（本地回复 / TTS 播放完毕恢复）
    if replyTimer_ then
        replyTimer_.elapsed = replyTimer_.elapsed + dt
        if replyTimer_.elapsed >= replyTimer_.delay then
            local r = replyTimer_
            replyTimer_ = nil

            if r.isTTSDone then
                SetSpeakingState(false)
            else
                ShowTyping(false)
                SwitchExpression(r.expr)
                if r.text then
                    AddMessage(r.text, false)
                    BounceCharacter()
                    local particleCat = r.cat
                    if r.cat == "love" then particleCat = "shy" end
                    SpawnParticlesForExpr(particleCat)
                end
            end
        end
    end

    -- 表情回归计时器
    if exprRevertTimer_ then
        exprRevertTimer_.elapsed = exprRevertTimer_.elapsed + dt
        if exprRevertTimer_.elapsed >= exprRevertTimer_.delay then
            exprRevertTimer_ = nil
            SwitchExpression("normal")
        end
    end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        engine:Exit()
    end
end
