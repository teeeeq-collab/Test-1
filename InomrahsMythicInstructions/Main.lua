--------------------------------------------------------------------------------
-- Main: load, wire, and the slash command.
--------------------------------------------------------------------------------

local ADDON, IMI = ...

local Core, UI, Runtime, Util = IMI.Core, IMI.UI, IMI.Runtime, IMI.Util

-- The addon's own table, on one global.
--
-- Everything else here is private to the addon. This is deliberate and it is
-- one name: the self-test addon checks this one against the live client, and
-- there is no way to look at a running addon's internals from outside without
-- it. It is read-only in practice — nothing here changes behaviour when it is
-- absent, so the addon works with the self-test uninstalled, which is how it
-- will be installed almost always.
_G.InomrahsMI = IMI

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")

    InomrahsMythicInstructionsDB = Core.Init(InomrahsMythicInstructionsDB)
    UI.Init()

    -- After the UI, because history asks it where the user is standing when an
    -- edit happens, and that is the answer undo navigates back to.
    IMI.History.Init(IMI.Edit.Context)
    IMI.History.onChange = UI.RefreshHistoryButtons

    -- Arrows are secure handlers built with the UI; the pager they drive has to
    -- exist before they can reference it.
    local arrows = UI.Arrows()
    if arrows then
        Runtime.EnsureManager(UI.root)
        Runtime.BindArrow(arrows.prev, -1)
        Runtime.BindArrow(arrows.next, 1)
    end

    Util.Print("loaded. |cffffff00/imi|r opens it.")
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
-- Keybinding target
--
-- Global because Bindings.xml calls it by name. Walking a dungeon and pressing
-- one key on each pack is the practical way to build an enemy list; clicking a
-- panel button while hovering a mob is not possible.
--------------------------------------------------------------------------------

-- The binding identifier changed with the rename, so a key bound under the old
-- name is gone and has to be set again. That is the one-off cost of the rename.
BINDING_HEADER_INOMRAHSMI = "Inomrah's Mythic Instructions"
BINDING_NAME_INOMRAHSMI_ADDTARGET = "Add target as enemy"

function InomrahsMI_AddTarget()
    local name, why = IMI.Capture.AddTarget("target")
    if name then
        Util.Print(("added |cffffff00%s|r to %s."):format(name, why))
        if IMI.Edit and IMI.Edit.RefreshEnemies then IMI.Edit.RefreshEnemies() end
    else
        Util.Print("|cffff4444" .. (why or "could not add") .. "|r")
    end
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

-- Only /imi. /mm belongs to Mythic Mentor, and two addons claiming the same
-- slash command means whichever loads second silently wins.
SLASH_INOMRAHSMI1 = "/imi"
SlashCmdList.INOMRAHSMI = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")

    if arg == "demo" then
        if InCombatLockdown() then
            Util.Print("|cffff4444not in combat.|r")
            return
        end
        local cat = createDemo()
        UI.RefreshCategories()
        Util.Print(("added |cffffff00%s|r - open Run and select it."):format(cat.name))

    elseif arg == "starter" then
        if InCombatLockdown() then
            Util.Print("|cffff4444not in combat.|r")
            return
        end
        local made, skipped = IMI.Starter.Create()
        UI.RefreshCategories()
        if IMI.Edit and IMI.Edit.Refresh then IMI.Edit.Refresh() end
        Util.Print(("created %d dungeon(s)%s."):format(#made,
            (#skipped > 0) and (", skipped %d already there"):format(#skipped) or ""))
        Util.Print("|cffaaaaaaTrash is empty by design - target a mob and press the "
            .. "Add target keybind, or the button in Edit.|r")

    elseif arg == "add" then
        InomrahsMI_AddTarget()

    elseif arg == "debug" then
        IMI.Runtime.Debug()

    elseif arg == "settings" then
        UI.Show("settings")

    elseif arg == "edit" then
        UI.Show("edit")

    elseif arg == "wipe" then
        if InCombatLockdown() then
            Util.Print("|cffff4444not in combat.|r")
            return
        end
        InomrahsMythicInstructionsDB = Core.Init({})
        -- The database is a different table now, so the history built against
        -- the old one describes states that no longer connect to anything.
        -- Undoing a wipe is not a promise worth making from a debug command.
        IMI.History.Init()
        UI.RefreshCategories()
        UI.RefreshHistoryButtons()
        Util.Print("data cleared. undo history reset too.")

    else
        UI.Toggle()
        Util.Print("commands: starter | add | demo | debug | edit | settings | wipe")
    end
end
