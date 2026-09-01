--------------------------------------------------------------------------------
-- Capture: filling in enemy names from the game rather than by typing them.
--
-- This is the only place the addon reads anything about the world, and it reads
-- one thing: the name of the unit you are targeting, when you press a key. No
-- events are registered, nothing polls, and nothing runs while you play. That
-- keeps the isolation principle intact — the addon still cannot be broken by a
-- patch changing something it watches, because it watches nothing.
--
-- It exists because trash names cannot be shipped: they are unknown for the new
-- dungeons, and inventing them would be worse than leaving them out.
--------------------------------------------------------------------------------

local ADDON, MM = ...

MM.Capture = {}
local Capture = MM.Capture
local Core, Util = MM.Core, MM.Util

local targetCategoryId

function Capture.SetCategory(catId)
    targetCategoryId = catId
end

function Capture.Category()
    return targetCategoryId
end

--- Adds the current target as an enemy, with one empty line ready to write.
--- Duplicates by name are refused rather than stacked, so tab-targeting through
--- a pull and pressing the key on everything cannot produce a list full of
--- repeats.
function Capture.AddTarget(unit)
    unit = unit or "target"

    if InCombatLockdown() then
        return nil, "can't add enemies in combat"
    end

    local catId = targetCategoryId
    if not catId or not Core.GetCategory(catId) then
        return nil, "open Edit and choose a dungeon first"
    end

    if not UnitExists(unit) then
        return nil, "nothing targeted"
    end

    local name = UnitName(unit)
    if type(name) ~= "string" or name == "" then
        return nil, "could not read that unit's name"
    end

    local cat = Core.GetCategory(catId)
    for _, enemy in ipairs(cat.enemies) do
        if enemy.name == name then
            return nil, ("%s is already in %s"):format(name, cat.name)
        end
    end

    local enemy = Core.AddEnemy(catId, name)
    Core.AddLine(catId, enemy.id, "", "")
    return name, cat.name
end
