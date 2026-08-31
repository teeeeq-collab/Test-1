--------------------------------------------------------------------------------
-- Util: the 255-byte guard, and small shared helpers.
--------------------------------------------------------------------------------

local ADDON, MM = ...

MM.Util = {}
local Util = MM.Util

-- WoW caps a macro body at 255 BYTES, not characters. This distinction is the
-- whole reason this file exists: SetMaxLetters counts characters, so 255
-- characters containing one accented letter or a pasted smart quote is over the
-- byte cap and CreateMacro truncates it silently.
Util.MAX_MACRO_BYTES = 255

--- True if b is a UTF-8 continuation byte (10xxxxxx), i.e. the middle of a
--- multi-byte character rather than the start of one.
local function isContinuation(b)
    return b ~= nil and b >= 0x80 and b < 0xC0
end

--- Byte length. In Lua 5.1 the # operator on a string is already bytes; this
--- exists so call sites read as a deliberate choice rather than an accident.
function Util.ByteLen(text)
    return #(text or "")
end

--- Longest prefix of `text` that fits in maxBytes without splitting a
--- character. Walks back off any partial UTF-8 sequence at the cut point.
function Util.TrimToBytes(text, maxBytes)
    text = text or ""
    maxBytes = maxBytes or Util.MAX_MACRO_BYTES

    if #text <= maxBytes then
        return text
    end

    local cut = maxBytes
    while cut > 0 and isContinuation(text:byte(cut + 1)) do
        cut = cut - 1
    end

    return text:sub(1, cut)
end

--- Bytes still available. Negative means over the cap.
function Util.BytesRemaining(text)
    return Util.MAX_MACRO_BYTES - Util.ByteLen(text)
end

function Util.FitsInMacro(text)
    return Util.ByteLen(text) <= Util.MAX_MACRO_BYTES
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

    -- Strip a leading slash command and the space after it.
    local stripped = firstLine:match("^/%a+%s+(.*)$")
    return stripped or firstLine
end

--------------------------------------------------------------------------------
-- Ids
--------------------------------------------------------------------------------

local idCounter = 0

--- Ids only need to be unique within one SavedVariables file. Time plus a
--- counter is enough, and stays stable once written.
function Util.NewId(prefix)
    idCounter = idCounter + 1
    return string.format("%s%d%03d", prefix or "id", time(), idCounter % 1000)
end

--------------------------------------------------------------------------------
-- Tables
--------------------------------------------------------------------------------

--- Index of the first entry whose .id matches, or nil.
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
    print("|cff8f7fe8MythicMacros|r " .. tostring(msg))
end
