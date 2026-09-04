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

local ADDON, IMI = ...

IMI.Core = {}
local Core = IMI.Core
local Util = IMI.Util

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
        width       = nil,   -- and these when it is first resized
        height      = nil,
        sidebarCollapsed = false,
        -- The user's own palette, by Style key. Empty means "as shipped".
        colors      = {},
    }
end

local function defaultProfile()
    return { categories = {} }
end

local function newVariant(name)
    return {
        id      = Util.NewId("var"),
        name    = name or "Default",
        enemies = {},
        pages   = {},
    }
end

--- Move a category from holding enemies and pages directly to holding variants
--- that hold them.
---
--- Runs in place and only when the old shape is found, so it is safe on every
--- load and cannot touch data that has already moved. Whatever was there
--- becomes the first variant rather than being rebuilt, so nothing is lost and
--- nothing has to be re-entered.
local function migrateCategory(cat)
    if cat.variants then return end

    local first = newVariant("Default")
    first.enemies = cat.enemies or {}
    first.pages   = cat.pages or {}

    cat.variants = { first }
    cat.activeVariant = first.id
    cat.enemies, cat.pages = nil, nil
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

    for _, profile in pairs(db.profiles) do
        for _, cat in ipairs(profile.categories or {}) do
            migrateCategory(cat)
        end
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
--- Every mutator ends here, which makes it the one place undo has to hook to
--- cover all of them — including any written later by someone who never went
--- looking for a list of them.
local function edited()
    Core.db.editsSinceExport = (Core.db.editsSinceExport or 0) + 1
    if Core.onEdit then Core.onEdit() end
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
    local first = newVariant("Default")
    local cat = {
        id            = Util.NewId("cat"),
        name          = name or "New category",
        variants      = { first },
        activeVariant = first.id,
    }
    table.insert(Core.Categories(), cat)
    edited()
    return cat
end

--------------------------------------------------------------------------------
-- Variants
--
-- A dungeon holds several complete sets of enemies and pages -- one per
-- strategy, key level, or whatever else changes the calls. They share nothing:
-- editing one cannot disturb another, which is the entire point of having them
-- rather than one set with conditional text.
--------------------------------------------------------------------------------

function Core.Variants(catId)
    local cat = Core.GetCategory(catId)
    return cat and cat.variants or {}
end

--- The variant everything else acts on. Falls back to the first, so a category
--- whose active variant was deleted still resolves rather than going blank.
function Core.Variant(catId, variantId)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end
    if variantId then return (Util.FindById(cat.variants, variantId)) end
    return (Util.FindById(cat.variants, cat.activeVariant)) or cat.variants[1]
end

function Core.ActiveVariantId(catId)
    local variant = Core.Variant(catId)
    return variant and variant.id
end

function Core.SetActiveVariant(catId, variantId)
    local cat = Core.GetCategory(catId)
    if not cat or not Util.FindById(cat.variants, variantId) then return false end
    cat.activeVariant = variantId
    return true
end

--- Deep copy, because a variant that shared tables with the one it came from
--- would not be a separate strategy at all: editing either would change both.
local function copyVariantContents(source, target)
    for _, enemy in ipairs(source.enemies) do
        local copy = {
            id     = Util.NewId("enemy"),
            name   = enemy.name,
            perRow = enemy.perRow,
            lines  = {},
        }
        for _, line in ipairs(enemy.lines) do
            copy.lines[#copy.lines + 1] = {
                id      = Util.NewId("line"),
                caption = line.caption,
                body    = line.body,
            }
        end
        target.enemies[#target.enemies + 1] = copy
        -- Remember which new enemy each old one became, so page references can
        -- be remapped instead of pointing back at the original variant.
        enemy.__copyId = copy.id
    end

    for _, page in ipairs(source.pages) do
        local copy = { id = Util.NewId("page"), name = page.name, enemyIds = {} }
        for _, oldId in ipairs(page.enemyIds) do
            local old = Util.FindById(source.enemies, oldId)
            if old and old.__copyId then
                copy.enemyIds[#copy.enemyIds + 1] = old.__copyId
            end
        end
        target.pages[#target.pages + 1] = copy
    end

    for _, enemy in ipairs(source.enemies) do enemy.__copyId = nil end
end

--- `copyFromId` nil gives an empty variant; otherwise the named one is copied
--- whole, enemies, lines, pages and all.
function Core.AddVariant(catId, name, copyFromId)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end

    local variant = newVariant(name or ("Variant " .. (#cat.variants + 1)))

    if copyFromId then
        local source = Util.FindById(cat.variants, copyFromId)
        if source then copyVariantContents(source, variant) end
    end

    table.insert(cat.variants, variant)
    edited()
    return variant
end

function Core.RenameVariant(catId, variantId, name)
    local variant = Core.Variant(catId, variantId)
    if not variant or not name or not name:match("%S") then return false end
    variant.name = name
    edited()
    return true
end

--- Refuses to remove the last one: a dungeon with no variant has nowhere to
--- keep anything, and the failure would surface later as an empty panel.
function Core.DeleteVariant(catId, variantId)
    local cat = Core.GetCategory(catId)
    if not cat or #cat.variants <= 1 then return false end

    local index = Util.IndexById(cat.variants, variantId)
    if not index then return false end

    table.remove(cat.variants, index)
    if cat.activeVariant == variantId then
        cat.activeVariant = cat.variants[1].id
    end
    edited()
    return true
end

--- The active variant's contents. Everything below reads through these, so the
--- rest of the addon never has to know variants exist.
function Core.Enemies(catId)
    local variant = Core.Variant(catId)
    return variant and variant.enemies or {}
end

function Core.Pages(catId)
    local variant = Core.Variant(catId)
    return variant and variant.pages or {}
end

function Core.GetCategory(id)
    return (Util.FindById(Core.Categories(), id))
end

--- A dungeon's own colour, or nil for the addon's usual one.
---
--- One colour per dungeon, not a palette: the rest is derived from it. Picking
--- five colours to describe one dungeon is not a thing anyone wants to do.
function Core.SetCategoryColor(id, color)
    local cat = Core.GetCategory(id)
    if not cat then return false end

    local wanted = IMI.Color.Valid(color) and { color[1], color[2], color[3] } or nil
    local current = cat.color
    local same = (wanted == nil and current == nil)
        or (wanted and current and wanted[1] == current[1]
            and wanted[2] == current[2] and wanted[3] == current[3])
    if same then return true end

    cat.color = wanted
    edited()
    return true
end

function Core.CategoryColor(id)
    local cat = Core.GetCategory(id)
    return cat and IMI.Color.Valid(cat.color) and cat.color or nil
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

--- Move to a position rather than by a step. A drag knows where it was dropped,
--- and turning that back into a delta only to add it again is a chance to be
--- off by one for no gain. Out-of-range targets are clamped rather than
--- refused: the cursor can leave the list, and the nearest end is what was
--- meant.
function Core.MoveCategoryTo(id, target)
    local cats = Core.Categories()
    local index = Util.IndexById(cats, id)
    if not index or #cats == 0 then return nil end

    target = math.floor(tonumber(target) or index)
    if target < 1 then target = 1 end
    if target > #cats then target = #cats end
    if target == index then return index end

    edited()
    return Util.Move(cats, index, target - index)
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
    table.insert(Core.Enemies(catId), enemy)
    edited()
    return enemy
end

function Core.GetEnemy(catId, enemyId)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end
    return (Util.FindById(Core.Enemies(catId), enemyId))
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

    local enemies = Core.Enemies(catId)
    local index = Util.IndexById(enemies, enemyId)
    if not index then return false end
    table.remove(enemies, index)

    for _, page in ipairs(Core.Pages(catId)) do
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

    local enemies = Core.Enemies(catId)
    local index = Util.IndexById(enemies, enemyId)
    if not index then return nil end

    edited()
    return Util.Move(enemies, index, delta)
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

    local variant = Core.Variant(catId)
    if not variant then return false end

    if mode == "name" then
        table.sort(variant.enemies, function(a, b)
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
    end

    if descending then
        local reversed = {}
        for i = #variant.enemies, 1, -1 do
            reversed[#reversed + 1] = variant.enemies[i]
        end
        variant.enemies = reversed
    end

    edited()
    return true
end

--- The enemies in display order, without disturbing what is stored.
function Core.EnemiesInOrder(catId, mode, descending)
    local cat = Core.GetCategory(catId)
    if not cat then return {} end

    local list = {}
    for i, enemy in ipairs(Core.Enemies(catId)) do list[i] = enemy end

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

    local newCaption = (caption ~= nil) and caption or line.caption
    local newBody    = (body ~= nil) and Util.TrimToChars(body) or line.body

    -- Clicking into a box and back out again is not an edit. Recording it
    -- anyway put a step on the undo stack that undid nothing and counted
    -- against the "edits since export" warning.
    if newCaption == line.caption and newBody == line.body then return true end

    line.caption, line.body = newCaption, newBody
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
        name     = name or ("Section " .. (#Core.Pages(catId) + 1)),
        enemyIds = {},
    }
    table.insert(Core.Pages(catId), page)
    edited()
    return page
end

function Core.GetPage(catId, pageId)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end
    return (Util.FindById(Core.Pages(catId), pageId))
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

    local pages = Core.Pages(catId)
    local index = Util.IndexById(pages, pageId)
    if not index then return false end

    table.remove(pages, index)
    edited()
    return true
end

function Core.MovePage(catId, pageId, delta)
    local cat = Core.GetCategory(catId)
    if not cat then return nil end

    local pages = Core.Pages(catId)
    local index = Util.IndexById(pages, pageId)
    if not index then return nil end

    edited()
    return Util.Move(pages, index, delta)
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
        local enemy = Util.FindById(Core.Enemies(catId), id)
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
    for _, page in ipairs(Core.Pages(catId)) do
        for _, enemy in ipairs(Core.PageEnemies(catId, page.id)) do
            for _, line in ipairs(enemy.lines) do
                out[#out + 1] = { page = page, enemy = enemy, line = line }
            end
        end
    end
    return out
end
