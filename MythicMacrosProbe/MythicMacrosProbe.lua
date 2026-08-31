--------------------------------------------------------------------------------
-- MythicMacros Probe
--
-- Not the addon. This measures the specific mechanisms the MythicMacros design
-- is betting on, so the real code is written against confirmed behaviour rather
-- than against reporting that contradicts itself.
--
-- Six things are under test:
--
--   A. Limits      -- macro slots, macro name length, and whether the macro body
--                     cap is really 255 BYTES (the whole basis of the input guard)
--   B. Execution   -- 2x2: macrotext vs real macro, against /run vs a chat line.
--                     Rows show whether macrotext still executes; columns show
--                     whether /run is the blocked part, so a dead cell cannot be
--                     misread.
--   C. Combat      -- which operations are refused once a pull starts
--   D. Paging      -- can a page be flipped mid-combat, and does it need the
--                     secure-handler machinery or is plain Hide() enough?
--   E. EditBox     -- does SetMaxLetters count bytes or characters?
--   F. Batch       -- can ~20 macros be created in one go, and what happens at
--                     the cap?
--
-- Results are written to SavedVariables, so anything collected inside a key
-- survives a reload and can be printed afterwards with /mmprobe report.
--------------------------------------------------------------------------------

local PREFIX     = "MMP_"
local RUN_MACRO  = PREFIX .. "RUN"
local CHAT_MACRO = PREFIX .. "CHAT"

local TOKEN_MT = "MMProbe-MT"   -- chat sent via the macrotext attribute
local TOKEN_RM = "MMProbe-RM"   -- chat sent via a real macro

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
    record("B.exec." .. tostring(tag), "FIRED",
        InCombatLockdown() and "in combat" or "out of combat")
end

--------------------------------------------------------------------------------
-- Macro plumbing. All pcall'd: this is an API surface that may throw, and an
-- error must not take the panel down.
--------------------------------------------------------------------------------

local ICONS = { 134400, "INV_MISC_QUESTIONMARK" }

local function createMacro(name, body)
    local lastErr
    for _, icon in ipairs(ICONS) do
        local ok, res = pcall(CreateMacro, name, icon, body, false)
        if ok and res then
            db().created[name] = true
            return res
        end
        lastErr = ok and "returned nil" or res
    end
    return nil, lastErr
end

local function deleteMacro(name)
    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        local ok = pcall(DeleteMacro, idx)
        db().created[name] = nil
        return ok
    end
    db().created[name] = nil
    return false
end

local function cleanupMacros()
    if InCombatLockdown() then
        out("|cffff4444can't delete macros in combat.|r")
        return
    end
    local removed = 0
    for name in pairs(db().created) do
        if deleteMacro(name) then removed = removed + 1 end
    end
    out(("removed %d probe macro(s)."):format(removed))
end

--------------------------------------------------------------------------------
-- A. Limits
--------------------------------------------------------------------------------

local function testLimits()
    if InCombatLockdown() then
        out("|cffff4444run this out of combat.|r")
        return
    end

    local version, _, _, toc = GetBuildInfo()
    record("A.build", ("%s toc=%s"):format(tostring(version), tostring(toc)))

    local acct, char = GetNumMacros()
    record("A.slots.account",   ("%s used of %s"):format(tostring(acct), tostring(MAX_ACCOUNT_MACROS)))
    record("A.slots.character", ("%s used of %s"):format(tostring(char), tostring(MAX_CHARACTER_MACROS)))

    -- How long may a macro NAME be? The addon wants short generated names, but
    -- needs to know the ceiling before assuming one.
    local longName = string.rep("N", 32)
    local idx, err = createMacro(longName, "/run return")
    if idx then
        local realName = GetMacroInfo(idx)
        record("A.nameLimit", ("asked 32, got %d"):format(#tostring(realName)),
            "stored as: " .. tostring(realName))
        deleteMacro(longName)
        -- The name may have been truncated, so clean up under the stored name too.
        if realName and realName ~= longName then deleteMacro(realName) end
    else
        record("A.nameLimit", "CREATE FAILED", err)
    end

    -- THE important one. A body of 120 multi-byte characters is 360 bytes but
    -- only 120 characters. What comes back tells us which unit the cap is in.
    local multi = string.rep("\226\130\172", 120)   -- 120 x U+20AC EURO SIGN
    record("A.bodySent", ("%d bytes / %d chars"):format(#multi, 120))

    local bidx, berr = createMacro(PREFIX .. "BYTES", multi)
    if bidx then
        local stored = GetMacroBody(bidx) or ""
        record("A.bodyStored", ("%d bytes"):format(#stored),
            (#stored < #multi) and "TRUNCATED - cap is in bytes if this is ~255"
                                or "not truncated")
        deleteMacro(PREFIX .. "BYTES")
    else
        record("A.bodyStored", "CREATE FAILED", berr)
    end

    -- And the same length in plain ASCII, for comparison.
    local ascii = string.rep("x", 300)
    local aidx, aerr = createMacro(PREFIX .. "ASCII", ascii)
    if aidx then
        local stored = GetMacroBody(aidx) or ""
        record("A.bodyAscii", ("sent 300 bytes, stored %d"):format(#stored))
        deleteMacro(PREFIX .. "ASCII")
    else
        record("A.bodyAscii", "CREATE FAILED", aerr)
    end
end

--------------------------------------------------------------------------------
-- E. EditBox semantics
--------------------------------------------------------------------------------

local function testEditBox()
    local eb = CreateFrame("EditBox", nil, UIParent)
    eb:SetMaxLetters(10)
    eb:SetAutoFocus(false)
    eb:Hide()

    -- 10 euro signs: 10 characters, 30 bytes.
    eb:SetText(string.rep("\226\130\172", 10))
    local got = eb:GetText() or ""
    record("E.setMaxLetters", ("kept %d bytes"):format(#got),
        (#got > 10) and "counts CHARACTERS - byte guard is required"
                     or "counts BYTES - SetMaxLetters alone would suffice")

    eb:SetText(string.rep("x", 20))
    record("E.asciiClamp", ("asked 20 ascii, kept %d"):format(#(eb:GetText() or "")))
end

--------------------------------------------------------------------------------
-- F. Batch creation
--------------------------------------------------------------------------------

local function testBatch()
    if InCombatLockdown() then
        out("|cffff4444run this out of combat.|r")
        return
    end

    local made, failedAt, failErr = 0, nil, nil
    for i = 1, 20 do
        local name = ("%sB%02d"):format(PREFIX, i)
        local idx, err = createMacro(name, "/run return " .. i)
        if idx then
            made = made + 1
        else
            failedAt, failErr = i, err
            break
        end
    end

    record("F.batchCreated", made, failedAt and ("stopped at " .. failedAt .. ": " .. tostring(failErr)) or "all 20 ok")

    -- Deleting shifts indices, which is exactly why the addon resolves by name.
    -- Delete forwards and confirm every one goes.
    local removed = 0
    for i = 1, 20 do
        if deleteMacro(("%sB%02d"):format(PREFIX, i)) then removed = removed + 1 end
    end
    record("F.batchRemoved", removed, (removed == made) and "clean" or "LEFTOVERS - check macro list")
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "MMProbeFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(470, 560)
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
local function label(text, colour)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 14, y)
    fs:SetWidth(440)
    fs:SetJustifyH("LEFT")
    fs:SetText((colour or "|cffffffff") .. text .. "|r")
    y = y - 15
    return fs
end

local function plain(text, x, w, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function secure(text, x, setup)
    local b = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetSize(212, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "macro")
    setup(b)
    return b
end

label("Out of combat, press these three:", "|cffaaaaaa")
plain("A. Limits", 14, 140, testLimits)
plain("E. EditBox", 166, 140, testEditBox)
plain("F. Batch x20", 318, 140, testBatch)
y = y - 32

label(" ")
label("B. Execution matrix. 'Create macros' first, then all four:")
plain("Create macros", 14, 140, function()
    if InCombatLockdown() then out("|cffff4444not in combat.|r") return end
    local runIdx, runErr = createMacro(RUN_MACRO, "/run MMProbeSignal('realmacro')")
    record("B.macro.run", runIdx and ("created idx=" .. runIdx) or "FAILED", runErr)
    local chatIdx, chatErr = createMacro(CHAT_MACRO,
        ("%s %s check"):format(db().chatVerb, TOKEN_RM))
    record("B.macro.chat", chatIdx and ("created idx=" .. chatIdx) or "FAILED", chatErr)
end)
y = y - 30

local btnMtRun = secure("macrotext + /run", 14, function(b)
    b:SetAttribute("macrotext", "/run MMProbeSignal('macrotext')")
end)
local btnMtChat = secure("macrotext + chat", 240, function(b)
    b:SetAttribute("macrotext", ("%s %s check"):format(db().chatVerb, TOKEN_MT))
end)
y = y - 28

secure("real macro + /run", 14, function(b) b:SetAttribute("macro", RUN_MACRO) end)
secure("real macro + chat", 240, function(b) b:SetAttribute("macro", CHAT_MACRO) end)
y = y - 32

label(" ")
label("C + D. Get into combat, then press both of these:", "|cffffcc44")

--- The design assumes attribute writes and macro edits are refused in combat,
--- and that page flipping therefore cannot go through them.
plain("C. Combat ops", 14, 200, function()
    record("C.lockdown", InCombatLockdown() and "IN COMBAT" or "out of combat",
        "results below only mean something if this says IN COMBAT")

    local ok, err = pcall(function()
        btnMtRun:SetAttribute("macrotext", "/run MMProbeSignal('macrotext')")
    end)
    record("C.SetAttribute", ok and "ALLOWED" or "BLOCKED", not ok and err or nil)

    local idx = GetMacroIndexByName(RUN_MACRO)
    if idx and idx > 0 then
        local okE, errE = pcall(EditMacro, idx, RUN_MACRO, nil, "/run MMProbeSignal('realmacro')")
        record("C.EditMacro", okE and "ALLOWED" or "BLOCKED", not okE and errE or nil)
    else
        record("C.EditMacro", "SKIPPED", "create the macros first")
    end

    local okC, errC = pcall(CreateMacro, PREFIX .. "CBT", ICONS[1], "/run return", false)
    record("C.CreateMacro", okC and "ALLOWED" or "BLOCKED", not okC and errC or nil)
    if okC then deleteMacro(PREFIX .. "CBT") end

    local okS, errS = pcall(function() frame:SetScale(1.0) end)
    record("C.SetScale", okS and "ALLOWED" or "BLOCKED", not okS and errS or nil)
end)
y = y - 30

--------------------------------------------------------------------------------
-- D. Paging. Two mechanisms, because if the plain one works the real addon
-- avoids a large amount of secure-handler machinery.
--------------------------------------------------------------------------------

local pagePlain = CreateFrame("Frame", "MMProbePagePlain", frame)
pagePlain:SetSize(212, 24)
pagePlain:SetPoint("TOPLEFT", 240, y)
local pagePlainBtn = CreateFrame("Button", "MMProbePlainChild", pagePlain,
    "SecureActionButtonTemplate,UIPanelButtonTemplate")
pagePlainBtn:SetAllPoints()
pagePlainBtn:SetText("plain frame + secure child")
pagePlainBtn:SetAttribute("type", "macro")
pagePlainBtn:SetAttribute("macrotext", "/run return")

--- Can insecure code hide a plain frame that contains a protected button, once
--- combat has started? If yes, paging needs no secure handlers at all.
plain("D1. Plain Hide()", 14, 200, function()
    local wasShown = pagePlain:IsShown()
    local ok, err = pcall(function()
        if wasShown then pagePlain:Hide() else pagePlain:Show() end
    end)
    -- A blocked action often does not throw; it just fails to apply. So the
    -- real check is whether the visibility actually changed.
    local changed = (pagePlain:IsShown() ~= wasShown)
    record("D1.plainHide",
        changed and "WORKED" or "NO EFFECT",
        ("combat=%s, pcall=%s%s"):format(
            tostring(InCombatLockdown()),
            ok and "no error" or "threw",
            (not ok) and (": " .. tostring(err)) or ""))
end)
y = y - 30

local pageA = CreateFrame("Frame", "MMProbePageA", frame, "SecureHandlerBaseTemplate")
pageA:SetSize(212, 24)
pageA:SetPoint("TOPLEFT", 240, y)
pageA.text = pageA:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pageA.text:SetAllPoints()
pageA.text:SetText("|cff44ff44PAGE A|r")

local pageB = CreateFrame("Frame", "MMProbePageB", frame, "SecureHandlerBaseTemplate")
pageB:SetSize(212, 24)
pageB:SetPoint("TOPLEFT", 240, y)
pageB.text = pageB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pageB.text:SetAllPoints()
pageB.text:SetText("|cffff8844PAGE B|r")
pageB:Hide()

local btnFlip = CreateFrame("Button", "MMProbeFlip", frame,
    "SecureHandlerClickTemplate,UIPanelButtonTemplate")
btnFlip:SetSize(200, 24)
btnFlip:SetPoint("TOPLEFT", 14, y)
btnFlip:SetText("D2. Secure flip")
btnFlip:RegisterForClicks("AnyUp")
btnFlip:SetFrameRef("pageA", pageA)
btnFlip:SetFrameRef("pageB", pageB)
btnFlip:SetAttribute("_onclick", [[
    local a = self:GetFrameRef("pageA")
    local b = self:GetFrameRef("pageB")
    if a:IsShown() then a:Hide(); b:Show() else b:Hide(); a:Show() end
]])
btnFlip:HookScript("OnClick", function()
    record("D2.secureFlip", pageA:IsShown() and "showing A" or "showing B",
        "combat=" .. tostring(InCombatLockdown()))
end)
y = y - 34

label(" ")
plain("Print report", 14, 140, function() MMProbeReport() end)
plain("Remove macros", 166, 140, cleanupMacros)

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------

function MMProbeReport()
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
-- Chat echo detection
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, e in ipairs({
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_SAY",
}) do
    events:RegisterEvent(e)
end

events:SetScript("OnEvent", function(_, event, msg)
    if type(msg) ~= "string" then return end
    local where = event .. " / " .. (InCombatLockdown() and "in combat" or "out of combat")
    if msg:find(TOKEN_MT, 1, true) then
        record("B.chat.macrotext", "RECEIVED", where)
    elseif msg:find(TOKEN_RM, 1, true) then
        record("B.chat.realmacro", "RECEIVED", where)
    end
end)

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

SLASH_MMPROBE1 = "/mmprobe"
SlashCmdList.MMPROBE = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")

    if arg == "report" then
        MMProbeReport()
    elseif arg == "clean" then
        cleanupMacros()
    elseif arg == "reset" then
        MMProbeDB.results = {}
        out("results cleared.")
    elseif arg == "say" or arg == "party" then
        if InCombatLockdown() then out("|cffff4444not in combat.|r") return end
        db().chatVerb = (arg == "say") and "/say" or "/p"
        btnMtChat:SetAttribute("macrotext", ("%s %s check"):format(db().chatVerb, TOKEN_MT))
        local idx = GetMacroIndexByName(CHAT_MACRO)
        if idx and idx > 0 then
            pcall(EditMacro, idx, CHAT_MACRO, nil, ("%s %s check"):format(db().chatVerb, TOKEN_RM))
        end
        out("chat tests now use |cffffff00" .. db().chatVerb .. "|r")
    else
        if frame:IsShown() then frame:Hide() else frame:Show() end
        out("commands: report | clean | reset | say | party")
    end
end

out("loaded. |cffffff00/mmprobe|r opens the panel.")
