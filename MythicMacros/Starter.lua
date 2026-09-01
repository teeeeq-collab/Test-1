--------------------------------------------------------------------------------
-- Starter: the season's dungeons, pre-created.
--
-- The dungeon pool is stated confidently. The enemies inside them are not, and
-- deliberately so.
--
-- Trash names for the five Midnight dungeons are past this addon's knowledge,
-- and a plausible-looking invented list is worse than an empty one: callouts
-- would be written for mobs that do not exist while the ones that do go
-- unnoticed. So trash is left to the capture tool, which reads real names off
-- real mobs, correctly localised, with nothing guessed.
--
-- Boss names for the three returning dungeons are filled in, marked for
-- checking. They are old content and unlikely to have changed, but "unlikely"
-- is not "verified".
--------------------------------------------------------------------------------

local ADDON, MM = ...

MM.Starter = {}
local Starter = MM.Starter
local Core = MM.Core

-- Mythic+ Season 2, patch 12.1. Five Midnight dungeons and three returning.
local SEASON = {
    { name = "Altar of Fangs",      bosses = nil },
    { name = "Murder Row",          bosses = nil },
    { name = "Den of Nalorakk",     bosses = nil },
    { name = "The Blinding Vale",   bosses = nil },
    { name = "Voidscar Arena",      bosses = nil },

    { name = "Kings' Rest", bosses = {
        "The Golden Serpent", "Mchimba the Embalmer",
        "The Council of Tribes", "Dazar, The First King" } },

    { name = "Temple of Sethraliss", bosses = {
        "Adderis and Aspix", "Merektha", "Galvazzt", "Avatar of Sethraliss" } },

    { name = "Ruby Life Pools", bosses = {
        "Melidrussa Chillworn", "Kokia Blazehoof", "Kyrakka and Erkhart Stormvein" } },
}

--- Pages are laid out as a route: trash, boss, trash, boss. Where the bosses
--- are known the pages carry their names; where they are not, the pages are
--- numbered and you rename them as you learn the route.
local function buildPages(catId, bosses)
    if bosses then
        for i, boss in ipairs(bosses) do
            Core.AddPage(catId, ("Trash %d"):format(i))

            local page  = Core.AddPage(catId, boss)
            local enemy = Core.AddEnemy(catId, boss, 3)   -- 3 across: the boss layout
            Core.AddLine(catId, enemy.id, "", "")
            Core.AddEnemyToPage(catId, page.id, enemy.id)
        end
    else
        for i = 1, 3 do
            Core.AddPage(catId, ("Trash %d"):format(i))
            Core.AddPage(catId, ("Boss %d"):format(i))
        end
    end
end

--- Creates any season dungeon not already present. Existing categories are left
--- alone, so running this twice cannot duplicate or overwrite work.
function Starter.Create()
    local existing = {}
    for _, cat in ipairs(Core.Categories()) do
        existing[cat.name] = true
    end

    local made, skipped = {}, {}
    for _, dungeon in ipairs(SEASON) do
        if existing[dungeon.name] then
            skipped[#skipped + 1] = dungeon.name
        else
            local cat = Core.AddCategory(dungeon.name)
            buildPages(cat.id, dungeon.bosses)
            made[#made + 1] = dungeon.name
        end
    end

    return made, skipped
end

function Starter.DungeonCount()
    return #SEASON
end
