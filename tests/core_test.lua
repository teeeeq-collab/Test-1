local MM = {}
loadfile("MythicMacros/Util.lua")("MythicMacros", MM)
loadfile("MythicMacros/Core.lua")("MythicMacros", MM)
local Core, Util = MM.Core, MM.Util

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

ck("insertion order kept", names(ord.enemies) == "Zeta,alpha,Mid", names(ord.enemies))

Core.MoveEnemy(ord.id, mid.id, -1)
ck("moved up one step", names(ord.enemies) == "Zeta,Mid,alpha", names(ord.enemies))
Core.MoveEnemy(ord.id, mid.id, -1)
Core.MoveEnemy(ord.id, mid.id, -1)
ck("cannot move past the top", names(ord.enemies) == "Mid,Zeta,alpha", names(ord.enemies))

-- Viewing a sort must not rewrite what is stored.
local view = Core.EnemiesInOrder(ord.id, "name", false)
ck("alphabetical view ignores case", names(view) == "alpha,Mid,Zeta", names(view))
ck("stored order untouched by viewing", names(ord.enemies) == "Mid,Zeta,alpha", names(ord.enemies))

local desc = Core.EnemiesInOrder(ord.id, "name", true)
ck("reversed view", names(desc) == "Zeta,Mid,alpha", names(desc))

-- Sorting must never disturb what a page plays, which is the page's own order.
local pg = Core.AddPage(ord.id, "Route")
Core.AddEnemyToPage(ord.id, pg.id, zeta.id)
Core.AddEnemyToPage(ord.id, pg.id, alpha.id)
local before = names(Core.PageEnemies(ord.id, pg.id))

Core.SortEnemies(ord.id, "name", false)
ck("sorting rewrites the stored order", names(ord.enemies) == "alpha,Mid,Zeta", names(ord.enemies))
ck("page order survives a library sort",
   names(Core.PageEnemies(ord.id, pg.id)) == before,
   names(Core.PageEnemies(ord.id, pg.id)))

print(("ordering: %d passed, %d failed"):format(p2, f2))
if f2 > 0 then os.exit(1) end
