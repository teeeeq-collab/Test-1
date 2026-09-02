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

check("stale marker", function() MM.Edit.RefreshStaleMarker() end)
check("settings apply", function() MM.UI.ApplySettings() end)
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
