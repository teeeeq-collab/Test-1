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

check("switching to every tab", function()
    MM.Edit.ShowTab("dungeons")
    MM.Edit.ShowTab("enemies")
    MM.Edit.ShowTab("pages")
end)

check("dungeons tab with no dungeons", function() MM.Edit.RefreshDungeons() end)

check("starter dungeons then refresh", function()
    MM.Starter.Create()
    MM.Edit.RefreshDungeons()
    MM.UI.RefreshCategories()
end)

check("selecting a dungeon and listing its enemies", function()
    local cat = MM.Core.Categories()[1]
    MM.Capture.SetCategory(cat.id)
    MM.Edit.ShowTab("dungeons")
    MM.Edit.RefreshDungeons()
end)

check("enemies tab with content", function()
    local cat = MM.Core.Categories()[6]     -- Kings' Rest: has boss cards
    local e = MM.Core.AddEnemy(cat.id, "Trash pack")
    MM.Core.AddLine(cat.id, e.id, "Strat", "/p kick it")
    MM.Edit.ShowTab("enemies")
    MM.Edit.RefreshEnemies()
end)

check("pages tab with content", function()
    MM.Edit.ShowTab("pages")
    MM.Edit.RefreshPages()
end)

check("Edit.Refresh from any state", function() MM.Edit.Refresh() end)

check("stale marker", function() MM.Edit.RefreshStaleMarker() end)

check("settings apply", function() MM.UI.ApplySettings() end)

check("export window", function()
    local cat = MM.Core.Categories()[6]
    local str = MM.Export.EncodeCategory(cat.id)
    MM.UI.ShowExport("Export", str)
end)

check("import window", function()
    MM.UI.ShowImport("Import", function() return "nothing" end)
end)

check("show and hide the panel", function()
    MM.UI.Show("run")
    MM.UI.Toggle()
    MM.UI.Toggle()
end)

check("building a category's buttons", function()
    local cat = MM.Core.Categories()[6]
    local container = CreateFrame("Frame", nil, UIParent)
    MM.Runtime.EnsureManager(container)
    local ok, err = MM.Runtime.Build(container, cat.id, MM.Core.Settings())
    if not ok then error(tostring(err)) end
end)

check("binding the page arrows", function()
    local arrows = MM.UI.Arrows()
    if not arrows then error("no arrows built") end
    if not MM.Runtime.BindArrow(arrows.prev, -1) then error("prev arrow refused") end
    if not MM.Runtime.BindArrow(arrows.next, 1) then error("next arrow refused") end
end)

realPrint(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
