local IMI = {}
loadfile("InomrahsMythicInstructions/Util.lua")("InomrahsMythicInstructions", IMI)
loadfile("InomrahsMythicInstructions/Core.lua")("InomrahsMythicInstructions", IMI)
local Core, Util = IMI.Core, IMI.Util

local pass, fail = 0, 0
local function check(label, cond)
    if cond then pass = pass + 1 else fail = fail + 1 print("  FAIL: " .. label) end
end

Core.Init({})

-- Categories -----------------------------------------------------------------
local cat = Core.AddCategory("Den of Nalorakk")
check("category created", cat and cat.name == "Den of Nalorakk")
check("category retrievable", Core.GetCategory(cat.id) == cat)

-- Enemies and lines ----------------------------------------------------------
local harrower = Core.AddEnemy(cat.id, "Twinfang Harrower")
local matriarch = Core.AddEnemy(cat.id, "Matriarch", 3)
check("perRow default", harrower.perRow == 1)
check("perRow set", matriarch.perRow == 3)
check("perRow clamped", Core.SetEnemyPerRow(cat.id, matriarch.id, 99)
      and Core.GetEnemy(cat.id, matriarch.id).perRow == 6)

local l1 = Core.AddLine(cat.id, harrower.id, "Strat", "/p freedom the snare")
local l2 = Core.AddLine(cat.id, harrower.id, "Panic", "/p FRENZY - kite it")
check("lines added", #harrower.lines == 2)
check("line order", harrower.lines[1].id == l1.id)
Core.MoveLine(cat.id, harrower.id, l1.id, 1)
check("line moved", harrower.lines[1].id == l2.id)

-- The length backstop --------------------------------------------------------
local long = string.rep("x", 400)
Core.SetLine(cat.id, harrower.id, l1.id, nil, long)
check("body trimmed on write", Util.CharLen(Core.GetLine(cat.id, harrower.id, l1.id).body) == 255)

local euro = string.rep("\226\130\172", 200)   -- 200 chars, 600 bytes
Core.SetLine(cat.id, harrower.id, l1.id, nil, euro)
check("multibyte body kept whole",
      Util.CharLen(Core.GetLine(cat.id, harrower.id, l1.id).body) == 200)

-- Pages and shared enemies ---------------------------------------------------
local p1 = Core.AddPage(cat.id, "Opening trash")
local p2 = Core.AddPage(cat.id, "To first boss")

check("added to page", Core.AddEnemyToPage(cat.id, p1.id, harrower.id))
check("no duplicate on one page", not Core.AddEnemyToPage(cat.id, p1.id, harrower.id))
Core.AddEnemyToPage(cat.id, p1.id, matriarch.id)
Core.AddEnemyToPage(cat.id, p2.id, matriarch.id)

check("matriarch on two pages",
      #Core.PageEnemies(cat.id, p1.id) == 2 and #Core.PageEnemies(cat.id, p2.id) == 1)

-- Shared definition: one edit, both pages
Core.RenameEnemy(cat.id, matriarch.id, "Matriarch (linked)")
check("edit reaches both pages",
      Core.PageEnemies(cat.id, p1.id)[2].name == "Matriarch (linked)" and
      Core.PageEnemies(cat.id, p2.id)[1].name == "Matriarch (linked)")

-- Remove from page is not delete
Core.RemoveEnemyFromPage(cat.id, p1.id, matriarch.id)
check("removed from one page only",
      #Core.PageEnemies(cat.id, p1.id) == 1 and #Core.PageEnemies(cat.id, p2.id) == 1)
check("definition survives removal", Core.GetEnemy(cat.id, matriarch.id) ~= nil)

-- Delete prunes every page reference
Core.DeleteEnemy(cat.id, matriarch.id)
check("delete prunes page refs", #Core.PageEnemies(cat.id, p2.id) == 0)
check("no dangling ids", #Core.GetPage(cat.id, p2.id).enemyIds == 0)

-- Profiles -------------------------------------------------------------------
local made = Core.CreateProfile("Default")
check("profile clash suffixed", made == "Default (2)")
check("last profile protected",
      Core.DeleteProfile(made) and not Core.DeleteProfile("Default"))

-- Export staleness -----------------------------------------------------------
check("edits counted", Core.EditsSinceExport() > 0)
Core.MarkExported()
check("counter resets", Core.EditsSinceExport() == 0)
Core.AddCategory("Another")
check("counter resumes", Core.EditsSinceExport() == 1)

-- Build set ------------------------------------------------------------------
local lines = Core.CategoryLines(cat.id)
check("category lines collected", #lines == 2)

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

-- Ordering ---------------------------------------------------------------
print("")
local ord = Core.AddCategory("Ordering")
local zeta  = Core.AddEnemy(ord.id, "Zeta")
local alpha = Core.AddEnemy(ord.id, "alpha")
local mid   = Core.AddEnemy(ord.id, "Mid")

local function names(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.name end
    return table.concat(out, ",")
end

local p2, f2 = 0, 0
local function ck(label, cond, got)
    if cond then p2 = p2 + 1 else f2 = f2 + 1 print("  FAIL " .. label .. " -> " .. tostring(got)) end
end

ck("insertion order kept", names(Core.Enemies(ord.id)) == "Zeta,alpha,Mid", names(Core.Enemies(ord.id)))

Core.MoveEnemy(ord.id, mid.id, -1)
ck("moved up one step", names(Core.Enemies(ord.id)) == "Zeta,Mid,alpha", names(Core.Enemies(ord.id)))
Core.MoveEnemy(ord.id, mid.id, -1)
Core.MoveEnemy(ord.id, mid.id, -1)
ck("cannot move past the top", names(Core.Enemies(ord.id)) == "Mid,Zeta,alpha", names(Core.Enemies(ord.id)))

-- Viewing a sort must not rewrite what is stored.
local view = Core.EnemiesInOrder(ord.id, "name", false)
ck("alphabetical view ignores case", names(view) == "alpha,Mid,Zeta", names(view))
ck("stored order untouched by viewing", names(Core.Enemies(ord.id)) == "Mid,Zeta,alpha", names(Core.Enemies(ord.id)))

local desc = Core.EnemiesInOrder(ord.id, "name", true)
ck("reversed view", names(desc) == "Zeta,Mid,alpha", names(desc))

-- Sorting must never disturb what a page plays, which is the page's own order.
local pg = Core.AddPage(ord.id, "Route")
Core.AddEnemyToPage(ord.id, pg.id, zeta.id)
Core.AddEnemyToPage(ord.id, pg.id, alpha.id)
local before = names(Core.PageEnemies(ord.id, pg.id))

Core.SortEnemies(ord.id, "name", false)
ck("sorting rewrites the stored order", names(Core.Enemies(ord.id)) == "alpha,Mid,Zeta", names(Core.Enemies(ord.id)))
ck("page order survives a library sort",
   names(Core.PageEnemies(ord.id, pg.id)) == before,
   names(Core.PageEnemies(ord.id, pg.id)))

print(("ordering: %d passed, %d failed"):format(p2, f2))
if f2 > 0 then os.exit(1) end

-- Variants ---------------------------------------------------------------
print("")
local p3, f3 = 0, 0
local function ck3(label, cond, got)
    if cond then p3 = p3 + 1 else f3 = f3 + 1 print("  FAIL " .. label .. " -> " .. tostring(got)) end
end

local dv = Core.AddCategory("Variant test")
ck3("a new dungeon has one variant", #Core.Variants(dv.id) == 1)
ck3("it is active", Core.ActiveVariantId(dv.id) == Core.Variants(dv.id)[1].id)

local base = Core.AddEnemy(dv.id, "Base mob")
Core.AddLine(dv.id, base.id, "Strat", "/p base call")
local basePage = Core.AddPage(dv.id, "Route")
Core.AddEnemyToPage(dv.id, basePage.id, base.id)

-- Empty variant
local empty = Core.AddVariant(dv.id, "Empty one")
Core.SetActiveVariant(dv.id, empty.id)
ck3("an empty variant starts empty",
    #Core.Enemies(dv.id) == 0 and #Core.Pages(dv.id) == 0,
    #Core.Enemies(dv.id))

-- Copied variant
Core.SetActiveVariant(dv.id, Core.Variants(dv.id)[1].id)
local copy = Core.AddVariant(dv.id, "Copy", Core.Variants(dv.id)[1].id)
Core.SetActiveVariant(dv.id, copy.id)

ck3("a copy carries the enemies", #Core.Enemies(dv.id) == 1)
ck3("a copy carries the lines", #Core.Enemies(dv.id)[1].lines == 1)
ck3("a copy carries the pages", #Core.Pages(dv.id) == 1)
ck3("page references point inside the copy",
    #Core.PageEnemies(dv.id, Core.Pages(dv.id)[1].id) == 1,
    #Core.PageEnemies(dv.id, Core.Pages(dv.id)[1].id))

-- Independence is the whole point of having variants at all.
local copiedEnemy = Core.Enemies(dv.id)[1]
ck3("the copy has its own enemy ids", copiedEnemy.id ~= base.id)
Core.SetLine(dv.id, copiedEnemy.id, copiedEnemy.lines[1].id, nil, "/p changed in the copy")
Core.RenameEnemy(dv.id, copiedEnemy.id, "Renamed in copy")

Core.SetActiveVariant(dv.id, Core.Variants(dv.id)[1].id)
ck3("editing a copy leaves the original alone",
    Core.Enemies(dv.id)[1].lines[1].body == "/p base call",
    Core.Enemies(dv.id)[1].lines[1].body)
ck3("renaming in a copy leaves the original alone",
    Core.Enemies(dv.id)[1].name == "Base mob", Core.Enemies(dv.id)[1].name)

ck3("variants can be renamed", Core.RenameVariant(dv.id, copy.id, "Fortified")
    and Core.Variant(dv.id, copy.id).name == "Fortified")

ck3("a variant can be deleted", Core.DeleteVariant(dv.id, empty.id)
    and #Core.Variants(dv.id) == 2)

-- Deleting the active one must leave something selected, not nothing.
Core.SetActiveVariant(dv.id, copy.id)
Core.DeleteVariant(dv.id, copy.id)
ck3("deleting the active variant selects another",
    Core.Variant(dv.id) ~= nil and #Core.Variants(dv.id) == 1)

ck3("the last variant cannot be deleted",
    not Core.DeleteVariant(dv.id, Core.Variants(dv.id)[1].id))

-- Migration ---------------------------------------------------------------
local old = {
    version = 1,
    activeProfile = "Default",
    profiles = { Default = { categories = {
        { id = "catOld", name = "Pre-variants",
          enemies = { { id = "e1", name = "Old mob", perRow = 1,
                        lines = { { id = "l1", caption = "", body = "/p still here" } } } },
          pages   = { { id = "p1", name = "Old page", enemyIds = { "e1" } } } },
    } } },
}
Core.Init(old)
local migrated = Core.GetCategory("catOld")
ck3("migration wraps old data in a variant", migrated and #migrated.variants == 1)
ck3("nothing is lost", #Core.Enemies("catOld") == 1 and #Core.Pages("catOld") == 1)
ck3("the line survives", Core.Enemies("catOld")[1].lines[1].body == "/p still here",
    Core.Enemies("catOld")[1].lines[1].body)
ck3("page references still resolve", #Core.PageEnemies("catOld", "p1") == 1)
ck3("the old fields are gone", migrated.enemies == nil and migrated.pages == nil)

Core.Init(old)   -- twice must be harmless
ck3("migrating twice changes nothing", #Core.GetCategory("catOld").variants == 1)

print(("variants: %d passed, %d failed"):format(p3, f3))
if f3 > 0 then os.exit(1) end
