local MM = {}
loadfile("MythicMacros/Util.lua")("MythicMacros", MM)
loadfile("MythicMacros/Core.lua")("MythicMacros", MM)
loadfile("MythicMacros/Starter.lua")("MythicMacros", MM)
local Core, Starter = MM.Core, MM.Starter

local pass, fail = 0, 0
local function check(label, cond, extra)
    if cond then pass = pass + 1
    else fail = fail + 1; print("  FAIL: " .. label .. (extra and ("  -> " .. tostring(extra)) or "")) end
end

Core.Init({})
local made, skipped = Starter.Create()

check("all dungeons created", #made == Starter.DungeonCount(), #made)
check("nothing skipped on a clean profile", #skipped == 0)
check("categories present", #Core.Categories() == Starter.DungeonCount())

local byName = {}
for _, cat in ipairs(Core.Categories()) do byName[cat.name] = cat end

check("Blinding Vale present", byName["The Blinding Vale"] ~= nil)
check("Den of Nalorakk present", byName["Den of Nalorakk"] ~= nil)
check("Kings' Rest present", byName["Kings' Rest"] ~= nil)

-- Known-boss dungeons get named boss pages and a boss card; unknown ones do not
-- get invented enemies.
local kr = byName["Kings' Rest"]
local krPages = Core.Pages(kr.id)
check("boss pages named", Core.GetPage(kr.id, krPages[2].id).name == "The Golden Serpent")
check("boss card created", #Core.Enemies(kr.id) == 4, #Core.Enemies(kr.id))
check("boss laid out across", Core.Enemies(kr.id)[1].perRow == 3)
check("boss card has an empty line ready", #Core.Enemies(kr.id)[1].lines == 1
      and Core.Enemies(kr.id)[1].lines[1].body == "")

local vale = byName["The Blinding Vale"]
check("no invented enemies", #Core.Enemies(vale.id) == 0, #Core.Enemies(vale.id))
check("page skeleton present", #Core.Pages(vale.id) == 6, #Core.Pages(vale.id))

-- Running twice must not duplicate or overwrite.
local made2, skipped2 = Starter.Create()
check("second run creates nothing", #made2 == 0)
check("second run skips all", #skipped2 == Starter.DungeonCount())
check("no duplicate categories", #Core.Categories() == Starter.DungeonCount())

-- Existing work is untouched.
local mine = Core.AddCategory("Den of Nalorakk (mine)")
Core.AddEnemy(mine.id, "Matriarch")
Starter.Create()
check("hand-made category survives", Core.GetCategory(mine.id) ~= nil
      and #Core.Enemies(mine.id) == 1)

-- The starter set must arrive as one variant each, ready to branch from.
check("each dungeon starts with one variant", (function()
    for _, cat in ipairs(Core.Categories()) do
        if #Core.Variants(cat.id) ~= 1 then return false end
    end
    return true
end)())

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
