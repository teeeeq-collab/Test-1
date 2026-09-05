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

for _, f in ipairs({ "Util", "Color", "Style", "Core", "History", "Runtime", "UI",
                     "Picker", "Binds", "Edit", "Export", "Sheet", "Starter", "Capture" }) do
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

check("a callout box always has room for every line of its text", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Growing")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")
    local short = IMI.Core.AddLine(cat.id, e.id, "", "/p kick")
    -- Long enough to wrap several times.
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

    -- The box is tall enough for the wrapped text, not for a guess at it. An
    -- edit box does not clip its own text and cannot ellipsize it, so a box
    -- one line short does not truncate -- it paints that line over the row
    -- beneath it, which is what shipped.
    local box = boxes[2]
    local wrapped = IMI.Edit.MeasureWrapped(box, box:GetText())
    if longH < wrapped then
        error(("the box is shorter than its own text: %s for %s of text")
            :format(tostring(longH), tostring(wrapped)))
    end

    -- Even a single line needs room above and below it, which the height taken
    -- straight from the measurement did not leave: descenders went through the
    -- bottom edge.
    -- A real margin, not one pixel of slack: the text sat flush against the
    -- edges and the descenders went through the bottom.
    local MARGIN = 4
    local oneLine = IMI.Edit.MeasureWrapped(boxes[1], boxes[1]:GetText())
    if shortH < oneLine + MARGIN then
        error(("a one-line box left no room for its text: %s for %s")
            :format(tostring(shortH), tostring(oneLine)))
    end
    if longH < wrapped + MARGIN then
        error(("a wrapped box left no room for its text: %s for %s")
            :format(tostring(longH), tostring(wrapped)))
    end

    -- Focus changes what you can do to a box, not how tall it is. It used to
    -- change both, and that is where the overlap came from.
    box:SetFocus()
    IMI.Edit.RefreshEnemies()
    if IMI.Edit.LineBoxes()[2]:GetHeight() ~= longH then
        error("the box changed height when it gained focus")
    end
    box:ClearFocus()
    IMI.Edit.RefreshEnemies()
    if IMI.Edit.LineBoxes()[2]:GetHeight() ~= longH then
        error("the box changed height when it lost focus")
    end
    if short == nil then error("the short line vanished") end
end)

-- The shape that actually shipped broken. Sizing a box by dividing the text's
-- total width by the box's width assumes text can break anywhere; it breaks at
-- spaces, so long words leave the end of each line empty and the real wrapping
-- needs more lines than the division predicts. An edit box does not clip or
-- ellipsize, so the missing line is painted over the row underneath.
check("a box sized for long words counts the lines wrapping actually needs", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Wrapping")
    local e = IMI.Core.AddEnemy(cat.id, "Mob")

    -- Four words, each over half the box wide: two can never share a line, so
    -- this is four lines however the widths add up.
    local word = ("s"):rep(36)
    IMI.Core.AddLine(cat.id, e.id, "",
        ("%s %s %s %s"):format(word, word, word, word))

    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("enemies")

    local box = IMI.Edit.LineBoxes()[1]
    local wrapped = IMI.Edit.MeasureWrapped(box, box:GetText())
    if box:GetHeight() < wrapped + 4 then
        error(("the box is %s tall for %s of wrapped text")
            :format(tostring(box:GetHeight()), tostring(wrapped)))
    end
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

-- Closing goes through a secure snippet, which is allowed in combat where a
-- plain script is not.
check("closing goes through the restricted environment", function()
    local closeBtn = IMI.UI.CloseButton()
    if not closeBtn then error("no close button") end
    if closeBtn:GetFrameRef("window") ~= IMI.UI.root then
        error("the close button does not point at the window")
    end
    if not tostring(closeBtn:GetAttribute("_onclick")):find("Hide", 1, true) then
        error("the close button has no snippet, so it cannot close in combat")
    end
end)

-- Moving and resizing do not, and cannot. Measured in the client on 12.1.0: a
-- frame handle in the restricted environment has Show, Hide, IsShown, SetWidth,
-- SetHeight, SetPoint, ClearAllPoints, SetAttribute, GetAttribute and
-- GetFrameRef — and none of StartMoving, StopMovingOrSizing or StartSizing.
--
-- Driving them through a snippet anyway called methods that are not there,
-- which broke dragging and resizing outright rather than only in combat,
-- because the snippet is the only path once it is installed.
check("moving and resizing stay plain scripts", function()
    local titleBar = IMI.UI.TitleBar()
    if titleBar:GetAttribute("_ondragstart") then
        error("dragging is driven by a snippet, and the restricted environment "
              .. "cannot move a frame")
    end
    if not titleBar:GetScript("OnDragStart") then error("the title bar cannot be dragged") end

    for _, grip in ipairs(IMI.UI.ResizeGrips()) do
        if grip:GetAttribute("_onmousedown") then
            error("a resize edge is driven by a snippet, and the restricted "
                  .. "environment cannot resize a frame")
        end
        if not grip:GetScript("OnMouseDown") then error("a resize edge does nothing") end
        if not grip:GetAttribute("edge") then error("a resize edge does not say which edge") end
    end
end)

-- Refused rather than silently doing nothing: the window not moving is the same
-- picture whether it was told no or the call was dropped.
check("moving and resizing are refused in combat, not attempted", function()
    IMI.Core.Init({})
    IMI.UI.ApplySettings()
    local before = IMI.UI.root:GetWidth()

    stub.inCombat = true
    local grip = IMI.UI.ResizeGrips()[1]
    grip:GetScript("OnMouseDown")(grip)
    IMI.UI.TitleBar():GetScript("OnDragStart")()
    stub.inCombat = false

    if IMI.UI.root:GetWidth() ~= before then error("the window resized in combat") end
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

--------------------------------------------------------------------------------
-- Opacity fades the grounds only, and the palette follows the open dungeon.
--------------------------------------------------------------------------------

check("opacity fades the panel, not the text or the rule around it", function()
    IMI.Core.Init({})
    local s = IMI.Core.Settings()

    local b = CreateFrame("Button", nil, UIParent)
    IMI.Style.Button(b, "readable")

    s.opacity = 0.4
    IMI.UI.ApplySettings()

    if b.bg.alpha ~= 0.4 then error("the ground did not fade: " .. tostring(b.bg.alpha)) end
    if b.label.alpha ~= 1 then error("the text faded with it: " .. tostring(b.label.alpha)) end
    for _, edge in ipairs(b.borderEdges) do
        if edge.alpha ~= 1 then error("the rule faded with it: " .. tostring(edge.alpha)) end
    end
    -- Fading the window itself is what used to take the text with it.
    if IMI.UI.root.alpha ~= 1 then error("the window itself was faded") end

    s.opacity = 1
    IMI.UI.ApplySettings()
    if b.bg.alpha ~= 1 then error("the ground did not come back") end
end)

check("a dungeon's colour reaches the headings, edges and selection", function()
    IMI.Core.Init({})
    local plain = IMI.Core.AddCategory("Plain")
    local green = IMI.Core.AddCategory("Green")
    IMI.Core.SetCategoryColor(green.id, { 0.2, 0.9, 0.3 })

    IMI.UI.Show("edit")
    IMI.UI.SelectCategory(plain.id)
    local base = { IMI.Style.active.gold[1], IMI.Style.active.gold[2] }

    IMI.UI.SelectCategory(green.id)
    if IMI.Style.active.gold[2] ~= 0.9 then
        error("the panel edge did not take the dungeon's colour")
    end
    if IMI.Style.active.accent[2] ~= 0.9 then
        error("selection did not take the dungeon's colour")
    end
    -- Headings are derived rather than copied: a very dark pick must stay
    -- readable as text.
    if not IMI.Style.active.goldText then error("headings lost their colour") end

    IMI.UI.SelectCategory(plain.id)
    if IMI.Style.active.gold[2] ~= base[2] then
        error("the colour did not go away with the dungeon")
    end
end)

check("a very dark dungeon colour is still readable as a heading", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Midnight")
    IMI.Core.SetCategoryColor(cat.id, { 0.03, 0.02, 0.08 })
    IMI.UI.Show("edit")
    IMI.UI.SelectCategory(cat.id)

    local _, _, v = IMI.Color.RGBtoHSV(IMI.Style.active.goldText[1],
        IMI.Style.active.goldText[2], IMI.Style.active.goldText[3])
    if v < 0.5 then error("the heading colour is too dark to read: " .. tostring(v)) end
    -- The edge itself is left exactly as picked; only text is lifted.
    if IMI.Style.active.gold[3] ~= 0.08 then error("the panel edge was altered") end
end)

check("the user's palette survives a reload and can be reset", function()
    IMI.Core.Init({})
    IMI.Style.SetDungeonColor(nil)          -- no dungeon open, so nothing on top
    local s = IMI.Core.Settings()
    s.colors = { accent = { 1, 0, 0 } }
    IMI.UI.ApplySettings()

    if IMI.Style.active.accent[1] ~= 1 or IMI.Style.active.accent[2] ~= 0 then
        error("a stored colour was not applied on load")
    end

    IMI.Style.ResetUserColors()
    if IMI.Style.active.accent[1] == 1 and IMI.Style.active.accent[2] == 0 then
        error("reset did not put the palette back")
    end

    -- Nonsense in the saved variables must read as "nothing set".
    s.colors = { accent = "not a colour", gold = { 1 } }
    IMI.UI.ApplySettings()
    if type(IMI.Style.active.accent) ~= "table" then error("a bad stored colour got through") end
end)

check("a dungeon colour sits on top of the user's palette", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Over")
    IMI.Core.SetCategoryColor(cat.id, { 0, 0, 1 })
    IMI.Core.Settings().colors = { gold = { 1, 0, 0 } }
    IMI.UI.ApplySettings()

    if IMI.Style.active.gold[1] ~= 1 then error("the user's colour was not applied") end

    IMI.UI.Show("edit")
    IMI.UI.SelectCategory(cat.id)
    if IMI.Style.active.gold[3] ~= 1 then error("the dungeon colour did not win while open") end

    IMI.UI.SelectCategory(nil)
    if IMI.Style.active.gold[1] ~= 1 then
        error("closing the dungeon did not fall back to the user's colour")
    end
    IMI.Core.Settings().colors = {}
    IMI.UI.ApplySettings()
end)

-- Clicking a colour is the one part of the picker that can be off by one.
check("clicking the colour field lands on the cell under the cursor", function()
    local function cell(x, y) 
        local c, r = IMI.Picker.CellAt(x, y, 10, 10, 24, 16)
        return c .. "," .. r
    end
    if cell(0, 0) ~= "1,1" then error("the top-left cell is not 1,1: " .. cell(0, 0)) end
    if cell(9, 9) ~= "1,1" then error("within the first cell left it: " .. cell(9, 9)) end
    if cell(10, 0) ~= "2,1" then error("crossing into the second column missed it") end
    if cell(0, 10) ~= "1,2" then error("crossing into the second row missed it") end
    if cell(9999, 9999) ~= "24,16" then error("past the end did not clamp") end
    if cell(-50, -50) ~= "1,1" then error("before the start did not clamp") end
end)

-- A marker that points somewhere other than the colour you picked is worse than
-- no marker, so the mapping is the same arithmetic the swatches themselves use.
check("the markers land on the colour that is selected", function()
    local CELL, COLS, ROWS = 9, 24, 16
    local fieldW, fieldH = COLS * CELL, ROWS * CELL

    -- Click a cell, then ask where the marker goes: it must land inside it.
    for _, cell in ipairs({ { 1, 1 }, { 12, 8 }, { 24, 16 } }) do
        local col, row = cell[1], cell[2]
        local s, v = IMI.Picker.FieldColor(col, row, 200)
        local mx, my = IMI.Picker.FieldOffset(s, v, fieldW, fieldH)

        local backCol, backRow = IMI.Picker.CellAt(mx, my, CELL, CELL, COLS, ROWS)
        if backCol ~= col or backRow ~= row then
            error(("cell %d,%d marked at %d,%d"):format(col, row, backCol, backRow))
        end
    end

    -- The hue strip runs 0 at the top to 360 at the bottom.
    if IMI.Picker.HueOffset(0, 144) ~= 0 then error("hue 0 is not at the top") end
    if math.abs(IMI.Picker.HueOffset(180, 144) - 72) > 0.01 then
        error("hue 180 is not halfway down: " .. IMI.Picker.HueOffset(180, 144))
    end
    -- 360 is the same colour as 0, so the marker returns to the top rather than
    -- sliding off the bottom of the strip.
    if IMI.Picker.HueOffset(360, 144) ~= 0 then error("hue 360 fell off the strip") end
    if IMI.Picker.HueOffset(400, 144) >= 144 then error("a hue past 360 left the strip") end
end)

check("the markers move with the colour", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Marked")
    IMI.UI.Show("edit")
    IMI.UI.SelectCategory(cat.id)
    IMI.Edit.SetCategory(cat.id)

    IMI.Core.SetCategoryColor(cat.id, { 1, 0, 0 })
    IMI.Edit.ShowColorPicker()
    local d = IMI.Picker.Frame().dialog
    if not d.hueMarker or not d.fieldMarker then error("the picker has no markers") end

    local function anchorOf(frame)
        local p = frame.points[#frame.points]
        return p and p.x, p and p.y
    end

    local _, redY = anchorOf(d.hueMarker)
    d.state.h = 240                       -- blue, two thirds down the strip
    d:Repaint()
    local _, blueY = anchorOf(d.hueMarker)
    if not (blueY < redY) then
        error(("the hue marker did not move down: %s then %s")
            :format(tostring(redY), tostring(blueY)))
    end

    local satX = select(1, anchorOf(d.fieldMarker))
    d.state.s = 0.1
    d:Repaint()
    if not (select(1, anchorOf(d.fieldMarker)) < satX) then
        error("the field marker did not follow saturation")
    end

    -- Through the click, not through Repaint. The checks above drove Repaint
    -- directly and so proved only that the marker can move: clicking the field
    -- changed the colour and moved nothing, because that one path applied the
    -- new colour without repainting anything.
    d.state.h, d.state.s, d.state.v = 120, 1, 1
    d:Repaint()

    local click = d.field:GetScript("OnClick")
    if not click then error("the colour field does not answer a click") end
    click(d.field)

    local fieldW, fieldH = d.field:GetWidth(), d.field:GetHeight()
    local wantX, wantY = IMI.Picker.FieldOffset(d.state.s, d.state.v, fieldW, fieldH)
    local gotX, gotY = anchorOf(d.fieldMarker)
    if math.abs(gotX - wantX) > 0.5 or math.abs(gotY - (-wantY)) > 0.5 then
        error(("clicking the field left the marker behind: it is at %s,%s and the "
            .. "colour is at %s,%s"):format(tostring(gotX), tostring(gotY),
            tostring(wantX), tostring(-wantY)))
    end
    IMI.Picker.Frame():Hide()
end)

check("the colour field runs saturation across and brightness down", function()
    local s1, v1 = IMI.Picker.FieldColor(1, 1, 200)
    local s2, v2 = IMI.Picker.FieldColor(24, 16, 200)
    if not (s2 > s1) then error("saturation does not increase to the right") end
    if not (v2 < v1) then error("brightness does not decrease downwards") end
end)

check("the picker opens on the colour already set, and can clear it", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Picked")
    IMI.UI.Show("edit")
    IMI.UI.SelectCategory(cat.id)
    IMI.Edit.SetCategory(cat.id)

    IMI.Core.SetCategoryColor(cat.id, { 1, 0, 0 })
    if not IMI.Edit.ShowColorPicker() then error("the picker refused to open") end

    local d = IMI.Picker.Frame().dialog
    if math.abs(d.state.h) > 1 then error("it did not open on red: hue " .. tostring(d.state.h)) end

    d.onChange({ 0, 0, 1 })
    local set = IMI.Core.CategoryColor(cat.id)
    if set[3] ~= 1 then error("changing the colour did not store it") end
    if IMI.Style.active.gold[3] ~= 1 then error("the change was not applied live") end

    d.onReset()
    if IMI.Core.CategoryColor(cat.id) ~= nil then error("reset did not clear the colour") end
    if IMI.Style.DungeonColor() ~= nil then error("reset did not clear the live colour") end
end)

--------------------------------------------------------------------------------
-- Capturing a key. The most dangerous thing this addon does: while a frame
-- holds the keyboard nothing reaches the game, including the Escape that opens
-- the menu and the slash command that would fix it.
--------------------------------------------------------------------------------

check("a key capture gives the keyboard back on the key", function()
    local f = IMI.UI.KeyCapture(CreateFrame("Frame", nil, UIParent))
    if f.keyboard then error("it took the keyboard before being armed") end

    local got
    IMI.UI.ArmKeyCapture(f, function(chord) got = chord end)
    if not f.keyboard then error("arming did not take the keyboard") end

    f:GetScript("OnKeyDown")(f, "K")
    if got ~= "K" then error("the key did not reach the handler: " .. tostring(got)) end
    if f.keyboard then error("the keyboard was not given back") end
end)

check("escape gives it back", function()
    local f = IMI.UI.KeyCapture(CreateFrame("Frame", nil, UIParent))
    IMI.UI.ArmKeyCapture(f, function() error("escape should not assign") end)
    f:GetScript("OnKeyDown")(f, "ESCAPE")
    if f.keyboard then error("escape left the keyboard held") end
end)

-- The fault that shipped: a key arriving while nothing was armed returned early
-- with the keyboard still held, so every key was swallowed — Escape included,
-- and with it any way to type the command that would have fixed it.
check("a key arriving unarmed gives the keyboard back rather than eating it", function()
    local f = IMI.UI.KeyCapture(CreateFrame("Frame", nil, UIParent))
    f:EnableKeyboard(true)                     -- held, but nothing is waiting
    f.captureArmed = false

    f:GetScript("OnKeyDown")(f, "ESCAPE")
    if f.keyboard then error("a stuck capture swallowed escape and kept the keyboard") end
end)

check("hiding the frame gives it back", function()
    local f = IMI.UI.KeyCapture(CreateFrame("Frame", nil, UIParent))
    IMI.UI.ArmKeyCapture(f, function() end)
    f:GetScript("OnHide")(f)
    if f.keyboard then error("closing the dialog left the keyboard held") end
end)

-- The guarantee: no fault here can cost more than a few seconds.
check("it times out on its own", function()
    local f = IMI.UI.KeyCapture(CreateFrame("Frame", nil, UIParent))
    IMI.UI.ArmKeyCapture(f, function() end)

    f.captureUntil = -1                        -- as if the wait had run out
    f:GetScript("OnUpdate")(f)
    if f.keyboard then error("the capture held the keyboard past its timeout") end
    if f:GetScript("OnUpdate") then error("it is still watching after releasing") end
end)

check("and everything can be released at once", function()
    local f = IMI.UI.KeyCapture(CreateFrame("Frame", nil, UIParent))
    IMI.UI.ArmKeyCapture(f, function() end)
    if IMI.UI.ReleaseAllKeys() < 1 then error("nothing was released") end
    if f.keyboard then error("release-all left a capture holding the keyboard") end
end)

-- The other way to lose the keyboard, and the one that does not look like a
-- capture at all: a focused edit box takes every key you press, so the game
-- stops answering its bindings while chat still works. Opening a window is
-- never a good enough reason to take the keyboard.
check("opening the export window does not take the keyboard", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Copyable")
    IMI.UI.ShowExport("Export", IMI.Export.EncodeCategory(cat.id))

    local box = IMI.UI.StringBox()
    if not box then error("no export box") end
    if box.focused then error("the export window focused its box on open") end
end)

check("and lets go when it closes", function()
    local box = IMI.UI.StringBox()
    box:SetFocus()                              -- as Select all does
    if not box.focused then error("the box did not take focus when asked") end

    IMI.UI.StringWindow():GetScript("OnHide")()
    if box.focused then error("closing the window left the box holding the keyboard") end
end)

check("escape lets go before hiding", function()
    local box = IMI.UI.StringBox()
    box:SetFocus()
    box:GetScript("OnEscapePressed")(box)
    if box.focused then error("escape hid the window but kept the keyboard") end
end)

check("the safety valve reaches a focused box too", function()
    local box = IMI.UI.StringBox()
    box:SetFocus()
    IMI.UI.ReleaseAllKeys()
    if box.focused then error("release-all left an edit box holding the keyboard") end
end)

-- Hiding a frame does not release the keyboard from the box inside it. That is
-- the whole lesson: the window was closed and the keyboard stayed gone.
check("every box lets go when it is hidden", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Focus")
    local mob = IMI.Core.AddEnemy(cat.id, "Mob")
    IMI.Core.AddLine(cat.id, mob.id, "", "/p line")
    IMI.UI.Show("edit")
    IMI.UI.SelectCategory(cat.id)
    IMI.Edit.SetCategory(cat.id)

    local boxes = {
        ["a callout line"] = IMI.Edit.LineBoxes()[1],
        ["the new-dungeon name"] = IMI.UI.Sidebar().newName,
        ["a dungeon rename"] = IMI.UI.SidebarRows()[1] and IMI.UI.SidebarRows()[1].rename,
    }

    for what, box in pairs(boxes) do
        if box then
            -- Shown first: these are hidden most of the time, and hiding
            -- something already hidden changes nothing, so the check would
            -- pass without the release ever running.
            box:Show()
            box:SetFocus()
            box:Hide()
            if box.focused then
                error(what .. " kept the keyboard after being hidden")
            end
        end
    end
end)

-- Clearing focus is not enough, and the last lockout proved it: /imi unstick
-- cleared focus, changed nothing, and only a reload helped. A frame that has
-- enabled the keyboard holds it whether or not anything has focus.
check("the safety valve reaches a frame holding the keyboard, not only focus", function()
    local held = CreateFrame("Frame", "InomrahsMIStuckForTest", UIParent)
    held:EnableKeyboard(true)
    held:Show()

    IMI.UI.ReleaseAllKeys()
    if held.keyboard then
        error("a frame of ours kept the keyboard when nothing had focus")
    end
end)

check("and it says what was holding it", function()
    local held = CreateFrame("Frame", "InomrahsMIStuckReport", UIParent)
    held:EnableKeyboard(true)
    held:Show()

    local report = IMI.UI.KeyboardReport()
    if not report:find("InomrahsMIStuckReport", 1, true) then
        error("the report did not name the frame holding the keyboard: " .. report)
    end
    IMI.UI.ReleaseAllKeys()

    if not IMI.UI.KeyboardReport():find("nothing", 1, true) then
        error("after releasing, the report still claims something holds it")
    end
end)

--------------------------------------------------------------------------------
-- Secret Values
--
-- The walk that finds what is holding the keyboard touches every frame in the
-- game, and 12.1 hands back Secret Values from frames this addon has no
-- business reading: the read succeeds and the first truth test on the result
-- throws. Unguarded, the walk aborted on the first one -- so the safety valve
-- itself was the thing that stopped working, in the exact situation it exists
-- for. These reproduce that shape: a frame that throws when it is asked.
--------------------------------------------------------------------------------

check("a frame that throws when read does not stop the release", function()
    local hostile = CreateFrame("Frame", "SomeOtherAddonsSecretFrame", UIParent)
    hostile.IsKeyboardEnabled = function()
        error("attempt to perform boolean test on a secret boolean value")
    end

    local held = CreateFrame("Frame", "InomrahsMIStuckPastSecret", UIParent)
    held:EnableKeyboard(true)
    held:Show()

    IMI.UI.ReleaseAllKeys()
    if held.keyboard then
        error("the walk stopped at the secret frame and released nothing after it")
    end
end)

check("and a frame with a secret name is described rather than fatal", function()
    local hostile = CreateFrame("Frame", "SecretlyNamedFrame", UIParent)
    hostile:EnableKeyboard(true)
    hostile:Show()
    hostile.GetName = function()
        error("attempt to concatenate a secret string value")
    end

    local report = IMI.UI.KeyboardReport()
    if type(report) ~= "string" then error("the report threw on a secret name") end
end)

check("and a walk that cannot advance is reported, not thrown", function()
    local real = _G.EnumerateFrames
    local first = true
    _G.EnumerateFrames = function(previous)
        if first then first = false; return real() end
        error("attempt to index a secret value")
    end

    local ok, report = pcall(IMI.UI.KeyboardReport)
    _G.EnumerateFrames = real

    if not ok then error("a broken walk escaped as an error: " .. tostring(report)) end
    if not report:find("unreadable", 1, true) then
        error("the report did not say frames went unread: " .. report)
    end
end)

--------------------------------------------------------------------------------
-- Importing over a profile
--
-- The one action in the addon with no undo behind it: it replaces everything
-- loaded. So the question in front of it has three answers, and each of them
-- has to do exactly what it says.
--------------------------------------------------------------------------------

local function makeString()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Theirs")
    local mob = IMI.Core.AddEnemy(cat.id, "Their mob")
    IMI.Core.AddLine(cat.id, mob.id, "", "/p theirs")
    IMI.Core.AddPage(cat.id, "Their page")
    return IMI.Export.EncodeProfile()
end

local function withMine(str)
    IMI.Core.Init({})
    IMI.Core.AddCategory("Mine")
    IMI.UI.Show("edit")
    return str
end

check("importing asks before it replaces anything", function()
    local str = withMine(makeString())
    IMI.UI.ImportOverProfile(str)

    local d = IMI.UI.ConfirmFrame()
    if not d or not d:IsShown() then error("nothing asked") end
    if not d.dialog.alt:IsShown() then error("there is no third answer") end
    if IMI.Core.Categories()[1].name ~= "Mine" then
        error("it replaced the profile before asking")
    end
    d:Hide()
end)

check("cancelling changes nothing", function()
    local str = withMine(makeString())
    IMI.UI.ImportOverProfile(str)
    IMI.UI.ConfirmFrame().dialog.cancel:GetScript("OnClick")()

    if IMI.Core.Categories()[1].name ~= "Mine" then error("cancel imported anyway") end
    if #IMI.Core.ProfileNames() ~= 1 then error("cancel saved something") end
end)

check("importing without saving replaces what was loaded", function()
    local str = withMine(makeString())
    IMI.UI.ImportOverProfile(str)
    IMI.UI.ConfirmFrame().dialog.accept:GetScript("OnClick")()

    if #IMI.Core.Categories() ~= 1 then error("expected one dungeon") end
    if IMI.Core.Categories()[1].name ~= "Theirs" then
        error("the import did not land: " .. IMI.Core.Categories()[1].name)
    end
    if #IMI.Core.ProfileNames() ~= 1 then error("it saved a copy it was told not to") end
end)

check("saving first keeps the old profile under the name given", function()
    local str = withMine(makeString())
    IMI.UI.ImportOverProfile(str)
    IMI.UI.ConfirmFrame().dialog.alt:GetScript("OnClick")()

    local prompt = IMI.UI.PromptFrame()
    if not prompt or not prompt:IsShown() then error("it did not ask for a name") end
    prompt.dialog.box:SetText("My season 2")
    prompt.dialog.accept:GetScript("OnClick")()

    local saved
    for _, name in ipairs(IMI.Core.ProfileNames()) do
        if name == "My season 2" then saved = name end
    end
    if not saved then
        error("the old profile was not kept: " .. table.concat(IMI.Core.ProfileNames(), ", "))
    end
    if #IMI.Core.db.profiles[saved].categories ~= 1
        or IMI.Core.db.profiles[saved].categories[1].name ~= "Mine" then
        error("the saved copy is not what was loaded")
    end

    -- And the import still happened, into the profile that was being replaced
    -- rather than into the copy.
    if IMI.Core.Categories()[1].name ~= "Theirs" then
        error("it saved but did not import")
    end
end)

check("a paste that is neither a string nor a sheet is refused", function()
    withMine(makeString())
    local ok, err = IMI.UI.ImportOverProfile("just some words")
    if ok then error("nonsense was accepted") end
    if type(err) ~= "string" then error("no reason given") end
    if IMI.Core.Categories()[1].name ~= "Mine" then error("it changed something anyway") end
end)

-- The Run screen was left holding a dungeon that no longer existed: its secure
-- buttons kept drawing over the new profile and the heading read "category not
-- found". An import replaces everything, so everything built from the old
-- profile has to go with it.
check("importing clears what Run had built from the old profile", function()
    local str = withMine(makeString())

    -- Standing in Run with the old dungeon open, which is where it went wrong.
    IMI.UI.Show("run")
    IMI.UI.SelectCategory(IMI.Core.Categories()[1].id)
    IMI.UI.OpenRun(IMI.Core.Categories()[1].id)
    if IMI.Runtime.BuiltCategory() == nil then error("nothing was built to begin with") end

    IMI.UI.ImportOverProfile(str)
    IMI.UI.ConfirmFrame().dialog.accept:GetScript("OnClick")()

    local built = IMI.Runtime.BuiltCategory()
    if built and not IMI.Core.GetCategory(built) then
        error("Run is still holding a dungeon that no longer exists")
    end
    for _, button in ipairs(IMI.Runtime.PageButtons(1) or {}) do
        if button:IsVisible() then
            error("a callout from the old profile is still on screen")
        end
    end
end)

check("the question says how much it found, not just how many dungeons", function()
    withMine(makeString())
    IMI.UI.ImportOverProfile("Enemy: Big Mob\nkick it\nstun it")

    local body = IMI.UI.ConfirmFrame().dialog.body:GetText()
    if not body:find("1 enemy", 1, true) then
        error("the question does not say how many enemies: " .. body)
    end
    if not body:find("2 callouts", 1, true) then
        error("the question does not say how many callouts: " .. body)
    end
    IMI.UI.ConfirmFrame():Hide()
end)

check("a spreadsheet paste goes through the same question", function()
    withMine(makeString())
    IMI.UI.ImportOverProfile("Enemy: Big Mob\nkick it")

    local d = IMI.UI.ConfirmFrame()
    if not d or not d:IsShown() then error("a sheet paste did not ask") end
    d.dialog.accept:GetScript("OnClick")()

    if IMI.Core.Categories()[1].name ~= "Imported" then
        error("the sheet did not import: " .. IMI.Core.Categories()[1].name)
    end
    local enemies = IMI.Core.Enemies(IMI.Core.Categories()[1].id)
    if #enemies ~= 1 or enemies[1].name ~= "Big Mob" then error("wrong enemy") end
    if #enemies[1].lines ~= 1 then error("the callout did not come with it") end
end)

--------------------------------------------------------------------------------
-- Picking from a list rather than stepping through it
--------------------------------------------------------------------------------

check("the page name box is also the list of pages", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Paged")
    for i = 1, 4 do IMI.Core.AddPage(cat.id, "Page " .. i) end

    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("pages")

    local chooser = IMI.Edit.PagePicker()
    if not chooser then error("the page box has no list") end
    if #chooser.rows < 4 then
        error("the list does not hold every page: " .. #chooser.rows)
    end

    -- The fourth page, without pressing the arrow three times.
    chooser.rows[4]:GetScript("OnClick")()
    if IMI.Edit.Context().pageId ~= IMI.Core.Pages(cat.id)[4].id then
        error("picking from the list did not change page")
    end

    -- Renaming still has to work, which is the whole reason it is a box and
    -- not a button.
    chooser.overlay:GetScript("OnDoubleClick")(chooser.overlay)
    if chooser.overlay:IsShown() then error("double-click did not hand over to the box") end
end)

--------------------------------------------------------------------------------
-- The channel a callout actually goes out on
--
-- The setting is only worth anything if it reaches the macro text on the
-- button. Everything above this is bookkeeping; this is the part that decides
-- what the group sees.
--------------------------------------------------------------------------------

check("each page's callouts carry that page's channel", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Channelled")
    local mob = IMI.Core.AddEnemy(cat.id, "Mob")
    IMI.Core.AddLine(cat.id, mob.id, "", "kick it")

    local gathering = IMI.Core.AddPage(cat.id, "Gathering")
    local pull = IMI.Core.AddPage(cat.id, "Pull")
    IMI.Core.AddEnemyToPage(cat.id, gathering.id, mob.id)
    IMI.Core.AddEnemyToPage(cat.id, pull.id, mob.id)

    IMI.Core.Settings().channel = "/p"
    IMI.Core.SetCategoryChannel(cat.id, "/raid")
    IMI.Core.SetPageChannel(cat.id, pull.id, "/i")

    IMI.UI.Show("run")
    IMI.UI.OpenRun(cat.id)

    local onGathering = IMI.Runtime.PageButtons(1)[1]:GetAttribute("macrotext")
    local onPull = IMI.Runtime.PageButtons(2)[1]:GetAttribute("macrotext")

    if onGathering ~= "/raid kick it" then
        error("the gathering page did not take the dungeon channel: " .. tostring(onGathering))
    end
    if onPull ~= "/i kick it" then
        error("the pull page did not take its own channel: " .. tostring(onPull))
    end
end)

check("a line that is already a command is left alone whatever the override", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Commands")
    local mob = IMI.Core.AddEnemy(cat.id, "Mob")
    IMI.Core.AddLine(cat.id, mob.id, "", "/cast Kick")
    local page = IMI.Core.AddPage(cat.id, "Route")
    IMI.Core.AddEnemyToPage(cat.id, page.id, mob.id)
    IMI.Core.SetCategoryChannel(cat.id, "/raid")

    IMI.UI.Show("run")
    IMI.UI.OpenRun(cat.id)
    local macro = IMI.Runtime.PageButtons(1)[1]:GetAttribute("macrotext")
    if macro ~= "/cast Kick" then error("a command was prefixed: " .. tostring(macro)) end
end)

check("the override toggles show what is stored and set what is toggled", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Toggles")
    local page = IMI.Core.AddPage(cat.id, "Route")

    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("pages")
    IMI.Edit.RefreshPages()

    local w = IMI.Edit.ChannelWidgets()
    if w.dungeon:GetChecked() then error("a fresh dungeon came up overridden") end
    if w.dungeonDrop:IsShown() then error("the chooser is showing with the toggle off") end

    -- Turning it on has to store something, not just light up.
    w.dungeon:GetScript("OnClick")(w.dungeon)
    if not IMI.Core.GetCategory(cat.id).channel then
        error("toggling on stored no channel")
    end
    if not w.dungeonDrop:IsShown() then error("the chooser did not appear") end

    -- And off has to clear it, not set it to whatever was showing.
    w.dungeon:GetScript("OnClick")(w.dungeon)
    if IMI.Core.GetCategory(cat.id).channel ~= nil then
        error("toggling off left a channel behind")
    end

    if w.page:GetChecked() then error("a fresh page came up overridden") end
    w.page:GetScript("OnClick")(w.page)
    if not IMI.Core.GetPage(cat.id, page.id).channel then
        error("the page toggle stored nothing")
    end
end)

check("a new page does not inherit the open page's override", function()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Fresh pages")
    local first = IMI.Core.AddPage(cat.id, "First")
    IMI.Core.SetPageChannel(cat.id, first.id, "/i")

    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("pages")

    local second = IMI.Core.AddPage(cat.id, "Second")
    if second.channel ~= nil then error("the new page copied the old one's channel") end
end)

--------------------------------------------------------------------------------
-- Setting a keybind, through the dialog
--
-- Eighty-five checks covered the parts -- chords, conflicts, which row an
-- assignment lands on -- and none of them covered the one thing that matters:
-- click Set, press a key, is it stored. It was not, for every version the
-- feature has existed in, and no test noticed because no test pressed a key.
--------------------------------------------------------------------------------

local function pageWithACallout()
    IMI.Core.Init({})
    local cat = IMI.Core.AddCategory("Binding")
    local mob = IMI.Core.AddEnemy(cat.id, "Mob")
    local line = IMI.Core.AddLine(cat.id, mob.id, "", "/p kick")
    local second = IMI.Core.AddLine(cat.id, mob.id, "", "/p stun")
    local page = IMI.Core.AddPage(cat.id, "Route")
    IMI.Core.AddEnemyToPage(cat.id, page.id, mob.id)

    IMI.UI.Show("edit")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("pages")
    IMI.Binds.Open(cat.id, page.id)

    return cat, page, line, second, IMI.Binds.Frame().dialog
end

local function press(d, key)
    local script = d:GetScript("OnKeyDown")
    if not script then error("the dialog does not answer the keyboard") end
    script(d, key)
end

check("clicking Set and pressing a key stores the key", function()
    local cat, page, line, _, d = pageWithACallout()

    local row = d.rows[1]
    if not row then error("the dialog listed no callouts") end

    row.button:GetScript("OnClick")(row.button, "LeftButton")
    if not d.captureArmed then error("clicking Set did not arm the capture") end

    press(d, "E")

    local stored = IMI.Core.LineBind(cat.id, page.id, line.id)
    if stored ~= "E" then error("the key was not stored: " .. tostring(stored)) end
    if d.captureArmed then error("the capture is still armed after the key") end
end)

check("and the row shows it afterwards", function()
    local _, _, _, _, d = pageWithACallout()
    d.rows[1].button:GetScript("OnClick")(d.rows[1].button, "LeftButton")
    press(d, "E")

    local shown = IMI.Binds.Frame().dialog.rows[1].button:GetText()
    if shown ~= "E" then error("the row still reads " .. tostring(shown)) end
end)

check("a chord is stored whole", function()
    local cat, page, line, _, d = pageWithACallout()
    d.rows[1].button:GetScript("OnClick")(d.rows[1].button, "LeftButton")

    stub.shift, stub.ctrl = true, true
    press(d, "E")
    stub.shift, stub.ctrl = false, false

    local stored = IMI.Core.LineBind(cat.id, page.id, line.id)
    if stored ~= "CTRL-SHIFT-E" then error("wrong chord: " .. tostring(stored)) end
end)

check("Escape sets nothing and gives the keyboard back", function()
    local cat, page, line, _, d = pageWithACallout()
    d.rows[1].button:GetScript("OnClick")(d.rows[1].button, "LeftButton")
    press(d, "ESCAPE")

    if IMI.Core.LineBind(cat.id, page.id, line.id) ~= nil then
        error("Escape bound a key")
    end
    if d.keyboard then error("Escape left the keyboard held") end
end)

check("giving a key to a second callout takes it off the first", function()
    local cat, page, first, second, d = pageWithACallout()

    d.rows[1].button:GetScript("OnClick")(d.rows[1].button, "LeftButton")
    press(d, "E")

    local rows = IMI.Binds.Frame().dialog.rows
    rows[2].button:GetScript("OnClick")(rows[2].button, "LeftButton")
    press(IMI.Binds.Frame().dialog, "E")

    if IMI.Core.LineBind(cat.id, page.id, second.id) ~= "E" then
        error("the second callout did not take the key")
    end
    if IMI.Core.LineBind(cat.id, page.id, first.id) ~= nil then
        error("both callouts answer to the same key")
    end
end)

check("right-clicking a key clears it", function()
    local cat, page, line, _, d = pageWithACallout()
    d.rows[1].button:GetScript("OnClick")(d.rows[1].button, "LeftButton")
    press(d, "E")

    local rows = IMI.Binds.Frame().dialog.rows
    rows[1].button:GetScript("OnClick")(rows[1].button, "RightButton")
    if IMI.Core.LineBind(cat.id, page.id, line.id) ~= nil then
        error("right-click did not clear the key")
    end
end)

check("the paging rows bind too", function()
    local _, _, _, _, d = pageWithACallout()

    -- Last two rows are Next page and Previous page, shared by every page.
    local rows = d.rows
    local nextRow = rows[#IMI.Binds.Rows(d.catId, d.pageId) - 1]
    nextRow.button:GetScript("OnClick")(nextRow.button, "LeftButton")
    press(d, "F")

    if IMI.Core.Settings().pageNextKey ~= "F" then
        error("the paging key was not stored: "
            .. tostring(IMI.Core.Settings().pageNextKey))
    end
end)

-- A dialog covers what it is asking about, so it has to be readable over it
-- and movable off it.
check("a dialog does not fade with the opacity setting", function()
    IMI.Style.SetOpacity(0.3)

    local _, _, _, _, d = pageWithACallout()
    if not d.ground then error("the dialog has no ground to check") end
    if (d.ground.alpha or 1) < 1 then
        error("the dialog faded with the panel: alpha " .. tostring(d.ground.alpha))
    end

    -- And the panel it sits over still does fade, or the setting would have
    -- stopped working rather than stopped reaching dialogs.
    if (IMI.UI.ContentPanel().ground.alpha or 1) >= 1 then
        error("the content panel no longer follows opacity")
    end

    IMI.Style.SetOpacity(1)
end)

check("and can be dragged out of the way", function()
    local _, _, _, _, d = pageWithACallout()
    if not d:GetScript("OnDragStart") then error("the dialog cannot be moved") end
    if not d:GetScript("OnDragStop") then error("a drag would never stop") end
end)

realPrint(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
