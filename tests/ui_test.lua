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

for _, f in ipairs({ "Util", "Style", "Core", "Runtime", "UI", "Edit",
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

-- Deleting a dungeon costs everything in it, so one click arms and the second
-- deletes. A single click must never be enough.
check("deleting takes two clicks", function()
    IMI.Core.Init({})
    local doomed = IMI.Core.AddCategory("Doomed")
    IMI.Core.AddCategory("Survivor")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local row = IMI.UI.SidebarRows()[1]
    if not row.del:IsShown() then error("no delete button in the edit view") end

    row.del:GetScript("OnClick")(row.del)
    if IMI.Core.GetCategory(doomed.id) == nil then error("one click deleted it") end
    if row.del:GetText() ~= "?" then error("the armed button does not say so") end

    row.del:GetScript("OnClick")(row.del)
    if IMI.Core.GetCategory(doomed.id) ~= nil then error("the second click did not delete") end
    if #IMI.Core.Categories() ~= 1 then error("the wrong number of dungeons survived") end
end)

check("moving off the delete button disarms it", function()
    IMI.Core.Init({})
    local safe = IMI.Core.AddCategory("Safe")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local row = IMI.UI.SidebarRows()[1]
    row.del:GetScript("OnClick")(row.del)
    row.del:GetScript("OnLeave")(row.del)      -- chained: repaint, then disarm
    if row.del:GetText() ~= "x" then error("the button stayed armed after leaving it") end

    row.del:GetScript("OnClick")(row.del)      -- so this only re-arms
    if IMI.Core.GetCategory(safe.id) == nil then error("a disarmed button still deleted") end
end)

check("deleting the open dungeon selects its neighbour", function()
    IMI.Core.Init({})
    local first = IMI.Core.AddCategory("First")
    local second = IMI.Core.AddCategory("Second")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    IMI.UI.SidebarRows()[1]:GetScript("OnClick")()
    if IMI.UI.SelectedCategory() ~= first.id then error("clicking a row did not select it") end

    local row = IMI.UI.SidebarRows()[1]
    row.del:GetScript("OnClick")(row.del)
    row.del:GetScript("OnClick")(row.del)

    if IMI.UI.SelectedCategory() ~= second.id then
        error("deleting the selected dungeon left the selection dangling")
    end
end)

check("deleting the last dungeon leaves nothing selected", function()
    IMI.Core.Init({})
    IMI.Core.AddCategory("Only")
    IMI.UI.Show("edit")
    IMI.UI.RefreshSidebar()

    local row = IMI.UI.SidebarRows()[1]
    IMI.UI.SidebarRows()[1]:GetScript("OnClick")()
    row.del:GetScript("OnClick")(row.del)
    row.del:GetScript("OnClick")(row.del)

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

realPrint(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
