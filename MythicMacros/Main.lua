--------------------------------------------------------------------------------
-- Main: load, wire, and the slash command.
--------------------------------------------------------------------------------

local ADDON, MM = ...

local Core, UI, Runtime, Util = MM.Core, MM.UI, MM.Runtime, MM.Util

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")

    MythicMacrosDB = Core.Init(MythicMacrosDB)
    UI.Init()

    -- Arrows are secure handlers built with the UI; the pager they drive has to
    -- exist before they can reference it.
    local arrows = UI.Arrows()
    if arrows then
        Runtime.EnsureManager(UI.root)
        Runtime.BindArrow(arrows.prev, -1)
        Runtime.BindArrow(arrows.next, 1)
    end

    Util.Print("loaded. |cffffff00/mm|r opens it.")
end)

--------------------------------------------------------------------------------
-- Demo data
--
-- Edit does not exist yet, so without this there is no way to see Run working.
-- It builds a category with the shapes that matter: a plain enemy, one with two
-- lines, a boss laid out three across, and an enemy shared between two pages.
--------------------------------------------------------------------------------

local function createDemo()
    local cat = Core.AddCategory("Demo Dungeon")

    local harrower = Core.AddEnemy(cat.id, "Twinfang Harrower")
    Core.AddLine(cat.id, harrower.id, "Strat", "/p Harrower - freedom the snare on the tank")
    Core.AddLine(cat.id, harrower.id, "Panic", "/p HARROWER FRENZY - stop dps and kite")

    local serpent = Core.AddEnemy(cat.id, "Primal Serpent")
    Core.AddLine(cat.id, serpent.id, "", "/p Primal Serpent - spread 5 yards, dispel at 4")

    local matriarch = Core.AddEnemy(cat.id, "Matriarch")
    Core.AddLine(cat.id, matriarch.id, "Open", "/p Matriarch - CC the adds first")
    Core.AddLine(cat.id, matriarch.id, "Split", "/p Matriarch splitting - one dps per whelp")

    local boss = Core.AddEnemy(cat.id, "Boss: Ra'Vi", 3)
    Core.AddLine(cat.id, boss.id, "P1", "/p Ra'Vi P1 - spread for the volley")
    Core.AddLine(cat.id, boss.id, "P2", "/p Ra'Vi P2 - stack behind the pillar")
    Core.AddLine(cat.id, boss.id, "Soak", "/p Ra'Vi - soak the orbs in pairs")
    Core.AddLine(cat.id, boss.id, "Bloodlust", "/p Bloodlust now")

    local p1 = Core.AddPage(cat.id, "Opening trash")
    Core.AddEnemyToPage(cat.id, p1.id, harrower.id)
    Core.AddEnemyToPage(cat.id, p1.id, serpent.id)
    Core.AddEnemyToPage(cat.id, p1.id, matriarch.id)

    local p2 = Core.AddPage(cat.id, "To first boss")
    Core.AddEnemyToPage(cat.id, p2.id, matriarch.id)   -- same definition, two pages

    local p3 = Core.AddPage(cat.id, "Boss: Ra'Vi")
    Core.AddEnemyToPage(cat.id, p3.id, boss.id)

    return cat
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

SLASH_MYTHICMACROS1 = "/mm"
SlashCmdList.MYTHICMACROS = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")

    if arg == "demo" then
        if InCombatLockdown() then
            Util.Print("|cffff4444not in combat.|r")
            return
        end
        local cat = createDemo()
        UI.RefreshCategories()
        Util.Print(("added |cffffff00%s|r - open Run and select it."):format(cat.name))

    elseif arg == "settings" then
        UI.Show("settings")

    elseif arg == "edit" then
        UI.Show("edit")

    elseif arg == "wipe" then
        if InCombatLockdown() then
            Util.Print("|cffff4444not in combat.|r")
            return
        end
        MythicMacrosDB = Core.Init({})
        UI.RefreshCategories()
        Util.Print("data cleared.")

    else
        UI.Toggle()
        Util.Print("commands: demo | edit | settings | wipe")
    end
end
