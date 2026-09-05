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

--------------------------------------------------------------------------------
-- Out and back
--
-- The one property worth guaranteeing about the written form: what comes out
-- goes back in unchanged. Column widths are taste; this is not.
--------------------------------------------------------------------------------

check("a channel row sets the dungeon's override", function()
    local profile = IMI.Sheet.Parse("Dungeon:\tAltar\nChannel:\t/i\nEnemy:\tMob\n\tkick")
    if profile.categories[1].channel ~= "/i" then
        error("no channel: " .. tostring(profile.categories[1].channel))
    end
end)

check("a channel written without its slash still reads", function()
    local profile = IMI.Sheet.Parse("Dungeon:\tAltar\nChannel:\traid\nEnemy:\tMob\n\tkick")
    if profile.categories[1].channel ~= "/raid" then
        error("wrong channel: " .. tostring(profile.categories[1].channel))
    end
end)

check("a colour row is read, and a typo is not", function()
    local good = IMI.Sheet.Parse("Dungeon:\tA\nColor:\t#33cc66\nEnemy:\tMob\n\tkick")
    local colour = good.categories[1].color
    if not colour then error("the colour was not read") end
    if math.abs(colour[1] - 0x33 / 255) > 0.001 then error("wrong red") end

    local bad = IMI.Sheet.Parse("Dungeon:\tA\nColor:\tgreenish\nEnemy:\tMob\n\tkick")
    if bad.categories[1].color ~= nil then error("a typo became a colour") end
end)

check("what is written out reads back the same", function()
    local original = IMI.Sheet.Parse(table.concat({
        "Dungeon:\tAltar of Fangs",
        "Channel:\t/i",
        "Enemy:\tRavenous Descendant\tVenom Leech",
        "\tKick the Enrage\tDispel the leech",
        "\tSpread for the cone\t",
        "",
        "Dungeon:\tMurder Row",
        "Enemy:\tBribed Captain",
        "\tInterrupt the shout",
    }, "\n"))

    local back = IMI.Sheet.Parse(IMI.Sheet.Format(original))
    if #back.categories ~= #original.categories then
        error("a dungeon was lost on the way out and back")
    end

    for i, cat in ipairs(original.categories) do
        local other = back.categories[i]
        if cat.name ~= other.name then error("wrong name: " .. other.name) end
        if cat.channel ~= other.channel then
            error("the channel did not survive: " .. tostring(other.channel))
        end
        local a, b = cat.variants[1].enemies, other.variants[1].enemies
        if #a ~= #b then error("enemies lost: " .. #a .. " became " .. #b) end
        for j, enemy in ipairs(a) do
            if enemy.name ~= b[j].name then error("wrong enemy: " .. b[j].name) end
            if #enemy.lines ~= #b[j].lines then
                error(("%s: %d callouts became %d")
                    :format(enemy.name, #enemy.lines, #b[j].lines))
            end
            for k, line in ipairs(enemy.lines) do
                if line.body ~= b[j].lines[k].body then
                    error("a callout changed: " .. b[j].lines[k].body)
                end
            end
        end
    end
end)

-- More enemies than fit across a readable sheet are written in blocks, and the
-- blocks have to read back as one dungeon rather than several.
check("a dungeon wider than one block survives the trip", function()
    local rows = { "Dungeon:\tWide", "Enemy:" }
    local names = { "Enemy:" }
    for i = 1, 9 do names[#names + 1] = "Mob " .. i end
    rows[2] = table.concat(names, "\t")
    local callouts = { "" }
    for i = 1, 9 do callouts[#callouts + 1] = "kick " .. i end
    rows[3] = table.concat(callouts, "\t")

    local original = IMI.Sheet.Parse(table.concat(rows, "\n"))
    local back = IMI.Sheet.Parse(IMI.Sheet.Format(original))
    if #back.categories ~= 1 then
        error("the blocks became " .. #back.categories .. " dungeons")
    end
    if #enemies(back) ~= 9 then error("expected nine enemies, got " .. #enemies(back)) end
    if enemies(back)[9].lines[1].body ~= "kick 9" then error("the last block lost its callout") end
end)

check("rows starting with # are notes, not enemies", function()
    local profile = IMI.Sheet.Parse(table.concat({
        "# Fill this in and paste it into Import.",
        "# A row starting Dungeon or Enemy is an instruction.",
        "Dungeon:\tAltar",
        "Enemy:\tMob",
        "\tkick",
    }, "\n"))
    if not profile then error("the template was refused") end
    local list = enemies(profile)
    if #list ~= 1 then error("a note became an enemy: " .. #list) end
    if profile.categories[1].name ~= "Altar" then error("wrong dungeon name") end
end)

-- The file handed to people to start from. If this stops importing, the
-- template and the parser have come apart.
check("the shipped template imports", function()
    local file = io.open("tools/profile-template.csv")
    if not file then error("tools/profile-template.csv is missing") end
    local text = file:read("*a")
    file:close()

    local profile, err, count = IMI.Sheet.Parse(text)
    if not profile then error("the template does not import: " .. tostring(err)) end
    if count ~= 2 then error("expected two dungeons in the template, got " .. count) end
    if profile.categories[1].channel ~= "/i" then
        error("the template's channel row did not read")
    end
end)

realPrint(("\nsheet: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
