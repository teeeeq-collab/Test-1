--------------------------------------------------------------------------------
-- Mutation testing: breaking the code on purpose, to find tests that were not
-- really checking anything.
--
-- A passing suite proves less than it looks. A test can pass because the code
-- is right, or because the test would have passed whatever the code did. This
-- tells the two apart: it makes one small, deliberate change to the source at a
-- time, runs the suite, and reports every change the suite did not notice.
--
-- A surviving mutant is a claim the addon makes that nothing checks. Some are
-- harmless — a constant only used for spacing, a guard that cannot be reached.
-- The point is to read the list and decide, rather than to drive it to zero.
--
--   lua5.1 tests/mutate.lua                  every file
--   lua5.1 tests/mutate.lua Core             files matching "Core"
--   lua5.1 tests/mutate.lua Core 40          and at most 40 mutants
--
-- Each file is restored from a copy held in memory. A run that is killed part
-- way through leaves one file mutated, so this refuses to start unless the tree
-- is clean and the damage is one command to undo:
--
--   git checkout -- InomrahsMythicInstructions
--------------------------------------------------------------------------------

local FILTER = arg and arg[1]
local LIMIT = tonumber(arg and arg[2]) or math.huge

local SOURCE_DIR = "InomrahsMythicInstructions"

--------------------------------------------------------------------------------
-- Where in a line it is safe to change something
--------------------------------------------------------------------------------

--- Marks which characters of a line are inside a string or a comment, so a
--- mutation cannot rewrite a message, a snippet or a comment and call the
--- resulting non-change a surviving mutant.
local function maskOf(line)
    local mask = {}
    local quote, i = nil, 1

    while i <= #line do
        local c = line:sub(i, i)

        if quote then
            mask[i] = true
            if c == "\\" then
                mask[i + 1] = true
                i = i + 1
            elseif c == quote then
                quote = nil
            end
        elseif c == '"' or c == "'" then
            quote = c
            mask[i] = true
        elseif line:sub(i, i + 1) == "--" then
            for j = i, #line do mask[j] = true end
            break
        elseif line:sub(i, i + 1) == "[[" or line:sub(i, i + 2) == "[==" then
            for j = i, #line do mask[j] = true end
            break
        else
            mask[i] = false
        end
        i = i + 1
    end

    return mask
end

local function clear(mask, from, to)
    for i = from, to do
        if mask[i] then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- The changes to try
--------------------------------------------------------------------------------

-- Each entry finds a pattern and says what to put in its place. Deliberately
-- small: one operator, one constant, one word. A large change tends to break
-- the file rather than the behaviour, and a mutant that does not compile
-- teaches nothing.
local RULES = {
    { find = "==",    replace = "~=",    name = "equality flipped" },
    { find = "~=",    replace = "==",    name = "inequality flipped" },
    { find = "<=",    replace = "<",     name = "bound tightened" },
    { find = ">=",    replace = ">",     name = "bound tightened" },
    { find = " and ", replace = " or ",  name = "and became or" },
    { find = " or ",  replace = " and ", name = "or became and" },
    { find = "true",  replace = "false", name = "true became false" },
    { find = "false", replace = "true",  name = "false became true" },
    { find = " + ",   replace = " - ",   name = "plus became minus" },
    { find = " - ",   replace = " + ",   name = "minus became plus" },
    { find = "not ",  replace = "",      name = "negation dropped" },
}

local function mutationsFor(lines)
    local out = {}

    for index, line in ipairs(lines) do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^%-%-") then
            local mask = maskOf(line)

            for _, rule in ipairs(RULES) do
                local from = 1
                while true do
                    local a, b = line:find(rule.find, from, true)
                    if not a then break end
                    if clear(mask, a, b) then
                        out[#out + 1] = {
                            line = index,
                            name = rule.name,
                            text = line:sub(1, a - 1) .. rule.replace .. line:sub(b + 1),
                            was = trimmed,
                        }
                    end
                    from = b + 1
                end
            end

            -- Numbers: a constant nobody checks is a constant that can drift.
            local from = 1
            while true do
                local a, b, digits = line:find("(%d+)", from)
                if not a then break end
                local before = line:sub(a - 1, a - 1)
                if clear(mask, a, b) and not before:match("[%w_.]") then
                    out[#out + 1] = {
                        line = index,
                        name = "number changed",
                        text = line:sub(1, a - 1) .. tostring(tonumber(digits) + 1)
                            .. line:sub(b + 1),
                        was = trimmed,
                    }
                end
                from = b + 1
            end
        end
    end

    return out
end

--------------------------------------------------------------------------------
-- Running them
--------------------------------------------------------------------------------

--- Runs a command and reports whether it succeeded.
---
--- The exit status is echoed and parsed rather than read from close(), because
--- Lua 5.1's popen does not report it: close() returns true whatever the
--- command did. Taking that for success made every mutant look like a survivor
--- and the first run of this file report that none were caught — a tool that
--- was itself the thing it exists to catch.
local function shell(command)
    local pipe = io.popen("{ " .. command .. " ; } 2>&1; echo \"__EXIT__$?\"")
    local output = pipe:read("*a") or ""
    pipe:close()

    local code = tonumber(output:match("__EXIT__(%d+)%s*$"))
    output = output:gsub("__EXIT__%d+%s*$", "")
    return code == 0, output
end

local function readLines(path)
    local lines, file = {}, io.open(path, "r")
    if not file then return nil end
    for line in file:lines() do lines[#lines + 1] = line end
    file:close()
    return lines
end

local function writeLines(path, lines)
    local file = assert(io.open(path, "w"))
    file:write(table.concat(lines, "\n"), "\n")
    file:close()
end

local _, dirty = shell("git status --porcelain -- " .. SOURCE_DIR)
if dirty and dirty:match("%S") then
    print("Refusing to run: " .. SOURCE_DIR .. " has uncommitted changes.")
    print("Mutants are undone with git checkout, which would take them with it.")
    os.exit(1)
end

local _, listing = shell("ls " .. SOURCE_DIR .. "/*.lua")
local files = {}
for path in listing:gmatch("[^\n]+") do
    if not path:find("/Libs/") and (not FILTER or path:find(FILTER, 1, true)) then
        files[#files + 1] = path
    end
end

print(("Mutating %d file%s. Each mutant is one run of the suite."):format(
    #files, #files == 1 and "" or "s"))
print("If this is interrupted: git checkout -- " .. SOURCE_DIR .. "\n")

local killed, survived, broke = 0, 0, 0
local survivors = {}
local total = 0

for _, path in ipairs(files) do
    local original = readLines(path)
    local mutations = mutationsFor(original)

    for _, mutation in ipairs(mutations) do
        if total >= LIMIT then break end
        total = total + 1

        local lines = {}
        for i, line in ipairs(original) do lines[i] = line end
        lines[mutation.line] = mutation.text
        writeLines(path, lines)

        local compiles = shell("luac5.1 -p " .. path)
        if not compiles then
            -- A mutant that does not compile tests nothing about the tests.
            broke = broke + 1
        else
            local passed = shell("./tests/run.sh")
            if passed then
                survived = survived + 1
                survivors[#survivors + 1] = {
                    path = path, line = mutation.line,
                    name = mutation.name, was = mutation.was,
                }
                io.write("!")
            else
                killed = killed + 1
                io.write(".")
            end
        end

        io.flush()
        -- Restored from the copy held here, not with git: a process per mutant
        -- was most of the running time, and the original is already in memory.
        -- git is the safety net for a run that is killed, not the mechanism.
        writeLines(path, original)
    end
end

shell("git checkout -- " .. SOURCE_DIR)

print("\n")
print(("%d mutants: %d caught, %d survived, %d did not compile")
    :format(total, killed, survived, broke))

if #survivors > 0 then
    print("\nSurvived — the suite did not notice these:\n")
    for _, s in ipairs(survivors) do
        print(("  %s:%d  %s"):format(s.path, s.line, s.name))
        print(("      %s"):format(s.was))
    end
end

local checked = killed + survived
if checked > 0 then
    print(("\n%.0f%% of meaningful mutants were caught."):format(killed / checked * 100))
end
