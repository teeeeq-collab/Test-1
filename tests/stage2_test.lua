--------------------------------------------------------------------------------
-- Stage 2, loaded and driven against the stub.
--
-- Nothing here can measure a combat capability. What it catches is the class of
-- fault that has cost this project the most time: a local used before it is
-- declared, a frame reached for before it exists, a command that throws on a
-- fresh install, and -- new for Stage 2 -- an owner architecture that claims
-- separation it does not have.
--------------------------------------------------------------------------------

local realPrint = print
package.path = "tests/?.lua;" .. package.path
local stub = require("wowstub")
stub.install()

local pass, fail = 0, 0
local function check(label, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; realPrint("  FAIL: " .. label .. "\n         " .. tostring(err)) end
end

local IMI = {}
for _, f in ipairs({ "Libs/LibStub/LibStub", "Libs/LibDeflate/LibDeflate",
                     "Libs/LibSerialize/LibSerialize" }) do
    loadfile("InomrahsMythicInstructions/" .. f .. ".lua")()
end
for _, f in ipairs({ "Util", "Color", "Style", "Core", "History", "Runtime", "UI",
                     "Picker", "Binds", "Edit", "Export", "Sheet", "Starter",
                     "Capture" }) do
    loadfile("InomrahsMythicInstructions/" .. f .. ".lua")("InomrahsMythicInstructions", IMI)
end
_G.InomrahsMI = IMI
InomrahsMythicInstructionsDB = IMI.Core.Init({})
IMI.UI.Init()

loadfile("InomrahsMISelfTest/Manifest.lua")()
loadfile("InomrahsMISelfTest/SelfTest.lua")("InomrahsMISelfTest")
loadfile("InomrahsMISelfTest/RunLab.lua")("InomrahsMISelfTest")

check("Stage 2 loads after the lab", function()
    local chunk, err = loadfile("InomrahsMISelfTest/Stage2.lua")
    if not chunk then error("Stage2.lua: " .. tostring(err)) end
    chunk("InomrahsMISelfTest")
    if type(_G.InomrahsMISelfTestStage2) ~= "table" then
        error("Stage2 did not publish its table")
    end
end)

local S2 = _G.InomrahsMISelfTestStage2
local Lab = _G.InomrahsMISelfTestRunLab
InomrahsMISelfTestAPI.Report = function() end

check("every command is safe before setup", function()
    for _, arg in ipairs({ "", "preflight", "arm", "status", "reset", "release",
                           "nonsense" }) do
        local ok, err = pcall(S2.Command, arg)
        if not ok then error(("stage2 %s -> %s"):format(arg, tostring(err))) end
    end
end)

check("the slash command reaches Stage 2, with the rest of the line", function()
    local handler = SlashCmdList.INOMRAHSMISELFTEST
    local real = S2.Command
    local seen
    S2.Command = function(a) seen = a end

    local cases = {
        { typed = "runlab stage2", expect = "" },
        { typed = "runlab stage2 arm", expect = "arm" },
        { typed = "RUNLAB STAGE2 PREFLIGHT", expect = "preflight" },
        { typed = "  runlab  stage2   status ", expect = "status" },
    }
    for _, case in ipairs(cases) do
        seen = nil
        pcall(handler, case.typed)
        if seen ~= case.expect then
            S2.Command = real
            error(("/imitest %s handed Stage 2 %q, expected %q")
                :format(case.typed, tostring(seen), case.expect))
        end
    end

    -- And a near miss must not be handed to it.
    for _, typed in ipairs({ "runlab stage22", "runlab status", "runlab" }) do
        seen = nil
        pcall(handler, typed)
        if seen ~= nil then
            S2.Command = real
            error(("/imitest %s was handed to Stage 2 as %q"):format(typed, seen))
        end
    end
    S2.Command = real
end)

check("setup, reset and release are each idempotent", function()
    for _ = 1, 3 do S2.Command("setup") end
    for _ = 1, 3 do S2.Command("reset") end
    for _ = 1, 3 do S2.Command("release") end
    S2.Command("setup")
end)

-- The whole architectural claim of Stage 2 is that three owners hold three
-- disjoint key sets. Two names resolving to one frame, or one key appearing in
-- two owners' sets, would make the separation argument vacuous while every
-- in-game result still looked fine.
check("the three binding owners are distinct frames", function()
    S2.Command("setup")
    local F = S2.frames
    if not (F.pager and F.moder and F.toggler) then error("an owner is missing") end
    if F.pager == F.moder or F.moder == F.toggler or F.pager == F.toggler then
        error("two owners are the same frame")
    end
    for _, name in ipairs({ "Pager", "Moder", "Toggler" }) do
        if not _G["InomrahsMISelfTestS2" .. name] then
            error(name .. " is not a named global, so nothing can address it")
        end
    end
end)

check("no key is owned by two owners", function()
    local seen = {}
    for _, entry in ipairs(S2.KEYS) do
        if seen[entry.key] then
            error(("%s is claimed by %s and %s"):format(entry.key, seen[entry.key],
                entry.owner))
        end
        seen[entry.key] = entry.owner
    end
    for _, key in pairs(S2.CollideKeys) do
        if seen[key] then error(key .. " collides with a real Stage 2 key") end
        seen[key] = "collider"
    end

    -- The pager is the only owner allowed to clear, so it must own exactly the
    -- three keys a flip rebuilds and nothing else.
    local pagerKeys = 0
    for _, entry in ipairs(S2.KEYS) do
        if entry.owner == "pager" then pagerKeys = pagerKeys + 1 end
    end
    if pagerKeys ~= 3 then
        error(("the pager owns %d keys; it must own exactly action, next, prev")
            :format(pagerKeys))
    end
end)

check("only the pager clears bindings", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")

    -- The mode apply body must not clear anything: that is the entire reason
    -- the mode owner exists as a separate frame.
    local apply = source:match("local MODE_APPLY = %[==%[(.-)%]==%]")
    if not apply then error("could not find MODE_APPLY") end
    if apply:find("ClearBindings", 1, true) then
        error("the mode apply clears bindings, which would erase the pager's keys")
    end

    local toggle = source:match("local TOGGLE_SNIPPET = %[==%[(.-)%]==%]")
    if not toggle then error("could not find TOGGLE_SNIPPET") end
    if toggle:find("ClearBindings", 1, true) then
        error("the toggle clears bindings; hiding the root must cost nothing")
    end
    if toggle:find("pageIndex", 1, true) or toggle:find('"mode"', 1, true) then
        error("the toggle touches page or mode state")
    end
end)

-- Stage 1 lost two whole runs to steps whose checks read attributes the
-- restricted side had written. The page and mode readers must derive state from
-- prebuilt frames instead.
check("state is read from prebuilt visuals, not restricted attributes", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    for _, name in ipairs({ "S2.Page", "S2.Mode" }) do
        local body = source:match("function " .. name:gsub("%.", "%%.") .. "%b()(.-)\nend\n")
        if not body then error("could not find " .. name) end
        if body:find("GetAttribute", 1, true) then
            error(name .. " reads an attribute; those come back unreadable")
        end
        if not body:find("shown(", 1, true) then
            error(name .. " does not read the prebuilt visuals")
        end
    end
end)

check("the sequence covers every required test family", function()
    S2.Command("setup")
    local steps = S2.BuildSequence()
    if #steps < 30 then
        error(("the sequence is only %d steps"):format(#steps))
    end
    local phases = {}
    for _, step in ipairs(steps) do
        if step.phase then phases[step.phase] = (phases[step.phase] or 0) + 1 end
    end
    for _, wanted in ipairs({ "A contextual binding", "B mode by mouse",
                              "C mode keys", "D cycle", "E hidden", "F preserve",
                              "G navigation in Minimal", "H escaping Minimal",
                              "collision probe" }) do
        if not phases[wanted] then error("no steps for phase " .. wanted) end
    end
end)

-- An action assertion that passes on the total going up would let a stale
-- binding through, which in production means running the previous page's macro.
check("an action step never passes on the wrong page firing", function()
    S2.Command("setup")
    local steps = S2.BuildSequence()
    local step
    for _, s in ipairs(steps) do
        if s.capability == "ACTION key targets page 2 after NEXT" then step = s end
    end
    if not step then error("could not find the page 2 action step") end

    -- Read what the step actually recorded. Swapping Lab.Record here would
    -- prove nothing: the steps captured it as an upvalue when the file loaded,
    -- so a later substitution is never seen by them.
    S2.results = {}
    S2.fired[1], S2.fired[2] = 0, 0
    step.enter()
    S2.fired[1] = 1                                    -- the wrong page fires
    step.done()

    local entry = S2.results[#S2.results]
    if not entry then error("the step recorded nothing") end
    if (entry.conclusion or ""):match("^YES") then
        error("page 1 fired while page 2 was expected and the step passed")
    end
    if not (entry.conclusion or ""):match("stale") then
        error("a stale binding is not named as such: " .. tostring(entry.conclusion))
    end
end)

check("both pages firing at once is worse than neither", function()
    S2.Command("setup")
    local steps = S2.BuildSequence()
    local step
    for _, s in ipairs(steps) do
        if s.capability == "ACTION key targets page 1 before any flip" then step = s end
    end
    if not step then error("could not find the first action step") end

    S2.results = {}
    S2.fired[1], S2.fired[2] = 0, 0
    step.enter()
    S2.fired[1], S2.fired[2] = 1, 1                    -- both fire from one press
    step.done()

    local captured = S2.results[#S2.results]
    if not captured then error("the step recorded nothing") end
    if not (captured.conclusion or ""):match("^FAIL") then
        error("one press firing both pages was not reported as FAIL: "
            .. tostring(captured.conclusion))
    end
end)

-- The isolation promise, checked as text rather than trusted. A production
-- reference added by accident later would compile perfectly and be invisible.
check("Stage 2 names no production frame and reaches for no production data", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    for _, pattern in ipairs({ "InomrahsMIToggle", "InomrahsMIPager", "InomrahsMIRoot",
                               "InomrahsMythicInstructionsDB", "IMI%.Core",
                               "IMI%.Runtime", "IMI%.UI", "InomrahsMI%.",
                               "_G%.InomrahsMI[^S]" }) do
        if source:find(pattern) then
            error("Stage 2 references production: " .. pattern)
        end
    end
    -- Every frame it creates must carry the Stage 2 prefix.
    for name in source:gmatch('CreateFrame%("%a+", "([^"]+)"') do
        if not name:find("^InomrahsMISelfTestS2") then
            error("frame " .. name .. " is not namespaced to Stage 2")
        end
    end
end)

check("the summary appears in the lab report", function()
    S2.Command("setup")
    local shown
    InomrahsMISelfTestAPI.Report = function(text) shown = text end
    Lab.Command("copy")
    InomrahsMISelfTestAPI.Report = function() end

    if not shown then error("no report") end
    if not shown:find("Stage 2", 1, true) then
        error("the report does not carry the Stage 2 summary")
    end
end)

check("preflight reports the owners and the keys", function()
    S2.Command("setup")
    local lines = {}
    S2.Preflight(function(...) lines[#lines + 1] = string.format(...) end)
    local text = table.concat(lines, "\n")
    for _, wanted in ipairs({ "three binding owners are distinct frames",
                              "rescue is outside the root", "CTRL-SHIFT-F6" }) do
        if not text:find(wanted, 1, true) then
            error("preflight never mentions " .. wanted)
        end
    end
end)

-- The canonical reset state, spelled out because "reset" that lands somewhere
-- slightly different each time makes every later step a coin toss.
check("reset lands on the canonical baseline", function()
    S2.Command("setup")
    local F = S2.frames

    F.pageId1:Hide(); F.pageId2:Show()
    F.visFull:Hide(); F.visMinimal:Show()
    F.action1:Hide(); F.root:Hide()
    S2.fired[1] = 9

    S2.Restore()

    if S2.Page() ~= 1 then error("reset did not return to page 1") end
    if S2.Mode() ~= 1 then error("reset did not return to Full") end
    if S2.RootVisible() ~= true then error("reset left the root hidden") end
    if S2.ActionBodyShown() ~= true then error("reset left the action body hidden") end
    if (S2.fired[1] or 0) ~= 0 then error("reset did not clear the counters") end

    -- And doing it twice must not land anywhere else.
    S2.Restore()
    if S2.Page() ~= 1 or S2.Mode() ~= 1 then error("reset is not idempotent") end
end)

check("Stage 1's surface is put away while Stage 2 runs", function()
    S2.Command("setup")
    local labRoot = _G.InomrahsMISelfTestRunLabRoot
    if not labRoot then error("no Stage 1 root") end
    local ok, isShown = pcall(labRoot.IsShown, labRoot)
    if ok and isShown == true then
        error("Stage 1's window is still up; it would cover the Stage 2 test")
    end

    S2.Command("release")
    if Lab.Hibernate and Lab.Hibernate(false) ~= false then
        error("release did not wake Stage 1 back up")
    end
end)

-- The Stage 1 lesson, applied to the Stage 2 script: one action per step, and
-- a step that names a state refuses to measure until that state holds. Without
-- the second half, arriving in the wrong state records a confident YES about a
-- claim the step never tested.
check("no step asks for two actions, and action steps declare their state", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    local build = source:match("local function buildSequence%b()(.-)\nend\n")
    if not build then error("could not find buildSequence") end

    -- "press X, then Y" and "twice" are the shapes that hid a second action.
    for _, phrase in ipairs({ '"|r, then "', "twice." }) do
        if build:find(phrase, 1, true) then
            error("a step still asks for more than one action: " .. phrase)
        end
    end

    -- Every action step whose capability names a mode or the hidden root must
    -- carry the state its claim is about.
    for block in build:gmatch("add%(actionStep(.-)\n\n") do
        local capability = select(2, block:match('"([^"]*)"%s*,%s*"([^"]*)"')) or ""
        local aboutState = capability:find("Minimal") or capability:find("hidden")
            or capability:find("Full") or capability:find("mode")
        if aboutState and not block:find("mode = MODE_", 1, true)
            and not block:find("root = ", 1, true) then
            error(("the step %q claims a state it never checks"):format(capability))
        end
    end
end)

-- The first live run of Stage 2 armed Stage 1's keys, because both bars carry
-- buttons called PREFLIGHT and ARM and the instructions pointed at the wrong
-- one. Nine steps failed for want of a binding that was never made.
check("Stage 2 has its own preflight and arm, and Stage 1's bar is put away", function()
    S2.Command("setup")
    local bar = _G.InomrahsMISelfTestS2RescueBar
    if not bar then error("no Stage 2 bar") end

    local wanted = { PREFLIGHT = false, ARM = false, STATUS = false, RESET = false }
    for _, child in ipairs(bar.children or {}) do
        local text = child.label and child.label.text
        if text and wanted[text] ~= nil then
            wanted[text] = true
            if not child.scripts or not child.scripts.OnClick then
                error(("the %s button on the Stage 2 bar does nothing"):format(text))
            end
        end
    end
    for text, found in pairs(wanted) do
        if not found then error("no " .. text .. " button on the Stage 2 bar") end
    end

    local labBar = _G.InomrahsMISelfTestRunLabRescueBar
    if labBar then
        local ok, isShown = pcall(labBar.IsShown, labBar)
        if ok and isShown == true then
            error("Stage 1's bar is still up; its ARM would arm the wrong stage")
        end
    end

    S2.Command("release")
    if labBar then
        local ok, isShown = pcall(labBar.IsShown, labBar)
        if ok and isShown ~= true then error("release did not restore Stage 1's bar") end
    end
end)

-- And the step that waits for arming must point at the right bar.
check("the arming step names the Stage 2 bar", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    local build = source:match("local function buildSequence%b()(.-)\nend\n")
    if not build:find("STAGE 2", 1, true) then
        error("the arming step does not say which bar to use")
    end
end)

-- A snippet is a string the client compiles at click time. A syntax error in
-- one is completely silent: the button looks fine and does nothing, which is
-- indistinguishable from the operation being refused.
check("every snippet compiles, as assembled", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    local function body(name)
        local b = source:match("local " .. name .. " = %[==%[(.-)%]==%]")
        if not b then error("could not find " .. name) end
        return b
    end
    local function substituted(text)
        return (text:gsub("FULL_W_VALUE", "240"):gsub("FULL_H_VALUE", "32")
                    :gsub("FULL_SCALE_VALUE", "1.0"):gsub("COMPACT_W_VALUE", "160")
                    :gsub("COMPACT_H_VALUE", "24"):gsub("COMPACT_SCALE_VALUE", "0.85"))
    end

    local bind, present = body("BIND_BODY"), body("PAGE_PRESENT")
    local assembled = {
        flip = body("FLIP_SNIPPET") .. present .. bind,
        rebind = body("REBIND_SNIPPET") .. present .. bind,
        mode = "local moder = x\nlocal wanted = 1\n" .. body("MODE_APPLY"),
        toggle = body("TOGGLE_SNIPPET"),
        rescue = body("RESCUE_SNIPPET"),
        collide = body("COLLIDE_SNIPPET"),
    }
    for name, text in pairs(assembled) do
        local chunk, err = loadstring(substituted(text), name)
        if not chunk then
            error(("the %s snippet does not compile: %s"):format(name, tostring(err)))
        end
    end

    -- And no placeholder may survive substitution, or the snippet compiles
    -- with a nil global where a number should be.
    for name, text in pairs(assembled) do
        if substituted(text):find("_VALUE") then
            error(("the %s snippet still contains an unsubstituted placeholder")
                :format(name))
        end
    end
end)

-- The flip is the one snippet that does several things before it touches
-- anything visible, so "the page did not change" covers five different causes.
-- It stamps between every call, and each stamp must follow the call it vouches
-- for: a stamp before its call proves nothing.
check("the flip stamps between each call, in order", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    local body = source:match("local FLIP_SNIPPET = %[==%[(.-)%]==%]")
    if not body then error("could not find FLIP_SNIPPET") end
    body = body:gsub("%-%-[^\n]*", "")

    local order = { "entered", "gotmanager", "readindex", "wroteindex" }
    local at = {}
    for _, name in ipairs(order) do
        at[name] = body:find('SetAttribute%("' .. name .. '"')
        if not at[name] then error("the flip never stamps " .. name) end
    end
    for i = 2, #order do
        if at[order[i]] < at[order[i - 1]] then
            error(("%s is stamped before %s"):format(order[i], order[i - 1]))
        end
    end

    -- gotmanager must come after the ref is fetched, wroteindex after the write.
    local getRef = body:find('GetFrameRef%("manager"%)')
    local setIndex = body:find('SetAttribute%("pageIndex"')
    if not (getRef < at.gotmanager) then error("gotmanager is stamped too early") end
    if not (setIndex < at.wroteindex) then error("wroteindex is stamped too early") end

    -- And a nil manager must be distinguishable from a manager that worked.
    if not body:find("nomanager", 1, true) then
        error("a nil manager reference is silent")
    end
end)

-- The handle form of SetBindingClick completed without throwing and bound
-- nothing: the pager's own counter reached 3 while every Stage 2 key was dead
-- and every mouse control worked. A call that succeeds and does nothing has no
-- error to notice, so the binding target is a name now, and the report asks
-- the client what is bound rather than trusting the snippet.
check("bindings are made by name, not by frame handle", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")

    local bind = source:match("local BIND_BODY = %[==%[(.-)%]==%]")
    if not bind then error("could not find BIND_BODY") end
    if bind:find("SetBindingClick%(true, %w+Key, %w+Button%)") then
        error("the bind body still passes a frame handle to SetBindingClick")
    end
    if not bind:find('GetAttribute("action" .. index .. "Name")', 1, true) then
        error("the action is not bound by name")
    end

    -- The names have to be recorded out of combat; GetName does not exist in
    -- the restricted environment.
    for _, name in ipairs({ "action1Name", "action2Name", "nextName", "prevName" }) do
        if not source:find('SetAttribute("' .. name .. '"', 1, true) then
            error("the pager never records " .. name)
        end
    end

    -- And the other two owners must not have been left on handles.
    if source:find('SetBindingClick%(true, "%%s", self:GetFrameRef') then
        error("an owner still binds to a frame handle")
    end

    -- The report must ask the client, not the snippet -- and must ask about
    -- override bindings, which is the only kind Stage 2 makes. Without the
    -- second argument the readout reports NOTHING for a key that is bound.
    if not source:find("GetBindingAction", 1, true) then
        error("status never asks the client what is bound")
    end
    if not source:find("pcall(GetBindingAction, entry.key, true)", 1, true) then
        error("the readout never asks about override bindings")
    end
end)

-- CTRL-SHIFT-F8 flipped the page from the keyboard while CTRL-SHIFT-F6 did
-- nothing -- same owner, same bind body, same call, different target. The
-- secure handler buttons register AnyUp and work; Stage 1's action button,
-- which fired in every hidden state, registers both up and down. Stage 2's
-- registered AnyUp alone.
check("action buttons register both click edges, like the one that works", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    local body = source:match("local function actionButton%b()(.-)\nend\n")
    if not body then error("could not find actionButton") end
    if not body:find('RegisterForClicks("AnyUp", "AnyDown")', 1, true) then
        error("the action buttons do not register both click edges")
    end
    -- And they must be counted, or a binding that never arrives and a macro
    -- that never runs are the same zero.
    if not body:find("HookScript", 1, true) then
        error("the action buttons are not click-counted")
    end

    local lab = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")
    if not lab:find('F.action:RegisterForClicks("AnyUp", "AnyDown")', 1, true) then
        error("the Stage 1 action button no longer registers both edges, so "
            .. "this check no longer mirrors a known-working configuration")
    end
end)

-- In combat the flip reached wroteindex and never reached presented, so it
-- throws somewhere inside the presentation block. Showing a plain frame and
-- showing a protected one are different operations and were in one loop; they
-- are stamped separately now, because "it stops in here somewhere" is not an
-- answer.
check("the presentation block stamps each kind of frame separately", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    local body = source:match("local PAGE_PRESENT = %[==%[(.-)%]==%]")
    if not body then error("could not find PAGE_PRESENT") end
    local code = body:gsub("%-%-[^\n]*", "")

    for _, stamp in ipairs({ "gotmoder", "readmode", "didlabels", "didactions" }) do
        if not code:find('SetAttribute%("' .. stamp .. '"') then
            error("the presentation block never stamps " .. stamp)
        end
    end

    -- The labels and the action buttons must be in separate loops, or one
    -- stamp covers both kinds of frame and names neither.
    local labelsAt = code:find('SetAttribute%("didlabels"')
    local actionsAt = code:find('SetAttribute%("didactions"')
    local firstAction = code:find('GetFrameRef%("action1"%)')
    if not (labelsAt < firstAction) then
        error("the action buttons are touched before the label stamp, so a "
            .. "failure on either reads the same")
    end
    if not (firstAction < actionsAt) then error("didactions is stamped too early") end

    -- Fetching a reference and using it are stamped apart, and no frame ref
    -- name is built by concatenation: that is what production's flip does and
    -- it has never been verified in combat, so it cannot be assumed safe here.
    for _, stamp in ipairs({ "gotlabels", "gotactions" }) do
        if not code:find('SetAttribute%("' .. stamp .. '"') then
            error("the fetch is not stamped apart from the use: " .. stamp)
        end
    end
    if code:find('GetFrameRef%("%w+" %.%.') then
        error("a frame reference name is still built by concatenation")
    end
end)

-- Stage 2 is meant to mirror production closely enough for a result to mean
-- something. Production's pages are secure headers holding the callout
-- buttons; hanging the actions off a plain frame was a deviation, and it is
-- the only structural difference between the protected frames a snippet can
-- show in combat and the ones it apparently cannot.
check("the action buttons live under a secure header, as in production", function()
    S2.Command("setup")
    local area = _G.InomrahsMISelfTestS2ActionArea
    if not area then error("the action area is not a named frame") end
    for _, name in ipairs({ "Action1", "Action2" }) do
        local button = _G["InomrahsMISelfTestS2" .. name]
        if not button then error("no " .. name) end
        if button:GetParent() ~= area then
            error(name .. " is not a child of the action area")
        end
    end

    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    if not source:find('"InomrahsMISelfTestS2ActionArea", F.root,\n        "SecureHandlerBaseTemplate"', 1, true) then
        error("the action area is not a SecureHandlerBaseTemplate")
    end

    -- Production sets this explicitly for the same reason.
    local body = source:match("local function actionButton%b()(.-)\nend\n")
    if not body:find("EnableMouse(true)", 1, true) then
        error("the action buttons do not enable the mouse explicitly")
    end
end)

-- The presentation block must reach its frames in one hop, from whichever
-- frame is running it. Two hops -- self gives the manager, the manager gives
-- the label -- is what production does and what has never worked in combat
-- here, and both the arrows and the pager carry the references so one hop is
-- always available.
check("the presentation block reaches its frames in one hop", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    local body = source:match("local PAGE_PRESENT = %[==%[(.-)%]==%]")
    if not body then error("could not find PAGE_PRESENT") end
    local code = body:gsub("%-%-[^\n]*", "")

    if code:find("m:GetFrameRef") then
        error("the presentation block still fetches a handle through the manager")
    end
    for _, ref in ipairs({ "moder", "pageId1", "pageId2", "action1", "action2" }) do
        if not code:find('self:GetFrameRef%("' .. ref .. '"%)') then
            error("the block does not fetch " .. ref .. " from self")
        end
    end

    -- And the arrows must actually carry them, or the flip fetches nil.
    S2.Command("setup")
    for _, name in ipairs({ "Prev", "Next" }) do
        local button = _G["InomrahsMISelfTestS2" .. name]
        if not button then error("no " .. name) end
        for _, ref in ipairs({ "moder", "pageId1", "pageId2", "action1", "action2" }) do
            if not (button.attributes and button.attributes["ref:" .. ref]) then
                error(("%s does not carry a reference to %s"):format(name, ref))
            end
        end
    end
end)

-- Two consecutive live runs returned byte-identical counters, and there was no
-- way to tell whether the fix between them had done nothing or had never been
-- installed. Every status says which build produced it now.
check("status reports the build that produced it", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    if not source:find('GetAddOnMetadata', 1, true) then
        error("status never reports the self-test version")
    end
    if not source:find('say("self-test %s"', 1, true) then
        error("the version is not the first line of the status")
    end
end)

-- The A/B: the same two calls the flip cannot complete in combat, from a
-- button that holds both frames directly and does nothing else first.
check("the label probe does only the label swap", function()
    S2.Command("setup")
    if not _G.InomrahsMISelfTestS2LabelProbe then error("no label probe button") end

    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    local body = source:match("local LABEL_PROBE = %[==%[(.-)%]==%]")
    if not body then error("could not find LABEL_PROBE") end
    local code = body:gsub("%-%-[^\n]*", "")

    -- Nothing may precede the swap except fetching the two frames: anything
    -- else and a failure could be blamed on it instead.
    for _, forbidden in ipairs({ "GetAttribute%(\"mode", "SetBindingClick",
                                 "ClearBindings", "pageIndex" }) do
        if code:find(forbidden) then
            error("the probe does more than the swap: " .. forbidden)
        end
    end
    if code:find("m:GetFrameRef") then
        error("the probe fetches through another handle, which is the thing "
            .. "being ruled out")
    end
    for _, stamp in ipairs({ "entered", "gotlabels", "hid", "ran" }) do
        if not code:find('SetAttribute%("' .. stamp .. '"') then
            error("the probe never stamps " .. stamp)
        end
    end
end)

-- Every frame a snippet shows or hides in combat must be a secure frame. The
-- label probe measured a plain one being refused at Hide while every secure
-- one this project has tried has worked, and production builds its pages the
-- same way.
check("every frame the snippets show or hide is a secure frame", function()
    S2.Command("setup")
    for _, name in ipairs({ "Root", "PageId1", "PageId2",
                            "VisFull", "VisCompact", "VisMinimal",
                            "Action1", "Action2", "ActionArea" }) do
        local frame = _G["InomrahsMISelfTestS2" .. name]
        if not frame then error("no " .. name) end
        if not (frame.template and frame.template:find("Secure")) then
            error(("%s is a plain frame; a snippet cannot hide it in combat")
                :format(name))
        end
    end

    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    if source:find('CreateFrame%("Frame", "InomrahsMISelfTestS2Root", UIParent%)') then
        error("the root is created without a secure template")
    end
end)

-- Every chord with three modifiers was bound correctly and never delivered a
-- single press, while every two-modifier chord in the same run worked every
-- time. A key that is bound and never arrives is indistinguishable from a
-- refused operation, and it cost most of the hidden-root phase.
check("no test chord uses three modifiers", function()
    local chords = {}
    for _, entry in ipairs(S2.KEYS) do chords[#chords + 1] = entry.key end
    for _, key in pairs(S2.CollideKeys) do chords[#chords + 1] = key end

    for _, chord in ipairs(chords) do
        local modifiers = 0
        for _, name in ipairs({ "CTRL", "ALT", "SHIFT" }) do
            if chord:find(name, 1, true) then modifiers = modifiers + 1 end
        end
        if modifiers > 2 then
            error(("%s uses %d modifiers; three never arrived in a live run")
                :format(chord, modifiers))
        end
    end
end)

-- The follow-up must be a real subset of the full sequence -- the same step
-- objects -- rather than a second hand-written list that can drift from it.
check("the follow-up is a shorter subset that still covers what is open", function()
    S2.Command("setup")
    local full = S2.BuildSequence(nil)
    local short = S2.BuildSequence("followup")

    if #short >= #full then
        error(("the follow-up is %d steps and the full run %d")
            :format(#short, #full))
    end
    if #short < 8 then
        error(("the follow-up is only %d steps; the filter dropped too much")
            :format(#short))
    end

    local phases = {}
    for _, step in ipairs(short) do
        if step.phase then phases[step.phase] = true end
    end
    for _, wanted in ipairs({ "stage 2 setup", "combat", "E hidden",
                              "F preserve", "collision probe", "done" }) do
        if not phases[wanted] then
            error("the follow-up drops the phase " .. wanted)
        end
    end
    for _, gone in ipairs({ "A contextual binding", "B mode by mouse",
                            "C mode keys", "D cycle" }) do
        if phases[gone] then
            error("the follow-up still re-runs " .. gone)
        end
    end

    -- Every follow-up step must exist in the full run. Comparing the tables
    -- themselves proves nothing here -- each call builds fresh ones -- so this
    -- compares what the report will actually key on.
    local fullCapabilities = {}
    for _, step in ipairs(full) do
        if step.capability then fullCapabilities[step.capability] = true end
    end
    for _, step in ipairs(short) do
        if step.capability and not fullCapabilities[step.capability] then
            error(("the follow-up has a step the full run does not: %q")
                :format(step.capability))
        end
    end
end)

-- The hidden phase cannot assume a mode that only the earlier phases would
-- have set, or a follow-up run starts from wherever it happens to be.
check("the hidden phase sets its own starting state", function()
    S2.Command("setup")
    local short = S2.BuildSequence("followup")
    local found
    for _, step in ipairs(short) do
        if step.capability == "starting state for the hidden phase" then found = step end
    end
    if not found then error("the hidden phase never establishes its start state") end
end)

-- Every SecureActionButtonTemplate here must register both click edges. One
-- pair was fixed and another was left behind, and the second pair cost the
-- collision probe an entire run: its snippet ran and neither observer key
-- registered a press. Checked by enumeration so a third pair cannot be missed.
check("every action button registers both click edges", function()
    local source = io.open("InomrahsMISelfTest/Stage2.lua"):read("*a")
    local single = 0
    for _ in source:gmatch('RegisterForClicks%("AnyUp"%)') do single = single + 1 end
    if single > 1 then
        error(("%d frames still register a single click edge; only the secure "
            .. "handler helper may"):format(single))
    end

    S2.Command("setup")
    for _, name in ipairs({ "Action1", "Action2", "CollidePage", "CollideMode" }) do
        local button = _G["InomrahsMISelfTestS2" .. name]
        if not button then error("no " .. name) end
        local edges = button.clickRegistrations or button.registeredClicks
        -- The stub records the arguments; fall back to the source when it does
        -- not, since the enumeration above already covers the file.
        if edges and #edges < 2 then
            error(name .. " registers only one click edge")
        end
    end
end)

-- Printed so a change in the sequence length is visible in the run output
-- rather than counted by hand before every handoff.
S2.Command("setup")
realPrint(("stage2 sequence: %d steps"):format(#S2.BuildSequence()))

realPrint(("\nstage2: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
