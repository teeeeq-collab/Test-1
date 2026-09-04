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

-- Every key the client needs more than this addon does. Checked as a list
-- rather than a sample: mutation testing showed that with only three of them
-- tested, the other six could be made bindable without anything noticing.
for _, key in ipairs({ "ESCAPE", "ENTER", "NUMPADENTER", "LSHIFT", "RSHIFT",
                       "LCTRL", "RCTRL", "LALT", "RALT", "UNKNOWN" }) do
    ck(key .. " cannot be bound", Binds.Chord(key) == nil, Binds.Chord(key))
    -- Nor with a modifier held: SHIFT-ESCAPE must not close a door either.
    ck(key .. " cannot be bound with a modifier", Binds.Chord(key, true, true) == nil)
end

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

--------------------------------------------------------------------------------
-- Which branch a row takes. A callout's key belongs to its page; the two paging
-- keys belong to every page. Nothing was checking that the right one was
-- written, so a paging key could have been stored on a page and quietly stopped
-- working on the next one.
--------------------------------------------------------------------------------
-- A dungeon of its own, and the paging keys put back afterwards: this sits in
-- the middle of the file and the checks below it still expect what they set up.
local branchCat = Core.AddCategory("Branching")
local branchMob = Core.AddEnemy(branchCat.id, "Mob")
local branchLine = Core.AddLine(branchCat.id, branchMob.id, "", "/p go")
local branchPage = Core.AddPage(branchCat.id, "One")
Core.AddEnemyToPage(branchCat.id, branchPage.id, branchMob.id)
local keptNext, keptPrev = Core.Settings().pageNextKey, Core.Settings().pagePrevKey

Binds.Assign(branchCat.id, branchPage.id,
    { kind = "line", id = branchLine.id }, "5")
ck("a callout key goes on its page",
    Core.LineBind(branchCat.id, branchPage.id, branchLine.id) == "5")
ck("and not into the paging keys", Core.Settings().pageNextKey ~= "5")

Binds.Assign(branchCat.id, branchPage.id, { kind = "next" }, "6")
ck("a next-page key goes to the setting", Core.Settings().pageNextKey == "6")
ck("and not onto the page", Core.PageBinds(branchCat.id, branchPage.id)["6"] == nil)

Binds.Assign(branchCat.id, branchPage.id, { kind = "prev" }, "7")
ck("a previous-page key goes to its own setting", Core.Settings().pagePrevKey == "7")
ck("without disturbing next", Core.Settings().pageNextKey == "6")

Binds.Assign(branchCat.id, branchPage.id, { kind = "next" }, nil)
ck("clearing a paging key clears it", Core.Settings().pageNextKey == nil)

Core.Settings().pageNextKey, Core.Settings().pagePrevKey = keptNext, keptPrev

--------------------------------------------------------------------------------
-- The badge on a button, and how a chord reads on it.
--------------------------------------------------------------------------------
ck("a plain key reads as itself", Binds.Short("E") == "E", Binds.Short("E"))
ck("a chord reads with a plus", Binds.Short("CTRL-E") == "CTRL+E", Binds.Short("CTRL-E"))
ck("three parts", Binds.Short("ALT-CTRL-SHIFT-F1") == "ALT+CTRL+SHIFT+F1",
    Binds.Short("ALT-CTRL-SHIFT-F1"))
-- Long names would make a badge wider than the button it sits on.
ck("the wheel is shortened", Binds.Short("MOUSEWHEELDOWN") == "MWDn",
    Binds.Short("MOUSEWHEELDOWN"))
ck("the numpad is shortened", Binds.Short("NUMPAD7") == "N7", Binds.Short("NUMPAD7"))
ck("a shortened chord", Binds.Short("SHIFT-NUMPAD7") == "SHIFT+N7",
    Binds.Short("SHIFT-NUMPAD7"))
ck("nothing reads as nothing", Binds.Short(nil) == nil)
ck("an empty key reads as nothing", Binds.Short("") == nil)

-- A badge sized for "E" would be a sliver; one sized for "ALT+CTRL+SHIFT+F1"
-- would cover the button. It follows its text.
local badge = IMI.Style.KeyBadge(IMI.UI.root)
badge:SetKey("E")
local narrow = badge:GetWidth()
badge:SetKey("ALT+CTRL+SHIFT+F1")
ck("a badge grows with its text", badge:GetWidth() > narrow,
    ("%s then %s"):format(tostring(narrow), tostring(badge:GetWidth())))
ck("a badge has a floor", narrow >= 18, narrow)
badge:SetKey(nil)
ck("no key means no badge", not badge:IsShown())

--------------------------------------------------------------------------------
-- Badges appear only where a key exists, whatever the setting says.
--------------------------------------------------------------------------------
Core.Settings().showBindsRun = true
Core.SetLineBind(cat.id, p1.id, l1.id, "CTRL-1")
Core.SetLineBind(cat.id, p1.id, l2.id, nil)
Runtime.Build(IMI.UI.root, cat.id, Core.Settings())

local buttons = Runtime.PageButtons(1)
ck("a bound callout carries a badge", buttons[1].badge:IsShown())
ck("and it reads as the chord", buttons[1].badge.label.text == "CTRL+1",
    buttons[1].badge.label.text)
ck("an unbound callout carries none", not buttons[2].badge:IsShown())

Core.Settings().showBindsRun = false
Runtime.Build(IMI.UI.root, cat.id, Core.Settings())
ck("turning them off hides the badge", not Runtime.PageButtons(1)[1].badge:IsShown())
Core.Settings().showBindsRun = true

--------------------------------------------------------------------------------
-- A line on two pages with two keys has to say both.
--------------------------------------------------------------------------------
Core.SetLineBind(cat.id, p1.id, l1.id, "1")
Core.SetLineBind(cat.id, p2.id, l1.id, "2")
local keys = Core.LineKeys(cat.id, l1.id)
ck("both pages are reported", #keys == 2, #keys)
ck("with the page each belongs to", keys[1].page == "First" and keys[2].page == "Second")
ck("a line with no key reports none", #Core.LineKeys(cat.id, l2.id) == 0)

--------------------------------------------------------------------------------
-- Opening and closing the window from a key, which the slash command cannot do
-- in combat.
--------------------------------------------------------------------------------
local toggle = IMI.UI.ToggleButton()
ck("there is a button for the key to click", toggle ~= nil)
ck("it points at the window", toggle:GetFrameRef("window") == IMI.UI.root)
ck("and toggles from inside the restricted environment",
    tostring(toggle:GetAttribute("_onclick")):find("IsShown", 1, true) ~= nil)

Core.Settings().toggleKey = "CTRL-M"
IMI.UI.ApplyToggleKey()
local bound = stub.bindings[toggle] or {}
ck("the key is bound to it", bound["CTRL-M"] ~= nil, bound["CTRL-M"])

-- Its own owner, so a page flip clearing the pager's bindings cannot take it.
Runtime.ShowPage(1)
bound = stub.bindings[toggle] or {}
ck("turning the page does not unbind it", bound["CTRL-M"] ~= nil)

Core.Settings().toggleKey = nil
IMI.UI.ApplyToggleKey()
bound = stub.bindings[toggle] or {}
ck("clearing it unbinds", bound["CTRL-M"] == nil)

--------------------------------------------------------------------------------
-- A snippet runs on every click the frame accepts, so a frame whose work is a
-- snippet must accept one direction. Registering both ran it on the way down
-- and again on the way up: the window closed while the key was held and
-- reopened on release.
--------------------------------------------------------------------------------
-- Read from what the addon recorded, which is also what the in-game self-test
-- reads: the client offers no way to ask a frame what it registered for.
local function directions(frame)
    return frame and frame.__clickTypes and #frame.__clickTypes or 0
end

ck("the toggle accepts one direction", directions(toggle) == 1, directions(toggle))
ck("so does the close button", directions(IMI.UI.CloseButton()) == 1,
    directions(IMI.UI.CloseButton()))

local arrows = IMI.UI.Arrows()
ck("so do the page arrows",
    directions(arrows.next) == 1 and directions(arrows.prev) == 1)

-- Every one of them, found rather than listed, so a snippet frame added later
-- cannot quietly miss this.
for _, frame in ipairs({ toggle, IMI.UI.CloseButton(), arrows.next, arrows.prev }) do
    if frame:GetAttribute("_onclick") and directions(frame) ~= 1 then
        ck("a snippet frame accepts more than one direction", false, directions(frame))
    end
end

-- The callout buttons are the exception, and a measured one: the probe recorded
-- two clicks and one message, so both directions are what they were built with.
Runtime.Build(IMI.UI.root, cat.id, Core.Settings())
ck("callout buttons keep both, as measured",
    directions(Runtime.PageButtons(1)[1]) == 2, directions(Runtime.PageButtons(1)[1]))

realPrint(("\nbinds: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
