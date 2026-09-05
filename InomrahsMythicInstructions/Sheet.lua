--------------------------------------------------------------------------------
-- Sheet: turning pasted spreadsheet rows into dungeons.
--
-- Writing callouts is easier in a spreadsheet than in a game panel -- a column
-- per enemy, a row per instruction, and everything visible at once -- and a
-- spreadsheet is also how a group shares a plan before anyone opens the game.
-- What was missing was a way to get that back in without retyping it.
--
-- So the import box takes a paste as well as a string. Selecting cells in
-- Google Sheets or Excel and copying them puts tab-separated rows on the
-- clipboard, which is exactly what this reads. Nothing has to be exported,
-- converted, or installed: select, copy, paste.
--
-- The shape it expects, which is the shape the sheet already has:
--
--   Dungeon:  Altar of Fangs
--   Page:     Route 1
--   Enemy:    Ravenous Descendant   Venom Leech
--             Kick the Enrage       Dispel the leech
--             Spread for the cone   Stack for the pull
--
-- A row whose first cell says Dungeon, Page or Enemy is an instruction to this
-- parser. Every other row is callouts, read across into whichever enemies the
-- last Enemy row named. Blank rows separate blocks and mean nothing else, so
-- laying the sheet out to be readable does not change what it imports.
--
-- Deliberately forgiving about everything except structure: a sheet somebody
-- made by hand is going to have stray spaces, empty columns and a missing
-- header, and refusing it over any of those would send them back to typing.
--------------------------------------------------------------------------------

local ADDON, IMI = ...

IMI.Sheet = {}
local Sheet = IMI.Sheet
local Util = IMI.Util

--------------------------------------------------------------------------------
-- Reading the paste
--------------------------------------------------------------------------------

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- One row of comma-separated cells, honouring quotes.
---
--- Only needed for the downloaded-CSV route: copying cells straight out of a
--- spreadsheet gives tabs, which need none of this. But a comma inside a
--- quoted callout is common enough -- "kick, then stack" -- that splitting on
--- every comma would quietly cut callouts in half.
local function csvCells(line)
    local cells, cell, quoted, i = {}, {}, false, 1

    while i <= #line do
        local c = line:sub(i, i)
        if quoted then
            if c == '"' then
                if line:sub(i + 1, i + 1) == '"' then
                    cell[#cell + 1] = '"'
                    i = i + 1
                else
                    quoted = false
                end
            else
                cell[#cell + 1] = c
            end
        elseif c == '"' then
            quoted = true
        elseif c == "," then
            cells[#cells + 1] = table.concat(cell)
            cell = {}
        else
            cell[#cell + 1] = c
        end
        i = i + 1
    end

    cells[#cells + 1] = table.concat(cell)
    return cells
end

--- The paste as a grid of trimmed cells.
---
--- Tabs win wherever they appear: a copy out of a spreadsheet is tab separated
--- and its cells may well contain commas, so guessing commas first would split
--- a callout down the middle.
function Sheet.Grid(text)
    if type(text) ~= "string" then return {} end

    local tabbed = text:find("\t", 1, true) ~= nil
    local rows = {}

    for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local cells = {}
        if tabbed then
            -- Trailing empty cells matter here: they are the columns an enemy
            -- has no callout in, and gmatch would drop them.
            local from = 1
            while true do
                local at = line:find("\t", from, true)
                if not at then
                    cells[#cells + 1] = trim(line:sub(from))
                    break
                end
                cells[#cells + 1] = trim(line:sub(from, at - 1))
                from = at + 1
            end
        else
            for i, cell in ipairs(csvCells(line)) do cells[i] = trim(cell) end
        end
        rows[#rows + 1] = cells
    end

    return rows
end

--------------------------------------------------------------------------------
-- Reading the structure
--------------------------------------------------------------------------------

local function blank(cells)
    for _, cell in ipairs(cells or {}) do
        if cell ~= "" then return false end
    end
    return true
end

local KEYWORDS = {
    dungeon = "dungeon", dungeons = "dungeon",
    page = "page", pages = "page", route = "page",
    enemy = "enemy", enemies = "enemy",
    channel = "channel", chat = "channel",
    color = "color", colour = "color",
}

--- Which keyword a row starts with, if any.
---
--- Accepts what people actually type -- with or without a colon, singular or
--- plural, any case -- and deliberately keeps the list short. "Mob" was in it
--- for one draft, which made a sheet whose first column read "Mob" import
--- nothing at all: a plausible enemy name is a bad keyword.
local function keyword(cell)
    return KEYWORDS[trim(cell):lower():gsub(":%s*$", "")]
end

local function firstFilled(cells, from)
    for i = from or 1, #cells do
        if cells[i] ~= "" then return cells[i] end
    end
    return nil
end

--- A colour written the way a person writes one: #33cc66, or 33cc66.
---
--- Returned as the three numbers the addon stores, or nil, which leaves the
--- dungeon its default rather than making one up from a typo.
function Sheet.Color(text)
    local hex = tostring(text or ""):match("^#?(%x%x%x%x%x%x)$")
    if not hex then return nil end

    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
    }
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- A category in the shape an export carries, so the same code adopts both.
local function newCategory(name)
    local variant = { id = "sheetvar", name = "Default", enemies = {}, pages = {} }
    return {
        id = "sheetcat",
        name = name,
        variants = { variant },
        activeVariant = variant.id,
        _variant = variant,
    }
end

--- Turns a paste into something that can be imported.
---
--- Returns a profile, or nil and a reason. The reason is the message a person
--- sees after a paste that was not a string either, so it says what this
--- wanted rather than that something failed.
function Sheet.Parse(text)
    local rows = Sheet.Grid(text)

    local categories = {}
    local category, page, columns = nil, nil, nil
    local nextId = 0

    local function id(prefix)
        nextId = nextId + 1
        return ("sheet%s%d"):format(prefix, nextId)
    end

    local function ensureCategory()
        if category then return category end
        category = newCategory("Imported")
        categories[#categories + 1] = category
        return category
    end

    for _, cells in ipairs(rows) do
        -- A row starting with # is a note to whoever is filling the sheet in.
        -- Templates are worth nothing without instructions on them, and a
        -- template whose instructions import as an enemy is worse than none.
        if (cells[1] or ""):sub(1, 1) == "#" then
            columns = nil

        elseif blank(cells) then
            -- A blank row ends the current block of enemies, so the next set of
            -- callouts cannot land in the previous block's columns.
            columns = nil
        else
            -- A keyword only counts when something follows it. A lone word in
            -- the first column is a name, whatever it happens to say.
            local word = keyword(cells[1])
            if word and not firstFilled(cells, 2) then word = nil end

            if word == "dungeon" then
                category = newCategory(firstFilled(cells, 2) or "Imported")
                categories[#categories + 1] = category
                page, columns = nil, nil

            elseif word == "page" then
                ensureCategory()
                page = { id = id("page"), name = firstFilled(cells, 2) or "Page",
                         enemyIds = {} }
                category._variant.pages[#category._variant.pages + 1] = page
                columns = nil

            elseif word == "channel" then
                -- Applies to whatever is open: a channel row after a Page row
                -- overrides that page, otherwise the dungeon. The same nesting
                -- the panel uses, so a sheet cannot express something the
                -- interface cannot show.
                ensureCategory()
                local wanted = firstFilled(cells, 2)
                if wanted and not wanted:match("^/") then wanted = "/" .. wanted end
                if page then page.channel = wanted else category.channel = wanted end

            elseif word == "color" then
                ensureCategory()
                category.color = Sheet.Color(firstFilled(cells, 2))

            elseif word == "enemy" then
                ensureCategory()
                columns = {}
                for i = 2, #cells do
                    if cells[i] ~= "" then
                        local enemy = { id = id("enemy"), name = cells[i],
                                        perRow = 1, lines = {} }
                        category._variant.enemies[#category._variant.enemies + 1] = enemy
                        columns[i] = enemy
                        if page then page.enemyIds[#page.enemyIds + 1] = enemy.id end
                    end
                end

            elseif columns then
                for i, enemy in pairs(columns) do
                    local body = cells[i]
                    if body and body ~= "" then
                        enemy.lines[#enemy.lines + 1] =
                            { id = id("line"), caption = "", body = body }
                    end
                end

            else
                -- No Enemy row has been seen in this block, so this one names
                -- the enemies. It is what a sheet with nothing but a header row
                -- of names looks like, and it is worth reading rather than
                -- refusing over a missing keyword.
                ensureCategory()
                columns = {}
                for i = 1, #cells do
                    if cells[i] ~= "" then
                        local enemy = { id = id("enemy"), name = cells[i],
                                        perRow = 1, lines = {} }
                        category._variant.enemies[#category._variant.enemies + 1] = enemy
                        columns[i] = enemy
                        if page then page.enemyIds[#page.enemyIds + 1] = enemy.id end
                    end
                end
            end
        end
    end

    -- Anything with no enemies at all was a heading, a note, or an empty sheet,
    -- and importing it would replace a profile with nothing.
    local kept = {}
    for _, cat in ipairs(categories) do
        cat._variant = nil
        if #cat.variants[1].enemies > 0 then kept[#kept + 1] = cat end
    end

    -- One name and nothing else is a sentence somebody pasted by accident, not
    -- a sheet, and importing it would replace a whole profile with one empty
    -- dungeon. A real sheet is either several columns of names or a column
    -- with callouts under it, so asking for one of those separates the two
    -- without turning away a sheet that is only a list of names so far.
    local names, lines = 0, 0
    for _, cat in ipairs(kept) do
        for _, enemy in ipairs(cat.variants[1].enemies) do
            names = names + 1
            lines = lines + #enemy.lines
        end
    end

    if #kept == 0 or (lines == 0 and names < 2) then
        return nil, "this does not look like an export string or a sheet: "
            .. "put the enemy names in one row and their callouts underneath"
    end

    -- A sheet says nothing about pages unless it was asked to, and a dungeon
    -- with no page has nothing to show in Run.
    for _, cat in ipairs(kept) do
        local variant = cat.variants[1]
        if #variant.pages == 0 then
            local page1 = { id = "sheetpage0", name = "All", enemyIds = {} }
            for _, enemy in ipairs(variant.enemies) do
                page1.enemyIds[#page1.enemyIds + 1] = enemy.id
            end
            variant.pages[1] = page1
        end
    end

    return { categories = kept }, nil, #kept
end

--------------------------------------------------------------------------------
-- Writing one back out
--
-- The other direction, and the one that makes the sheet a place you can work
-- rather than only a place you start. Pasting this into a spreadsheet lands one
-- cell per cell, because that is what a tab-separated paste does everywhere.
--
-- What comes out imports back in unchanged, which is the only property worth
-- guaranteeing here: anything else is a matter of taste about column widths.
--------------------------------------------------------------------------------

local function variantOf(cat)
    if cat.variants then
        for _, variant in ipairs(cat.variants) do
            if variant.id == cat.activeVariant then return variant end
        end
        return cat.variants[1]
    end
    return cat
end

--- Every dungeon in a profile as tab-separated rows.
---
--- Enemies go across in blocks, because a spreadsheet with forty enemies in one
--- row is unreadable and unusable. The block width is the only thing here that
--- is a judgement rather than a rule.
function Sheet.Format(profile, perBlock)
    perBlock = perBlock or 4
    local out = {}

    local function row(...) out[#out + 1] = table.concat({ ... }, "\t") end

    for _, cat in ipairs((profile or {}).categories or {}) do
        local variant = variantOf(cat) or {}

        row("Dungeon:", cat.name or "")
        if cat.channel then row("Channel:", cat.channel) end

        local enemies = variant.enemies or {}
        for from = 1, math.max(1, #enemies), perBlock do
            local block = {}
            for i = from, math.min(from + perBlock - 1, #enemies) do
                block[#block + 1] = enemies[i]
            end
            if #block > 0 then
                local names, deepest = { "Enemy:" }, 0
                for _, enemy in ipairs(block) do
                    names[#names + 1] = enemy.name or ""
                    deepest = math.max(deepest, #(enemy.lines or {}))
                end
                row(unpack(names))

                for line = 1, deepest do
                    local cells = { "" }
                    for _, enemy in ipairs(block) do
                        local body = (enemy.lines or {})[line]
                        cells[#cells + 1] = body and body.body or ""
                    end
                    row(unpack(cells))
                end
                row("")
            end
        end
    end

    return table.concat(out, "\n")
end
