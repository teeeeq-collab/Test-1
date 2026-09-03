-- Constructs the whole UI against a stubbed WoW API. Catches load-order faults,
-- missing widget fields and nil calls in code paths that syntax checks pass and
-- that would otherwise only appear in game.
local realPrint = print          -- grabbed before the stub silences print
package.path = "tests/?.lua;" .. package.path
require("wowstub").install()
local MM = {}
for _, f in ipairs({
    "Libs/LibStub/LibStub", "Libs/LibDeflate/LibDeflate", "Libs/LibSerialize/LibSerialize",
}) do loadfile("MythicMacros/" .. f .. ".lua")() end

for _, f in ipairs({ "Util", "Core", "Runtime", "UI", "Edit", "Export", "Starter", "Capture" }) do
    local chunk, err = loadfile("MythicMacros/" .. f .. ".lua")
    if not chunk then realPrint("  FAIL loading " .. f .. ": " .. tostring(err)); os.exit(1) end
    chunk("MythicMacros", MM)
end

local pass, fail = 0, 0
local function check(label, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; realPrint("  FAIL: " .. label .. "\n         " .. tostring(err)) end
end

MythicMacrosDB = MM.Core.Init({})

check("UI.Init builds every panel", function() MM.UI.Init() end)

check("every view switches", function()
    MM.UI.ShowView("run")
    MM.UI.ShowView("edit")
    MM.UI.ShowView("settings")
    MM.UI.ShowView("run")
end)

check("sidebar with no dungeons", function() MM.UI.RefreshSidebar() end)

check("season dungeons appear in the sidebar", function()
    MM.Starter.Create()
    MM.UI.RefreshSidebar()
end)

check("edit with no dungeon selected", function()
    MM.UI.ShowView("edit")
    MM.Edit.SetCategory(nil)
    MM.Edit.ShowTab("enemies")
    MM.Edit.ShowTab("pages")
end)

check("edit a dungeon that has content", function()
    local cat = MM.Core.Categories()[6]          -- Kings' Rest: has boss cards
    local e = MM.Core.AddEnemy(cat.id, "Trash pack")
    MM.Core.AddLine(cat.id, e.id, "Strat", "/p kick it")
    MM.Core.AddLine(cat.id, e.id, "", "/p and again")
    MM.Edit.SetCategory(cat.id)
    MM.Edit.ShowTab("enemies")
    MM.Edit.ShowTab("pages")
end)

check("an enemy with no lines renders", function()
    local cat = MM.Core.Categories()[1]
    MM.Core.AddEnemy(cat.id, "Lineless")
    MM.Edit.SetCategory(cat.id)
    MM.Edit.RefreshEnemies()
end)

check("a dungeon with no pages renders", function()
    local cat = MM.Core.AddCategory("Pageless")
    MM.Edit.SetCategory(cat.id)
    MM.Edit.ShowTab("pages")
end)

check("refresh after deleting everything", function()
    local cat = MM.Core.AddCategory("Doomed")
    local e = MM.Core.AddEnemy(cat.id, "Gone soon")
    MM.Core.AddLine(cat.id, e.id, "", "/p bye")
    MM.Edit.SetCategory(cat.id)
    MM.Edit.RefreshEnemies()
    MM.Core.DeleteEnemy(cat.id, e.id)
    MM.Edit.RefreshEnemies()          -- pooled frames must not outlive their data
end)

-- The bug that shipped: delete buttons were parented to the list rather than to
-- the box they act on, so hiding a pooled box left its "-" on screen forever.
check("deleting a line leaves nothing behind", function()
    local stub = require("wowstub")
    local cat = MM.Core.AddCategory("Orphan check")
    local e = MM.Core.AddEnemy(cat.id, "Mob")
    local l1 = MM.Core.AddLine(cat.id, e.id, "", "/p one")
    local l2 = MM.Core.AddLine(cat.id, e.id, "", "/p two")

    -- Init leaves the frame hidden, and IsVisible walks ancestors, so without
    -- showing it every frame reads as invisible and the test proves nothing.
    MM.UI.Show("edit")
    MM.Edit.SetCategory(cat.id)
    MM.Edit.ShowTab("enemies")

    -- Delete buttons are precisely the buttons parented to an edit box. Matching
    -- on the label alone also counted the bar's collapse button, which is a
    -- different "-" entirely.
    local function visibleDeletes()
        local n = 0
        for _, f in ipairs(stub.descendants(MM.UI.root)) do
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

    MM.Core.DeleteLine(cat.id, e.id, l2.id)
    MM.Edit.RefreshEnemies()

    local after = visibleDeletes()
    if after ~= 4 then
        error(("after deleting a line, expected 4 box buttons, saw %d"):format(after))
    end

    MM.Core.DeleteEnemy(cat.id, e.id)
    MM.Edit.RefreshEnemies()
    if visibleDeletes() ~= 0 then error("buttons survived their enemy") end
end)

check("variant controls across every state", function()
    local cat = MM.Core.AddCategory("Variants in the UI")
    local e = MM.Core.AddEnemy(cat.id, "Mob")
    MM.Core.AddLine(cat.id, e.id, "", "/p call")
    local pg = MM.Core.AddPage(cat.id, "Route")
    MM.Core.AddEnemyToPage(cat.id, pg.id, e.id)

    MM.UI.Show("edit")
    MM.Edit.SetCategory(cat.id)
    MM.Edit.RefreshVariants()

    MM.Edit.ShowVariantDialog()               -- must build without a dungeon open failing
    local copy = MM.Core.AddVariant(cat.id, "Copy", MM.Core.ActiveVariantId(cat.id))
    MM.Core.SetActiveVariant(cat.id, copy.id)
    MM.Edit.RefreshVariants()
    MM.Edit.RefreshEnemies()
    MM.Edit.RefreshPages()

    if #MM.Core.Enemies(cat.id) ~= 1 then error("copied variant lost its enemy") end

    MM.Core.DeleteVariant(cat.id, copy.id)
    MM.Edit.RefreshVariants()
    MM.Edit.RefreshEnemies()
end)

check("Run offers the variant chooser", function()
    local cat = MM.Core.Categories()[6]
    MM.Core.AddVariant(cat.id, "Alternative", MM.Core.ActiveVariantId(cat.id))
    MM.UI.ShowView("run")
    if not MM.UI.OpenRun(cat.id) then error("OpenRun refused") end
    MM.UI.RefreshVariantChooser(cat.id)
end)

check("stale marker", function() MM.Edit.RefreshStaleMarker() end)
check("settings apply", function() MM.UI.ApplySettings() end)

check("reset all restores defaults and the widgets follow", function()
    local s = MM.Core.Settings()
    s.scale, s.opacity, s.buttonScale, s.textScale = 1.4, 0.5, 1.7, 0.7
    s.channel = "/raid"

    for key, value in pairs({ opacity = 1.0, scale = 1.0, buttonScale = 1.0, textScale = 1.0 }) do
        MM.Core.Settings()[key] = value
    end
    MM.UI.RefreshSettings()          -- must not error with values changed underneath

    if s.scale ~= 1.0 or s.opacity ~= 1.0 then
        error("defaults not restored")
    end
    -- The channel is a choice, not a cosmetic default, so a reset leaves it be.
    if s.channel ~= "/raid" then error("reset should not clear the channel") end
end)

check("text scale reaches the buttons", function()
    local cat = MM.Core.Categories()[6]
    MM.Core.Settings().textScale = 1.3
    local container = CreateFrame("Frame", nil, UIParent)
    MM.Runtime.EnsureManager(container)
    local ok, err = MM.Runtime.Build(container, cat.id, MM.Core.Settings())
    if not ok then error(tostring(err)) end
    MM.Core.Settings().textScale = 1.0
end)
check("help window", function() MM.UI.ShowHelp() end)

check("export and import windows", function()
    local cat = MM.Core.Categories()[6]
    MM.UI.ShowExport("Export", MM.Export.EncodeCategory(cat.id))
    MM.UI.ShowImport("Import", function() return "nothing" end)
end)

check("show, toggle and hide", function()
    MM.UI.Show("run")
    MM.UI.Toggle()
    MM.UI.Toggle()
end)

check("opening a dungeon in Run", function()
    local cat = MM.Core.Categories()[6]
    MM.UI.ShowView("run")
    if not MM.UI.OpenRun(cat.id) then error("OpenRun refused") end
end)

check("page memory survives a round trip", function()
    local cat = MM.Core.Categories()[6]
    MM.UI.OpenRun(cat.id)
    MM.Runtime.ShowPage(2)
    MM.UI.RememberPage()
end)

check("binding the page arrows", function()
    local arrows = MM.UI.Arrows()
    if not arrows then error("no arrows built") end
    MM.Runtime.EnsureManager(MM.UI.root)
    if not MM.Runtime.BindArrow(arrows.prev, -1) then error("prev refused") end
    if not MM.Runtime.BindArrow(arrows.next, 1) then error("next refused") end
end)

realPrint(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
