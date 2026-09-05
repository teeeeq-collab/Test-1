-- Pasting a spreadsheet. The format people already write their callouts in.
local realPrint = print
package.path = "tests/?.lua;" .. package.path

local IMI = {}
loadfile("InomrahsMythicInstructions/Util.lua")("InomrahsMythicInstructions", IMI)
loadfile("InomrahsMythicInstructions/Sheet.lua")("InomrahsMythicInstructions", IMI)

local pass, fail = 0, 0
local function check(label, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; realPrint("  FAIL: " .. label .. "\n         " .. tostring(err)) end
end

local function enemies(profile, catIndex)
    return profile.categories[catIndex or 1].variants[1].enemies
end

-- The shape the example sheet is in: a label column, enemies across, callouts
-- underneath.
local SHEET = table.concat({
    "Enemy:\tRavenous Descendant\tVenom Leech",
    "\tKick the Enrage\tDispel the leech",
    "\tSpread for the cone\tStack for the pull",
    "",
    "Enemy\tBribed Captain\tStreet Sneak",
    "\tInterrupt the shout\tStun on pull",
}, "\n")

check("a pasted sheet becomes enemies with their callouts", function()
    local profile, err, count = IMI.Sheet.Parse(SHEET)
    if not profile then error(tostring(err)) end
    if count ~= 1 then error("expected one dungeon, got " .. tostring(count)) end

    local list = enemies(profile)
    if #list ~= 4 then error("expected four enemies, got " .. #list) end
    if list[1].name ~= "Ravenous Descendant" then error("wrong first enemy: " .. list[1].name) end
    if #list[1].lines ~= 2 then error("expected two callouts, got " .. #list[1].lines) end
    if list[1].lines[1].body ~= "Kick the Enrage" then
        error("wrong callout: " .. list[1].lines[1].body)
    end
    -- Read down its own column, not across the row.
    if list[2].lines[2].body ~= "Stack for the pull" then
        error("callouts did not follow their column: " .. list[2].lines[2].body)
    end
end)

check("a blank row separates blocks rather than joining them", function()
    local profile = IMI.Sheet.Parse(SHEET)
    local list = enemies(profile)
    -- Without the separation, "Interrupt the shout" would land on Ravenous.
    if #list[1].lines ~= 2 then error("the second block leaked into the first") end
    if list[3].name ~= "Bribed Captain" then error("wrong third enemy: " .. list[3].name) end
    if list[3].lines[1].body ~= "Interrupt the shout" then
        error("wrong callout on the second block")
    end
end)

check("a sheet with no keyword at all still reads", function()
    local profile, err = IMI.Sheet.Parse("Mob One\tMob Two\nkick\tstun")
    if not profile then error(tostring(err)) end
    local list = enemies(profile)
    if #list ~= 2 or list[1].name ~= "Mob One" then error("header row was not read as names") end
    if list[2].lines[1].body ~= "stun" then error("callout did not land") end
end)

check("Dungeon and Page rows name what they say", function()
    local profile, _, count = IMI.Sheet.Parse(table.concat({
        "Dungeon:\tAltar of Fangs",
        "Page:\tFirst pull",
        "Enemy:\tMob A",
        "\tkick",
        "",
        "Dungeon:\tMurder Row",
        "Enemy:\tMob B",
        "\tstun",
    }, "\n"))
    if count ~= 2 then error("expected two dungeons, got " .. tostring(count)) end
    if profile.categories[1].name ~= "Altar of Fangs" then error("wrong dungeon name") end
    local pages = profile.categories[1].variants[1].pages
    if #pages ~= 1 or pages[1].name ~= "First pull" then error("the page was not named") end
    if #pages[1].enemyIds ~= 1 then error("the enemy did not join the page") end
end)

-- A dungeon with no page has nothing to show in Run, so a sheet that never
-- mentions pages still gets one.
check("a sheet with no pages still gets one", function()
    local profile = IMI.Sheet.Parse(SHEET)
    local pages = profile.categories[1].variants[1].pages
    if #pages ~= 1 then error("expected exactly one page, got " .. #pages) end
    if #pages[1].enemyIds ~= 4 then error("not every enemy reached the page") end
end)

check("commas inside a quoted cell do not split it", function()
    local profile = IMI.Sheet.Parse('Mob\n"kick, then stack"')
    local list = enemies(profile)
    if list[1].lines[1].body ~= "kick, then stack" then
        error("the callout was cut at the comma: " .. tostring(list[1].lines[1].body))
    end
end)

check("tabs win over commas", function()
    -- A copy out of a spreadsheet is tab separated and its cells may contain
    -- commas. Splitting on commas first would cut this callout in half.
    local profile = IMI.Sheet.Parse("Mob A\tMob B\nkick, then stack\tstun")
    local list = enemies(profile)
    if #list ~= 2 then error("expected two columns, got " .. #list) end
    if list[1].lines[1].body ~= "kick, then stack" then
        error("wrong callout: " .. tostring(list[1].lines[1].body))
    end
end)

check("an empty cell leaves a gap rather than shifting the column", function()
    local profile = IMI.Sheet.Parse("Mob A\tMob B\n\tonly B\nboth A\tboth B")
    local list = enemies(profile)
    if #list[1].lines ~= 1 or list[1].lines[1].body ~= "both A" then
        error("A picked up B's callout")
    end
    if #list[2].lines ~= 2 then error("B lost a callout") end
end)

-- A sentence pasted by accident is not a sheet, and accepting it would replace
-- a whole profile with one empty dungeon named after the sentence.
check("a single line of prose is not a sheet", function()
    if IMI.Sheet.Parse("just some words") then error("prose was accepted") end
    if IMI.Sheet.Parse("Ravenous Descendant") then error("one name was accepted") end
end)

check("but a row of names with no callouts yet is", function()
    local profile = IMI.Sheet.Parse("Mob One\tMob Two\tMob Three")
    if not profile then error("a list of names was refused") end
    if #enemies(profile) ~= 3 then error("wrong number of names") end
end)

check("and so is one enemy with callouts under it", function()
    local profile = IMI.Sheet.Parse("Mob One\nkick\nstun")
    if not profile then error("a single column was refused") end
    if #enemies(profile)[1].lines ~= 2 then error("its callouts did not come with it") end
end)

check("nothing usable says what it wanted", function()
    local profile, err = IMI.Sheet.Parse("\n\n\n")
    if profile then error("an empty paste was accepted") end
    if not tostring(err):find("sheet") then error("unhelpful message: " .. tostring(err)) end
end)

realPrint(("\nsheet: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
