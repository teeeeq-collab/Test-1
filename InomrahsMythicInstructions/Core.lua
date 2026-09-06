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
        -- Paging keys. Global rather than per page: a key that turned the page
        -- on one page and did nothing on the next would be worse than none.
        pageNextKey = nil,
        pagePrevKey = nil,
        toggleKey   = nil,   -- opens and closes the window
        showBindsRun  = true,
        showBindsEdit = true,
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

--- Everything a profile owns, copied.
---
--- The dungeons and the look together: a profile that restored your dungeons
--- but left the previous one's colours and scales behind would not be the
--- thing you saved. Settings that describe the window rather than the profile
--- -- where it is and how big -- are deliberately left out, so loading a
--- profile does not move your window.
local WINDOW_SETTINGS = { point = true, width = true, height = true }

--- Only settings this build knows about, and only where the type matches what
--- it expects.
---
--- A profile can arrive from a string somebody else made, on a version that is
--- not this one. Copying whatever it contains into the live settings would let
--- a stale or hand-edited file put a table where a number belongs, and the
--- failure would surface much later, somewhere unrelated to importing.
local function sanitiseSettings(incoming, into)
    if type(incoming) ~= "table" then return end

    local defaults = defaultSettings()
    for key, default in pairs(defaults) do
        local value = incoming[key]
        if value ~= nil and not WINDOW_SETTINGS[key]
            and (default == nil or type(value) == type(default)) then
            into[key] = Util.DeepCopy(value)
        end
    end
end

function Core.SnapshotProfile()
    local settings = {}
    for key, value in pairs(Core.db.settings) do
        if not WINDOW_SETTINGS[key] then settings[key] = Util.DeepCopy(value) end
    end

    return {
        categories = Util.DeepCopy(Core.Profile().categories or {}),
        settings   = settings,
    }
end

--- Saves what is loaded right now under a name of its own. Returns the name
--- actually used, which may be suffixed if that one was taken.
function Core.SaveProfileAs(name)
    return Core.CreateProfile(name, Core.SnapshotProfile())
end

--- Loads a profile, look and all.
---
--- Separate from SetActiveProfile, which only moves the pointer: import needs
--- to move the pointer without disturbing the settings, and a player switching
--- profiles needs the settings to follow. One function doing both would have to
--- guess which was meant.
function Core.SwitchProfile(name)
    if not Core.SetActiveProfile(name) then return false end

    sanitiseSettings(Core.db.profiles[name].settings, Core.db.settings)
    return true
end

function Core.RenameProfile(from, to)
    to = (to and to:match("%S") and to) or nil
    if not to or not Core.db.profiles[from] or Core.db.profiles[to] then return false end

    Core.db.profiles[to] = Core.db.profiles[from]
    Core.db.profiles[from] = nil
    if Core.db.activeProfile == from then Core.db.activeProfile = to end
    edited()
    return true
end

--- Overwrites what is loaded. This is what import does, and the reason import
--- asks first: nothing here is recoverable afterwards.
function Core.ReplaceProfile(data)
    if type(data) ~= "table" or type(data.categories) ~= "table" then return false end

    local profile = Core.Profile()
    profile.categories = Util.DeepCopy(data.categories)

    if type(data.settings) == "table" then
        sanitiseSettings(data.settings, Core.db.settings)
        profile.settings = Util.DeepCopy(Core.db.settings)
    end

    edited()
    return true
end

--- Which profile is loaded.
function Core.ActiveProfile() return Core.db.activeProfile end

--------------------------------------------------------------------------------
-- Where plain text goes
--
-- One setting for the whole addon was not enough. A raid wants /raid and a key
-- wants /i, and the thing that decides which is the dungeon you opened, not a
-- preference you have to remember to change on the way in. A page wants it
-- narrower still: the same route reads better in /p while people are still
-- gathering and in /i once the timer is running.
--
-- So a channel can be set at three levels and the nearest one wins: the page,
-- then the dungeon, then the master setting. Absent means "whatever the level
-- above says", which is why every override is a toggle and not just a value --
-- there has to be a way to say nothing.
--------------------------------------------------------------------------------

local function validChannel(channel)
    if type(channel) ~= "string" then return nil end
    for _, known in ipairs(Util.CHANNELS) do
        if channel == known then return channel end
    end
    return nil
end

--- What a line on this page actually gets sent to.
---
--- Both arguments are optional: asking with no page answers for the dungeon,
--- and asking with neither answers the master setting. That is what makes this
--- the single place the order is written down.
function Core.ChannelFor(catId, pageId)
    if pageId then
        local page = Core.GetPage(catId, pageId)
        local channel = page and validChannel(page.channel)
        if channel then return channel, "page" end
    end

    if catId then
        local cat = Core.GetCategory(catId)
        local channel = cat and validChannel(cat.channel)
        if channel then return channel, "dungeon" end
    end

    return validChannel(Core.db.settings.channel) or Util.DEFAULT_CHANNEL, "master"
end

--- nil turns the override off, which is not the same as setting it to the
--- channel the level above happens to use today.
function Core.SetCategoryChannel(catId, channel)
    local cat = Core.GetCategory(catId)
    if not cat then return false end

    local wanted = channel and validChannel(channel) or nil
    if cat.channel == wanted then return true end

    cat.channel = wanted
    edited()
    return true
end

function Core.SetPageChannel(catId, pageId, channel)
    local page = Core.GetPage(catId, pageId)
    if not page then return false end

    local wanted = channel and validChannel(channel) or nil
    if page.channel == wanted then return true end

    page.channel = wanted
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
    -- Old line id -> new line id, for remapping the pages afterwards.
    local lineCopies = {}

    for _, enemy in ipairs(source.enemies) do
        local copy = {
            id     = Util.NewId("enemy"),
            name   = enemy.name,
            perRow = enemy.perRow,
            lines  = {},
        }
        for _, line in ipairs(enemy.lines) do
            local newLine = {
                id      = Util.NewId("line"),
                caption = line.caption,
                body    = line.body,
            }
            copy.lines[#copy.lines + 1] = newLine
            lineCopies[line.id] = newLine.id
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

        -- The composition comes too, remapped onto the new ids. Copying the
        -- old ids straight across would leave every entry pointing into the
        -- variant it was copied from: silently inert, and impossible to see.
        if page.lineDisabled then
            for oldLineId in pairs(page.lineDisabled) do
                local newId = lineCopies[oldLineId]
                if newId then
                    copy.lineDisabled = copy.lineDisabled or {}
                    copy.lineDisabled[newId] = true
                end
            end
        end

        if page.lineOverrides then
            for oldLineId, entry in pairs(page.lineOverrides) do
                local newId = lineCopies[oldLineId]
                if newId then
                    copy.lineOverrides = copy.lineOverrides or {}
                    copy.lineOverrides[newId] = {
                        caption = entry.caption, body = entry.body,
                    }
                end
            end
        end

        if page.lineOrder then
            for oldEnemyId, ids in pairs(page.lineOrder) do
                local old = Util.FindById(source.enemies, oldEnemyId)
                if old and old.__copyId then
                    local mapped = {}
                    for _, oldLineId in ipairs(ids) do
                        local newId = lineCopies[oldLineId]
                        if newId then mapped[#mapped + 1] = newId end
                    end
                    if #mapped > 0 then
                        copy.lineOrder = copy.lineOrder or {}
                        copy.lineOrder[old.__copyId] = mapped
                    end
                end
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

    -- The enemy's lines have to be forgotten before the enemy goes, because
    -- afterwards there is nothing left to ask which lines were its.
    local enemy = enemies[index]
    for _, line in ipairs(enemy.lines or {}) do
        Core.ForgetLineOnPages(catId, line.id)
    end
    table.remove(enemies, index)

    for _, page in ipairs(Core.Pages(catId)) do
        for i = #page.enemyIds, 1, -1 do
            if page.enemyIds[i] == enemyId then
                table.remove(page.enemyIds, i)
            end
        end
        if page.lineOrder then
            page.lineOrder[enemyId] = nil
            if not next(page.lineOrder) then page.lineOrder = nil end
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
    Core.ForgetLineOnPages(catId, lineId)
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
        -- Keys are per page, by line: the same key calls a different thing on
        -- each page of the route, which is the whole point of pages.
        binds    = {},
    }
    table.insert(Core.Pages(catId), page)
    edited()
    return page
end

--------------------------------------------------------------------------------
-- Keybinds
--
-- A key belongs to a page and names a line on it. Stored by line id rather than
-- by position, so reordering enemies or deleting one does not silently move a
-- key onto a different callout.
--------------------------------------------------------------------------------

--- The keys set on a page, as { [lineId] = key }. Always a table, so callers
--- need not care whether the page predates this feature.
function Core.PageBinds(catId, pageId)
    local page = Core.GetPage(catId, pageId)
    if not page then return {} end
    page.binds = page.binds or {}
    return page.binds
end

function Core.LineBind(catId, pageId, lineId)
    return Core.PageBinds(catId, pageId)[lineId]
end

--- Sets or clears one key. A key can only mean one thing on a page, so taking
--- it from whatever held it is part of assigning it — leaving both would make
--- which one fires depend on table order.
function Core.SetLineBind(catId, pageId, lineId, key)
    local page = Core.GetPage(catId, pageId)
    if not page or not lineId then return false end
    page.binds = page.binds or {}

    if key == nil or key == "" then
        if page.binds[lineId] == nil then return true end
        page.binds[lineId] = nil
        edited()
        return true
    end

    local taken
    for otherId, otherKey in pairs(page.binds) do
        if otherKey == key and otherId ~= lineId then taken = otherId end
    end
    if taken then page.binds[taken] = nil end

    if page.binds[lineId] == key and not taken then return true end
    page.binds[lineId] = key
    edited()
    return true
end

--- Drops keys pointing at lines that no longer exist. Deleting a line leaves
--- its key behind otherwise, and it would come back the moment a new line
--- happened to be given the same id.
function Core.PruneBinds(catId, pageId)
    local page = Core.GetPage(catId, pageId)
    if not page or not page.binds then return 0 end

    local live = {}
    for _, enemy in ipairs(Core.PageEnemies(catId, pageId)) do
        for _, line in ipairs(enemy.lines) do live[line.id] = true end
    end

    local removed = 0
    for lineId in pairs(page.binds) do
        if not live[lineId] then
            page.binds[lineId] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then edited() end
    return removed
end

--- Every key a line answers to, across the pages it appears on, with the page
--- each belongs to. A line can sit on several pages and take a different key on
--- each, so the Enemies tab — which has no page in view — has to say all of
--- them rather than guess one.
function Core.LineKeys(catId, lineId)
    local out = {}
    for _, page in ipairs(Core.Pages(catId)) do
        local key = page.binds and page.binds[lineId]
        if key then out[#out + 1] = { key = key, page = page.name } end
    end
    return out
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

            -- The page's composition of that enemy goes with it. Keeping it
            -- would quietly restore a months-old arrangement if the enemy were
            -- ever added back, which is not what "add" means.
            if page.lineOrder then
                page.lineOrder[enemyId] = nil
                if not next(page.lineOrder) then page.lineOrder = nil end
            end
            local enemy = Core.GetEnemy(catId, enemyId)
            for _, line in ipairs(enemy and enemy.lines or {}) do
                if page.lineDisabled then page.lineDisabled[line.id] = nil end
                if page.lineOverrides then page.lineOverrides[line.id] = nil end
            end
            if page.lineDisabled and not next(page.lineDisabled) then
                page.lineDisabled = nil
            end
            if page.lineOverrides and not next(page.lineOverrides) then
                page.lineOverrides = nil
            end

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

--------------------------------------------------------------------------------
-- Page composition: what a page does with the lines it inherits
--
-- A page holds enemies by id and, until now, nothing else: every enemy brought
-- all of its lines, in the enemy's own order, with the enemy's own wording. A
-- page could therefore only ever be a subset of enemies, never a composition.
--
-- Three sparse tables change that, and sparse is the point. Absence means
-- inherit, so a page that has never been composed stores nothing at all and
-- reads exactly as it did before:
--
--     page.lineDisabled  = { [lineId] = true }
--     page.lineOrder     = { [enemyId] = { lineId, lineId, ... } }
--     page.lineOverrides = { [lineId] = { caption = ..., body = ... } }
--
-- Overrides are per field. A page that renames a callout keeps inheriting its
-- body, so fixing a typo in the enemy's wording still reaches every page that
-- did not deliberately rewrite it. That means presence has to be tested rather
-- than truth: an override of "" is a deliberate empty caption, not an absent
-- one, and `overrides.caption or line.caption` would silently discard it.
--------------------------------------------------------------------------------

--- The disabled set for a page, created on demand.
local function disabledSet(page, create)
    if not page.lineDisabled and create then page.lineDisabled = {} end
    return page.lineDisabled
end

function Core.IsLineEnabledOnPage(catId, pageId, lineId)
    local page = Core.GetPage(catId, pageId)
    if not page or not page.lineDisabled then return true end
    return page.lineDisabled[lineId] ~= true
end

function Core.SetLineEnabledOnPage(catId, pageId, lineId, enabled)
    local page = Core.GetPage(catId, pageId)
    if not page then return false end

    if enabled then
        if page.lineDisabled then
            page.lineDisabled[lineId] = nil
            if not next(page.lineDisabled) then page.lineDisabled = nil end
        end
    else
        disabledSet(page, true)[lineId] = true
    end
    edited()
    return true
end

--- The order a page shows one enemy's lines in, as line tables.
---
--- Resolution, in this order: the ids the page listed that still exist, then
--- every source line the page has not listed, in the enemy's own order. So a
--- line added to the enemy after the page was composed appears at the end
--- rather than vanishing, and a line deleted from the enemy leaves no hole.
function Core.PageLineOrder(catId, pageId, enemyId)
    local enemy = Core.GetEnemy(catId, enemyId)
    if not enemy then return {} end

    local page = Core.GetPage(catId, pageId)
    local order = page and page.lineOrder and page.lineOrder[enemyId]
    if not order then return enemy.lines end

    local out, seen = {}, {}
    for _, id in ipairs(order) do
        local line = Util.FindById(enemy.lines, id)
        if line and not seen[id] then
            out[#out + 1] = line
            seen[id] = true
        end
    end
    for _, line in ipairs(enemy.lines) do
        if not seen[line.id] then out[#out + 1] = line end
    end
    return out
end

function Core.HasPageLineOrder(catId, pageId, enemyId)
    local page = Core.GetPage(catId, pageId)
    return (page and page.lineOrder and page.lineOrder[enemyId]) ~= nil
end

--- Move a line to an absolute position within its enemy, on this page only.
---
--- Writes the full resolved order rather than a delta, so the stored list is
--- always complete and the next reader does not have to merge anything.
function Core.MoveLineOnPageTo(catId, pageId, enemyId, lineId, target)
    local page = Core.GetPage(catId, pageId)
    if not page then return nil end

    local lines = Core.PageLineOrder(catId, pageId, enemyId)
    local from
    for i, line in ipairs(lines) do
        if line.id == lineId then from = i break end
    end
    if not from then return nil end

    target = math.max(1, math.min(#lines, target or from))
    if target == from then return from end

    local ids = {}
    for _, line in ipairs(lines) do ids[#ids + 1] = line.id end
    table.remove(ids, from)
    table.insert(ids, target, lineId)

    page.lineOrder = page.lineOrder or {}
    page.lineOrder[enemyId] = ids
    edited()
    return target
end

function Core.ResetPageLineOrder(catId, pageId, enemyId)
    local page = Core.GetPage(catId, pageId)
    if not page or not page.lineOrder then return false end

    page.lineOrder[enemyId] = nil
    if not next(page.lineOrder) then page.lineOrder = nil end
    edited()
    return true
end

--- Move an enemy to an absolute position on the page.
function Core.MoveEnemyOnPageTo(catId, pageId, enemyId, target)
    local page = Core.GetPage(catId, pageId)
    if not page then return nil end

    local from
    for i, id in ipairs(page.enemyIds) do
        if id == enemyId then from = i break end
    end
    if not from then return nil end

    target = math.max(1, math.min(#page.enemyIds, target or from))
    if target == from then return from end

    table.remove(page.enemyIds, from)
    table.insert(page.enemyIds, target, enemyId)
    edited()
    return target
end

--------------------------------------------------------------------------------
-- Overrides
--------------------------------------------------------------------------------

function Core.HasLineOverride(catId, pageId, lineId, field)
    local page = Core.GetPage(catId, pageId)
    local entry = page and page.lineOverrides and page.lineOverrides[lineId]
    if not entry then return false end
    if field then return entry[field] ~= nil end
    return entry.caption ~= nil or entry.body ~= nil
end

--- Set or clear one field of a page-specific override.
---
--- `nil` clears the field and lets it inherit again; the empty string is a
--- value, not a clear.
function Core.SetLineOverride(catId, pageId, lineId, field, value)
    if field ~= "caption" and field ~= "body" then return false end

    local page = Core.GetPage(catId, pageId)
    if not page then return false end

    if value == nil then
        local entry = page.lineOverrides and page.lineOverrides[lineId]
        if not entry then return false end
        entry[field] = nil
        if not next(entry) then page.lineOverrides[lineId] = nil end
        if not next(page.lineOverrides) then page.lineOverrides = nil end
    else
        if field == "body" then value = Util.TrimToChars(value) end
        page.lineOverrides = page.lineOverrides or {}
        page.lineOverrides[lineId] = page.lineOverrides[lineId] or {}
        page.lineOverrides[lineId][field] = value
    end
    edited()
    return true
end

function Core.ResetLineOverride(catId, pageId, lineId)
    local page = Core.GetPage(catId, pageId)
    if not page or not page.lineOverrides then return false end
    if not page.lineOverrides[lineId] then return false end

    page.lineOverrides[lineId] = nil
    if not next(page.lineOverrides) then page.lineOverrides = nil end
    edited()
    return true
end

--- One line as a given page sees it.
---
--- Returns a fresh table rather than the stored line, so a caller that writes
--- to what it is handed cannot accidentally edit the source through a page.
function Core.ResolveLine(catId, pageId, enemyId, lineId)
    local line = Core.GetLine(catId, enemyId, lineId)
    if not line then return nil end

    local page = Core.GetPage(catId, pageId)
    local entry = page and page.lineOverrides and page.lineOverrides[lineId]

    local caption = line.caption
    local body    = line.body
    if entry then
        if entry.caption ~= nil then caption = entry.caption end
        if entry.body ~= nil then body = entry.body end
    end

    return {
        id           = line.id,
        caption      = caption,
        body         = body,
        isMacro      = Util.IsMacroLine(body),
        enabled      = Core.IsLineEnabledOnPage(catId, pageId, lineId),
        bind         = Core.LineBind(catId, pageId, lineId),
        captionLocal = entry ~= nil and entry.caption ~= nil,
        bodyLocal    = entry ~= nil and entry.body ~= nil,
    }
end

--- Every line the page shows for one enemy, resolved and in page order,
--- including the disabled ones. This is what the Page Builder draws: a disabled
--- callout stays visible and reorderable, it simply does not reach Run.
function Core.PageEditorLines(catId, pageId, enemyId)
    local out = {}
    for _, line in ipairs(Core.PageLineOrder(catId, pageId, enemyId)) do
        out[#out + 1] = Core.ResolveLine(catId, pageId, enemyId, line.id)
    end
    return out
end

--- The same list, enabled only. This is what Run builds buttons from, what
--- Preview draws and what the fit calculation measures -- one resolved truth,
--- so a page cannot look different in the three places that show it.
function Core.PageRunLines(catId, pageId, enemyId)
    local out = {}
    for _, resolved in ipairs(Core.PageEditorLines(catId, pageId, enemyId)) do
        if resolved.enabled then out[#out + 1] = resolved end
    end
    return out
end

--- How many of an enemy's lines on this page are active, and how many exist.
function Core.PageLineCounts(catId, pageId, enemyId)
    local total, active = 0, 0
    for _, resolved in ipairs(Core.PageEditorLines(catId, pageId, enemyId)) do
        total = total + 1
        if resolved.enabled then active = active + 1 end
    end
    return active, total
end

--- Chat callouts and macros for one enemy, for the navigator's two badges.
function Core.EnemyLineCounts(catId, enemyId)
    local enemy = Core.GetEnemy(catId, enemyId)
    if not enemy then return 0, 0 end

    local chat, macro = 0, 0
    for _, line in ipairs(enemy.lines) do
        if Util.IsMacroLine(line.body) then macro = macro + 1 else chat = chat + 1 end
    end
    return chat, macro
end

--------------------------------------------------------------------------------

--- Forget everything every page recorded about a line.
---
--- Called wherever a line stops existing. A stale disabled flag is invisible
--- until an id is reused; a stale override would then apply someone else's
--- wording to an unrelated callout.
local function forgetLine(catId, lineId)
    for _, page in ipairs(Core.Pages(catId)) do
        if page.lineDisabled then
            page.lineDisabled[lineId] = nil
            if not next(page.lineDisabled) then page.lineDisabled = nil end
        end
        if page.lineOverrides then
            page.lineOverrides[lineId] = nil
            if not next(page.lineOverrides) then page.lineOverrides = nil end
        end
        if page.lineOrder then
            for enemyId, ids in pairs(page.lineOrder) do
                for i = #ids, 1, -1 do
                    if ids[i] == lineId then table.remove(ids, i) end
                end
                if #ids == 0 then page.lineOrder[enemyId] = nil end
            end
            if not next(page.lineOrder) then page.lineOrder = nil end
        end
    end
end

Core.ForgetLineOnPages = forgetLine

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
