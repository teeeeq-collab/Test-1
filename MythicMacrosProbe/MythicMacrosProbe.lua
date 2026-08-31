--------------------------------------------------------------------------------
-- MythicMacros Probe
--
-- This is NOT the addon. It answers the questions that decide how the real
-- addon has to be built on Midnight 12.x.
--
-- The core of it is a 2x2 matrix:
--
--                        | payload: /run        | payload: chat line
--   ---------------------+----------------------+---------------------
--   macrotext attribute  | test 1               | test 2
--   real character macro | test 3               | test 4
--
-- Comparing rows tells us whether "macrotext" is dead (the reports conflict).
-- Comparing columns tells us whether it is /run that is blocked rather than
-- the delivery mechanism, so a dead cell can't be misread.
--
-- Every result is written to SavedVariables, so results collected inside a key
-- survive a /reload and can be printed afterwards with /mmprobe report.
--------------------------------------------------------------------------------

local PREFIX      = "MMP_"
local RUN_MACRO   = PREFIX .. "RUN"
local CHAT_MACRO  = PREFIX .. "CHAT"

-- Distinct tokens so chat echo detection can tell the two paths apart.
local TOKEN_MT    = "MMProbe-MT"   -- sent via macrotext
local TOKEN_RM    = "MMProbe-RM"   -- sent via real macro

MMProbeDB = MMProbeDB or {}

local function db()
    MMProbeDB.results  = MMProbeDB.results or {}
    MMProbeDB.created  = MMProbeDB.created or {}
    MMProbeDB.chatVerb = MMProbeDB.chatVerb or "/p"
    return MMProbeDB
end

local function out(msg)
    print("|cff33ff99MMProbe|r " .. msg)
end

local function record(key, value, note)
    db().results[key] = {
        value = tostring(value),
        note  = note and tostring(note) or nil,
        when  = date("%Y-%m-%d %H:%M:%S"),
    }
    out(("|cffaaaaaa%s|r = |cffffff00%s|r%s"):format(
        key, tostring(value), note and (" |cffaaaaaa(" .. tostring(note) .. ")|r") or ""))
end

--------------------------------------------------------------------------------
-- Signal target, called by macros via /run.
--------------------------------------------------------------------------------

function MMProbeSignal(tag)
    record("exec." .. tostring(tag), "FIRED",
        InCombatLockdown() and "in combat" or "out of combat")
end

--------------------------------------------------------------------------------
-- Snapshots
--------------------------------------------------------------------------------

local function snapshotEnv()
    local version, _, _, tocversion = GetBuildInfo()
    local iname, itype, diffID, diffName, _, _, _, instID = GetInstanceInfo()

    record("env.build",      ("%s  toc=%s"):format(tostring(version), tostring(tocversion)))
    record("env.instance",   ("%s | type=%s | id=%s"):format(
                             tostring(iname), tostring(itype), tostring(instID)))
    record("env.difficulty", ("%s (%s)"):format(tostring(diffName), tostring(diffID)))
    record("env.combat",     InCombatLockdown() and "IN COMBAT" or "out of combat")
    record("env.group",      ("party=%d raid=%s"):format(
                             GetNumSubgroupMembers(), tostring(IsInRaid())))

    local ok, lvl = pcall(function() return C_ChallengeMode.GetActiveKeystoneInfo() end)
    record("env.keystoneLevel", ok and tostring(lvl) or "unavailable")

    local ok2, active = pcall(function() return C_ChallengeMode.IsChallengeModeActive() end)
    record("env.challengeActive", ok2 and tostring(active) or "unavailable")
end

local function snapshotSlots()
    local acct, char = GetNumMacros()
    record("slots.account",   ("%s used of %s"):format(tostring(acct), tostring(MAX_ACCOUNT_MACROS)))
    record("slots.character", ("%s used of %s"):format(tostring(char), tostring(MAX_CHARACTER_MACROS)))
end

--------------------------------------------------------------------------------
-- Macro plumbing. Everything is pcall'd: we are probing an API surface that may
-- throw, and an error here must not take the panel down with it.
--------------------------------------------------------------------------------

local ICON_CANDIDATES = { 134400, "INV_MISC_QUESTIONMARK" }

local function macroBodies()
    return
        "/run MMProbeSignal('realmacro')",
        ("%s %s check"):format(db().chatVerb, TOKEN_RM)
end

local function ensureMacro(name, body)
    local idx = GetMacroIndexByName(name)

    if idx and idx > 0 then
        -- Try keeping the existing icon first (nil), then explicit fallbacks.
        -- Note: a plain ipairs over {nil, ...} would stop at the hole.
        local attempts = { { false }, { true, ICON_CANDIDATES[1] }, { true, ICON_CANDIDATES[2] } }
        local lastErr
        for _, attempt in ipairs(attempts) do
            local ok, err
            if attempt[1] then
                ok, err = pcall(EditMacro, idx, name, attempt[2], body)
            else
                ok, err = pcall(EditMacro, idx, name, nil, body)
            end
            if ok then
                record("macro.edit." .. name, "OK idx=" .. tostring(idx))
                return idx
            end
            lastErr = err
        end
        record("macro.edit." .. name, "FAILED", lastErr)
        return nil
    end

    local lastErr
    for _, icon in ipairs(ICON_CANDIDATES) do
        local ok, res = pcall(CreateMacro, name, icon, body, false)
        if ok and res then
            db().created[name] = true
            record("macro.create." .. name, "OK idx=" .. tostring(res))
            return res
        end
        lastErr = ok and "returned nil (slots full?)" or res
    end
    record("macro.create." .. name, "FAILED", lastErr)
    return nil
end

local function createProbeMacros()
    if InCombatLockdown() then
        out("|cffff4444can't create macros in combat -- that itself is a result.|r")
        record("macro.createInCombat", "REFUSED", "InCombatLockdown was true")
        return
    end
    snapshotSlots()
    local runBody, chatBody = macroBodies()
    ensureMacro(RUN_MACRO, runBody)
    ensureMacro(CHAT_MACRO, chatBody)
    snapshotSlots()
end

local function cleanupMacros()
    if InCombatLockdown() then
        out("|cffff4444can't delete macros in combat.|r")
        return
    end
    local removed = 0
    for name in pairs(db().created) do
        local idx = GetMacroIndexByName(name)
        if idx and idx > 0 and pcall(DeleteMacro, idx) then
            removed = removed + 1
        end
        db().created[name] = nil
    end
    out(("removed %d probe macro(s)."):format(removed))
    snapshotSlots()
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "MMProbeFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(440, 500)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetFrameStrata("DIALOG")
frame:Hide()

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -5)
frame.title:SetText("MythicMacros Probe")

local y = -32
local LINE, ROW = 15, 28

local function label(text, colour)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 14, y)
    fs:SetWidth(410)
    fs:SetJustifyH("LEFT")
    fs:SetText((colour or "|cffffffff") .. text .. "|r")
    y = y - LINE
    return fs
end

-- A secure button carrying one cell of the 2x2 matrix.
local function secureTest(text, xOffset, setup)
    local b = CreateFrame("Button", nil, frame,
        "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetSize(198, 24)
    b:SetPoint("TOPLEFT", xOffset, y)
    b:SetText(text)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "macro")
    setup(b)
    return b
end

local function plainButton(text, xOffset, width, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(width or 198, 24)
    b:SetPoint("TOPLEFT", xOffset, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

label("Click every button. Results print to chat and are saved to disk.", "|cffaaaaaa")
label(" ")

-- Row 1: macrotext -------------------------------------------------------
label("macrotext attribute  (reported as protected in 12.0 -- is it?)")
local btnMtRun = secureTest("macrotext + /run", 14, function(b)
    b:SetAttribute("macrotext", "/run MMProbeSignal('macrotext')")
end)
local btnMtChat = secureTest("macrotext + chat", 222, function(b)
    b:SetAttribute("macrotext", ("%s %s check"):format(db().chatVerb, TOKEN_MT))
end)
y = y - ROW

-- Row 2: real macro ------------------------------------------------------
label("real character macro  (the path the real addon would use)")
local btnRmRun = secureTest("real macro + /run", 14, function(b)
    b:SetAttribute("macro", RUN_MACRO)
end)
local btnRmChat = secureTest("real macro + chat", 222, function(b)
    b:SetAttribute("macro", CHAT_MACRO)
end)
y = y - ROW

label(" ")
label("Chat tests need a group. Run them inside an active key for the real answer.", "|cffaaaaaa")
label(" ")

-- Combat behaviour -------------------------------------------------------
label("Click this one WHILE IN COMBAT:")
plainButton("Test: combat ops", 14, 198, function()
    record("combat.lockdown", InCombatLockdown() and "IN COMBAT" or "out of combat")

    local okAttr, errAttr = pcall(function()
        btnMtRun:SetAttribute("macrotext", "/run MMProbeSignal('macrotext')")
    end)
    record("combat.SetAttribute", okAttr and "ALLOWED" or "BLOCKED", not okAttr and errAttr or nil)

    local idx = GetMacroIndexByName(RUN_MACRO)
    if idx and idx > 0 then
        local runBody = macroBodies()
        local okEdit, errEdit = pcall(EditMacro, idx, RUN_MACRO, nil, runBody)
        record("combat.EditMacro", okEdit and "ALLOWED" or "BLOCKED", not okEdit and errEdit or nil)
    else
        record("combat.EditMacro", "SKIPPED", "probe macros not created yet")
    end
end)

-- Secure page flip -------------------------------------------------------
local pageA = CreateFrame("Frame", "MMProbePageA", frame, "SecureHandlerBaseTemplate")
pageA:SetSize(198, 24)
pageA:SetPoint("TOPLEFT", 222, y)
pageA.text = pageA:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pageA.text:SetAllPoints()
pageA.text:SetText("|cff44ff44PAGE A|r")

local pageB = CreateFrame("Frame", "MMProbePageB", frame, "SecureHandlerBaseTemplate")
pageB:SetSize(198, 24)
pageB:SetPoint("TOPLEFT", 222, y)
pageB.text = pageB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pageB.text:SetAllPoints()
pageB.text:SetText("|cffff8844PAGE B|r")
pageB:Hide()
y = y - ROW

label("Click this WHILE IN COMBAT -- does the box on the right change?")
local btnFlip = CreateFrame("Button", "MMProbeFlip", frame,
    "SecureHandlerClickTemplate,UIPanelButtonTemplate")
btnFlip:SetSize(198, 24)
btnFlip:SetPoint("TOPLEFT", 14, y)
btnFlip:SetText("Test: flip page")
btnFlip:RegisterForClicks("AnyUp")
btnFlip:SetFrameRef("pageA", pageA)
btnFlip:SetFrameRef("pageB", pageB)
btnFlip:SetAttribute("_onclick", [[
    local a = self:GetFrameRef("pageA")
    local b = self:GetFrameRef("pageB")
    if a:IsShown() then a:Hide(); b:Show() else b:Hide(); a:Show() end
]])
pageA:SetPoint("TOPLEFT", 222, y)
pageB:SetPoint("TOPLEFT", 222, y)
y = y - ROW - 8

-- Setup / teardown -------------------------------------------------------
label("Setup / teardown", "|cffaaaaaa")
plainButton("Create macros", 14, 130, createProbeMacros)
plainButton("Remove macros", 152, 130, cleanupMacros)

local report  -- forward declaration
plainButton("Print report", 290, 130, function() report() end)
y = y - ROW

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------

report = function()
    out("|cffffff00========== PROBE REPORT ==========|r")
    local keys = {}
    for k in pairs(db().results) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local r = db().results[k]
        print(("  %s = %s%s"):format(k, r.value, r.note and ("   -- " .. r.note) or ""))
    end
    if #keys == 0 then print("  (nothing recorded yet)") end
    out("|cffffff00========== END REPORT ==========|r")
end

--------------------------------------------------------------------------------
-- Chat echo detection: did the line actually land?
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, e in ipairs({
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_SAY",
    "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
}) do
    events:RegisterEvent(e)
end

events:SetScript("OnEvent", function(_, event, msg)
    if event == "PLAYER_ENTERING_WORLD" then
        snapshotEnv()
        snapshotSlots()
    elseif event == "CHALLENGE_MODE_START" then
        record("env.keyStarted", "yes")
        snapshotEnv()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        record("env.keyCompleted", "yes")
    elseif type(msg) == "string" then
        local where = event .. " / " .. (InCombatLockdown() and "in combat" or "out of combat")
        if msg:find(TOKEN_MT, 1, true) then
            record("chat.echo.macrotext", "RECEIVED", where)
        elseif msg:find(TOKEN_RM, 1, true) then
            record("chat.echo.realmacro", "RECEIVED", where)
        end
    end
end)

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

SLASH_MMPROBE1 = "/mmprobe"
SlashCmdList.MMPROBE = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")

    if arg == "report" then
        report()
    elseif arg == "clean" then
        cleanupMacros()
    elseif arg == "env" then
        snapshotEnv(); snapshotSlots()
    elseif arg == "reset" then
        MMProbeDB.results = {}
        out("results cleared.")
    elseif arg == "say" or arg == "party" then
        if InCombatLockdown() then out("|cffff4444not in combat.|r") return end
        db().chatVerb = (arg == "say") and "/say" or "/p"
        btnMtChat:SetAttribute("macrotext",
            ("%s %s check"):format(db().chatVerb, TOKEN_MT))
        local _, chatBody = macroBodies()
        local idx = GetMacroIndexByName(CHAT_MACRO)
        if idx and idx > 0 then pcall(EditMacro, idx, CHAT_MACRO, nil, chatBody) end
        out("chat tests now use |cffffff00" .. db().chatVerb .. "|r")
    else
        if frame:IsShown() then frame:Hide() else frame:Show() end
        out("commands: report | clean | env | reset | say | party")
    end
end

out("loaded. |cffffff00/mmprobe|r opens the panel.")
