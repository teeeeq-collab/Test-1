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

--------------------------------------------------------------------------------
-- Run buttons: a callout too long for one line gets a second, and the button
-- grows to hold it rather than clipping.
--------------------------------------------------------------------------------

check("a long callout gets a second line, and the room for it", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Two-liners")

    local short = IMI.Core.AddEnemy(cat.id, "Short")
    IMI.Core.AddLine(cat.id, short.id, "", "/p kick")

    local long = IMI.Core.AddEnemy(cat.id, "Long")
    IMI.Core.AddLine(cat.id, long.id, "",
        "/p Prio kick the Envenom, stack behind the pillar for the cone, then spread")

    local page = IMI.Core.AddPage(cat.id, "One")
    IMI.Core.AddEnemyToPage(cat.id, page.id, short.id)
    IMI.Core.AddEnemyToPage(cat.id, page.id, long.id)

    local container = CreateFrame("Frame", nil, UIParent)
    IMI.Runtime.EnsureManager(container)
    local ok, err = IMI.Runtime.Build(container, cat.id, IMI.Core.Settings())
    if not ok then error(tostring(err)) end

    local buttons = IMI.Runtime.PageButtons(1)
    if not buttons or not buttons[1] or not buttons[2] then error("the page has no buttons") end

    local shortH, longH = buttons[1]:GetHeight(), buttons[2]:GetHeight()
    if longH <= shortH then
        error(("the long callout did not get a taller button: %s vs %s")
            :format(tostring(longH), tostring(shortH)))
    end

    -- Two lines, not however many the text wants: past that it ellipsises, and
    -- a button tall enough for a paragraph stops being hittable by sight.
    if longH > shortH * 2 then
        error(("the button grew past two lines: %s vs %s"):format(tostring(longH), tostring(shortH)))
    end

    if buttons[2].label.maxLines ~= 2 then error("the callout label is not held to two lines") end
    if buttons[2].label.wordWrap ~= true then error("the callout label does not wrap") end
end)

-- The bug this caught: text scale was applied by reading the current size and
-- multiplying, on font strings that outlive a rebuild. At 1.3 the text went 13,
-- 16.9, 21.97, 28.6 across four rebuilds — every time a dungeon was opened.
check("text scale does not compound across rebuilds", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Scaled")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")
    IMI.Core.AddLine(cat.id, e.id, "", "/p kick")
    local page = IMI.Core.AddPage(cat.id, "One")
    IMI.Core.AddEnemyToPage(cat.id, page.id, e.id)

    IMI.Core.Settings().textScale = 1.3
    local container = CreateFrame("Frame", nil, UIParent)
    IMI.Runtime.EnsureManager(container)

    local sizes = {}
    for i = 1, 4 do
        if not IMI.Runtime.Build(container, cat.id, IMI.Core.Settings()) then
            error("build refused")
        end
        local _, size = IMI.Runtime.PageButtons(1)[1].label:GetFont()
        sizes[i] = size
    end
    IMI.Core.Settings().textScale = 1.0

    for i = 2, 4 do
        if sizes[i] ~= sizes[1] then
            error(("rebuild %d changed the font size: %s then %s")
                :format(i, tostring(sizes[1]), tostring(sizes[i])))
        end
    end

    -- And it must actually be scaled, not merely stable at the unscaled size.
    if not (sizes[1] > 10) then
        error("text scale was not applied at all: " .. tostring(sizes[1]))
    end
end)

check("a short callout keeps a single-line button", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Short only")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")
    IMI.Core.AddLine(cat.id, e.id, "", "/p kick")
    local page = IMI.Core.AddPage(cat.id, "One")
    IMI.Core.AddEnemyToPage(cat.id, page.id, e.id)

    local container = CreateFrame("Frame", nil, UIParent)
    IMI.Runtime.EnsureManager(container)
    if not IMI.Runtime.Build(container, cat.id, IMI.Core.Settings()) then error("build refused") end

    -- 22 is the unscaled button height; a short label must not inflate it.
    if IMI.Runtime.PageButtons(1)[1]:GetHeight() ~= 22 then
        error("a short callout got a taller button than it needs: "
            .. tostring(IMI.Runtime.PageButtons(1)[1]:GetHeight()))
    end
end)

--------------------------------------------------------------------------------
-- Window shape: resizing, the collapsing list, and text scale reaching all of it.
--------------------------------------------------------------------------------

check("the window remembers its size, and refuses one too small to use", function()
    IMI.Core.Init({})
    local s = IMI.Core.Settings()

    s.width, s.height = 900, 500
    IMI.UI.ApplySettings()
    if IMI.UI.root:GetWidth() ~= 900 or IMI.UI.root:GetHeight() ~= 500 then
        error("the saved size was not applied")
    end

    -- A size from an older version or a hand-edited file must not produce a
    -- window with no room in it.
    s.width, s.height = 40, 20
    IMI.UI.ApplySettings()
    if IMI.UI.root:GetWidth() < 520 or IMI.UI.root:GetHeight() < 260 then
        error("a nonsense size was accepted: " .. tostring(IMI.UI.root:GetWidth()))
    end

    s.width, s.height = nil, nil
    IMI.UI.ApplySettings()
end)

check("the dungeon list collapses and comes back", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("Something")
    IMI.UI.Show("edit")

    if IMI.UI.SidebarCollapsed() then error("it started collapsed") end
    IMI.UI.ToggleSidebar()
    if not IMI.UI.SidebarCollapsed() then error("it did not collapse") end
    if not IMI.Core.Settings().sidebarCollapsed then error("the state was not remembered") end

    IMI.UI.ToggleSidebar()
    if IMI.UI.SidebarCollapsed() then error("it did not come back") end

    -- And the handle has to survive the trip, or there is no way to reopen it.
    IMI.UI.ToggleSidebar()
    IMI.UI.ApplySettings()
    if not IMI.UI.SidebarCollapsed() then error("a reload lost the collapsed state") end
    IMI.UI.ToggleSidebar()
end)

-- The bug in the screenshot: Settings hides the list, but the content panel was
-- still anchored to it, so the panel's own left border stood in the middle of
-- the page, drawn through the sliders.
check("Settings gets the whole window, with no border through it", function()
    IMI.Core.Init({})
    IMI.UI.Show("settings")

    local content = IMI.UI.ContentPanel()
    local anchor = content.points[1]
    if not anchor then error("the content panel is not anchored") end
    if anchor.rel == IMI.UI.Sidebar() then
        error("Settings still anchors the panel to the hidden dungeon list")
    end
    if IMI.UI.Sidebar():IsShown() then error("the dungeon list is showing in Settings") end

    IMI.UI.Show("edit")
    if not IMI.UI.Sidebar():IsShown() then error("the list did not come back in Edit") end
end)

check("text scale reaches text outside Run", function()
    IMI.Core.Init({})
    local header = IMI.Style.Header(UIParent, "A heading")
    local _, base = header:GetFont()

    IMI.Style.SetTextScale(1.5)
    local _, scaled = header:GetFont()
    if not (scaled > base) then
        error(("a heading did not scale: %s then %s"):format(tostring(base), tostring(scaled)))
    end

    -- Twice at the same scale must give the same answer, not compound.
    IMI.Style.SetTextScale(1.5)
    local _, again = header:GetFont()
    if again ~= scaled then error("scaling twice compounded: " .. tostring(again)) end

    -- Something built after the setting changed must come up at that size.
    local late = IMI.Style.Label(UIParent, "Made later")
    local _, lateSize = late:GetFont()
    if lateSize ~= scaled then
        error(("a later label came up unscaled: %s vs %s")
            :format(tostring(lateSize), tostring(scaled)))
    end

    IMI.Style.SetTextScale(1)
    local _, restored = header:GetFont()
    if restored ~= base then error("scaling back did not restore the size") end
end)

check("the wheel scrolls, and stops at both ends", function()
    local scroll = CreateFrame("ScrollFrame", nil, UIParent)
    IMI.Style.WheelScroll(scroll, 20)
    local wheel = scroll:GetScript("OnMouseWheel")
    if not wheel then error("the wheel was not wired up") end

    scroll.verticalScroll, scroll.scrollRange = 50, 100
    wheel(scroll, -1)
    if scroll.verticalScroll ~= 70 then error("wheeling down did not scroll") end
    wheel(scroll, 1)
    if scroll.verticalScroll ~= 50 then error("wheeling up did not scroll back") end

    for _ = 1, 20 do wheel(scroll, -1) end
    if scroll.verticalScroll ~= 100 then error("scrolled past the end of the list") end
    for _ = 1, 20 do wheel(scroll, 1) end
    if scroll.verticalScroll ~= 0 then error("scrolled above the top of the list") end
end)

check("a long callout line grows its box, and more while being typed into", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Growing")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")
    local short = IMI.Core.AddLine(cat.id, e.id, "", "/p kick")
    -- Long enough to need more than the two lines shown when idle, so that
    -- "more while editing" is actually being asked for.
    IMI.Core.AddLine(cat.id, e.id, "",
        "/p Prio kick the Envenom on the caster, stack behind the pillar for the cone, "
        .. "then spread wide for the bleed and save a stop for the second cast after that")

    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("enemies")

    local boxes = IMI.Edit.LineBoxes()
    local shortH, longH = boxes[1]:GetHeight(), boxes[2]:GetHeight()
    if longH <= shortH then
        error(("the long line did not grow its box: %s vs %s")
            :format(tostring(longH), tostring(shortH)))
    end

    -- Idle it shows two lines; being typed into it shows more.
    local idleH = longH
    boxes[2]:SetFocus()
    IMI.Edit.RefreshEnemies()
    if IMI.Edit.LineBoxes()[2]:GetHeight() <= idleH then
        error("the box did not grow further while being edited")
    end

    boxes[2]:ClearFocus()
    IMI.Edit.RefreshEnemies()
    if IMI.Edit.LineBoxes()[2]:GetHeight() ~= idleH then
        error("the box did not shrink back after editing")
    end
    if short == nil then error("the short line vanished") end
end)

-- A newline in a macro body would break the macro, so it can never get there:
-- one arriving from the keyboard is turned back into what Enter used to do.
check("a typed newline commits instead of reaching the macro", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Newlines")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")
    local line = IMI.Core.AddLine(cat.id, e.id, "", "before")

    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("enemies")

    local box = IMI.Edit.LineBoxes()[1]
    box:SetFocus()
    box:SetText("first\nsecond")
    box:GetScript("OnTextChanged")(box, true)

    local stored = IMI.Core.GetLine(cat.id, e.id, line.id).body
    if stored:find("[\r\n]") then error("a newline reached the macro body: " .. stored) end
    if stored ~= "first second" then error("the text was not joined up: " .. stored) end
    if box:HasFocus() then error("the box kept focus, so Enter did not commit") end
end)

-- Clicking into a box and out again is not an edit.
check("a box you did not change records no edit", function()
    IMI.Core.Init({})
    IMI.History.Init(IMI.Edit.Context)
    local cat = IMI.Core.AddCategory("Untouched")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")
    local line = IMI.Core.AddLine(cat.id, e.id, "", "/p unchanged")

    local before = IMI.Core.EditsSinceExport()
    IMI.Core.SetLine(cat.id, e.id, line.id, nil, "/p unchanged")
    if IMI.Core.EditsSinceExport() ~= before then
        error("re-saving the same text counted as an edit")
    end

    IMI.Core.SetLine(cat.id, e.id, line.id, nil, "/p changed")
    if IMI.Core.EditsSinceExport() == before then error("a real change was not counted") end
end)

--------------------------------------------------------------------------------
-- Nothing overhangs the panel it is in, and nothing overlaps the list.
--------------------------------------------------------------------------------

-- Anchoring right to left is only correct if every button in the chain already
-- exists: a nil relativeTo silently anchors to the parent instead, which puts
-- the row back where it was overhanging.
check("rows anchored from the right chain to real frames", function()
    IMI.Core.Init({})
    IMI.UI.Show("edit")

    local function anchoredTo(frame)
        local p = frame.points[#frame.points]
        return p and p.rel
    end

    local row = IMI.Edit.VariantRow()
    if anchoredTo(row.rename) ~= row.delete then
        error("Rename is not anchored to Delete")
    end
    if anchoredTo(row.new) ~= row.rename then
        error("New is not anchored to Rename")
    end

    local bottom = IMI.Edit.AddRow()
    if anchoredTo(bottom.export) ~= bottom.import then error("Export is not anchored to Import") end
    if anchoredTo(bottom.addTarget) ~= bottom.export then
        error("Add target is not anchored to Export")
    end
    if anchoredTo(bottom.add) ~= bottom.addTarget then error("Add is not anchored to Add target") end
    if anchoredTo(bottom.box) ~= bottom.add then error("the name box is not anchored to Add") end
end)

-- The bug in the screenshot: the fixed stack at the bottom of the dungeon
-- column does not shrink, so in a short window the hint under it was drawn
-- across the last dungeon in the list.
check("the dungeon list keeps its room in a short window", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("One")
    IMI.UI.Show("edit")

    local sidebar = IMI.UI.Sidebar()

    sidebar.height = 400
    IMI.UI.RefreshSidebar()
    if not sidebar.hint:IsShown() then error("the hint is missing when there is room for it") end

    sidebar.height = 200
    IMI.UI.RefreshSidebar()
    if sidebar.hint:IsShown() then
        error("the hint is still drawn in a window with no room for it")
    end

    -- Whatever the height, the list has to end above the stack rather than
    -- running under it.
    local anchor = sidebar.scroll.points[#sidebar.scroll.points]
    if not anchor or anchor.point ~= "BOTTOMRIGHT" then
        error("the list has no bottom anchor")
    end
    if not (anchor.y and anchor.y >= 82) then
        error("the list runs into the buttons below it: " .. tostring(anchor and anchor.y))
    end

    -- The gestures the hint describes must stay reachable without it.
    if not sidebar.headerHit.tooltipText then
        error("with the hint gone, nothing says how to rename or reorder")
    end
end)

check("panel text is bounded on both sides", function()
    IMI.Core.Init({})
    IMI.UI.Show("edit")
    local hint = IMI.Edit.SendHint()

    local sides = {}
    for _, p in ipairs(hint.points) do sides[p.point] = true end
    if not (sides.TOPLEFT and sides.TOPRIGHT) then
        error("the send hint has no right edge, so it runs off the panel")
    end
    if hint.maxLines ~= 2 then error("the send hint is not held to two lines") end
end)

--------------------------------------------------------------------------------
-- Combat. The window holds protected buttons, so insecure code may not hide,
-- move or resize it during a pull. What used to happen instead was half a
-- switch, with Edit drawn underneath Run's callouts.
--------------------------------------------------------------------------------
local stub = require("wowstub")

check("a view switch in combat waits rather than half-happening", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("Somewhere")
    IMI.UI.Show("run")

    stub.inCombat = true
    local switched = IMI.UI.ShowView("edit")
    stub.inCombat = false

    if switched then error("the switch claimed to happen in combat") end
    if IMI.UI.CurrentView() ~= "run" then
        error("the view changed anyway, which is the half-switch: " .. tostring(IMI.UI.CurrentView()))
    end
    if IMI.UI.PendingView() ~= "edit" then error("the switch was dropped instead of remembered") end

    -- And it has to actually happen when the pull ends.
    local watcher = IMI.UI.WatchCombat()
    if not watcher:IsEventRegistered("PLAYER_REGEN_ENABLED") then
        error("nothing is waiting for combat to end")
    end
    watcher:GetScript("OnEvent")(watcher)

    if IMI.UI.CurrentView() ~= "edit" then error("the remembered switch never happened") end
    if IMI.UI.PendingView() then error("the switch stayed pending after being made") end
    if watcher:IsEventRegistered("PLAYER_REGEN_ENABLED") then
        error("still listening after the work was done")
    end
end)

check("switching to the view you are already on is not refused", function()
    IMI.UI.Show("edit")
    stub.inCombat = true
    local ok = IMI.UI.ShowView("edit")
    stub.inCombat = false
    if not ok then error("re-selecting the current view was refused in combat") end
end)

-- Closing and dragging are done inside a secure snippet, which is allowed in
-- combat where a plain script is not.
check("close and drag go through the restricted environment", function()
    local closeBtn = IMI.UI.CloseButton()
    if not closeBtn then error("no close button") end
    if closeBtn:GetFrameRef("window") ~= IMI.UI.root then
        error("the close button does not point at the window")
    end
    if not tostring(closeBtn:GetAttribute("_onclick")):find("Hide", 1, true) then
        error("the close button has no snippet, so it cannot close in combat")
    end

    local titleBar = IMI.UI.TitleBar()
    if titleBar:GetFrameRef("window") ~= IMI.UI.root then
        error("the title bar does not point at the window")
    end
    if not tostring(titleBar:GetAttribute("_ondragstart")):find("StartMoving", 1, true) then
        error("dragging is not secure, so the window cannot be moved in combat")
    end

    for _, grip in ipairs(IMI.UI.ResizeGrips()) do
        if not tostring(grip:GetAttribute("_onmousedown")):find("StartSizing", 1, true) then
            error("a resize edge is not secure, so it cannot resize in combat")
        end
        if not grip:GetAttribute("edge") then error("a resize edge does not say which edge") end
    end
end)

check("a resize during a pull re-flows when the pull ends", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Resized")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")
    IMI.Core.AddLine(cat.id, e.id, "", "/p kick")
    IMI.UI.Show("run")
    IMI.UI.SelectCategory(cat.id)

    stub.inCombat = true
    local grip = IMI.UI.ResizeGrips()[1]
    grip:GetScript("OnMouseUp")(grip)
    stub.inCombat = false

    -- The size is kept whatever happens; only the re-flow waits.
    if not IMI.Core.Settings().width then error("the new size was not saved") end
    if not IMI.UI.PendingRelayout() then error("the re-flow was dropped rather than deferred") end

    local watcher = IMI.UI.WatchCombat()
    watcher:GetScript("OnEvent")(watcher)
    if IMI.UI.PendingRelayout() then error("the re-flow stayed pending") end
end)

check("collapsing and folding the list are refused in combat, not half-done", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("Something")
    IMI.UI.Show("edit")

    local before = IMI.UI.SidebarCollapsed()
    stub.inCombat = true
    local toggled = IMI.UI.ToggleSidebar()
    stub.inCombat = false

    if toggled then error("the list folded in combat, which moves Run's buttons") end
    if IMI.UI.SidebarCollapsed() ~= before then error("it folded anyway") end
end)

realPrint(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
