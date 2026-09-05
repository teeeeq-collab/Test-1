--------------------------------------------------------------------------------
-- The capability lab, loaded and driven against the stub.
--
-- Nothing here can measure a combat capability -- that is the whole point of the
-- lab, and it needs the live client. What this catches is the class of fault
-- that has cost this project the most: a local used before it is declared, a
-- frame reached for before it exists, a command that errors on a fresh install.
-- Those are all load-order and wiring faults, and they are all visible here.
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

-- The self-test addon expects the production addon loaded beside it.
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

check("the self-test loads", function()
    local chunk, err = loadfile("InomrahsMISelfTest/Manifest.lua")
    if not chunk then error("Manifest.lua: " .. tostring(err)) end
    chunk("InomrahsMISelfTest")

    chunk, err = loadfile("InomrahsMISelfTest/SelfTest.lua")
    if not chunk then error("SelfTest.lua: " .. tostring(err)) end
    chunk("InomrahsMISelfTest")
end)

check("and exposes the API the lab borrows", function()
    local api = _G.InomrahsMISelfTestAPI
    if type(api) ~= "table" then error("no API table") end
    for _, name in ipairs({ "Report", "Approximately", "IsTrue", "SafeString",
                            "KeyboardReport", "ReleaseKeyboard" }) do
        if type(api[name]) ~= "function" then error("API is missing " .. name) end
    end
    if api.Approximately(90.000007629395, 90) ~= true then
        error("the tolerant comparison rejects the client's own value")
    end
    if api.Approximately(90.5, 90) ~= false then
        error("the tolerant comparison is too forgiving")
    end
end)

check("the lab loads after it", function()
    local chunk, err = loadfile("InomrahsMISelfTest/RunLab.lua")
    if not chunk then error("RunLab.lua: " .. tostring(err)) end
    chunk("InomrahsMISelfTest")

    if type(_G.InomrahsMISelfTestRunLab) ~= "table" then error("no lab table") end
    if type(_G.InomrahsMISelfTestRunLab.Command) ~= "function" then
        error("the lab has no Command")
    end
end)

local Lab = _G.InomrahsMISelfTestRunLab

-- Every command on a lab that has not been built. A fresh install where the
-- player types the wrong thing first must not throw.
check("every command is safe before setup", function()
    for _, arg in ipairs({ "", "help", "preflight", "arm", "status", "report",
                           "copy", "reset", "release", "nonsense" }) do
        local ok, err = pcall(Lab.Command, arg)
        if not ok then error(("/imitest runlab %s -> %s"):format(arg, tostring(err))) end
    end
end)

check("setup builds it", function()
    Lab.Command("setup")
    if not Lab.Built() then error("setup did not build the lab") end
end)

-- The name every probe can reach must exist as a global, because the macro text
-- is a string the game runs later and cannot see an upvalue.
check("the evidence counter is reachable the way a macro reaches it", function()
    if type(_G.InomrahsMISelfTestRunLabFired) ~= "function" then
        error("the macro's counter function is not a global")
    end
    local before = _G.InomrahsMISelfTestRunLabFired
    before(1)
end)

check("setup is idempotent", function()
    for _ = 1, 3 do Lab.Command("setup") end
end)

check("and so are reset and release", function()
    for _ = 1, 3 do Lab.Command("reset") end
    for _ = 1, 3 do Lab.Command("release") end
end)

check("every command is safe after setup", function()
    Lab.Command("setup")
    for _, arg in ipairs({ "help", "preflight", "arm", "status", "report",
                           "copy", "reset", "release" }) do
        local ok, err = pcall(Lab.Command, arg)
        if not ok then error(("/imitest runlab %s -> %s"):format(arg, tostring(err))) end
    end
end)

-- The safety invariant the whole design rests on: nothing in this file may
-- name a production frame. Checked as text, because a reference added later
-- would compile perfectly and be invisible.
check("the lab never names a production frame", function()
    local f = io.open("InomrahsMISelfTest/RunLab.lua")
    local source = f:read("*a")
    f:close()

    for name in source:gmatch('"(InomrahsMI[%w_]*)"') do
        if not name:match("^InomrahsMISelfTest") then
            error("names a production frame: " .. name)
        end
    end
    for _, forbidden in ipairs({ "InomrahsMIFrame", "InomrahsMIPager",
                                 "InomrahsMIToggle", "InomrahsMIPage",
                                 "InomrahsMIBtn" }) do
        if source:find(forbidden, 1, true) then
            error("mentions the production frame " .. forbidden)
        end
    end
end)

check("and never writes production data", function()
    local f = io.open("InomrahsMISelfTest/RunLab.lua")
    local source = f:read("*a")
    f:close()

    for _, forbidden in ipairs({ "InomrahsMythicInstructionsDB",
                                 "IMI.Core.", "InomrahsMI.Core",
                                 "SetCategoryChannel", "ReplaceProfile" }) do
        if source:find(forbidden, 1, true) then
            error("reaches into production: " .. forbidden)
        end
    end
end)

-- Rescue is the reason a destructive probe is safe to run. If it is ever
-- parented inside something a probe hides, the lab can strand itself.
check("the rescue control is outside everything the lab hides", function()
    local rescue = _G.InomrahsMISelfTestRunLabRescue
    local root = _G.InomrahsMISelfTestRunLabRoot
    if not rescue then error("no rescue button") end

    local node = rescue
    while node do
        if node == root then error("the rescue button is inside the lab root") end
        node = node.parent
    end
end)

check("the step panel is outside it too", function()
    local step = _G.InomrahsMISelfTestRunLabStep
    local root = _G.InomrahsMISelfTestRunLabRoot
    if not step then error("no step panel") end

    local node = step
    while node do
        if node == root then error("the instructions vanish when the root is hidden") end
        node = node.parent
    end
end)

check("the synthetic action carries a macro that proves execution", function()
    local action = _G.InomrahsMISelfTestRunLabAction
    if not action then error("no action button") end
    if action.attributes.type ~= "macro" then error("the action is not a macro button") end
    local macro = action.attributes.macrotext or ""
    if not macro:find("InomrahsMISelfTestRunLabFired", 1, true) then
        error("the macro does not increment the counter: " .. macro)
    end
end)

-- The mouse probes are worthless if the underlay is not exactly where the
-- action normally sits: a click that misses both proves nothing either way.
check("the underlay sits where the action normally does", function()
    local underlay = _G.InomrahsMISelfTestRunLabUnderlay
    local home = _G.InomrahsMISelfTestRunLabHome
    if not underlay or not home then error("underlay or home marker missing") end

    local point = underlay.points[1]
    if not point or point.rel ~= home then
        error("the underlay is not anchored to the action's home position")
    end
    if underlay.width ~= home.width or underlay.height ~= home.height then
        error("the underlay is a different size from the action")
    end
end)

-- Slash dispatch, including the commands that existed before the lab. A new
-- branch in that handler is exactly where the old ones get broken.
check("the slash command still answers, lab and not", function()
    local handler = SlashCmdList.INOMRAHSMISELFTEST
    if type(handler) ~= "function" then error("the slash command is not registered") end

    for _, arg in ipairs({ "runlab help", "runlab status", "runlab", "keyboard",
                           "clear" }) do
        local ok, err = pcall(handler, arg)
        if not ok then error(("/imitest %s -> %s"):format(arg, tostring(err))) end
    end
end)

-- "It did not error" is not the same fact as "it reached the lab". A handler
-- that quietly fell through to the whole self-test would pass the check above
-- while printing the ordinary report, which is exactly the symptom that is
-- impossible to tell apart from a mistyped command in a screenshot. So spy on
-- the lab and assert on what it was actually handed.
check("runlab reaches the lab, with the rest of the line", function()
    local handler = SlashCmdList.INOMRAHSMISELFTEST
    local real = Lab.Command
    local seen

    Lab.Command = function(a) seen = a end
    local restore = function() Lab.Command = real end

    local cases = {
        { typed = "runlab",              expect = "" },
        { typed = "runlab help",         expect = "help" },
        { typed = "runlab preflight",    expect = "preflight" },
        { typed = "runlab arm",          expect = "arm" },
        { typed = "RUNLAB ARM",          expect = "arm" },
        { typed = "  runlab   status  ", expect = "status" },
    }
    for _, case in ipairs(cases) do
        seen = nil
        local ok, err = pcall(handler, case.typed)
        if not ok then restore(); error(("/imitest %s -> %s"):format(case.typed, tostring(err))) end
        if seen == nil then
            restore()
            error(("/imitest %s never reached the lab"):format(case.typed))
        end
        if seen ~= case.expect then
            restore()
            error(("/imitest %s handed the lab %q, expected %q")
                :format(case.typed, seen, case.expect))
        end
    end

    -- And the other direction: a command that is not the lab's must never be
    -- handed to it. "runlabs" and "run lab" are near misses, not the prefix.
    for _, typed in ipairs({ "keyboard", "clear", "combat", "runlabs", "run lab" }) do
        seen = nil
        pcall(handler, typed)
        if seen ~= nil then
            restore()
            error(("/imitest %s was handed to the lab as %q"):format(typed, seen))
        end
    end

    restore()
end)

-- The command row. These exist because a mistyped slash command falls through
-- to the ordinary self-test and prints a report that looks like success.
check("preflight, arm, status and copy are buttons on the rescue bar", function()
    Lab.Command("setup")
    local bar = _G.InomrahsMISelfTestRunLabRescueBar
    if not bar then error("no rescue bar") end

    local wanted = { PREFLIGHT = true, ARM = true, STATUS = true, COPY = true }
    local found = {}
    for _, child in ipairs(bar.children or {}) do
        local text = child.label and child.label.text
        if text and wanted[text] then found[text] = child end
    end
    for text in pairs(wanted) do
        if not found[text] then error(("no %s button on the rescue bar"):format(text)) end
        if not found[text].scripts or not found[text].scripts.OnClick then
            error(("the %s button does nothing when clicked"):format(text))
        end
    end
end)

-- The bug this whole revision exists for: preflight and arm printed to chat
-- only, so the report window still held the previous self-test report and a
-- copy taken from it was indistinguishable from a successful lab run.
check("preflight, arm and help put their output in the report window", function()
    Lab.Command("setup")
    local realReport = InomrahsMISelfTestAPI.Report
    local shown
    InomrahsMISelfTestAPI.Report = function(text) shown = text end

    local function attempt(cmd)
        shown = nil
        local ok, err = pcall(Lab.Command, cmd)
        if not ok then
            InomrahsMISelfTestAPI.Report = realReport
            error(("runlab %s -> %s"):format(cmd, tostring(err)))
        end
        return shown
    end

    for _, cmd in ipairs({ "help", "preflight", "arm", "status" }) do
        local text = attempt(cmd)
        if not text then
            InomrahsMISelfTestAPI.Report = realReport
            error(("runlab %s showed nothing in the report window"):format(cmd))
        end
        if not text:find("RUN CAPABILITY LAB", 1, true) then
            InomrahsMISelfTestAPI.Report = realReport
            error(("runlab %s did not label its output as the lab's"):format(cmd))
        end
        if text:find("|c", 1, true) then
            InomrahsMISelfTestAPI.Report = realReport
            error(("runlab %s left colour escapes in the window text"):format(cmd))
        end
    end

    InomrahsMISelfTestAPI.Report = realReport
end)

check("the report survives having nothing to report", function()
    Lab.Command("setup")
    Lab.Command("report")
    Lab.Command("copy")
end)

realPrint(("\nrunlab: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
