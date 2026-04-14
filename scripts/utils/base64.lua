-- ============================================================================
-- base64.lua — 纯 Lua Base64 编解码（UrhoX 沙箱无内置 Base64 API）
-- ============================================================================

local Base64 = {}

local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function Base64.encode(data)
    if not data or #data == 0 then return "" end
    local result = {}
    local len = #data
    local i = 1
    while i <= len do
        local a = string.byte(data, i)
        local b = (i + 1 <= len) and string.byte(data, i + 1) or 0
        local c = (i + 2 <= len) and string.byte(data, i + 2) or 0
        local remain = len - i

        local n = (a << 16) + (b << 8) + c

        table.insert(result, string.sub(CHARS, (n >> 18 & 63) + 1, (n >> 18 & 63) + 1))
        table.insert(result, string.sub(CHARS, (n >> 12 & 63) + 1, (n >> 12 & 63) + 1))
        table.insert(result, remain >= 1 and string.sub(CHARS, (n >> 6 & 63) + 1, (n >> 6 & 63) + 1) or "=")
        table.insert(result, remain >= 2 and string.sub(CHARS, (n & 63) + 1, (n & 63) + 1) or "=")

        i = i + 3
    end
    return table.concat(result)
end

local DECODE_MAP = {}
for i = 1, 64 do
    DECODE_MAP[string.byte(CHARS, i)] = i - 1
end
DECODE_MAP[string.byte("=")] = 0

function Base64.decode(data)
    if not data or #data == 0 then return "" end
    -- 去除空白
    data = data:gsub("%s", "")
    local result = {}
    local len = #data
    local i = 1
    while i <= len do
        local a = DECODE_MAP[string.byte(data, i)] or 0
        local b = DECODE_MAP[string.byte(data, i + 1)] or 0
        local c = DECODE_MAP[string.byte(data, i + 2)] or 0
        local d = DECODE_MAP[string.byte(data, i + 3)] or 0

        local n = (a << 18) + (b << 12) + (c << 6) + d

        table.insert(result, string.char((n >> 16) & 255))
        if string.sub(data, i + 2, i + 2) ~= "=" then
            table.insert(result, string.char((n >> 8) & 255))
        end
        if string.sub(data, i + 3, i + 3) ~= "=" then
            table.insert(result, string.char(n & 255))
        end

        i = i + 4
    end
    return table.concat(result)
end

return Base64
