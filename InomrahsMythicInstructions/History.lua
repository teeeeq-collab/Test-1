--------------------------------------------------------------------------------
-- History: undo and redo for everything the Edit tab changes.
--
-- Snapshots, not inverse operations. There are twenty-seven places in Core that
-- change stored data, and writing an "unadd", "unmove" and "unsort" for each is
-- twenty-seven chances to get an edge case wrong — a deleted enemy that has to
-- come back at its old index and back onto the three pages that referenced it,
-- say. Copying the whole thing before each change cannot get that wrong, and it
-- is one piece of code rather than twenty-seven.
--
-- The cost is memory, which is why the stack is capped. A profile of eight
-- dungeons fully written out is on the order of tens of kilobytes, so thirty
-- steps is a couple of megabytes at the very worst and typically far less. That
-- is an ordinary amount for an addon to hold, and none of it is ever saved:
-- history lives for the session and starts empty on login.
--
-- Recording hangs off Core's own edit counter rather than off call sites in the
-- UI. Every mutator already calls it, so every mutator is covered, including
-- ones written later by someone who never read this file.
--------------------------------------------------------------------------------

local ADDON, IMI = ...

IMI.History = {}
local History = IMI.History
local Core = IMI.Core

local MAX_STEPS = 30

--- Called after anything moves, so the Undo and Redo buttons can go grey or
--- come back without the UI having to ask on a timer.
History.onChange = nil

local undoStack, redoStack = {}, {}
local baseline                  -- the state as it stands right now
local contextProvider           -- set by the UI: where the user is
local recording = false

--- Deep copy. Keys are strings and numbers and values are plain data, which is
--- all the schema ever holds, so this needs no cycle handling.
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

--- What history covers: the dungeons themselves, and which profile is current.
--- Settings are deliberately outside it. Undo after nudging the opacity slider
--- should take back the last thing you changed about a dungeon, not the slider,
--- and settings have their own reset buttons for that.
local function snapshot()
    return {
        profiles = copy(Core.db.profiles),
        activeProfile = Core.db.activeProfile,
    }
end

local function restore(data)
    -- Copied on the way out as well as in, so the entry left on the stack is
    -- never aliased by the live table and cannot be edited from underneath.
    Core.db.profiles = copy(data.profiles)
    Core.db.activeProfile = data.activeProfile
end

local function context()
    if not contextProvider then return nil end
    local ok, ctx = pcall(contextProvider)
    return ok and ctx or nil
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

--- Starts recording from the state as it stands. Called once the database is
--- loaded, so the first undo goes back to how things were at login.
function History.Init(provider)
    contextProvider = provider or contextProvider
    undoStack, redoStack = {}, {}
    baseline = snapshot()
    recording = true
    Core.onEdit = History.Record
end

--- One step. Pushes the state as it was before this change, tagged with where
--- the user was standing when they made it, which is where undo returns them.
function History.Record()
    if not recording or not baseline then return end

    undoStack[#undoStack + 1] = { data = baseline, context = context() }
    if #undoStack > MAX_STEPS then table.remove(undoStack, 1) end

    baseline = snapshot()

    -- A new change makes any undone future unreachable, which is what every
    -- other editor does and what people expect.
    for i = #redoStack, 1, -1 do redoStack[i] = nil end

    if History.onChange then History.onChange() end
end

--- Runs fn without recording anything it changes, and without disturbing the
--- stacks. For changes that are not the user's edits — loading, migrating.
function History.Silently(fn)
    local was = recording
    recording = false
    local ok, err = pcall(fn)
    recording = was
    baseline = snapshot()
    if not ok then error(err, 0) end
end

--------------------------------------------------------------------------------
-- Stepping
--------------------------------------------------------------------------------

function History.CanUndo() return #undoStack > 0 end
function History.CanRedo() return #redoStack > 0 end
function History.Depth() return #undoStack, #redoStack end

--- Steps one way or the other. Both directions are the same move — pop from one
--- stack, push the current state onto the other, restore — so they are one
--- function and cannot drift apart.
local function step(from, to)
    local entry = table.remove(from)
    if not entry then return nil end

    to[#to + 1] = { data = baseline, context = entry.context }
    if #to > MAX_STEPS then table.remove(to, 1) end

    restore(entry.data)
    baseline = snapshot()
    if History.onChange then History.onChange() end
    return entry.context or false
end

--- Returns where the undone change was made, so the caller can go there; false
--- when the step happened but nothing was recorded about where; nil when there
--- was nothing to undo.
function History.Undo() return step(undoStack, redoStack) end
function History.Redo() return step(redoStack, undoStack) end
