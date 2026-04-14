-- ============================================================================
-- AI 女友 — 视觉小说风格 · 仿 Live2D 角色动画
-- 布局: 角色立绘占满大半屏幕 + 底部半透明聊天面板
-- 动画: 呼吸起伏 · 身体轻摇 · 表情淡入淡出 · 互动弹跳 · 飘浮粒子
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- 1. 角色与表情配置
-- ============================================================================

local GF = {
    name     = "小雪",
    age      = "20",
    sign     = "天秤座",
    hobby    = "画画、听音乐、看日落",
    bio      = "喜欢安静的午后，和你在一起的每一刻都是最好的时光。",
    avatar   = "image/girlfriend_avatar_20260413152437.png",
}

-- 表情立绘路径（每张透明底全身立绘）
local EXPR_IMAGES = {
    normal    = "image/gf_normal_20260413153652.png",
    happy     = "image/gf_happy_20260413153548.png",
    shy       = "image/gf_shy_20260413153559.png",
    sad       = "image/gf_sad_20260413153546.png",
    surprised = "image/gf_surprised_20260413153810.png",
}

local BG_IMAGE = "image/scene_bg_20260413153659.png"

-- 表情 → 粒子映射
local EXPR_PARTICLES = {
    happy     = { emoji = "✨", count = 5 },
    shy       = { emoji = "❤️", count = 4 },
    love      = { emoji = "💕", count = 6 },
    sad       = { emoji = "💧", count = 3 },
    surprised = { emoji = "❗", count = 3 },
}

-- ============================================================================
-- 2. 回复系统
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

--- 关键词匹配
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

--- 生成回复
local function GenerateReply(userText)
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
}

-- ============================================================================
-- 4. 全局状态
-- ============================================================================

local uiRoot_         = nil
local exprPanels_     = {}    -- { normal = Panel, happy = Panel, ... }
local currentExpr_    = "normal"
local characterSway_  = nil
local characterBreath_= nil
local particleLayer_  = nil
local chatContainer_  = nil
local chatScroll_     = nil
local inputField_     = nil
local typingLabel_    = nil
local affection_      = 72
local messages_       = {}
local replyTimer_     = nil   -- { elapsed, delay, text, expr, cat }

-- ============================================================================
-- 5. 时间工具
-- ============================================================================

local function TimeStr()
    local t = os.date("*t")
    return string.format("%02d:%02d", t.hour, t.min)
end

-- ============================================================================
-- 6. 表情切换系统
-- ============================================================================

local function SwitchExpression(newExpr)
    if newExpr == currentExpr_ then return end
    -- 淡出当前
    if exprPanels_[currentExpr_] then
        exprPanels_[currentExpr_]:SetStyle({ opacity = 0 })
    end
    -- 淡入新表情
    if exprPanels_[newExpr] then
        exprPanels_[newExpr]:SetStyle({ opacity = 1 })
    end
    currentExpr_ = newExpr
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
            [0]   = { opacity = 0, translateX = offsetX, translateY = startY, scale = 0.3 },
            [0.15] = { opacity = 1, translateX = offsetX + math.random(-10, 10),
                       translateY = startY - 30, scale = 1.1 },
            [0.7] = { opacity = 0.7, translateX = offsetX + math.random(-20, 20),
                      translateY = endY + 30, scale = 0.9 },
            [1]   = { opacity = 0, translateX = offsetX + math.random(-15, 15),
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
        -- 稍微错开每个粒子的生成时间感觉
        SpawnParticle(particleLayer_, info.emoji, ox, sy)
    end
end

-- ============================================================================
-- 8. 角色弹跳反应
-- ============================================================================

local function BounceCharacter()
    if not characterBreath_ then return end
    -- 先停止呼吸动画，播放弹跳，再恢复
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
-- 10. 聊天系统
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

local function SendMessage(text)
    if not text or #text == 0 then return end
    AddMessage(text, true)

    -- 增加好感
    affection_ = math.min(100, affection_ + 1)

    -- 准备回复
    local replyText, expr, cat = GenerateReply(text)
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

-- ============================================================================
-- 11. UI 构建
-- ============================================================================

--- 全屏背景
local function BuildBackground()
    return UI.Panel {
        id = "bg",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundImage = BG_IMAGE,
        backgroundFit = "cover",
        pointerEvents = "none",
        -- 底部渐变遮罩用 backgroundGradient 叠加
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

--- 角色层（仿 Live2D：轻摇 → 呼吸 → 表情叠层）
local function BuildCharacter()
    -- 构建表情面板
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

    -- 呼吸层
    characterBreath_ = UI.Panel {
        id = "breath",
        width = "100%",
        height = "100%",
        transformOrigin = "bottom",
        children = exprChildren,
    }

    -- 轻摇层
    characterSway_ = UI.Panel {
        id = "sway",
        width = "100%",
        height = "100%",
        transformOrigin = "bottom",
        children = { characterBreath_ },
    }

    -- 粒子层
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

    -- 角色整体容器：点击弹跳
    return UI.Panel {
        id = "characterArea",
        position = "absolute",
        top = 0, left = 0, right = 0,
        height = "68%",
        alignItems = "center",
        justifyContent = "flex-end",
        pointerEvents = "box-none",
        children = {
            -- 角色本体
            UI.Panel {
                width = "75%",
                maxWidth = 420,
                height = "95%",
                pointerEvents = "auto",
                onClick = function(self)
                    BounceCharacter()
                    -- 点击时随机小互动
                    local reactions = { "happy", "shy", "surprised" }
                    local r = reactions[math.random(1, #reactions)]
                    SwitchExpression(r)
                    SpawnParticlesForExpr(r)
                    -- 2秒后恢复
                    replyTimer_ = {
                        elapsed = 0,
                        delay = 2.0,
                        text = nil, -- 不发消息，只恢复表情
                        expr = "normal",
                        cat = "default",
                    }
                end,
                children = { characterSway_ },
            },
            -- 角色脚下阴影
            UI.Panel {
                width = 160,
                height = 12,
                borderRadius = 80,
                backgroundColor = { 0, 0, 0, 40 },
                marginBottom = 4,
                pointerEvents = "none",
            },
            -- 粒子覆盖层
            particleLayer_,
        },
    }
end

--- 顶部信息栏（半透明悬浮）
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
            -- 头像
            UI.Panel {
                width = 38, height = 38,
                borderRadius = 19,
                overflow = "hidden",
                borderWidth = 2,
                borderColor = C.accent,
                children = {
                    UI.Panel {
                        width = "100%", height = "100%",
                        backgroundImage = GF.avatar,
                        backgroundFit = "cover",
                    },
                },
            },
            -- 名称 + 状态
            UI.Panel {
                flexGrow = 1, gap = 2,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label {
                                text = GF.name,
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

--- 底部聊天面板
local function BuildChatPanel()
    -- 打字指示
    typingLabel_ = UI.Panel {
        id = "typing",
        visible = false,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 14,
        paddingVertical = 4,
        gap = 3,
        children = {
            UI.Label { text = GF.name .. " 正在输入", fontSize = 11, fontColor = C.textMuted },
            UI.Label { text = "···", fontSize = 11, fontColor = C.accent },
        },
    }

    -- 消息容器
    chatContainer_ = UI.Panel {
        id = "msgs",
        width = "100%",
        paddingTop = 8,
        paddingBottom = 4,
        gap = 2,
    }

    -- 初始消息
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
                -- 提取纯文字（去掉 emoji 前缀）
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

    local inputBar = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 12,
        paddingTop = 4,
        paddingBottom = 10,
        gap = 8,
        children = {
            inputField_,
            UI.Button {
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
            },
        },
    }

    -- 整个聊天面板
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
            -- 把手
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
-- 12. 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "AI女友 - " .. GF.name

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

    -- 启动 Live2D 动画
    StartBreathingAnimation()
    StartSwayAnimation()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print("=== AI女友 · " .. GF.name .. " 已上线 ===")
    print("点击角色可以互动，输入文字或使用快捷回复聊天~")
end

function Stop()
    UI.Shutdown()
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 回复计时器
    if replyTimer_ then
        replyTimer_.elapsed = replyTimer_.elapsed + dt
        if replyTimer_.elapsed >= replyTimer_.delay then
            local r = replyTimer_
            replyTimer_ = nil
            ShowTyping(false)
            SwitchExpression(r.expr)

            if r.text then
                -- 正式回复消息
                AddMessage(r.text, false)
                BounceCharacter()
                -- 粒子效果
                local particleCat = r.cat
                if r.cat == "love" then particleCat = "shy" end
                SpawnParticlesForExpr(particleCat)
            end
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
