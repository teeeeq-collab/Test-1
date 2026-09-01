--------------------------------------------------------------------------------
-- Export: sharing a category, and backing up a profile.
--
-- Format:  !MM1:<adler>!<encoded>
--
-- The prefix carries the format version and an Adler-32 of the serialised
-- payload. Both exist because a truncated paste is the commonest import failure
-- — people miss the last characters when selecting — and testing showed it does
-- not reliably throw: it can pass decode and decompress and fail confusingly
-- much later. The checksum turns that into an accurate message.
--
-- Import deserialises a binary format and never evaluates Lua. Addons that
-- import by running the string as code let a profile string from another person
-- execute anything on the machine that imports it, and passing strings between
-- teammates is the entire point of this feature.
--------------------------------------------------------------------------------

local ADDON, MM = ...

MM.Export = {}
local Export = MM.Export
local Core, Util = MM.Core, MM.Util

local PREFIX  = "!MM1:"
local VERSION = 1

local Deflate, Serialize

local function libs()
    if not Deflate then
        Deflate   = LibStub and LibStub("LibDeflate", true)
        Serialize = LibStub and LibStub("LibSerialize", true)
    end
    return Deflate, Serialize
end

--------------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------------

local function encode(payload)
    local deflate, serialize = libs()
    if not (deflate and serialize) then
        return nil, "compression libraries are missing"
    end

    local ser     = serialize:Serialize(payload)
    local adler   = deflate:Adler32(ser)
    local encoded = deflate:EncodeForPrint(deflate:CompressDeflate(ser, { level = 9 }))

    return ("%s%d!%s"):format(PREFIX, adler, encoded)
end

--- One category. This is the unit that gets handed to a teammate, and it fits
--- in a chat message.
function Export.EncodeCategory(catId)
    local cat = Core.GetCategory(catId)
    if not cat then return nil, "category not found" end
    return encode({ v = VERSION, kind = "category", data = cat })
end

--- The whole profile. This is the backup unit, and belongs in a file.
function Export.EncodeProfile()
    return encode({ v = VERSION, kind = "profile", data = Core.Profile() })
end

--------------------------------------------------------------------------------
-- Decoding
--------------------------------------------------------------------------------

--- Shape validation. Deserialising safely says nothing about whether the
--- contents make sense, so every field an import will touch is checked before
--- anything is applied.
local function validCategory(cat)
    if type(cat) ~= "table" then return false, "not a category" end
    if type(cat.name) ~= "string" then return false, "category has no name" end
    if type(cat.enemies) ~= "table" then return false, "category has no enemies list" end
    if type(cat.pages) ~= "table" then return false, "category has no pages list" end

    for _, enemy in ipairs(cat.enemies) do
        if type(enemy) ~= "table" or type(enemy.name) ~= "string" then
            return false, "an enemy is malformed"
        end
        if type(enemy.lines) ~= "table" then
            return false, ("enemy %q has no lines"):format(tostring(enemy.name))
        end
        for _, line in ipairs(enemy.lines) do
            if type(line) ~= "table" or type(line.body) ~= "string" then
                return false, ("a line on %q is malformed"):format(tostring(enemy.name))
            end
        end
    end

    for _, page in ipairs(cat.pages) do
        if type(page) ~= "table" or type(page.enemyIds) ~= "table" then
            return false, "a page is malformed"
        end
    end

    return true
end

--- Returns kind, data, or nil plus a reason a person can act on.
function Export.Decode(str)
    if type(str) ~= "string" or str == "" then
        return nil, nil, "nothing to import"
    end

    str = str:gsub("%s", "")

    local adlerText, encoded = str:match("^" .. PREFIX .. "(%d+)!(.+)$")
    if not adlerText then
        if str:match("^!MM") then
            return nil, nil, "this looks like a MythicMacros string from a newer version"
        end
        return nil, nil, "not a MythicMacros export string"
    end

    local deflate, serialize = libs()
    if not (deflate and serialize) then
        return nil, nil, "compression libraries are missing"
    end

    local decoded = deflate:DecodeForPrint(encoded)
    if not decoded then
        return nil, nil, "the string is damaged - check you copied all of it"
    end

    local ser = deflate:DecompressDeflate(decoded)
    if not ser then
        return nil, nil, "the string is damaged or incomplete - check you copied all of it"
    end

    if tostring(deflate:Adler32(ser)) ~= adlerText then
        return nil, nil, "the string is incomplete - the end is missing"
    end

    local ok, payload = serialize:Deserialize(ser)
    if not ok or type(payload) ~= "table" then
        return nil, nil, "the string could not be read"
    end

    if payload.v ~= VERSION then
        return nil, nil, ("made by a different version (%s)"):format(tostring(payload.v))
    end

    return payload.kind, payload.data, nil
end

--------------------------------------------------------------------------------
-- Applying
--------------------------------------------------------------------------------

--- Ids are regenerated on import and page references remapped through the new
--- ids. Keeping the originals would collide with existing data and silently
--- join two unrelated enemies into one.
local function adoptCategory(source)
    local cat = Core.AddCategory(source.name)
    local idMap = {}

    for _, enemy in ipairs(source.enemies) do
        local new = Core.AddEnemy(cat.id, enemy.name, enemy.perRow)
        idMap[enemy.id or ""] = new.id
        for _, line in ipairs(enemy.lines) do
            Core.AddLine(cat.id, new.id, line.caption, line.body)
        end
    end

    for _, page in ipairs(source.pages) do
        local newPage = Core.AddPage(cat.id, page.name)
        for _, oldId in ipairs(page.enemyIds) do
            local newId = idMap[oldId]
            if newId then Core.AddEnemyToPage(cat.id, newPage.id, newId) end
        end
    end

    return cat
end

--- Never overwrites. An import lands as a new category or a new profile, so a
--- bad paste cannot destroy existing work.
function Export.Import(str)
    local kind, data, err = Export.Decode(str)
    if not kind then return nil, err end

    if kind == "category" then
        local ok, reason = validCategory(data)
        if not ok then return nil, reason end
        local cat = adoptCategory(data)
        return ("category %q"):format(cat.name)

    elseif kind == "profile" then
        if type(data) ~= "table" or type(data.categories) ~= "table" then
            return nil, "profile is malformed"
        end
        for _, cat in ipairs(data.categories) do
            local ok, reason = validCategory(cat)
            if not ok then return nil, reason end
        end

        local name = Core.CreateProfile("Imported")
        local previous = Core.db.activeProfile
        Core.SetActiveProfile(name)
        for _, cat in ipairs(data.categories) do adoptCategory(cat) end
        Core.SetActiveProfile(previous)
        return ("profile %q with %d categories"):format(name, #data.categories)
    end

    return nil, ("unknown export kind %q"):format(tostring(kind))
end
