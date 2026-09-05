--------------------------------------------------------------------------------
-- makestring: turn a written profile into an import string, outside the game.
--
--   lua5.1 tools/makestring.lua myprofile.txt
--   lua5.1 tools/makestring.lua myprofile.txt --out string.txt
--   lua5.1 tools/makestring.lua myprofile.txt --check
--
-- The input is the same text the addon's Import box takes: one instruction per
-- line, Dungeon:, Channel:, Color:, Page: or Enemy:, with callouts under the
-- enemy they belong to. A CSV or a tab-separated file works too.
--
-- The output is a single-line string, exactly what Settings > Profile > Export
-- produces in game, which means it can be pasted into Discord and imported by
-- anyone.
--
-- It is the addon's own code that does the work.
--
-- Nothing here reimplements the format. This loads Sheet.lua, Core.lua and
-- Export.lua -- the same files the addon runs -- so the string cannot drift
-- from what the addon accepts: if the addon changes, this changes with it. A
-- second implementation in another language would be a second thing to keep
-- right, and the first time the two disagreed it would be silent.
--
-- --check decodes the string it just produced and prints what came back, so a
-- run either proves itself or says why not.
--------------------------------------------------------------------------------

-- The libraries are written for the game, which has these as globals.
strmatch = string.match
strsub   = string.sub
strbyte  = string.byte
strchar  = string.char

local HERE = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local ROOT = HERE .. "/../InomrahsMythicInstructions"

local IMI = {}
local function load(path, ...)
    local chunk, err = loadfile(ROOT .. "/" .. path)
    if not chunk then
        io.stderr:write("cannot read " .. ROOT .. "/" .. path .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
    return chunk(...)
end

load("Libs/LibStub/LibStub.lua")
load("Libs/LibDeflate/LibDeflate.lua")
load("Libs/LibSerialize/LibSerialize.lua")
for _, file in ipairs({ "Util", "Color", "Core", "Sheet", "Export" }) do
    load(file .. ".lua", "InomrahsMythicInstructions", IMI)
end

--------------------------------------------------------------------------------

local function usage()
    io.stderr:write([[
usage: lua5.1 tools/makestring.lua <file> [--out <file>] [--check]

  <file>        a profile written one instruction per line:

                    Dungeon: Altar of Fangs
                    Channel: /i
                    Enemy: Ravenous Descendant
                    Kick the Enrage
                    Enemy: Venom Leech
                    Dispel the leech

  --out <file>  write the string to a file instead of standard output
  --check       decode the string afterwards and print what it holds
]])
    os.exit(1)
end

local input, output, check
local i = 1
while arg[i] do
    if arg[i] == "--out" then
        i = i + 1
        output = arg[i] or usage()
    elseif arg[i] == "--check" then
        check = true
    elseif arg[i]:sub(1, 2) == "--" then
        usage()
    else
        input = arg[i]
    end
    i = i + 1
end
if not input then usage() end

local file = io.open(input, "r")
if not file then
    io.stderr:write(("cannot read %s\n"):format(input))
    os.exit(1)
end
local text = file:read("*a")
file:close()

--------------------------------------------------------------------------------
-- Read it, build it, encode it
--------------------------------------------------------------------------------

local profile, err = IMI.Sheet.Parse(text)
if not profile then
    io.stderr:write(("%s: %s\n"):format(input, tostring(err)))
    os.exit(1)
end

-- Built through the addon's own Add calls rather than assembled by hand, so
-- every id is minted the way the addon mints them and the string holds exactly
-- what an in-game export of the same content would hold.
IMI.Core.Init({})
for _, cat in ipairs(profile.categories) do IMI.Export.Adopt(cat) end

local str, encodeErr = IMI.Export.EncodeProfile()
if not str then
    io.stderr:write(("could not encode: %s\n"):format(tostring(encodeErr)))
    os.exit(1)
end

if output then
    local out = io.open(output, "w")
    if not out then
        io.stderr:write(("cannot write %s\n"):format(output))
        os.exit(1)
    end
    out:write(str, "\n")
    out:close()
    io.stderr:write(("wrote %s (%d characters)\n"):format(output, #str))
else
    print(str)
end

--------------------------------------------------------------------------------
-- Prove it
--------------------------------------------------------------------------------

if not check then return end

local decoded, decodeErr, count = IMI.Export.Preview(str)
if not decoded then
    io.stderr:write(("the string it produced does not decode: %s\n"):format(tostring(decodeErr)))
    os.exit(1)
end

io.stderr:write(("\ndecodes to %d dungeon%s:\n"):format(count, count == 1 and "" or "s"))
for _, cat in ipairs(decoded.categories) do
    local variant = cat.variants and cat.variants[1] or cat
    local callouts = 0
    for _, enemy in ipairs(variant.enemies or {}) do
        callouts = callouts + #(enemy.lines or {})
    end
    io.stderr:write(("  %s — %d enemies, %d callouts, %d pages%s\n"):format(
        cat.name, #(variant.enemies or {}), callouts, #(variant.pages or {}),
        cat.channel and (", channel " .. cat.channel) or ""))
    for _, enemy in ipairs(variant.enemies or {}) do
        io.stderr:write(("     %-28s %d\n"):format(enemy.name, #(enemy.lines or {})))
    end
end
