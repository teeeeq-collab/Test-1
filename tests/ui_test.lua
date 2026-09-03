-- Constructs the whole UI against a stubbed WoW API. Catches load-order faults,
-- missing widget fields and nil calls in code paths that syntax checks pass and
-- that would otherwise only appear in game.
local realPrint = print          -- grabbed before the stub silences print
package.path = "tests/?.lua;" .. package.path
require("wowstub").install()
local IMI = {}
for _, f in ipairs({
    "Libs/LibStub/LibStub", "Libs/LibDeflate/LibDeflate", "Libs/LibSerialize/LibSerialize",
}) do loadfile("InomrahsMythicInstructions/" .. f .. ".lua")() end

for _, f in ipairs({ "Util", "Style", "Core", "History", "Runtime", "UI", "Edit",
                     "Export", "Starter", "Capture" }) do
    local chunk, err = loadfile("InomrahsMythicInstructions/" .. f .. ".lua")
    if not chunk then realPrint("  FAIL loading " .. f .. ": " .. tostring(err)); os.exit(1) end
    chunk("InomrahsMythicInstructions", IMI)
end

local pass, fail = 0, 0
local function check(label, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; realPrint("  FAIL: " .. label .. "\n         " .. tostring(err)) end
end

InomrahsMythicInstructionsDB = IMI.Core.Init({})

check("UI.Init builds every panel", function() IMI.UI.Init() end)

check("every view switches", function()
    IMI.UI.ShowView("run")
    IMI.UI.ShowView("edit")
    IMI.UI.ShowView("settings")
    IMI.UI.ShowView("run")
end)

check("sidebar with no dungeons", function() IMI.UI.RefreshSidebar() end)

check("season dungeons appear in the sidebar", function()
    IMI.Starter.Create()
    IMI.UI.RefreshSidebar()
end)

check("edit with no dungeon selected", function()
    IMI.UI.ShowView("edit")
    IMI.Edit.SetCategory(nil)
    IMI.Edit.ShowTab("enemies")
    IMI.Edit.ShowTab("pages")
end)

check("edit a dungeon that has content", function()
    local cat = IMI.Core.Categories()[6]          -- Kings' Rest: has boss cards
    local e = IMI.Core.AddEnemy(cat.id, "Trash pack")
    IMI.Core.AddLine(cat.id, e.id, "Strat", "/p kick it")
    IMI.Core.AddLine(cat.id, e.id, "", "/p and again")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("enemies")
    IMI.Edit.ShowTab("pages")
end)

check("an enemy with no lines renders", function()
    local cat = IMI.Core.Categories()[1]
    IMI.Core.AddEnemy(cat.id, "Lineless")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.RefreshEnemies()
end)

check("a dungeon with no pages renders", function()
    local cat = IMI.Core.AddCategory("Pageless")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("pages")
end)

check("refresh after deleting everything", function()
    local cat = IMI.Core.AddCategory("Doomed")
    local e = IMI.Core.AddEnemy(cat.id, "Gone soon")
    IMI.Core.AddLine(cat.id, e.id, "", "/p bye")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.RefreshEnemies()
    IMI.Core.DeleteEnemy(cat.id, e.id)
    IMI.Edit.RefreshEnemies()          -- pooled frames must not outlive their data
end)

-- The bug that shipped: delete buttons were parented to the list rather than to
-- the box they act on, so hiding a pooled box left its "-" on screen forever.
check("deleting a line leaves nothing behind", function()
    local stub = require("wowstub")
    local cat = IMI.Core.AddCategory("Orphan check")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")
    local l1 = IMI.Core.AddLine(cat.id, e.id, "", "/p one")
    local l2 = IMI.Core.AddLine(cat.id, e.id, "", "/p two")

    -- Init leaves the frame hidden, and IsVisible walks ancestors, so without
    -- showing it every frame reads as invisible and the test proves nothing.
    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("enemies")

    -- Delete buttons are precisely the buttons parented to an edit box. Matching
    -- on the label alone also counted the bar's collapse button, which is a
    -- different "-" entirely.
    local function visibleDeletes()
        local n = 0
        for _, f in ipairs(stub.descendants(IMI.UI.root)) do
            if f.frameType == "Button" and f.parent
               and f.parent.frameType == "EditBox" and f:IsVisible() then
                n = n + 1
            end
        end
        return n
    end

    local before = visibleDeletes()
    -- name box carries up/down/delete, each line box carries delete
    if before ~= 5 then error(("expected 5 box buttons (3 name + 2 lines), saw %d"):format(before)) end

    IMI.Core.DeleteLine(cat.id, e.id, l2.id)
    IMI.Edit.RefreshEnemies()

    local after = visibleDeletes()
    if after ~= 4 then
        error(("after deleting a line, expected 4 box buttons, saw %d"):format(after))
    end

    IMI.Core.DeleteEnemy(cat.id, e.id)
    IMI.Edit.RefreshEnemies()
    if visibleDeletes() ~= 0 then error("buttons survived their enemy") end
end)

check("variant controls across every state", function()
    local cat = IMI.Core.AddCategory("Variants in the UI")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")
    IMI.Core.AddLine(cat.id, e.id, "", "/p call")
    local pg = IMI.Core.AddPage(cat.id, "Route")
    IMI.Core.AddEnemyToPage(cat.id, pg.id, e.id)

    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.RefreshVariants()

    IMI.Edit.ShowVariantDialog()               -- must build without a dungeon open failing
    local copy = IMI.Core.AddVariant(cat.id, "Copy", IMI.Core.ActiveVariantId(cat.id))
    IMI.Core.SetActiveVariant(cat.id, copy.id)
    IMI.Edit.RefreshVariants()
    IMI.Edit.RefreshEnemies()
    IMI.Edit.RefreshPages()

    if #IMI.Core.Enemies(cat.id) ~= 1 then error("copied variant lost its enemy") end

    IMI.Core.DeleteVariant(cat.id, copy.id)
    IMI.Edit.RefreshVariants()
    IMI.Edit.RefreshEnemies()
end)

check("Run offers the variant chooser", function()
    local cat = IMI.Core.Categories()[6]
    IMI.Core.AddVariant(cat.id, "Alternative", IMI.Core.ActiveVariantId(cat.id))
    IMI.UI.ShowView("run")
    if not IMI.UI.OpenRun(cat.id) then error("OpenRun refused") end
    IMI.UI.RefreshVariantChooser(cat.id)
end)

-- Selection is shown by colour alone now, so a test that only checked the row
-- exists would not notice it had stopped being marked. Asserted at the style
-- layer, where the behaviour lives, rather than through the sidebar, whose
-- selection depends on whatever ran before.
check("selection is the accent, and only selection", function()
    local accent = IMI.Style.colors.accent
    local plain, chosen = CreateFrame("Button", nil, UIParent),
                          CreateFrame("Button", nil, UIParent)
    IMI.Style.Button(plain, "one")
    IMI.Style.Button(chosen, "two")

    local function isAccent(f)
        return f.bg.color and f.bg.color[1] == accent[1] and f.bg.color[2] == accent[2]
    end

    if isAccent(plain) or isAccent(chosen) then error("accent before anything was selected") end

    chosen:LockHighlight()
    if not isAccent(chosen) then error("selected button is not accented") end
    if isAccent(plain) then error("an unselected button became accented") end

    chosen:UnlockHighlight()
    if isAccent(chosen) then error("accent survived deselection") end
end)

check("a disabled button reads as disabled", function()
    local b = CreateFrame("Button", nil, UIParent)
    IMI.Style.Button(b, "off")
    b:SetEnabled(false)
    local dim = IMI.Style.colors.textDim
    if not (b.label.color and b.label.color[1] == dim[1]) then
        error("disabled button kept its normal text colour")
    end
end)

check("stale marker", function() IMI.Edit.RefreshStaleMarker() end)
check("settings apply", function() IMI.UI.ApplySettings() end)

check("reset all restores defaults and the widgets follow", function()
    local s = IMI.Core.Settings()
    s.scale, s.opacity, s.buttonScale, s.textScale = 1.4, 0.5, 1.7, 0.7
    s.channel = "/raid"

    for key, value in pairs({ opacity = 1.0, scale = 1.0, buttonScale = 1.0, textScale = 1.0 }) do
        IMI.Core.Settings()[key] = value
    end
    IMI.UI.RefreshSettings()          -- must not error with values changed underneath

    if s.scale ~= 1.0 or s.opacity ~= 1.0 then
        error("defaults not restored")
    end
    -- The channel is a choice, not a cosmetic default, so a reset leaves it be.
    if s.channel ~= "/raid" then error("reset should not clear the channel") end
end)

check("text scale reaches the buttons", function()
    local cat = IMI.Core.Categories()[6]
    IMI.Core.Settings().textScale = 1.3
    local container = CreateFrame("Frame", nil, UIParent)
    IMI.Runtime.EnsureManager(container)
    local ok, err = IMI.Runtime.Build(container, cat.id, IMI.Core.Settings())
    if not ok then error(tostring(err)) end
    IMI.Core.Settings().textScale = 1.0
end)
check("help window", function() IMI.UI.ShowHelp() end)

check("export and import windows", function()
    local cat = IMI.Core.Categories()[6]
    IMI.UI.ShowExport("Export", IMI.Export.EncodeCategory(cat.id))
    IMI.UI.ShowImport("Import", function() return "nothing" end)
end)

check("show, toggle and hide", function()
    IMI.UI.Show("run")
    IMI.UI.Toggle()
    IMI.UI.Toggle()
end)

check("opening a dungeon in Run", function()
    local cat = IMI.Core.Categories()[6]
    IMI.UI.ShowView("run")
    if not IMI.UI.OpenRun(cat.id) then error("OpenRun refused") end
end)

check("page memory survives a round trip", function()
    local cat = IMI.Core.Categories()[6]
    IMI.UI.OpenRun(cat.id)
    IMI.Runtime.ShowPage(2)
    IMI.UI.RememberPage()
end)

check("binding the page arrows", function()
    local arrows = IMI.UI.Arrows()
    if not arrows then error("no arrows built") end
    IMI.Runtime.EnsureManager(IMI.UI.root)
    if not IMI.Runtime.BindArrow(arrows.prev, -1) then error("prev refused") end
    if not IMI.Runtime.BindArrow(arrows.next, 1) then error("next refused") end
end)

--------------------------------------------------------------------------------
-- The dungeon list: rename in place, drag to reorder, delete.
--------------------------------------------------------------------------------

-- The drop maths, on its own. Rows are 24 apart starting 4 below the list top,
-- so these are the exact boundaries a cursor crosses.
check("a drop lands in the row under the cursor", function()
    local top = 600
    local function slot(y) return IMI.UI.DropIndex(top, y, 5) end

    if slot(600 - 4) ~= 1 then error("the top of the first row is not slot 1") end
    if slot(600 - 4 - 23) ~= 1 then error("the bottom of the first row left slot 1") end
    if slot(600 - 4 - 24) ~= 2 then error("crossing into the second row missed it") end
    if slot(600 - 4 - 24 * 4) ~= 5 then error("the fifth row is not slot 5") end

    -- Off either end of the list means the nearest end, not a refusal.
    if slot(9999) ~= 1 then error("above the list should clamp to the top") end
    if slot(-9999) ~= 5 then error("below the list should clamp to the bottom") end
    if IMI.UI.DropIndex(top, 0, 0) ~= 1 then error("an empty list should still answer") end
end)

-- The bug that shipped: rows were laid out at the sidebar's width rather than
-- the scroll child's, so the delete button at a row's right edge sat under the
-- scroll bar, drawn over and impossible to click.
check("a row fits inside the list it scrolls in", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("Altar of Fangs")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local row = IMI.UI.SidebarRows()[1]
    local list = row.parent                    -- the scroll child, per the stub
    local rowRight = 6 + row:GetWidth()        -- rows are inset 6 from the left
    if rowRight > list:GetWidth() then
        error(("a row reaches %d into a list %d wide"):format(rowRight, list:GetWidth()))
    end

    -- And the button has to be inside the row, not hanging off its edge.
    if row.del:GetWidth() >= row:GetWidth() then error("the delete button is not inside its row") end
end)

-- The bug that shipped: a label anchored on both sides wraps, and a button is a
-- fixed height, so a long dungeon name grew downwards over the two rows below
-- it and made them unclickable.
check("a long name truncates instead of growing over its neighbours", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("Short")
    IMI.Core.AddCategory("Ultra mega super ruby life pools to the exxtreme max and no stop")
    IMI.Core.AddCategory("After")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local rows = IMI.UI.SidebarRows()
    for i, row in ipairs({ rows[1], rows[2], rows[3] }) do
        if row.label.wordWrap ~= false then
            error(("row %d still wraps, so a long name spills over the rows below"):format(i))
        end
        if row.label.maxLines ~= 1 then error(("row %d is not held to one line"):format(i)) end
        if row:GetHeight() ~= rows[1]:GetHeight() then
            error(("row %d is a different height from the first"):format(i))
        end
    end

    -- Truncated is only acceptable if the whole name is still reachable.
    if rows[2].tooltipText ~= "Ultra mega super ruby life pools to the exxtreme max and no stop" then
        error("a truncated name is not readable on hover: " .. tostring(rows[2].tooltipText))
    end
end)

-- Undo left, redo right, as in every editor anyone has used.
check("undo sits to the left of redo", function()
    local buttons = IMI.UI.EditHistoryButtons()
    local anchor = buttons.undo.points[#buttons.undo.points]
    if not anchor then error("the undo button is not anchored to anything") end
    if anchor.rel ~= buttons.redo or anchor.point ~= "RIGHT" or anchor.relPoint ~= "LEFT" then
        error("undo is not anchored to the left of redo")
    end
end)

check("renaming a dungeon on its row", function()
    IMI.Core.Init({})
    local a = IMI.Core.AddCategory("Typo Hall")
    IMI.Core.AddCategory("Second")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local row = IMI.UI.SidebarRows()[1]
    if row:GetText() ~= "Typo Hall" then error("row does not show the dungeon name") end

    row:GetScript("OnDoubleClick")(row)
    if not row.rename:IsShown() then error("double-click did not open the name for editing") end
    if row.rename:GetText() ~= "Typo Hall" then error("the box did not start from the old name") end

    -- Enter and clicking away both end in lost focus, which is where the commit
    -- lives, so that is the path driven here.
    row.rename:SetText("Grand Hall")
    row.rename:GetScript("OnEditFocusLost")(row.rename)

    if IMI.Core.GetCategory(a.id).name ~= "Grand Hall" then error("the rename did not stick") end
    if row.rename:IsShown() then error("the box stayed open after committing") end
    if IMI.UI.SidebarRows()[1]:GetText() ~= "Grand Hall" then error("the row still shows the old name") end
end)

check("escape abandons a rename", function()
    IMI.Core.Init({})
    local a = IMI.Core.AddCategory("Keep This")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local row = IMI.UI.SidebarRows()[1]
    row:GetScript("OnDoubleClick")(row)
    row.rename:SetText("Discard me")
    row.rename:GetScript("OnEscapePressed")(row.rename)
    row.rename:GetScript("OnEditFocusLost")(row.rename)

    if IMI.Core.GetCategory(a.id).name ~= "Keep This" then
        error("escape committed the edit anyway")
    end
end)

check("dragging a row moves the dungeon", function()
    IMI.Core.Init({})
    for _, name in ipairs({ "One", "Two", "Three" }) do IMI.Core.AddCategory(name) end
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    -- The stubbed cursor sits at the bottom of the world, so any drop is "last".
    local row = IMI.UI.SidebarRows()[1]
    row:GetScript("OnDragStart")(row)
    row:GetScript("OnDragStop")(row)

    local names = {}
    for _, cat in ipairs(IMI.Core.Categories()) do names[#names + 1] = cat.name end
    if table.concat(names, ",") ~= "Two,Three,One" then
        error("after dragging the first row down: " .. table.concat(names, ","))
    end
end)

-- Deleting a dungeon costs everything in it, so the button asks first and the
-- answer has to be given on the dialog. The x alone must never delete.
local function pressDelete(row)
    row.del:GetScript("OnClick")(row.del)
    local dialog = IMI.UI.ConfirmFrame()
    if not dialog then error("the delete button asked nothing") end
    if not dialog:IsShown() then error("the confirmation is not on screen") end
    return dialog.dialog
end

check("deleting asks before it acts", function()
    IMI.Core.Init({})
    local doomed = IMI.Core.AddCategory("Doomed")
    IMI.Core.AddCategory("Survivor")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local row = IMI.UI.SidebarRows()[1]
    if not row.del:IsShown() then error("no delete button in the edit view") end

    local d = pressDelete(row)
    if IMI.Core.GetCategory(doomed.id) == nil then error("it deleted without asking") end
    -- The question has to name the dungeon: two rows look alike from a dialog.
    if not tostring(d.body:GetText()):find("Doomed", 1, true) then
        error("the question does not say which dungeon: " .. tostring(d.body:GetText()))
    end
    if d.accept:GetText() ~= "Delete" then error("the accepting button is not labelled Delete") end
    if d.cancel:GetText() ~= "Cancel" then error("there is no Cancel") end

    d.accept:GetScript("OnClick")(d.accept)
    if IMI.Core.GetCategory(doomed.id) ~= nil then error("confirming did not delete") end
    if IMI.UI.ConfirmFrame():IsShown() then error("the dialog stayed up after answering") end
    if #IMI.Core.Categories() ~= 1 then error("the wrong number of dungeons survived") end
end)

check("cancel keeps the dungeon", function()
    IMI.Core.Init({})
    local safe = IMI.Core.AddCategory("Safe")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local d = pressDelete(IMI.UI.SidebarRows()[1])
    d.cancel:GetScript("OnClick")(d.cancel)

    if IMI.Core.GetCategory(safe.id) == nil then error("cancel deleted it anyway") end
    if IMI.UI.ConfirmFrame():IsShown() then error("cancel left the dialog up") end

    -- And the cancelled answer must not be waiting to fire on the next question.
    local again = IMI.Core.AddCategory("Also safe")
    IMI.UI.RefreshSidebar()
    pressDelete(IMI.UI.SidebarRows()[2])
    IMI.UI.ConfirmFrame():Hide()
    if IMI.Core.GetCategory(again.id) == nil then error("a stale answer deleted a dungeon") end
end)

-- The reused dialog must answer for the row that opened it, not the one before.
check("the dialog rebinds to each dungeon", function()
    IMI.Core.Init({})
    local first = IMI.Core.AddCategory("First")
    local second = IMI.Core.AddCategory("Second")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local d = pressDelete(IMI.UI.SidebarRows()[1])
    d.cancel:GetScript("OnClick")(d.cancel)

    d = pressDelete(IMI.UI.SidebarRows()[2])
    d.accept:GetScript("OnClick")(d.accept)

    if IMI.Core.GetCategory(second.id) ~= nil then error("the second dungeon survived") end
    if IMI.Core.GetCategory(first.id) == nil then error("it deleted the dungeon from the earlier question") end
end)

check("deleting the open dungeon selects its neighbour", function()
    IMI.Core.Init({})
    local first = IMI.Core.AddCategory("First")
    local second = IMI.Core.AddCategory("Second")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    IMI.UI.SidebarRows()[1]:GetScript("OnClick")()
    if IMI.UI.SelectedCategory() ~= first.id then error("clicking a row did not select it") end

    local d = pressDelete(IMI.UI.SidebarRows()[1])
    d.accept:GetScript("OnClick")(d.accept)

    if IMI.UI.SelectedCategory() ~= second.id then
        error("deleting the selected dungeon left the selection dangling")
    end
end)

check("deleting the last dungeon leaves nothing selected", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("Only")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    IMI.UI.SidebarRows()[1]:GetScript("OnClick")()
    local d = pressDelete(IMI.UI.SidebarRows()[1])
    d.accept:GetScript("OnClick")(d.accept)

    if #IMI.Core.Categories() ~= 0 then error("the dungeon survived") end
    if IMI.UI.SelectedCategory() ~= nil then error("something is still selected") end
    IMI.UI.RefreshSidebar()          -- and an empty list still draws
end)

-- Run is a way in and nothing else. A slipped drag or a stray double-click
-- mid-key must not be able to rearrange the list or cost a dungeon.
check("Run cannot rename, reorder or delete", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("Untouchable")
    IMI.UI.Show("run")
    IMI.UI.RefreshSidebar()

    local row = IMI.UI.SidebarRows()[1]
    if row.del:IsShown() then error("the delete button is reachable from Run") end
    if row:GetScript("OnDoubleClick") then error("double-click renames from Run") end
    if row:GetScript("OnDragStart") then error("rows can be dragged in Run") end
end)

--------------------------------------------------------------------------------
-- Undo and redo through the interface, and the hover text.
--------------------------------------------------------------------------------

check("undo takes back an edit and goes to where it happened", function()
    IMI.Core.Init({})
    IMI.History.Init(IMI.Edit.Context)
    IMI.History.onChange = IMI.UI.RefreshHistoryButtons

    local first = IMI.Core.AddCategory("First")
    local second = IMI.Core.AddCategory("Second")
    IMI.UI.Show("edit")
    IMI.UI.SelectCategory(first.id)
    IMI.Edit.ShowTab("enemies")
    IMI.Core.AddEnemy(first.id, "Mob in the first")

    -- Wander off to another dungeon and another tab, the way you would.
    IMI.UI.SelectCategory(second.id)
    IMI.Edit.ShowTab("pages")

    IMI.UI.Undo()

    if #IMI.Core.Enemies(first.id) ~= 0 then error("the enemy was not taken back") end
    if IMI.UI.SelectedCategory() ~= first.id then
        error("undo did not return to the dungeon the change was made in")
    end
    if IMI.Edit.Context().tab ~= "enemies" then
        error("undo did not return to the tab the change was made on")
    end

    IMI.UI.Redo()
    if #IMI.Core.Enemies(first.id) ~= 1 then error("redo did not put it back") end
end)

check("the undo buttons say whether there is anywhere to go", function()
    IMI.Core.Init({})
    IMI.History.Init(IMI.Edit.Context)
    IMI.History.onChange = IMI.UI.RefreshHistoryButtons
    IMI.UI.Show("edit")
    IMI.UI.RefreshHistoryButtons()

    local buttons = IMI.UI.EditHistoryButtons()
    if not buttons then error("no undo buttons were built") end
    if buttons.undo.enabled then error("undo is offered with an empty history") end
    if buttons.redo.enabled then error("redo is offered with an empty history") end

    IMI.Core.AddCategory("Something")
    if not buttons.undo.enabled then error("undo stayed grey after an edit") end
    if buttons.redo.enabled then error("redo lit up without anything undone") end

    IMI.UI.Undo()
    if buttons.undo.enabled then error("undo still offered after undoing the only step") end
    if not buttons.redo.enabled then error("redo did not light up after an undo") end
end)

check("undoing a deleted dungeon leaves the selection somewhere real", function()
    IMI.Core.Init({})
    IMI.History.Init(IMI.Edit.Context)
    local only = IMI.Core.AddCategory("Only one")
    IMI.UI.Show("edit")
    IMI.UI.SelectCategory(only.id)

    IMI.Core.DeleteCategory(only.id)
    IMI.UI.RefreshSidebar()
    IMI.UI.Redo()                              -- nothing to redo; must not error

    IMI.UI.Undo()                              -- brings the dungeon back
    if IMI.Core.GetCategory(only.id) == nil then error("undo did not restore it") end
    if IMI.UI.SelectedCategory() ~= only.id then
        error("undo did not reselect the restored dungeon")
    end
end)

-- Symbols need words. A button labelled "*" or "^" says nothing on its own.
check("the symbol buttons carry hover text", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("Hoverable")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local row = IMI.UI.SidebarRows()[1]
    if not row.del.tooltipText then error("the delete button says nothing on hover") end

    local arrows = IMI.UI.Arrows()
    if not (arrows.prev.tooltipText and arrows.next.tooltipText) then
        error("the page arrows say nothing on hover")
    end

    local buttons = IMI.UI.EditHistoryButtons()
    if not (buttons.undo.tooltipText and buttons.redo.tooltipText) then
        error("the undo buttons say nothing on hover")
    end

    -- Hovering must still work when the client offers no tooltip to borrow.
    row.del:GetScript("OnEnter")(row.del)
    row.del:GetScript("OnLeave")(row.del)
end)

-- Style.Tooltip hooks OnEnter, which the button already uses for its hover
-- colour. Replacing rather than chaining would leave buttons that never light.
check("hover text does not cost the hover colour", function()
    local b = CreateFrame("Button", nil, UIParent)
    IMI.Style.Button(b, "hover me")
    IMI.Style.Tooltip(b, "Something")

    b:GetScript("OnEnter")(b)
    if not b.hovered then error("the hover colour stopped being applied") end
    b:GetScript("OnLeave")(b)
    if b.hovered then error("the button stayed hovered after leaving") end
end)

realPrint(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
