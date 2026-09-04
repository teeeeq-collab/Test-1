-- Overlap. Every overlap this addon has shipped was two anchors whose
-- arithmetic nobody added up; the harness now adds it up, so these are checked
-- rather than eyeballed in a screenshot.
local realPrint = print
package.path = "tests/?.lua;" .. package.path
local stub = require("wowstub")
stub.install()
local geom = require("geometry")

local IMI = {}
for _, f in ipairs({ "Libs/LibStub/LibStub", "Libs/LibDeflate/LibDeflate",
                     "Libs/LibSerialize/LibSerialize" }) do
    loadfile("InomrahsMythicInstructions/" .. f .. ".lua")()
end
for _, f in ipairs({ "Util", "Color", "Style", "Core", "History", "Runtime", "UI",
                     "Picker", "Binds", "Edit", "Export", "Starter", "Capture" }) do
    local chunk, err = loadfile("InomrahsMythicInstructions/" .. f .. ".lua")
    if not chunk then realPrint("  FAIL loading " .. f .. ": " .. tostring(err)); os.exit(1) end
    chunk("InomrahsMythicInstructions", IMI)
end

local pass, fail = 0, 0
local function ck(label, cond, got)
    if cond then pass = pass + 1
    else fail = fail + 1; realPrint("  FAIL: " .. label .. (got and ("\n         " .. tostring(got)) or "")) end
end

InomrahsMythicInstructionsDB = IMI.Core.Init({})
IMI.UI.Init()

local cat = IMI.Core.AddCategory("Overlap check")
local mob = IMI.Core.AddEnemy(cat.id, "Mob")
IMI.Core.AddLine(cat.id, mob.id, "", "/p one")
local page = IMI.Core.AddPage(cat.id, "Route")
IMI.Core.AddEnemyToPage(cat.id, page.id, mob.id)

IMI.UI.Show("edit")
IMI.UI.SelectCategory(cat.id)
IMI.Edit.SetCategory(cat.id)

--- Checks a named set of widgets against each other.
---
--- Only what is on screen: two frames may share a rectangle happily as long as
--- they are never shown together, which is how the Enemies and Pages panels
--- work.
local function noOverlaps(what, widgets)
    geom.resetAll(IMI.UI.root, stub)

    local resolved = {}
    for name, frame in pairs(widgets) do
        if frame and frame:IsVisible() then
            local rect, why = geom.rect(frame)
            if rect then
                resolved[#resolved + 1] = { name = name, rect = rect }
            else
                realPrint(("         (%s: %s unresolved — %s)"):format(what, name, tostring(why)))
            end
        end
    end

    local clashes = {}
    for i = 1, #resolved do
        for j = i + 1, #resolved do
            -- A pixel of slack: borders are drawn one pixel outside their
            -- frame and a shared edge is not an overlap.
            if geom.overlaps(resolved[i].rect, resolved[j].rect, 1) then
                clashes[#clashes + 1] = ("%s %s  and  %s %s"):format(
                    resolved[i].name, geom.describe(resolved[i].rect),
                    resolved[j].name, geom.describe(resolved[j].rect))
            end
        end
    end

    ck(what .. ": nothing overlaps", #clashes == 0, table.concat(clashes, "\n         "))
    ck(what .. ": something was actually checked", #resolved >= 2, #resolved)
end

--------------------------------------------------------------------------------
-- The Edit header. This is where both reported overlaps were: the Pages panel
-- started level with the tab buttons, and the character counter and the
-- unbacked-edits marker sat on top of the variant buttons.
--------------------------------------------------------------------------------
IMI.Edit.ShowTab("enemies")
local header = IMI.Edit.HeaderWidgets()
noOverlaps("Edit header, Enemies tab", header)

IMI.Edit.ShowTab("pages")
noOverlaps("Edit header, Pages tab", IMI.Edit.HeaderWidgets())

-- With the counter showing, which is what happens the moment a box has focus.
IMI.Edit.ShowTab("enemies")
local widgets = IMI.Edit.HeaderWidgets()
widgets.counter:Show()
widgets.stale:Show()
noOverlaps("Edit header with the counter and marker showing", widgets)

--------------------------------------------------------------------------------
-- The bar, and the window's own furniture.
--------------------------------------------------------------------------------
noOverlaps("Title bar", IMI.UI.BarWidgets())

--------------------------------------------------------------------------------
-- The dungeon column: the list must end above the stack pinned under it.
--------------------------------------------------------------------------------
IMI.UI.RefreshSidebar()
noOverlaps("Dungeon column", IMI.UI.SidebarWidgets())

--------------------------------------------------------------------------------
-- The rest of it: each panel's own controls, and the row along the bottom.
--------------------------------------------------------------------------------
IMI.Edit.ShowTab("pages")
noOverlaps("Pages panel controls", IMI.Edit.PagesPanelWidgets())

IMI.Edit.ShowTab("enemies")
noOverlaps("Enemies panel controls", IMI.Edit.EnemiesPanelWidgets())
noOverlaps("Edit bottom row", IMI.Edit.BottomRowWidgets())

--------------------------------------------------------------------------------
-- Run: the title shares its strip with the page arrows and the variant chooser.
--------------------------------------------------------------------------------
IMI.UI.Show("run")
IMI.UI.OpenRun(cat.id)
noOverlaps("Run view", IMI.UI.RunWidgets())

-- And with a name long enough to reach for the arrows.
IMI.Core.RenameCategory(cat.id, "A Dungeon With A Very Long Name Indeed Yes")
IMI.UI.OpenRun(cat.id)
noOverlaps("Run view with a long dungeon name", IMI.UI.RunWidgets())
IMI.Core.RenameCategory(cat.id, "Overlap check")

--------------------------------------------------------------------------------
-- The dialogs.
--------------------------------------------------------------------------------
IMI.UI.Show("edit")
IMI.Edit.SetCategory(cat.id)
IMI.UI.Confirm({ title = "Delete dungeon", body = "Really?", accept = "Delete" })
local confirm = IMI.UI.ConfirmFrame().dialog
noOverlaps("Confirmation dialog",
    { title = confirm.title, body = confirm.body,
      accept = confirm.accept, cancel = confirm.cancel })
IMI.UI.ConfirmFrame():Hide()

IMI.Edit.ShowColorPicker()
local picker = IMI.Picker.Frame().dialog
noOverlaps("Colour picker",
    { title = picker.title, field = picker.field, hue = picker.hue,
      swatch = picker.swatchFrame, reset = picker.reset, close = picker.close,
      hueSlider = picker.rows.hue.slider, hueBox = picker.rows.hue.box,
      satSlider = picker.rows.sat.slider, satBox = picker.rows.sat.box,
      valSlider = picker.rows.val.slider, valBox = picker.rows.val.box })
IMI.Picker.Frame():Hide()

IMI.Edit.ShowTab("pages")
IMI.Binds.Open(cat.id, page.id)
local binds = IMI.Binds.Frame().dialog
noOverlaps("Keybind dialog",
    { title = binds.title, help = binds.help, list = binds.scroll,
      clearAll = binds.clearAll, close = binds.close })
IMI.Binds.Frame():Hide()

realPrint(("\nlayout: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
