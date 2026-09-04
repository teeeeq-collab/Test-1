-- Keybinds. What matters is that a key means one thing on a page, that keys
-- follow the line rather than the position, and that the same key can mean
-- something different on the next page.
local realPrint = print
package.path = "tests/?.lua;" .. package.path
local stub = require("wowstub")
stub.install()

local IMI = {}
for _, f in ipairs({ "Util", "Color", "Style", "Core", "History", "Runtime", "UI",
                     "Picker", "Binds", "Edit" }) do
    local chunk, err = loadfile("InomrahsMythicInstructions/" .. f .. ".lua")
    if not chunk then realPrint("  FAIL loading " .. f .. ": " .. tostring(err)); os.exit(1) end
    chunk("InomrahsMythicInstructions", IMI)
end

local Core, Binds, Runtime = IMI.Core, IMI.Binds, IMI.Runtime

local pass, fail = 0, 0
local function ck(label, cond, got)
    if cond then pass = pass + 1
    else fail = fail + 1; realPrint("  FAIL: " .. label .. (got and ("  got: " .. tostring(got)) or "")) end
end

InomrahsMythicInstructionsDB = Core.Init({})

local cat = Core.AddCategory("Keys")
local mob = Core.AddEnemy(cat.id, "Mob")
local l1 = Core.AddLine(cat.id, mob.id, "", "/p one")
local l2 = Core.AddLine(cat.id, mob.id, "", "/p two")
local p1 = Core.AddPage(cat.id, "First")
local p2 = Core.AddPage(cat.id, "Second")
Core.AddEnemyToPage(cat.id, p1.id, mob.id)
Core.AddEnemyToPage(cat.id, p2.id, mob.id)

--------------------------------------------------------------------------------
Core.SetLineBind(cat.id, p1.id, l1.id, "1")
ck("a key is stored", Core.LineBind(cat.id, p1.id, l1.id) == "1")

-- The point of pages: the same key, a different callout.
Core.SetLineBind(cat.id, p2.id, l2.id, "1")
ck("the same key on another page is its own",
    Core.LineBind(cat.id, p2.id, l2.id) == "1" and Core.LineBind(cat.id, p2.id, l1.id) == nil)
ck("and does not disturb the first page", Core.LineBind(cat.id, p1.id, l1.id) == "1")

-- A key can only mean one thing on a page. Leaving both would make which one
-- fires depend on table order.
Core.SetLineBind(cat.id, p1.id, l2.id, "1")
ck("assigning a taken key takes it", Core.LineBind(cat.id, p1.id, l2.id) == "1")
ck("and clears the old holder", Core.LineBind(cat.id, p1.id, l1.id) == nil)

Core.SetLineBind(cat.id, p1.id, l2.id, nil)
ck("a key can be cleared", Core.LineBind(cat.id, p1.id, l2.id) == nil)

-- Keys follow the line, not its position, so reordering must not move them.
Core.SetLineBind(cat.id, p1.id, l2.id, "3")
Core.MoveEnemy(cat.id, mob.id, 1)
ck("reordering does not move a key", Core.LineBind(cat.id, p1.id, l2.id) == "3")

-- A key pointing at a deleted line has nothing to fire.
local doomed = Core.AddLine(cat.id, mob.id, "", "/p gone soon")
Core.SetLineBind(cat.id, p1.id, doomed.id, "4")
Core.DeleteLine(cat.id, mob.id, doomed.id)
ck("a key outlives its line until pruned", Core.LineBind(cat.id, p1.id, doomed.id) == "4")
ck("pruning removes it", Core.PruneBinds(cat.id, p1.id) == 1)
ck("and leaves the live ones", Core.LineBind(cat.id, p1.id, l2.id) == "3")

--------------------------------------------------------------------------------
-- Chords: one spelling per chord, whatever order the modifiers are read in.
--------------------------------------------------------------------------------
ck("a plain key", Binds.Chord("1") == "1")
ck("shift", Binds.Chord("1", true) == "SHIFT-1")
ck("ctrl and shift keep a fixed order",
    Binds.Chord("1", true, true) == "ALT-CTRL-SHIFT-1"
    or Binds.Chord("1", true, true) == "CTRL-SHIFT-1", Binds.Chord("1", true, true))
ck("all three", Binds.Chord("F1", true, true, true) == "ALT-CTRL-SHIFT-F1",
    Binds.Chord("F1", true, true, true))

-- Escape has to keep working, and a bare modifier is not a binding.
ck("escape is refused", Binds.Chord("ESCAPE") == nil)
ck("a bare shift is refused", Binds.Chord("LSHIFT") == nil)
ck("enter is refused", Binds.Chord("ENTER") == nil)

--------------------------------------------------------------------------------
-- The dialog's row list, and what conflicts with what.
--------------------------------------------------------------------------------
local rows = Binds.Rows(cat.id, p1.id)
ck("every line on the page is listed", #rows >= 2)
ck("paging is listed too", rows[#rows - 1].kind == "next" and rows[#rows].kind == "prev")

Core.Settings().pageNextKey = "9"
rows = Binds.Rows(cat.id, p1.id)
local index = Binds.Conflict(rows, "9")
ck("a paging key conflicts with a callout key", index ~= nil)
ck("a free key conflicts with nothing", Binds.Conflict(rows, "K") == nil)
Core.SetLineBind(cat.id, p1.id, l1.id, "7")
rows = Binds.Rows(cat.id, p1.id)
ck("a row does not conflict with itself",
    Binds.Conflict(rows, "7", 1) == nil)
ck("but does conflict with another row", Binds.Conflict(rows, "7") == 1)
-- An unset key must not read as clashing with every other unset row.
ck("no key conflicts with nothing", Binds.Conflict(rows, nil) == nil)
ck("nor does an empty one", Binds.Conflict(rows, "") == nil)

--------------------------------------------------------------------------------
-- What is actually live: the bindings applied when a page is shown.
--------------------------------------------------------------------------------
Core.Settings().pageNextKey, Core.Settings().pagePrevKey = "PAGEDOWN", "PAGEUP"
Core.SetLineBind(cat.id, p1.id, l1.id, "1")
Core.SetLineBind(cat.id, p2.id, l2.id, "1")

IMI.UI.Init()
local arrows = IMI.UI.Arrows()
Runtime.EnsureManager(IMI.UI.root)
Runtime.BindArrow(arrows.prev, -1)
Runtime.BindArrow(arrows.next, 1)

local ok, err = Runtime.Build(IMI.UI.root, cat.id, Core.Settings())
ck("the dungeon builds with keys on it", ok, err)

Runtime.ShowPage(1)
local live = stub.bindings[Runtime.Manager()] or {}
ck("the page's key is live", live["1"] ~= nil, live["1"])
ck("the paging keys are live", live["PAGEDOWN"] ~= nil and live["PAGEUP"] ~= nil)
local firstTarget = live["1"]

Runtime.ShowPage(2)
live = stub.bindings[Runtime.Manager()] or {}
ck("the same key is still live on page two", live["1"] ~= nil)
ck("but points at a different button", live["1"] ~= firstTarget,
    tostring(live["1"]) .. " vs " .. tostring(firstTarget))
ck("paging keys carried across", live["PAGEDOWN"] ~= nil)

-- A page with no keys must leave none behind from the page before it.
Core.SetLineBind(cat.id, p2.id, l2.id, nil)
Runtime.Build(IMI.UI.root, cat.id, Core.Settings())
Runtime.ShowPage(2)
live = stub.bindings[Runtime.Manager()] or {}
ck("a cleared key does not survive the rebuild", live["1"] == nil, live["1"])
ck("and paging still works", live["PAGEDOWN"] ~= nil)

realPrint(("\nbinds: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
