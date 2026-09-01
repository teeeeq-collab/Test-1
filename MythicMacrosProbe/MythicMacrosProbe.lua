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

-- Forward declarations. The slash command is registered before the UI is built
-- (see below), so it needs these names to exist beforehand.
local frame, btnMtChat

--------------------------------------------------------------------------------
-- Signal target, called by macros via /run.
--------------------------------------------------------------------------------

function MMProbeSignal(tag)
    record("B.exec." .. tostring(tag) .. (db().runCount and ("." .. db().runCount) or ""),
        "FIRED", InCombatLockdown() and "in combat" or "out of combat")
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
-- Slash command
--
-- Registered here, before any UI is built, deliberately. A Lua error aborts the
-- rest of the file, so anything registered after the failure never exists. The
-- first version of this probe put the command last, and a single bad call left
-- the whole addon silent with no way to ask it what went wrong. A diagnostic
-- tool has to survive its own bugs.
--------------------------------------------------------------------------------

SLASH_MMPROBE1 = "/mmprobe"
SlashCmdList.MMPROBE = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")

    if arg == "report" then
        MMProbeReport()
    elseif arg == "copy" then
        MMProbeShowCopy()
    elseif arg == "clean" then
        cleanupMacros()
    elseif arg == "reset" then
        MMProbeDB.results = {}
        out("results cleared.")
    elseif arg == "say" or arg == "party" or arg == "raid" or arg == "instance" then
        if InCombatLockdown() then
            out("|cffff4444can't change this in combat.|r") return
        end
        local verbs = { say = "/say", party = "/p", raid = "/raid", instance = "/i" }
        db().chatVerb = verbs[arg]
        if btnMtChat then
            btnMtChat:SetAttribute("macrotext", ("%s %s check"):format(db().chatVerb, TOKEN_MT))
        end
        local idx = GetMacroIndexByName(CHAT_MACRO)
        if idx and idx > 0 then
            pcall(EditMacro, idx, CHAT_MACRO, nil, ("%s %s check"):format(db().chatVerb, TOKEN_RM))
        end
        out("chat tests now use |cffffff00" .. db().chatVerb .. "|r")
    elseif not frame then
        out("|cffff4444the panel failed to build - /mmprobe report still works.|r")
    else
        if frame:IsShown() then frame:Hide() else frame:Show() end
        out("commands: report | copy | clean | reset | say | party | raid | instance")
    end
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
    record("A.slots.account",   ("%s used"):format(tostring(acct)))
    record("A.slots.character", ("%s used"):format(tostring(char)))

    -- MAX_ACCOUNT_MACROS came back nil on 12.1, so the cap has to come from
    -- somewhere else. Report what this build actually exposes.
    local found = {}
    for _, name in ipairs({
        "MAX_ACCOUNT_MACROS", "MAX_CHARACTER_MACROS",
        "NUM_ACCOUNT_MACROS", "NUM_CHARACTER_MACROS",
        "MAX_MACROS", "MACRO_ACCOUNT_LIMIT",
    }) do
        if _G[name] ~= nil then found[#found + 1] = name .. "=" .. tostring(_G[name]) end
    end
    if Constants and Constants.MacroConsts then
        for k, v in pairs(Constants.MacroConsts) do
            found[#found + 1] = "Constants.MacroConsts." .. tostring(k) .. "=" .. tostring(v)
        end
    end
    record("A.slotConstants", (#found > 0) and table.concat(found, ", ") or "NONE FOUND",
        "C_Macro namespace: " .. tostring(C_Macro ~= nil))

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

frame = CreateFrame("Frame", "MMProbeFrame", UIParent, "BasicFrameTemplateWithInset")
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

--- Style a button by hand instead of inheriting UIPanelButtonTemplate.
---
--- Mixing a secure template with UIPanelButtonTemplate is what broke the first
--- version of this probe: the button template's OnLoad replaced the secure
--- one's, so the frame never gained its secure methods. Worse for a probe, that
--- interaction could have silently disabled the very behaviour under test and
--- produced a confident wrong answer. Secure frames here inherit the secure
--- template and nothing else.
local function skin(b, text)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.13, 0.13, 0.18, 0.95)

    local edge = b:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.35, 0.35, 0.45, 1)
    edge:SetDrawLayer("BORDER", -1)

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetText(text)
    b.label = fs

    b:EnableMouse(true)
    b.bg = bg

    local function idle()  bg:SetColorTexture(0.13, 0.13, 0.18, 0.95) end
    local function hover() bg:SetColorTexture(0.22, 0.22, 0.30, 0.95) end
    local function press() bg:SetColorTexture(0.45, 0.40, 0.15, 1.00) end

    b:SetScript("OnEnter",     hover)
    b:SetScript("OnLeave",     idle)
    b:SetScript("OnMouseDown", press)
    b:SetScript("OnMouseUp",   hover)
    return b
end

--- `key` names the test so the click can be recorded against it.
---
--- An insecure OnClick hook fires whether or not the secure action behind it is
--- allowed to run. That separation is the point: "B.click.X = CLICKED" with no
--- matching "B.exec.X = FIRED" means the button works and the path is blocked,
--- while no CLICKED at all means the button never received the click and the
--- fault is mine. Without both, a silent button proves nothing.
local function secure(text, x, key, setup)
    local b = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    b:SetSize(212, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    skin(b, text)
    setup(b)

    b:HookScript("OnClick", function()
        record("B.click." .. key .. (db().runCount and ("." .. db().runCount) or ""), "CLICKED",
            InCombatLockdown() and "in combat" or "out of combat")
        b.label:SetTextColor(1, 0.85, 0.2)
    end)
    return b
end

label("Out of combat, press these three:", "|cffaaaaaa")
plain("A. Limits", 14, 140, testLimits)
plain("E. EditBox", 166, 140, testEditBox)
plain("F. Batch x20", 318, 140, testBatch)
y = y - 32

label(" ")
label("B. Execution matrix. 'Create macros' first, then all four:")
--- Idempotent: pressing this twice must not report a failure, or a harmless
--- no-op would read as a broken macro system. Each macro is also read back
--- after writing, because "CreateMacro returned an index" and "a usable macro
--- exists under that name" are not the same claim.
local function ensureProbeMacro(name, body, key)
    local idx = GetMacroIndexByName(name)

    if idx and idx > 0 then
        db().created[name] = true
        local ok = pcall(EditMacro, idx, name, nil, body)
        record(key, ("exists idx=%d"):format(idx),
            ok and "body refreshed" or "body could not be refreshed")
    else
        local newIdx, err = createMacro(name, body)
        if not newIdx then
            record(key, "CREATE FAILED", err or "no reason given")
            return
        end
        record(key, ("created idx=%d"):format(newIdx))
    end

    -- Read back. This is what the secure button will actually resolve.
    local check = GetMacroIndexByName(name)
    local storedName, _, storedBody = GetMacroInfo(check or 0)
    record(key .. ".verify",
        (check and check > 0) and "RESOLVES BY NAME" or "NOT FOUND BY NAME",
        storedBody and ("body is %d bytes"):format(#storedBody) or "no body read")
end

plain("Create macros", 14, 140, function()
    if InCombatLockdown() then out("|cffff4444not in combat.|r") return end
    ensureProbeMacro(RUN_MACRO, "/run MMProbeSignal('realmacro')", "B.macro.run")
    ensureProbeMacro(CHAT_MACRO, ("%s %s check"):format(db().chatVerb, TOKEN_RM), "B.macro.chat")
    out("now click the four buttons below, one press each.")
end)
y = y - 30

local btnMtRun = secure("macrotext + /run", 14, "macrotext.run", function(b)
    b:SetAttribute("macrotext", "/run MMProbeSignal('macrotext')")
end)
btnMtChat = secure("macrotext + chat", 240, "macrotext.chat", function(b)
    b:SetAttribute("macrotext", ("%s %s check"):format(db().chatVerb, TOKEN_MT))
end)
y = y - 28

secure("real macro + /run", 14, "realmacro.run", function(b) b:SetAttribute("macro", RUN_MACRO) end)
secure("real macro + chat", 240, "realmacro.chat", function(b) b:SetAttribute("macro", CHAT_MACRO) end)
y = y - 32

label(" ")
label("C + D. Get into combat, then press both of these:", "|cffffcc44")

--- Run one step under pcall and record a throw as a result.
---
--- A probe that dies halfway through loses every check after the failure, and
--- mid-key there is no second attempt. An error is also data: it names an API
--- that is missing or refusing, which is exactly what this tool exists to find
--- out. So nothing here is allowed to abort the run.
local function step(pfx, name, fn)
    local ok, err = pcall(fn)
    if not ok then
        record(pfx .. ".ERROR." .. name, "THREW", tostring(err))
    end
    return ok
end

--- The design assumes attribute writes and macro edits are refused in combat,
--- and that page flipping therefore cannot go through them.
--- Verify by effect, never by pcall.
---
--- D1 proved why: it recorded NO EFFECT with "pcall=no error". A blocked action
--- in WoW usually does not throw, it simply fails to apply. The first version of
--- these tests reported ALLOWED for all four operations purely because nothing
--- raised, which is not evidence of anything. Each one now writes a value and
--- reads it back.
local function combatOps(pfx)
    pfx = pfx or "C"
    local inCombat = InCombatLockdown()
    record(pfx .. ".lockdown", inCombat and "IN COMBAT" or "out of combat",
        inCombat and "results are meaningful" or "RE-RUN THIS IN COMBAT")

    -- SetAttribute: write a sentinel, read it back.
    step(pfx, "SetAttribute", function()
        local sentinel = "MMPsent" .. math.random(100000, 999999)
        pcall(function()
            btnMtRun:SetAttribute("macrotext", "/run MMProbeSignal('" .. sentinel .. "')")
        end)
        local got = btnMtRun:GetAttribute("macrotext")
        record(pfx .. ".SetAttribute",
            (type(got) == "string" and got:find(sentinel, 1, true)) and "APPLIED" or "NO EFFECT",
            "read back: " .. tostring(got):sub(1, 40))
    end)

    -- EditMacro: write a distinctive body, read it back.
    step(pfx, "EditMacro", function()
        local idx = GetMacroIndexByName(RUN_MACRO)
        if not idx or idx <= 0 then
            record(pfx .. ".EditMacro", "SKIPPED", "probe macros not created")
            return
        end
        local marker = "/run MMProbeSignal('edited" .. math.random(1000, 9999) .. "')"
        pcall(EditMacro, idx, RUN_MACRO, nil, marker)
        local body = GetMacroBody(idx)
        record(pfx .. ".EditMacro", (body == marker) and "APPLIED" or "NO EFFECT",
            "body now: " .. tostring(body):sub(1, 40))
        pcall(EditMacro, idx, RUN_MACRO, nil, "/run MMProbeSignal('realmacro')")
    end)

    -- CreateMacro / DeleteMacro: act, then look up by name.
    step(pfx, "CreateMacro", function()
        local tmp = PREFIX .. "CBT"
        pcall(CreateMacro, tmp, ICONS[1], "/run return", false)
        local made = GetMacroIndexByName(tmp)
        record(pfx .. ".CreateMacro", (made and made > 0) and "APPLIED" or "NO EFFECT")
        if made and made > 0 then
            pcall(DeleteMacro, made)
            record(pfx .. ".DeleteMacro",
                ((GetMacroIndexByName(tmp) or 0) == 0) and "APPLIED" or "NO EFFECT")
        end
    end)

    -- SetScale: change it, read it back, restore.
    step(pfx, "SetScale", function()
        local before = frame:GetScale() or 1
        local target = (before > 1.02) and 1.0 or 1.05
        pcall(frame.SetScale, frame, target)
        local after = frame:GetScale() or 1
        record(pfx .. ".SetScale",
            (math.abs(after - target) < 0.001) and "APPLIED" or "NO EFFECT",
            ("%.3f -> %.3f"):format(before, after))
        pcall(frame.SetScale, frame, before)
    end)
end

plain("C. Combat ops", 14, 200, function() combatOps("C") end)
y = y - 30

--------------------------------------------------------------------------------
-- D. Paging. Two mechanisms, because if the plain one works the real addon
-- avoids a large amount of secure-handler machinery.
--------------------------------------------------------------------------------

local pagePlain = CreateFrame("Frame", "MMProbePagePlain", frame)
pagePlain:SetSize(212, 24)
pagePlain:SetPoint("TOPLEFT", 240, y)
local pagePlainBtn = CreateFrame("Button", "MMProbePlainChild", pagePlain,
    "SecureActionButtonTemplate")
pagePlainBtn:SetAllPoints()
pagePlainBtn:SetAttribute("type", "macro")
pagePlainBtn:SetAttribute("macrotext", "/run return")
skin(pagePlainBtn, "plain frame + secure child")

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

local btnFlip = CreateFrame("Button", "MMProbeFlip", frame, "SecureHandlerClickTemplate")
btnFlip:SetSize(200, 24)
btnFlip:SetPoint("TOPLEFT", 14, y)
btnFlip:RegisterForClicks("AnyUp")
skin(btnFlip, "D2. Secure flip")

-- Whether the secure handler machinery is even present is itself a result worth
-- recording, not a reason to stop loading.
if type(btnFlip.SetFrameRef) == "function" then
    btnFlip:SetFrameRef("pageA", pageA)
    btnFlip:SetFrameRef("pageB", pageB)
    btnFlip:SetAttribute("_onclick", [[
        local a = self:GetFrameRef("pageA")
        local b = self:GetFrameRef("pageB")
        if a:IsShown() then a:Hide(); b:Show() else b:Hide(); a:Show() end
    ]])
    record("D2.setup", "OK", "secure handler methods present")
else
    record("D2.setup", "UNAVAILABLE",
        "SetFrameRef missing - secure handler paging is not usable")
    btnFlip.label:SetText("D2. unavailable")
end

btnFlip:HookScript("OnClick", function()
    local run = db().runCount and ("." .. db().runCount) or ""
    record("D2.secureFlipByHand" .. run,
        pageA:IsShown() and "showing A" or "showing B",
        ("combat=%s - a hardware click, which is what the addon's page arrows are")
            :format(tostring(InCombatLockdown())))
end)
y = y - 34

label(" ")
--- Everything that matters inside a key, on one press. Nobody wants to work a
--- six-button panel mid-pull.
--- Combat and an active key are independent variables, so this is meant to be
--- run more than once: between pulls, then mid-pull. Each run therefore writes
--- under its own prefix. Overwriting a previous run would destroy the very
--- comparison the second run exists to make.
local function runAllInKey()
    db().runCount = (db().runCount or 0) + 1
    local pfx = "K" .. db().runCount

    -- Conditions first, and guarded, so even a total failure still records the
    -- circumstances the attempt was made under.
    step(pfx, "conditions", function()
        local okA, active    = pcall(function() return C_ChallengeMode.IsChallengeModeActive() end)
        local okL, lvl       = pcall(function() return C_ChallengeMode.GetActiveKeystoneInfo() end)
        local okE, encounter = pcall(IsEncounterInProgress)
        local okG, members   = pcall(GetNumGroupMembers)
        local okR, inRaid    = pcall(IsInRaid)

        record(pfx .. ".conditions",
            ("combat=%s  keyActive=%s  keyLevel=%s  encounter=%s  raid=%s  group=%s  verb=%s")
            :format(
                tostring(InCombatLockdown()),
                okA and tostring(active) or "?",
                okL and tostring(lvl) or "?",
                okE and tostring(encounter) or "?",
                okR and tostring(inRaid) or "?",
                okG and tostring(members) or "?",
                tostring(db().chatVerb)),
            "every variable this run was taken under")
    end)

    step(pfx, "instance", function()
        local iname, itype, _, diffName, _, _, _, instID = GetInstanceInfo()
        record(pfx .. ".instance", ("%s | %s | %s | id=%s"):format(
            tostring(iname), tostring(itype), tostring(diffName), tostring(instID)))
    end)

    step(pfx, "combatOps", function() combatOps(pfx) end)

    step(pfx, "plainHide", function()
        local wasShown = pagePlain:IsShown()
        pcall(function()
            if wasShown then pagePlain:Hide() else pagePlain:Show() end
        end)
        record(pfx .. ".plainHide",
            (pagePlain:IsShown() ~= wasShown) and "WORKED" or "NO EFFECT")
    end)

    -- Deliberately NOT automated. Driving the secure flip with :Click() throws
    -- "Invalid 'self' frame handle" with selfHandle=nil: the restricted
    -- environment refuses a scripted click, while the same button works when
    -- clicked by hand, in combat. That distinction is a result, not a bug to
    -- work around, and it is fine for the addon, whose page arrows are real
    -- clicks.
    record(pfx .. ".secureFlip", "CLICK IT BY HAND",
        "scripted :Click() is refused by the restricted environment")

    out(("|cffffff00run %d recorded. Now click, by hand: D2. Secure flip, then the two chat buttons.|r")
        :format(db().runCount))
end

label("|cffffcc44IN A KEY: press this, then by hand: D2 flip + the two chat buttons.|r")
local btnInKey = plain("K. Run all in-key checks", 14, 300, function() runAllInKey() end)
y = y - 32

label("Report", "|cffaaaaaa")
plain("Print report", 14, 140, function() MMProbeReport() end)
plain("Remove macros", 166, 140, cleanupMacros)
plain("Copy report", 318, 140, function() MMProbeShowCopy() end)
y = y - 30

-- Size the panel to whatever the layout actually consumed. Hardcoding a height
-- is how a button ends up rendered off the bottom edge and reported missing.
frame:SetHeight(math.abs(y) + 44)

if not btnInKey then
    out("|cffff4444the in-key button failed to build.|r")
end

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------

--- The report as plain text. WoW's chat frame cannot be selected with the
--- mouse, so printing a report is not the same as being able to send it to
--- anyone. This is the form that actually leaves the game.
local function reportText()
    local lines = {
        "MythicMacros Probe report",
        ("client %s  toc %s  recorded %s"):format(
            tostring((GetBuildInfo())), tostring(select(4, GetBuildInfo())),
            date("%Y-%m-%d %H:%M:%S")),
        "",
    }

    local keys = {}
    for k in pairs(db().results) do keys[#keys + 1] = k end
    table.sort(keys)

    for _, k in ipairs(keys) do
        local r = db().results[k]
        lines[#lines + 1] = ("%-26s = %s%s"):format(
            k, r.value, r.note and ("   -- " .. r.note) or "")
    end

    if #keys == 0 then
        lines[#lines + 1] = "(nothing recorded yet)"
    end

    return table.concat(lines, "\n")
end

function MMProbeReport()
    out("|cffffff00========== PROBE REPORT ==========|r")
    for line in reportText():gmatch("[^\n]+") do print("  " .. line) end
    out("|cffffff00===== END =====|r  use |cffffff00Copy report|r to get it out")
end

--------------------------------------------------------------------------------
-- Copy window: a selectable edit box, pre-highlighted, so the report can be
-- lifted with one keystroke.
--------------------------------------------------------------------------------

local copyFrame

local function showCopyWindow()
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "MMProbeCopyFrame", UIParent,
            "BasicFrameTemplateWithInset")
        copyFrame:SetSize(640, 460)
        copyFrame:SetPoint("CENTER")
        copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        copyFrame:SetMovable(true)
        copyFrame:EnableMouse(true)
        copyFrame:RegisterForDrag("LeftButton")
        copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
        copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)

        local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", copyFrame.TitleBg, "TOP", 0, -5)
        title:SetText("Probe report - already selected, press Cmd-C / Ctrl-C")

        local scroll = CreateFrame("ScrollFrame", "MMProbeCopyScroll", copyFrame,
            "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -32)
        scroll:SetPoint("BOTTOMRIGHT", -34, 14)

        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetMultiLine(true)
        eb:SetMaxLetters(0)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(580)
        eb:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        scroll:SetScrollChild(eb)
        copyFrame.editBox = eb
    end

    copyFrame.editBox:SetText(reportText())
    copyFrame:Show()
    copyFrame.editBox:SetFocus()
    copyFrame.editBox:HighlightText()
end

function MMProbeShowCopy() showCopyWindow() end

--------------------------------------------------------------------------------
-- Chat echo detection
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, e in ipairs({
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_SAY",
}) do
    events:RegisterEvent(e)
end

events:SetScript("OnEvent", function(_, event, msg)
    if type(msg) ~= "string" then return end
    local where = event .. " / " .. (InCombatLockdown() and "in combat" or "out of combat")
    local run = db().runCount and ("." .. db().runCount) or ""
    if msg:find(TOKEN_MT, 1, true) then
        record("B.chat.macrotext" .. run, "RECEIVED", where)
    elseif msg:find(TOKEN_RM, 1, true) then
        record("B.chat.realmacro" .. run, "RECEIVED", where)
    end
end)

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

out("loaded. |cffffff00/mmprobe|r opens the panel.")
