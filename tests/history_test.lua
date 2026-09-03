-- Undo and redo. Snapshot-based, so what is checked is that stepping back and
-- forward reproduces states exactly, including the parts of the schema an
-- inverse-operation implementation would be most likely to miss: page
-- references to a deleted enemy, and ordering.
package.path = "tests/?.lua;" .. package.path
local IMI = {}
loadfile("InomrahsMythicInstructions/Util.lua")("InomrahsMythicInstructions", IMI)
loadfile("InomrahsMythicInstructions/Core.lua")("InomrahsMythicInstructions", IMI)
loadfile("InomrahsMythicInstructions/History.lua")("InomrahsMythicInstructions", IMI)
local Core, History = IMI.Core, IMI.History

local pass, fail = 0, 0
local function ck(label, cond, got)
    if cond then pass = pass + 1
    else fail = fail + 1; print("  FAIL: " .. label .. (got and ("  got: " .. tostring(got)) or "")) end
end

local function names(catId)
    local out = {}
    for _, e in ipairs(Core.Enemies(catId)) do out[#out + 1] = e.name end
    return table.concat(out, ",")
end

--------------------------------------------------------------------------------
Core.Init({})
History.Init(function() return { marker = "nowhere" } end)

ck("nothing to undo at the start", not History.CanUndo())
ck("nor to redo", not History.CanRedo())
ck("undo on an empty stack answers nil", History.Undo() == nil)

local cat = Core.AddCategory("Halls")
ck("adding a dungeon is one step", History.CanUndo())

Core.AddEnemy(cat.id, "First")
Core.AddEnemy(cat.id, "Second")
Core.AddEnemy(cat.id, "Third")
ck("three enemies", names(cat.id) == "First,Second,Third", names(cat.id))

History.Undo()
ck("undo takes back the last enemy", names(cat.id) == "First,Second", names(cat.id))
History.Undo()
ck("and the one before", names(cat.id) == "First", names(cat.id))
History.Redo()
ck("redo puts it back", names(cat.id) == "First,Second", names(cat.id))
History.Redo()
ck("and the next", names(cat.id) == "First,Second,Third", names(cat.id))
ck("nothing left to redo", not History.CanRedo())

-- A new change after undoing has to make the undone future unreachable.
History.Undo()
Core.AddEnemy(cat.id, "Different")
ck("a change after undo clears the redo stack", not History.CanRedo())
ck("and the new one stands", names(cat.id) == "First,Second,Different", names(cat.id))

--------------------------------------------------------------------------------
-- The case an inverse-operation undo gets wrong: deleting an enemy also strips
-- it from every page referencing it, and putting it back has to restore both.
--------------------------------------------------------------------------------
Core.Init({})
History.Init(function() return nil end)

local dungeon = Core.AddCategory("Kings' Rest")
local a = Core.AddEnemy(dungeon.id, "Matriarch")
local b = Core.AddEnemy(dungeon.id, "Adds")
Core.AddLine(dungeon.id, a.id, "Kick", "/p kick the heal")
Core.AddLine(dungeon.id, a.id, "", "/p stack for the cone")
local p1 = Core.AddPage(dungeon.id, "Left")
local p2 = Core.AddPage(dungeon.id, "Right")
Core.AddEnemyToPage(dungeon.id, p1.id, a.id)
Core.AddEnemyToPage(dungeon.id, p2.id, a.id)
Core.AddEnemyToPage(dungeon.id, p2.id, b.id)

ck("the enemy is on both pages",
    #Core.PageEnemies(dungeon.id, p1.id) == 1 and #Core.PageEnemies(dungeon.id, p2.id) == 2)

Core.DeleteEnemy(dungeon.id, a.id)
ck("deleting strips it from the pages",
    #Core.PageEnemies(dungeon.id, p1.id) == 0 and #Core.PageEnemies(dungeon.id, p2.id) == 1)

History.Undo()
ck("undo brings the enemy back", #Core.Enemies(dungeon.id) == 2, #Core.Enemies(dungeon.id))
ck("with both its lines", #Core.Enemies(dungeon.id)[1].lines == 2)
ck("and back onto both pages",
    #Core.PageEnemies(dungeon.id, p1.id) == 1 and #Core.PageEnemies(dungeon.id, p2.id) == 2)
ck("in its original position", Core.Enemies(dungeon.id)[1].name == "Matriarch",
    Core.Enemies(dungeon.id)[1].name)
ck("and the line text is intact",
    Core.Enemies(dungeon.id)[1].lines[1].body == "/p kick the heal",
    Core.Enemies(dungeon.id)[1].lines[1].body)

--------------------------------------------------------------------------------
-- Undoing a whole dungeon, and reordering.
--------------------------------------------------------------------------------
Core.Init({})
History.Init(function() return nil end)
local one = Core.AddCategory("One")
Core.AddCategory("Two")
Core.AddCategory("Three")

Core.MoveCategoryTo(one.id, 3)
local function order()
    local out = {}
    for _, c in ipairs(Core.Categories()) do out[#out + 1] = c.name end
    return table.concat(out, ",")
end
ck("moved", order() == "Two,Three,One", order())
History.Undo()
ck("undo restores the order", order() == "One,Two,Three", order())

Core.DeleteCategory(one.id)
ck("deleted", order() == "Two,Three", order())
History.Undo()
ck("undo brings a whole dungeon back", order() == "One,Two,Three", order())
ck("and by the same id", Core.GetCategory(one.id) ~= nil)

--------------------------------------------------------------------------------
-- Where the change was made travels with the step.
--------------------------------------------------------------------------------
Core.Init({})
local where = { page = "start" }
History.Init(function() return { page = where.page } end)

local c = Core.AddCategory("Context")           -- recorded while on "start"
where.page = "second"
Core.AddEnemy(c.id, "Mob")                       -- recorded while on "second"

local ctx = History.Undo()
ck("undo reports where that change was made", ctx and ctx.page == "second",
    ctx and ctx.page)
ctx = History.Undo()
ck("and the step before it", ctx and ctx.page == "start", ctx and ctx.page)

--------------------------------------------------------------------------------
-- Boundaries.
--------------------------------------------------------------------------------
Core.Init({})
History.Init(function() return nil end)

-- Settings are outside history: undo should take back a callout, not a slider.
Core.Settings().opacity = 0.5
ck("changing a setting records nothing", not History.CanUndo())

-- Silently is for loading and migrating, which are not the user's edits.
History.Silently(function() Core.AddCategory("Loaded") end)
ck("a silent change records nothing", not History.CanUndo())
ck("but it did happen", #Core.Categories() == 1)

local deep = Core.AddCategory("Deep")
for i = 1, 45 do Core.AddEnemy(deep.id, "Mob " .. i) end
local undoDepth = History.Depth()
ck("the stack is capped", undoDepth == 30, undoDepth)
for _ = 1, 30 do History.Undo() end
ck("undoing everything held leaves nothing", not History.CanUndo())
ck("and stops rather than erroring", History.Undo() == nil)
-- Capped means the oldest steps are gone, not that the data is corrupt.
ck("what is left is coherent", type(Core.Categories()) == "table")

print(("\nhistory: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
