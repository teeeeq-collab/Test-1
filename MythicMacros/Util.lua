--------------------------------------------------------------------------------
-- Util: the macro length guard, and small shared helpers.
--------------------------------------------------------------------------------

local ADDON, MM = ...

MM.Util = {}
local Util = MM.Util

-- Measured on 12.1.0 rather than assumed:
--
--   300 ASCII characters (300 bytes)      -> stored as 256
--   120 multi-byte characters (360 bytes) -> stored untouched
--
-- A byte cap would have cut the 360-byte body. It did not. So the cap counts
-- CHARACTERS and sits at 256. An earlier version of this file counted bytes,
-- which would have silently truncated a perfectly legal 200-character callout
-- containing accented text down to about 85 characters. The probe caught it.
--
-- 255 rather than the observed 256, because one spare character costs nothing
-- and being wrong at the boundary costs a corrupted macro.
Util.MAX_MACRO_CHARS = 255

--- Character count, not byte count. strlenutf8 is a WoW global; the fallback
--- pattern counts anything that is not a UTF-8 continuation byte, which is the
--- same thing for well-formed text.
function Util.CharLen(text)
    text = text or ""
    if strlenutf8 then
        return strlenutf8(text)
    end
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

--- Longest prefix of `text` that fits in maxChars, never splitting a character.
function Util.TrimToChars(text, maxChars)
    text = text or ""
    maxChars = maxChars or Util.MAX_MACRO_CHARS

    if Util.CharLen(text) <= maxChars then
        return text
    end

    local chars, out = 0, {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars = chars + 1
        if chars > maxChars then break end
        out[#out + 1] = char
    end
    return table.concat(out)
end

--- Characters still available. Negative means over the cap.
function Util.CharsRemaining(text)
    return Util.MAX_MACRO_CHARS - Util.CharLen(text)
end

function Util.FitsInMacro(text)
    return Util.CharLen(text) <= Util.MAX_MACRO_CHARS
end

--------------------------------------------------------------------------------
-- Labels
--------------------------------------------------------------------------------

--- What a button reads. A caption if one was given; otherwise the macro text
--- with its leading chat command stripped, so
---   "/p Prio kick <Piercing Hiss>"  ->  "Prio kick <Piercing Hiss>"
--- Multi-line bodies fall back to their first line.
function Util.ButtonLabel(line)
    if not line then return "" end

    local caption = line.caption
    if caption and caption:match("%S") then
        return caption
    end

    local body = line.body or ""
    local firstLine = body:match("^[^\n]*") or ""

    local stripped = firstLine:match("^/%a+%s+(.*)$")
    return stripped or firstLine
end

--------------------------------------------------------------------------------
-- Ids
--------------------------------------------------------------------------------

local idCounter = 0

-- WoW exposes `time`; plain Lua has os.time. Resolving both keeps this file
-- runnable outside the game, which is the only way it gets tested at all.
local now = _G.time or os.time

--- Ids only need to be unique within one SavedVariables file.
function Util.NewId(prefix)
    idCounter = idCounter + 1
    return string.format("%s%d%03d", prefix or "id", now(), idCounter % 1000)
end

--------------------------------------------------------------------------------
-- Tables
--------------------------------------------------------------------------------

function Util.IndexById(list, id)
    if not list then return nil end
    for i = 1, #list do
        if list[i].id == id then return i end
    end
    return nil
end

function Util.FindById(list, id)
    local i = Util.IndexById(list, id)
    return i and list[i] or nil, i
end

--- Move list[index] by delta, clamped. Returns the new index.
function Util.Move(list, index, delta)
    local target = index + delta
    if not list[index] or target < 1 or target > #list then
        return index
    end
    local item = table.remove(list, index)
    table.insert(list, target, item)
    return target
end

function Util.Print(msg)
    print("|cff8f7fe8Mythic Instructions|r " .. tostring(msg))
end
