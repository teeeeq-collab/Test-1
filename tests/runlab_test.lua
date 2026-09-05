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

check("the report survives having nothing to report", function()
    Lab.Command("setup")
    Lab.Command("report")
    Lab.Command("copy")
end)

realPrint(("\nrunlab: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
