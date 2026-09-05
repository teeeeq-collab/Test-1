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

-- The bug that stranded a live run at step 24 of 28: the clipped step told the
-- reader to press the second key, and then watched the first key's counter.
check("each action step watches the key it asks for", function()
    Lab.Command("setup")
    local source = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")

    -- The generic builder must not name a single chord or counter any more.
    local body = source:match("local function actionStep.-\nend\n")
    if not body then error("could not find actionStep") end
    for _, literal in ipairs({ "CHORDS%[1%]", "fired%[1%]", "firedSince%(1," }) do
        if body:find(literal) then
            error(("actionStep still hardcodes %s"):format(literal:gsub("%%", "")))
        end
    end

    -- And the step that asks for the second key must actually ask for action 2.
    -- Matched loosely on purpose: this asserts the pairing, not the shape of
    -- the call, so reformatting the step does not fail the check for no reason.
    local clipped = source:match('"action key on a clipped button"(.-)\n\n')
    if not clipped then error("could not find the clipped step") end
    if not clipped:find("CHORDS%[2%]") then
        error("the clipped step does not ask for the second key")
    end
    if not clipped:find(",%s*2%s*%)%)%s*$") then
        error("the clipped step does not select the second action")
    end
end)

-- The reported failure: an instruction that said "click X to bring it back,
-- then click Y" was one button and one measurement for two separate actions.
-- Click only the first, press "I clicked it", and the next step measured a
-- state nobody had set -- reporting a confident YES for a button that was
-- never hidden. Two invariants close it: one action per step, and every step
-- that names a state refuses to measure until that state actually holds.
check("no step asks for two clicks, and stateful steps check their state", function()
    local source = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")

    local build = source:match("local function buildSteps.-\nend\n")
    if not build then error("could not find buildSteps") end

    if build:find("bring it back, then") then
        error("a step still combines a restore and the next action in one click")
    end

    -- Judged on the capability, not the body text: the capability is what the
    -- report will claim, and "Nothing is hidden yet" is a body that mentions a
    -- state without asserting one.
    --
    -- The clipped step is exempt: its state is how the lab is built, not
    -- something the reader has to click into place first.
    for block in build:gmatch("add%(actionStep(.-)\n\n") do
        local _, capability = block:match('"([^"]*)"%s*,%s*"([^"]*)"')
        capability = capability or ""
        local stateful = (capability:find("hidden") or capability:find("parked")
            or capability:find("1x1")) and not capability:find("clipped")
        if stateful and not block:find("check =", 1, true) then
            error(("the step %q describes a state but never checks it")
                :format(capability))
        end
    end
end)

check("a stuck step can be skipped and a run can be resumed", function()
    Lab.Command("setup")
    local source = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")
    if not source:find('f.skip = plainButton', 1, true) then
        error("no skip button on the step panel")
    end
    if not source:find('F.step.skip:Show()', 1, true) then
        error("the skip button is never shown")
    end

    -- Shown by paintStep, so every step carries it from the moment it opens.
    -- Gating it behind a timeout meant the steps most likely to be stuck were
    -- the ones that made you wait ninety seconds to move on.
    local paint = source:match("local function paintStep%b()(.-)\nend\n")
    if not paint then error("could not find paintStep") end
    if not paint:find("F.step.skip:Show()", 1, true) then
        error("skip is not shown when a step is painted")
    end

    -- goto refuses nonsense and does not throw on any of it.
    for _, cmd in ipairs({ "goto 0", "goto 9999", "goto", "goto x" }) do
        local ok, err = pcall(Lab.Command, cmd)
        if not ok then error(("runlab %s -> %s"):format(cmd, tostring(err))) end
    end

    -- And a real jump marks everything before it as not attempted, so a
    -- resumed report cannot be read as a complete one.
    local realReport = InomrahsMISelfTestAPI.Report
    local shown
    InomrahsMISelfTestAPI.Report = function(text) shown = text end
    Lab.Command("goto 4")
    Lab.Command("copy")
    InomrahsMISelfTestAPI.Report = realReport

    if not shown then error("no report after goto") end
    if not shown:find("not attempted", 1, true) then
        error("goto did not mark the skipped steps as not attempted")
    end
end)

-- The follow-up must be a real subset of the full sequence, not a second
-- hand-written list that can drift from it.
check("the follow-up is shorter than the full run and covers what was open", function()
    Lab.Command("setup")
    local function length()
        local n
        local out = print
        print = function(line)
            local got = tostring(line):match("step numbers run 1 to (%d+)")
            if got then n = tonumber(got) end
        end
        Lab.Command("goto 99999")
        print = out
        return n
    end

    local full = length()
    Lab.Command("followup")
    local short = length()

    if not full or not short then error("could not measure the sequence length") end
    if short >= full then
        error(("the follow-up is %d steps, the full run %d"):format(short, full))
    end
    if short < 6 then
        error(("the follow-up is only %d steps -- the filter dropped too much"):format(short))
    end

    -- And reset must not silently drop back to the full run.
    Lab.Command("reset")
    if length() ~= short then error("reset rebuilt the wrong sequence") end

    Lab.Command("setup")
    if length() ~= full then error("setup did not go back to the full sequence") end
end)

-- A probe that measured nothing must not read as a pass. This is the same
-- defect as a check hardcoded to true, and it survived a live run: four lines
-- printed [ok] while saying "not attempted" and "nothing to scroll".
check("a probe that measured nothing does not report as ok", function()
    local source = io.open("InomrahsMISelfTest/SelfTest.lua"):read("*a")

    if not source:find("local function measured", 1, true) then
        error("no measured() helper")
    end
    if not source:find('r.ok == "none"', 1, true) then
        error("the report does not render the measured-nothing state")
    end

    -- Every probe whose detail can be "not attempted" or "nothing to scroll"
    -- must go through measured(), not a bare true.
    for _, marker in ipairs({ "A: restricted SetVerticalScroll",
                              "B: restricted SetPoint on protected content",
                              "B: did the content actually move",
                              "D: Run has something to scroll" }) do
        local call = source:match('"' .. marker:gsub("%p", "%%%1") .. '",%s*([^,\n]+)')
        if not call then error(("could not find the %s probe"):format(marker)) end
        if not call:find("measured", 1, true) then
            error(("the %s probe still records a bare %s"):format(marker, call))
        end
    end
end)

-- The bug that cost most of two live runs. The scroll viewport is anchored to
-- the root's bottom edge; the operation buttons were laid out from the bottom
-- too, and the viewport ended up covering six of them. They rendered perfectly
-- and ate every click, and the results came back as "the snippet never ran" --
-- indistinguishable, at the time, from the client refusing the operation.
--
-- Nothing in the suite looked at the lab's own layout. The production sweep
-- exists precisely for this and had never been pointed here.
check("nothing sits on top of the operation buttons", function()
    Lab.Command("setup")
    local geo = dofile("tests/geometry.lua")

    local root = _G.InomrahsMISelfTestRunLabRoot
    if not root then error("no lab root") end
    local rootRect = geo.resolve(root)
    if not rootRect then error("the lab root has no resolvable position") end

    -- Everything the lab builds that takes the mouse and is not an op button.
    local obstacles = {}
    for _, name in ipairs({ "Viewport", "Ancestor", "Action", "Clipped", "Home" }) do
        local frame = _G["InomrahsMISelfTestRunLab" .. name]
        local rect = frame and geo.resolve(frame)
        if rect then obstacles[#obstacles + 1] = { name = name, rect = rect } end
    end

    local names = { "OpRoot", "OpAnc", "OpAction", "OpVisual", "OpPark", "OpSize",
                    "OpGeo", "OpAnchor", "OpScale", "OpMouse", "OpFade" }
    local checked = 0
    for _, name in ipairs(names) do
        local button = _G["InomrahsMISelfTestRunLab" .. name]
        if button then
            local rect = geo.resolve(button)
            if not rect then error(name .. " has no resolvable position") end
            checked = checked + 1

            for _, obstacle in ipairs(obstacles) do
                if geo.overlaps(rect, obstacle.rect, 0) then
                    error(("%s is covered by %s -- %s vs %s")
                        :format(name, obstacle.name, geo.describe(rect),
                                geo.describe(obstacle.rect)))
                end
            end

            -- And inside the window, or it floats over the game world.
            if rect.left < rootRect.left - 0.5 or rect.right > rootRect.right + 0.5
                or rect.bottom < rootRect.bottom - 0.5 or rect.top > rootRect.top + 0.5 then
                error(("%s hangs outside the lab window -- %s not within %s")
                    :format(name, geo.describe(rect), geo.describe(rootRect)))
            end
        end
    end

    if checked < 11 then
        error(("only %d operation buttons were found, expected 11"):format(checked))
    end
end)

-- A state the lab cannot read must stall the step, never satisfy it. Treating
-- an unreadable position as "parked" produced the worst line in the second live
-- report: "action key while the button is parked off screen -- YES", recorded
-- against a button the same entry shows sitting at 160x34 in its usual place.
check("an unreadable state never satisfies a step", function()
    local source = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")

    for _, name in ipairs({ "awayFromHome", "tiny" }) do
        local body = source:match("local function " .. name .. "%b()(.-)\n    end")
        if not body then error("could not find " .. name) end
        if not body:find("return nil", 1, true) then
            error(("%s does not report an unreadable state as unknown"):format(name))
        end
    end

    -- And both gates must demand an explicit true, so nil cannot pass.
    local gates = 0
    for _ in source:gmatch("ok and result == true") do gates = gates + 1 end
    for _ in source:gmatch("if ok and result == true then return true end") do
        gates = gates + 1
    end
    if gates < 2 then
        error("a step gate accepts something other than an explicit true")
    end
end)

-- A step that measures counters knows more than "nothing observed" does. Its
-- record was thrown away whenever it timed out or was skipped -- which is
-- exactly when the answer mattered, because the counters say whether the
-- snippet ran.
check("a timed-out counter step still records what it measured", function()
    local source = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")

    if not source:find("recordOnTimeout", 1, true) then
        error("no recordOnTimeout path")
    end

    -- Both exits honour it: the timeout and the skip button.
    local timeouts = 0
    for _ in source:gmatch("step%.recordOnTimeout and step%.done") do
        timeouts = timeouts + 1
    end
    if timeouts < 2 then
        error(("only %d of the two exits run the step's own record"):format(timeouts))
    end

    -- And every step that counts clicks sets it, or its answer is lost.
    for _, marker in ipairs({ "secure width and height on a protected ancestor",
                             "secure re-anchor of a protected ancestor" }) do
        local block = source:match('capability = "' .. marker:gsub("%p", "%%%1") .. '",(.-)\n%s*text =')
        if not block or not block:find("recordOnTimeout", 1, true) then
            error(("%s loses its record on a timeout"):format(marker))
        end
    end
end)

-- The geometry record recomputed its "requested" size from ROOT_H - 90, which
-- stopped being the ancestor's height when the window was re-laid out. The
-- report then printed a request nobody made -- 104 beside an "after" of 71
-- that had actually been honoured exactly, which reads as a partial refusal.
check("the geometry record reports the size the snippet actually asks for", function()
    local source = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")

    -- The snippet halves the ancestor's own dimensions.
    local snippet = source:match("local TOGGLE_GEO = %[==%[(.-)%]==%]")
    if not snippet then error("could not find TOGGLE_GEO") end
    if not (snippet:find("WIDE_W / 2") and snippet:find("TALL_H / 2")) then
        error("TOGGLE_GEO no longer halves the ancestor")
    end
    if not source:find(':gsub("WIDE_W", tostring(ANC_W))', 1, true) then
        error("WIDE_W is not the ancestor's width")
    end

    -- So the record must halve the same two numbers, not re-derive them.
    if source:find("fmt%(%(ROOT_W %- 20%) / 2%)") or source:find("fmt%(%(ROOT_H %- 90%) / 2%)") then
        error("the record still recomputes the requested size from the root")
    end
    if not source:find("fmt(ANC_W / 2), fmt(ANC_H / 2)", 1, true) then
        error("the record does not report the size the snippet asks for")
    end
end)

-- A snippet that throws partway looks exactly like a click that never arrived:
-- both leave "ran" at zero. Every snippet stamps "entered" as its first line,
-- before anything that can fail, so the two separate.
check("every snippet records that it started before it can throw", function()
    local source = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")

    -- Lua patterns have no alternation, so match the two prefixes separately.
    -- %w does not include the underscore, which is how this check first found
    -- nothing at all and passed itself as if the file had no snippets.
    local checked = 0
    for _, prefix in ipairs({ "TOGGLE", "SNIPPET" }) do
        for name, body in source:gmatch("local (" .. prefix .. "[%w_]*) = %[==%[(.-)%]==%]") do
            checked = checked + 1
            local first = body:match("^%s*([^\n]+)")
            if not first or not first:find("entered", 1, true) then
                error(("%s does not stamp entered as its first line"):format(name))
            end
        end
    end
    if checked < 6 then
        error(("only %d snippets were found"):format(checked))
    end

    if not source:find('attr("entered")', 1, true) then
        error("runlab clicks does not report entered")
    end
end)

-- A snippet stops dead where it throws, so anything after that point is
-- silent. Every geometry snippet stamps between its calls: entered, cleared,
-- pointed, ran. Without that, "entered 1, ran 0" names a snippet but not the
-- call inside it, which is a gap wide enough to theorise into.
check("the geometry snippets stamp between each call", function()
    local source = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")

    for _, name in ipairs({ "TOGGLE_PARK", "TOGGLE_ANCHOR", "TOGGLE_SELF_ANCHOR" }) do
        local body = source:match("local " .. name .. " = %[==%[(.-)%]==%]")
        if not body then error("could not find " .. name) end

        -- Comments mention these calls by name. Matching prose as if it were
        -- code put "SetPoint" ahead of ClearAllPoints and failed a snippet
        -- that was written correctly.
        body = body:gsub("%-%-[^\n]*", "")

        local order = {}
        for stamp in body:gmatch('SetAttribute%("(%a+)"') do
            if stamp == "entered" or stamp == "cleared" or stamp == "pointed"
                or stamp == "ran" then
                order[#order + 1] = stamp
            end
        end
        local seen = table.concat(order, ",")
        for _, stamp in ipairs({ "entered", "cleared", "pointed", "ran" }) do
            if not seen:find(stamp, 1, true) then
                error(("%s never stamps %s"):format(name, stamp))
            end
        end

        -- And each stamp must follow the call it vouches for.
        local clearAt = body:find("ClearAllPoints", 1, true)
        local clearedAt = body:find('SetAttribute("cleared"', 1, true)
        local pointAt = body:find("SetPoint", 1, true)
        local pointedAt = body:find('SetAttribute("pointed"', 1, true)
        if not (clearAt < clearedAt and clearedAt < pointAt and pointAt < pointedAt) then
            error(("%s stamps out of order -- a stamp before its call proves nothing")
                :format(name))
        end
    end
end)

-- The insecure click counter is not evidence on its own: a hooked OnClick does
-- not fire when the script it hooks errors first, so a snippet that threw
-- looked exactly like a button nobody pressed. This lab reported "the button
-- was never clicked" about three buttons that were, in fact, clicked. Every
-- conclusion is drawn from "entered", stamped inside the snippet.
check("conclusions are drawn from entered, not from the click hook", function()
    local source = io.open("InomrahsMISelfTest/RunLab.lua"):read("*a")

    if source:find("the button was never clicked", 1, true) then
        error("a conclusion still claims a click never happened")
    end
    if not source:find("the snippet was never entered", 1, true) then
        error("no conclusion is phrased in terms of entry")
    end

    -- Every step that waits for a press must consult entered.
    local waits = 0
    for _ in source:gmatch('ranCount%(%s*"?%w*"?,?%s*"entered"%s*%)') do
        waits = waits + 1
    end
    if waits < 5 then
        error(("only %d places read entered; the click hook is still the gate"):format(waits))
    end
end)

check("the report survives having nothing to report", function()
    Lab.Command("setup")
    Lab.Command("report")
    Lab.Command("copy")
end)

-- Printed so a change in the sequence length is visible in the run output
-- rather than something to be counted by hand before every handoff.
InomrahsMISelfTestRunLab.Command("setup")
do
    local realReport = InomrahsMISelfTestAPI.Report
    InomrahsMISelfTestAPI.Report = function() end
    local out = print
    print = function(line)
        local n = tostring(line):match("step numbers run 1 to (%d+)")
        if n then realPrint(("runlab sequence: %s steps"):format(n)) end
    end
    InomrahsMISelfTestRunLab.Command("goto 9999")
    print = out
    InomrahsMISelfTestAPI.Report = realReport
end

realPrint(("\nrunlab: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
