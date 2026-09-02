--------------------------------------------------------------------------------
-- Core: the data model.
--
-- Shape:
--   profile   -> a named set of categories
--   category  -> a dungeon, or a user-made grouping
--   enemy     -> a name plus an ordered list of lines
--   line      -> a caption and the macro text it runs
--   page      -> a named section of the route, holding references to enemies
--
-- Pages hold enemy *ids*, never copies. An enemy on four pages is one
-- definition: edit it anywhere and every page follows.
--
-- Ordered data is stored in arrays so display order is the storage order and
-- reordering is a table move. Ids exist for cross-references, not for lookup
-- order.
--------------------------------------------------------------------------------

local ADDON, MM = ...

MM.Core = {}
local Core = MM.Core
local Util = MM.Util

local DB_VERSION = 1

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------

local function defaultSettings()
    return {
        opacity     = 1.0,
        channel     = "/p",   -- where plain text is sent
        enemySort   = "manual",
        enemySortDesc = false,
        scale       = 1.0,
        buttonScale = 1.0,
        textScale   = 1.0,
        point       = nil,   -- filled in when the frame is first dragged
    }
end

local function defaultProfile()
    return { categories = {} }
end

--- Called once, on load. Never destroys existing data: every field is filled in
--- only if absent, so a partially written or older file is repaired rather than
--- replaced.
function Core.Init(db)
    db = db or {}

    db.version       = db.version or DB_VERSION
    db.settings      = db.settings or defaultSettings()
    db.profiles      = db.profiles or {}
    db.activeProfile = db.activeProfile or "Default"

    -- Backfill any setting added after this file was last written.
    for k, v in pairs(defaultSettings()) do
        if db.settings[k] == nil then db.settings[k] = v end
    end

    if not db.profiles[db.activeProfile] then
        db.profiles[db.activeProfile] = defaultProfile()
    end

    -- Edits since the last export. Surfaced in Edit so an overdue backup is
    -- visible rather than discovered after a crash.
    db.editsSinceExport = db.editsSinceExport or 0

    Core.db = db
    return db
end

function Core.Settings()
    return Core.db.settings
end

--- Bump the counter that drives the export-staleness marker. Every mutation
--- below calls this, so nothing can change without the marker noticing.
local function edited()
    Core.db.editsSinceExport = (Core.db.editsSinceExport or 0) + 1
end

function Core.MarkExported()
    Core.db.editsSinceExport = 0
end

function Core.EditsSinceExport()
    return Core.db.editsSinceExport or 0
end

--------------------------------------------------------------------------------
-- Profiles
--------------------------------------------------------------------------------

function Core.Profile()
    return Core.db.profiles[Core.db.activeProfile]
end

function Core.ProfileNames()
    local names = {}
    for name in pairs(Core.db.profiles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

--- Returns the name actually used, which may be suffixed on a clash. Never
--- overwrites an existing profile.
function Core.CreateProfile(name, seed)
    name = (name and name:match("%S") and name) or "New profile"

    local unique, n = name, 2
    while Core.db.profiles[unique] do
        unique = ("%s (%d)"):format(name, n)
        n = n + 1
    end

    Core.db.profiles[unique] = seed or defaultProfile()
    edited()
    return unique
end

function Core.SetActiveProfile(name)
    if not Core.db.profiles[name] then return false end
    Core.db.activeProfile = name
    return true
end

--- Refuses to delete the last profile: an addon with no profile has nowhere to
--- put anything, and the failure would surface much later as a nil index.
function Core.DeleteProfile(name)
    local count = 0
    for _ in pairs(Core.db.profiles) do count = count + 1 end
    if count <= 1 or not Core.db.profiles[name] then return false end

    Core.db.profiles[name] = nil
    if Core.db.activeProfile == name then
        Core.db.activeProfile = Core.ProfileNames()[1]
    end
    edited()
    return true
end

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------

function Core.Categories()
    return Core.Profile().categories
end

function Core.AddCategory(name)
    local cat = {
        id      = Util.NewId("cat"),
        name    = name or "New category",
        enemies = {},
        pages   = {},
    }
    table.insert(Core.Categories(), cat)
    edited()
    return cat
end

function Core.GetCategory(id)
    return (Util.FindById(Core.Categories(), id))
end

function Core.RenameCategory(id, name)
    local cat = Core.GetCategory(id)
    if not cat or not name or not name:match("%S") then return false end
    cat.name = name
    edited()
    return true
end

function Core.DeleteCategory(id)
    local index = Util.IndexById(Core.Categories(), id)
    if not index then return false end
    table.remove(Core.Categories(), index)
    edited()
    return true
end

function Core.MoveCategory(id, delta)
    local index = Util.IndexById(Core.Categories(), id)
    if not index then return nil end
    edited()
    return Util.Move(Core.Categories(), index, delta)
end

--------------------------------------------------------------------------------
-- Enemies
--------------------------------------------------------------------------------

--- perRow is the layout control that replaced a boss type: 1 stacks the lines
--- vertically, higher fills horizontally then wraps, which is the boss look.
function Core.AddEnemy(catId, name, perRow)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end

    local enemy = {
        id     = Util.NewId("enemy"),
        name   = name or "New enemy",
        perRow = perRow or 1,
        lines  = {},
    }
    table.insert(cat.enemies, enemy)
    edited()
    return enemy
end

function Core.GetEnemy(catId, enemyId)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end
    return (Util.FindById(cat.enemies, enemyId))
end

function Core.RenameEnemy(catId, enemyId, name)
    local enemy = Core.GetEnemy(catId, enemyId)
    if not enemy or not name or not name:match("%S") then return false end
    enemy.name = name
    edited()
    return true
end

function Core.SetEnemyPerRow(catId, enemyId, perRow)
    local enemy = Core.GetEnemy(catId, enemyId)
    if not enemy then return false end
    enemy.perRow = math.max(1, math.min(6, tonumber(perRow) or 1))
    edited()
    return true
end

--- Deleting an enemy must also remove it from every page, or pages keep
--- references to something that no longer exists and the Run view renders a
--- gap it cannot explain.
function Core.DeleteEnemy(catId, enemyId)
    local cat = Core.GetCategory(catId)
    if not cat then return false end

    local index = Util.IndexById(cat.enemies, enemyId)
    if not index then return false end
    table.remove(cat.enemies, index)

    for _, page in ipairs(cat.pages) do
        for i = #page.enemyIds, 1, -1 do
            if page.enemyIds[i] == enemyId then
                table.remove(page.enemyIds, i)
            end
        end
    end

    edited()
    return true
end

function Core.MoveEnemy(catId, enemyId, delta)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end

    local index = Util.IndexById(cat.enemies, enemyId)
    if not index then return nil end

    edited()
    return Util.Move(cat.enemies, index, delta)
end

--- Rewrites the stored order to match a sort.
---
--- Kept separate from *viewing* a sort on purpose. Alphabetising the view is
--- harmless and reversible; alphabetising the stored order throws away a manual
--- arrangement, and that should be something asked for rather than a side
--- effect of changing how the list is displayed.
---
--- This never touches page contents. The order enemies appear in on a page is
--- the page's own, so sorting the library cannot rearrange anything you play
--- with.
function Core.SortEnemies(catId, mode, descending)
    local cat = Core.GetCategory(catId)
    if not cat then return false end

    if mode == "name" then
        table.sort(cat.enemies, function(a, b)
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
    end

    if descending then
        local reversed = {}
        for i = #cat.enemies, 1, -1 do
            reversed[#reversed + 1] = cat.enemies[i]
        end
        cat.enemies = reversed
    end

    edited()
    return true
end

--- The enemies in display order, without disturbing what is stored.
function Core.EnemiesInOrder(catId, mode, descending)
    local cat = Core.GetCategory(catId)
    if not cat then return {} end

    local list = {}
    for i, enemy in ipairs(cat.enemies) do list[i] = enemy end

    if mode == "name" then
        table.sort(list, function(a, b)
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
    end

    if descending then
        local reversed = {}
        for i = #list, 1, -1 do reversed[#reversed + 1] = list[i] end
        list = reversed
    end

    return list
end

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

function Core.AddLine(catId, enemyId, caption, body)
    local enemy = Core.GetEnemy(catId, enemyId)
    if not enemy then return nil end

    local line = {
        id      = Util.NewId("line"),
        caption = caption or "",
        body    = Util.TrimToChars(body or ""),
    }
    table.insert(enemy.lines, line)
    edited()
    return line
end

function Core.GetLine(catId, enemyId, lineId)
    local enemy = Core.GetEnemy(catId, enemyId)
    if not enemy then return nil end
    return (Util.FindById(enemy.lines, lineId))
end

--- Bodies are trimmed on the way in as a backstop. The edit box caps typing at
--- 255 characters, but a path that bypasses it — an import, a paste handled
--- oddly — must not be able to store something the game will truncate later.
function Core.SetLine(catId, enemyId, lineId, caption, body)
    local line = Core.GetLine(catId, enemyId, lineId)
    if not line then return false end

    if caption ~= nil then line.caption = caption end
    if body ~= nil then line.body = Util.TrimToChars(body) end
    edited()
    return true
end

function Core.DeleteLine(catId, enemyId, lineId)
    local enemy = Core.GetEnemy(catId, enemyId)
    if not enemy then return false end

    local index = Util.IndexById(enemy.lines, lineId)
    if not index then return false end

    table.remove(enemy.lines, index)
    edited()
    return true
end

function Core.MoveLine(catId, enemyId, lineId, delta)
    local enemy = Core.GetEnemy(catId, enemyId)
    if not enemy then return nil end

    local index = Util.IndexById(enemy.lines, lineId)
    if not index then return nil end

    edited()
    return Util.Move(enemy.lines, index, delta)
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

function Core.AddPage(catId, name)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end

    local page = {
        id       = Util.NewId("page"),
        name     = name or ("Section " .. (#cat.pages + 1)),
        enemyIds = {},
    }
    table.insert(cat.pages, page)
    edited()
    return page
end

function Core.GetPage(catId, pageId)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end
    return (Util.FindById(cat.pages, pageId))
end

function Core.RenamePage(catId, pageId, name)
    local page = Core.GetPage(catId, pageId)
    if not page or not name or not name:match("%S") then return false end
    page.name = name
    edited()
    return true
end

function Core.DeletePage(catId, pageId)
    local cat = Core.GetCategory(catId)
    if not cat then return false end

    local index = Util.IndexById(cat.pages, pageId)
    if not index then return false end

    table.remove(cat.pages, index)
    edited()
    return true
end

function Core.MovePage(catId, pageId, delta)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end

    local index = Util.IndexById(cat.pages, pageId)
    if not index then return nil end

    edited()
    return Util.Move(cat.pages, index, delta)
end

--------------------------------------------------------------------------------
-- Page contents
--------------------------------------------------------------------------------

--- Adds a reference. The same enemy may appear on several pages, which is the
--- point; it may not appear twice on one page, which would only ever be a
--- misclick.
function Core.AddEnemyToPage(catId, pageId, enemyId)
    local page  = Core.GetPage(catId, pageId)
    local enemy = Core.GetEnemy(catId, enemyId)
    if not page or not enemy then return false end

    for _, id in ipairs(page.enemyIds) do
        if id == enemyId then return false end
    end

    table.insert(page.enemyIds, enemyId)
    edited()
    return true
end

--- Removes from this page only. The definition survives, and so does its
--- presence on other pages.
function Core.RemoveEnemyFromPage(catId, pageId, enemyId)
    local page = Core.GetPage(catId, pageId)
    if not page then return false end

    for i = #page.enemyIds, 1, -1 do
        if page.enemyIds[i] == enemyId then
            table.remove(page.enemyIds, i)
            edited()
            return true
        end
    end
    return false
end

function Core.MoveEnemyOnPage(catId, pageId, enemyId, delta)
    local page = Core.GetPage(catId, pageId)
    if not page then return nil end

    local index
    for i, id in ipairs(page.enemyIds) do
        if id == enemyId then index = i break end
    end
    if not index then return nil end

    edited()
    return Util.Move(page.enemyIds, index, delta)
end

--- The enemies a page shows, resolved and in order. Ids that no longer resolve
--- are skipped rather than rendered as holes; DeleteEnemy already prunes them,
--- so this only matters for data that arrived some other way, such as an
--- import from an older export.
function Core.PageEnemies(catId, pageId)
    local cat  = Core.GetCategory(catId)
    local page = Core.GetPage(catId, pageId)
    if not cat or not page then return {} end

    local out = {}
    for _, id in ipairs(page.enemyIds) do
        local enemy = Util.FindById(cat.enemies, id)
        if enemy then out[#out + 1] = enemy end
    end
    return out
end

--- Every line the category needs buttons for. Used when a category is selected
--- and its buttons are built, which is the only moment they can be written.
function Core.CategoryLines(catId)
    local cat = Core.GetCategory(catId)
    if not cat then return {} end

    local out = {}
    for _, page in ipairs(cat.pages) do
        for _, enemy in ipairs(Core.PageEnemies(catId, page.id)) do
            for _, line in ipairs(enemy.lines) do
                out[#out + 1] = { page = page, enemy = enemy, line = line }
            end
        end
    end
    return out
end
