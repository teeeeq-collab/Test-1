-- Overlap. Every overlap this addon has shipped was two anchors whose
-- arithmetic nobody added up; the harness now adds it up, so these are checked
-- rather than eyeballed in a screenshot.
local realPrint = print
package.path = "tests/?.lua;" .. package.path
local stub = require("wowstub")
stub.install()
local geom = require("geometry")

local IMI = {}
for _, f in ipairs({ "Libs/LibStub/LibStub", "Libs/LibDeflate/LibDeflate",
                     "Libs/LibSerialize/LibSerialize" }) do
    loadfile("InomrahsMythicInstructions/" .. f .. ".lua")()
end
for _, f in ipairs({ "Util", "Color", "Style", "Core", "History", "Runtime", "UI",
                     "Picker", "Binds", "Edit", "Export", "Sheet", "Starter", "Capture" }) do
    local chunk, err = loadfile("InomrahsMythicInstructions/" .. f .. ".lua")
    if not chunk then realPrint("  FAIL loading " .. f .. ": " .. tostring(err)); os.exit(1) end
    chunk("InomrahsMythicInstructions", IMI)
end

local pass, fail = 0, 0
local function ck(label, cond, got)
    if cond then pass = pass + 1
    else fail = fail + 1; realPrint("  FAIL: " .. label .. (got and ("\n         " .. tostring(got)) or "")) end
end

InomrahsMythicInstructionsDB = IMI.Core.Init({})
IMI.UI.Init()

local cat = IMI.Core.AddCategory("Overlap check")
local mob = IMI.Core.AddEnemy(cat.id, "Mob")
IMI.Core.AddLine(cat.id, mob.id, "", "/p one")
local page = IMI.Core.AddPage(cat.id, "Route")
IMI.Core.AddEnemyToPage(cat.id, page.id, mob.id)

IMI.UI.Show("edit")
IMI.UI.SelectCategory(cat.id)
IMI.Edit.SetCategory(cat.id)

--- Checks a named set of widgets against each other.
---
--- Only what is on screen: two frames may share a rectangle happily as long as
--- they are never shown together, which is how the Enemies and Pages panels
--- work.
local function noOverlaps(what, widgets)
    geom.resetAll(IMI.UI.root, stub)

    -- Pairs a group declares as deliberate overlays, exempted by name rather
    -- than by leaving either widget out of the check entirely.
    local allowed = {}
    for _, pair in ipairs(widgets.__allow or {}) do allowed[pair] = true end

    local resolved = {}
    for name, frame in pairs(widgets) do
        if name ~= "__allow" and frame and frame:IsVisible() then
            local rect, why = geom.rect(frame)
            if rect then
                resolved[#resolved + 1] = { name = name, rect = rect }
            else
                realPrint(("         (%s: %s unresolved — %s)"):format(what, name, tostring(why)))
            end
        end
    end

    local clashes = {}
    for i = 1, #resolved do
        for j = i + 1, #resolved do
            -- A pixel of slack: borders are drawn one pixel outside their
            -- frame and a shared edge is not an overlap.
            local a, b = resolved[i].name, resolved[j].name
            if geom.overlaps(resolved[i].rect, resolved[j].rect, 1)
                and not (allowed[a .. ":" .. b] or allowed[b .. ":" .. a]) then
                clashes[#clashes + 1] = ("%s %s  and  %s %s"):format(
                    resolved[i].name, geom.describe(resolved[i].rect),
                    resolved[j].name, geom.describe(resolved[j].rect))
            end
        end
    end

    ck(what .. ": nothing overlaps", #clashes == 0, table.concat(clashes, "\n         "))
    ck(what .. ": something was actually checked", #resolved >= 2, #resolved)
end

--------------------------------------------------------------------------------
-- The Edit header. This is where both reported overlaps were: the Pages panel
-- started level with the tab buttons, and the character counter and the
-- unbacked-edits marker sat on top of the variant buttons.
--------------------------------------------------------------------------------
IMI.Edit.ShowTab("enemies")
local header = IMI.Edit.HeaderWidgets()
noOverlaps("Edit header, Enemies tab", header)

IMI.Edit.ShowTab("pages")
noOverlaps("Edit header, Pages tab", IMI.Edit.HeaderWidgets())

-- With the counter showing, which is what happens the moment a box has focus.
IMI.Edit.ShowTab("enemies")
local widgets = IMI.Edit.HeaderWidgets()
widgets.counter:Show()
widgets.stale:Show()
noOverlaps("Edit header with the counter and marker showing", widgets)

--------------------------------------------------------------------------------
-- The bar, and the window's own furniture.
--------------------------------------------------------------------------------
noOverlaps("Title bar", IMI.UI.BarWidgets())

--------------------------------------------------------------------------------
-- The dungeon column: the list must end above the stack pinned under it.
--------------------------------------------------------------------------------
IMI.UI.RefreshSidebar()
noOverlaps("Dungeon column", IMI.UI.SidebarWidgets())

--------------------------------------------------------------------------------
-- The rest of it: each panel's own controls, and the row along the bottom.
--------------------------------------------------------------------------------
IMI.Edit.ShowTab("pages")
noOverlaps("Pages panel controls", IMI.Edit.PagesPanelWidgets())

IMI.Edit.ShowTab("enemies")
noOverlaps("Enemies panel controls", IMI.Edit.EnemiesPanelWidgets())
noOverlaps("Edit bottom row", IMI.Edit.BottomRowWidgets())

--------------------------------------------------------------------------------
-- Run: the title shares its strip with the page arrows and the variant chooser.
--------------------------------------------------------------------------------
IMI.UI.Show("run")
IMI.UI.OpenRun(cat.id)
noOverlaps("Run view", IMI.UI.RunWidgets())

-- And with a name long enough to reach for the arrows.
IMI.Core.RenameCategory(cat.id, "A Dungeon With A Very Long Name Indeed Yes")
IMI.UI.OpenRun(cat.id)
noOverlaps("Run view with a long dungeon name", IMI.UI.RunWidgets())
IMI.Core.RenameCategory(cat.id, "Overlap check")

--------------------------------------------------------------------------------
-- The dialogs.
--------------------------------------------------------------------------------
IMI.UI.Show("edit")
IMI.Edit.SetCategory(cat.id)
IMI.UI.Confirm({ title = "Delete dungeon", body = "Really?", accept = "Delete" })
local confirm = IMI.UI.ConfirmFrame().dialog
noOverlaps("Confirmation dialog",
    { title = confirm.title, body = confirm.body,
      accept = confirm.accept, cancel = confirm.cancel })
IMI.UI.ConfirmFrame():Hide()

IMI.Edit.ShowColorPicker()
local picker = IMI.Picker.Frame().dialog
noOverlaps("Colour picker",
    { title = picker.title, field = picker.field, hue = picker.hue,
      swatch = picker.swatchFrame, reset = picker.reset, close = picker.close,
      hueSlider = picker.rows.hue.slider, hueBox = picker.rows.hue.box,
      satSlider = picker.rows.sat.slider, satBox = picker.rows.sat.box,
      valSlider = picker.rows.val.slider, valBox = picker.rows.val.box })
IMI.Picker.Frame():Hide()

IMI.Edit.ShowTab("pages")
IMI.Binds.Open(cat.id, page.id)
local binds = IMI.Binds.Frame().dialog
noOverlaps("Keybind dialog",
    { title = binds.title, help = binds.help, list = binds.scroll,
      clearAll = binds.clearAll, close = binds.close })
IMI.Binds.Frame():Hide()

--------------------------------------------------------------------------------
-- The chat-channel overrides.
--
-- Both dropdowns are hidden until their toggle is on, so a sweep taken with
-- them off checks the half of the row that cannot collide with anything. These
-- turn them on first.
--------------------------------------------------------------------------------

local function withOverridesOn()
    IMI.Core.SetCategoryChannel(cat.id, "/raid")
    IMI.Core.SetPageChannel(cat.id, page.id, "/i")
    IMI.Edit.SetCategory(cat.id)
    IMI.Edit.ShowTab("pages")
    IMI.Edit.RefreshPages()
end

withOverridesOn()
noOverlaps("Edit header with the dungeon override showing", IMI.Edit.HeaderWidgets())
noOverlaps("Pages panel with the page override showing", IMI.Edit.PagesPanelWidgets())
noOverlaps("Both channel overrides", IMI.Edit.ChannelWidgets())

IMI.Edit.ShowTab("enemies")
noOverlaps("Enemies panel with the dungeon override showing",
    IMI.Edit.EnemiesPanelWidgets())

IMI.Core.SetCategoryChannel(cat.id, nil)
IMI.Core.SetPageChannel(cat.id, page.id, nil)
IMI.Edit.SetCategory(cat.id)

--------------------------------------------------------------------------------
-- Settings: the Profile row, which is the busiest row in the addon.
--------------------------------------------------------------------------------
IMI.UI.Show("settings")
noOverlaps("Profile row", IMI.UI.ProfileWidgets())

IMI.UI.Show("edit")
IMI.Edit.SetCategory(cat.id)

--------------------------------------------------------------------------------
-- The window at its smallest.
--
-- Every overlap check above ran at the default size, where there is room to
-- spare, so the whole class of "fine until you make it narrow" went unseen: at
-- the minimum width the page row ran past the panel and "page 1 of 2" was
-- drawn through the Keybinds button. Narrow is where rows collide, so narrow
-- is where they are checked.
--------------------------------------------------------------------------------

IMI.UI.root:SetSize(IMI.UI.MinSize())
IMI.UI.Relayout()

IMI.UI.Show("edit")
IMI.Edit.SetCategory(cat.id)

IMI.Edit.ShowTab("pages")
noOverlaps("Pages panel at the minimum width", IMI.Edit.PagesPanelWidgets())

withOverridesOn()
noOverlaps("Edit header at the minimum width with the override showing",
    IMI.Edit.HeaderWidgets())
noOverlaps("Pages panel at the minimum width with the override showing",
    IMI.Edit.PagesPanelWidgets())
IMI.Core.SetCategoryChannel(cat.id, nil)
IMI.Core.SetPageChannel(cat.id, page.id, nil)
IMI.Edit.SetCategory(cat.id)
noOverlaps("Edit header at the minimum width, Pages tab", IMI.Edit.HeaderWidgets())

IMI.Edit.ShowTab("enemies")
noOverlaps("Enemies panel at the minimum width", IMI.Edit.EnemiesPanelWidgets())
noOverlaps("Edit header at the minimum width, Enemies tab", IMI.Edit.HeaderWidgets())
noOverlaps("Edit bottom row at the minimum width", IMI.Edit.BottomRowWidgets())

noOverlaps("Title bar at the minimum width", IMI.UI.BarWidgets())

-- Overlap is not the only way a row goes wrong at a narrow window. The
-- Settings page is a fixed-width scroll child that only scrolls up and down,
-- so a control past the right edge of the panel is not merely ugly: it cannot
-- be clicked at all.
IMI.UI.Show("settings")
noOverlaps("Profile row at the minimum width", IMI.UI.ProfileWidgets())

do
    local panel = geom.rect(IMI.UI.SettingsScroll())
    local out = {}
    for name, frame in pairs(IMI.UI.ProfileWidgets()) do
        local r = frame and geom.rect(frame)
        if r and panel and r.right > panel.right + 1 then
            out[#out + 1] = ("%s reaches %d, panel ends at %d")
                :format(name, r.right, panel.right)
        end
    end
    ck("Profile row: every control is reachable at the minimum width",
        #out == 0, table.concat(out, "\n         "))
end
IMI.UI.Show("edit")
noOverlaps("Dungeon column at the minimum width", IMI.UI.SidebarWidgets())

IMI.UI.Show("run")
IMI.UI.OpenRun(cat.id)
noOverlaps("Run view at the minimum width", IMI.UI.RunWidgets())

IMI.UI.root:SetSize(760, 380)
IMI.UI.Relayout()
IMI.UI.Show("edit")
IMI.Edit.SetCategory(cat.id)

--------------------------------------------------------------------------------
-- Overflow.
--
-- A dungeon with more enemies than the window is tall drew the extra cards
-- straight through the bottom edge and onto the game world: a plain frame does
-- not clip its children, and nothing else was stopping them. The cards live in
-- a scroll frame now, so this checks the two things that makes true -- that
-- they are inside something that clips, and that the scroll range is the
-- height that was actually laid out, not a guess.
--------------------------------------------------------------------------------

IMI.UI.Show("run")

local scroll, child = IMI.UI.RunScroll()
ck("Run: the callouts are in a scroll frame",
    scroll ~= nil and scroll.frameType == "ScrollFrame",
    scroll and scroll.frameType or "no scroll frame")
ck("Run: and it is the thing they are laid out in",
    scroll and scroll:GetScrollChild() == child, "the scroll child is not the page host")

-- Few enough to fit: nothing to scroll, and no bar for it.
IMI.UI.OpenRun(cat.id)
ck("Run: a dungeon that fits has nothing to scroll",
    child:GetHeight() <= scroll:GetHeight() + 1,
    ("child %s vs visible %s"):format(child:GetHeight(), scroll:GetHeight()))
ck("Run: and no scroll bar", scroll.ScrollBar and scroll.ScrollBar.shown == false,
    "the bar is showing for content that fits")

-- More than fits. This is the shape that used to draw over the game world.
for i = 1, 24 do
    local e = IMI.Core.AddEnemy(cat.id, "Overflow mob " .. i)
    IMI.Core.AddLine(cat.id, e.id, "", "/p line " .. i)
    IMI.Core.AddEnemyToPage(cat.id, page.id, e.id)
end
IMI.UI.OpenRun(cat.id)

ck("Run: a dungeon that overflows can be scrolled",
    child:GetHeight() > scroll:GetHeight(),
    ("child %s vs visible %s"):format(child:GetHeight(), scroll:GetHeight()))
ck("Run: and the bar appears to say so",
    scroll.ScrollBar and scroll.ScrollBar.shown == true,
    "no bar for content taller than the panel")

-- The scroll child is what clips, so nothing may be anchored above its top.
-- The page name used to be, and would now be invisible rather than clipped.
local pageFrame = IMI.Runtime.Page(1)
ck("Run: the page name is inside the scrolled area, not above it",
    pageFrame and pageFrame.title
        and (pageFrame.title.points[1] or {}).point == "TOPLEFT",
    "the page title is anchored outside the scroll child")

--------------------------------------------------------------------------------
-- Text that is longer than the space for it.
--
-- A label with a left anchor and no right one is as wide as its text, so a long
-- enemy name ran straight through the buttons beside it and off the panel.
-- Bounding it is what makes the ellipsis happen.
--------------------------------------------------------------------------------

IMI.UI.Show("edit")
IMI.Edit.SetCategory(cat.id)
IMI.Edit.ShowTab("pages")
IMI.Core.RenameEnemy(cat.id, mob.id,
    "An Enemy Whose Name Is Far Longer Than The Row It Has To Fit Inside")
IMI.Edit.RefreshPages()

local rows = IMI.Edit.PageRows()
local bounded, unbounded = 0, {}
for _, f in ipairs(rows) do
    if f:IsVisible() and f.text then
        local right = nil
        for _, p in ipairs(f.text.points or {}) do
            if p.point == "RIGHT" then right = p end
        end
        if right then bounded = bounded + 1 else unbounded[#unbounded + 1] = f.text.text end
    end
end
ck("Pages panel: every row label is bounded on the right", #unbounded == 0,
    table.concat(unbounded, " / "))
ck("Pages panel: and rows were actually checked", bounded > 0, bounded)

realPrint(("\nlayout: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
