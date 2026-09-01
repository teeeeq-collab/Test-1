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
check("boss pages named", Core.GetPage(kr.id, kr.pages[2].id).name == "The Golden Serpent")
check("boss card created", #kr.enemies == 4, #kr.enemies)
check("boss laid out across", kr.enemies[1].perRow == 3)
check("boss card has an empty line ready", #kr.enemies[1].lines == 1
      and kr.enemies[1].lines[1].body == "")

local vale = byName["The Blinding Vale"]
check("no invented enemies", #vale.enemies == 0, #vale.enemies)
check("page skeleton present", #vale.pages == 6, #vale.pages)

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
      and #Core.GetCategory(mine.id).enemies == 1)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
