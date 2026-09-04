# Inomrah's Mythic Instructions

A personal Mythic+ callout addon for WoW Midnight (12.1). A small panel of
labelled buttons, each firing a macro — one short instruction to the party —
organised into a page per dungeon section, so callouts are pressed by sight
rather than recalled as numpad positions.

`DESIGN.md` records the design and, more usefully, the behaviour measured on the
live client that shaped it.

## Installing

**If you have an older `MythicMacros` folder installed, delete it first.** The
addon was renamed, folder and all; leaving both in place means two copies
registering the same panel. Anything saved under the old name is not carried
over — the rename was made while there was nothing worth keeping.

Copy the `InomrahsMythicInstructions` folder into:

```
World of Warcraft/_retail_/Interface/AddOns/
```

Fully restart the client — WoW only scans for new addon folders at startup.

## Using it

`/imi` opens the panel. (`/mm` is deliberately not claimed — that is Mythic
Mentor's.) The bar carries **Run**, **Edit** and **Settings**, and
collapses with the `-` button to a strip.

**Start here:** `/imi starter` creates the eight Season 2 dungeons with a page
skeleton each. `/imi demo` instead creates one sample dungeon with content in it,
covering the shapes that matter — a one-line enemy, a two-line one, a boss laid
out three across, and one enemy shared between two pages.

### Colours

**Settings → Colours** sets the palette for the whole addon: panel edges,
headings, selection, text and faint text, each with its own picker and its own
**Reset**. **Reset colours** puts all five back.

**Edit → Dungeon UI Color** gives one dungeon its own colour, laid over that
palette while that dungeon is open. It colours the headings, the panel edges and
the selection highlight, so you can tell at a glance which dungeon you are in.
It deliberately does not touch the callouts themselves, or the dungeon names in
the list on the left. **Reset** in the picker clears it.

The picker has a saturation/brightness field, a hue strip beside it, and Hue,
Saturation and Brightness sliders with typed values. A bar on the strip shows
which hue you are on and a ring on the field shows where the colour sits; both
follow the sliders as well as the mouse. Changes apply as you make
them, on the real interface rather than on a preview square. A colour picked
very dark is lifted where it is used as text — the point of colouring a dungeon
is to recognise it, not to hide it.

**Opacity** fades the panels only. Text and the rules around buttons stay fully
visible at any opacity, which is the point of a see-through window.

### The window

Drag the **right edge** for width, the **bottom edge** for height, the
**bottom-right corner** for both. The size is remembered. Both are out of combat
only: the game does not let an addon move or resize a window holding protected
buttons mid-fight, and the restricted environment cannot do it either — measured
on 12.1.0, not assumed. The dungeon list keeps
its width — everything you gain goes to the panel beside it.

The **`<` on the divider** folds the dungeon list away when you want the whole
window for the panel. That is remembered too.

Both are out-of-combat only: they move Run's buttons, and that is refused
mid-fight.

**Text scale** in Settings now covers the whole addon, not just the callout
buttons in Run.

Made short enough, the dungeon column drops the hint under the list rather than
squeezing the list — the same two gestures are on the **Dungeons** heading's
hover text.

Lists answer the **mouse wheel**, and their scroll bars appear only when there
is something to scroll.

### In combat

The window holds the callout buttons, which are protected: the game does not let
an addon hide, move or resize a frame containing those while you are in combat.
That restriction is the whole reason the callouts work at all, so it is worked
with rather than around.

**Works in a pull:** pressing callouts, the page arrows, closing the window with
the **X**, dragging it by the title bar, and dragging its edges to resize. These
go through the game's restricted environment, which is allowed to do what a
plain addon script is not.

**Waits for the end of the pull:** switching between Run, Edit and Settings. Ask
for it during combat and it is remembered and done the moment combat drops —
it used to half-happen, drawing Edit underneath Run's callouts. A resize during
combat keeps the new size immediately; only the re-flow of the callouts waits.

**Refused in a pull:** collapsing the window to its bar, folding the dungeon
list away, undo and redo, and reopening the window with `/imi` once it is
closed. Each says so rather than failing quietly.

### The dungeon list

The list on the left is the same in Run and Edit, but only Edit lets you change
it. In Edit each row can be:

- **renamed** — double-click the name and type over it. Enter or clicking away
  keeps the change, Escape abandons it. A name too long for the row is cut off
  with an ellipsis; hover the row to read the whole thing.
- **reordered** — drag a row up or down. An orange line shows where it will
  land; drop past either end to send it to the top or the bottom.
- **deleted** — the red `x` at the right of the row. It asks first, naming the
  dungeon, with **Cancel** and **Delete**. Escape is the same as Cancel.

Deleting a dungeon takes every variant, enemy, line and page in it, and nothing
undoes that — export the profile first if you might want it back. The one time
it is refused is deleting the dungeon you are currently running, in combat:
its buttons are on screen and hiding those mid-fight is not allowed.

Run shows the same list with none of this attached, so a slipped drag or a stray
double-click mid-key cannot rearrange anything.

### Writing a callout

The line boxes wrap rather than scrolling sideways: two lines when you are
reading them, up to six while you are typing into one, and the card grows to
make room. A newline can never reach the macro — pressing Enter tidies the text,
saves, and lets go, exactly as it did before.

### Keybinds

**Edit → Pages → Keybinds** gives the callouts on a page their own keys. Click
**Set** on a row, press the key; right-click a key to clear it. Escape cancels.

A key belongs to **that page**. The same key calls a different callout on each
page of a route, which is what makes paging worth having — one hand position for
a whole dungeon instead of eighteen numpad positions to remember.

**Next page** and **Previous page** are in the same list and are the exception:
they are shared by every page, because a key that turned the page on one page
and did nothing on the next would be worse than no key at all.

A key can only mean one thing on a page — assigning one that is taken moves it,
and says so. Keys follow the callout, not its position, so reordering enemies
never quietly moves a key onto something else. **Clear this page** empties a
page's keys and leaves the two paging keys alone.

A callout with a key wears it in a small box in its top-left corner, sized to
what it says — "E" and "CTRL+E" are not the same width. The box appears only
where a key is actually set.

If the keyboard ever stops answering — the giveaway is that typing still works
in chat — `/imi unstick` gives it back. Type it into any chat box.

While a row is waiting for a key, the addon holds the keyboard so the key does
not also fire in the game. It gives it back on the key, on Escape, on closing
the dialog, and after ten seconds if none of those happen — and `/imi unstick`
releases everything, for a fault none of that covers.

Changing keys is out-of-combat only. The keys themselves work in combat: paging
rebinds from inside the game's restricted environment, so turning the page
mid-pull swaps which callouts your keys fire.

**Settings → Keybinds** holds the rest:

- **Open/close addon** — click, press a key, right-click to clear. This one
  works in combat, which `/imi` cannot: the key clicks a secure button rather
  than asking the addon to hide itself.
- **Show keybinds in Run mode** and **in Edit mode**, separately. Either way a
  box only appears where a key exists.

In Edit a callout can be on several pages with a different key on each. The box
shows the first; hovering it names them all with their pages.

### Undo and redo

`<-` and `->` at the top right of Edit. They take back and put back anything
that changed a dungeon — an added enemy, an edited line, a deleted page, a
reordered list, a whole deleted dungeon.

Undo also **goes to where the change was made**: the dungeon, the variant and
the tab, and on the Pages tab the page itself. So a change coming back is on
screen rather than somewhere you have to go and find.

Thirty steps are kept. History lives in memory only, so it starts empty each
time you log in — it is an editing convenience, not a backup. For a backup,
Export.

Settings are outside it, deliberately. Undo after nudging the opacity slider
takes back the last thing you changed about a *dungeon*; the sliders have their
own reset buttons.

Both are refused in combat: a step can delete the dungeon Run currently has on
screen, and hiding those buttons mid-fight is not allowed.

### How much text fits on a button

A callout too long for one line gets a second, and the button grows to hold it.
Past two lines it ends in an ellipsis — hovering shows the whole thing, and a
button tall enough for a paragraph stops being something you hit by sight.

The enemy name above a card stays on one line and truncates, so it cannot wrap
down onto its own buttons.

### Hover text

Buttons labelled with a symbol — `*`, `?`, `X`, `^`, `v`, `x`, `-`, `<`, `>` —
say what they do when you hover them, with a second line for anything with a
consequence worth knowing before clicking.

### Filling in the enemies

The starter dungeons arrive empty of trash, deliberately. Trash names for the
five Midnight dungeons are past this addon's knowledge, and shipping an invented
list would be worse than shipping none: you would write callouts for mobs that
do not exist and miss the ones that do.

So collect them from the game instead. Bind **Add target as enemy** under Key
Bindings → Inomrah's Mythic Instructions. Then open Edit, select the dungeon, walk it, and press
the key on each pack. Names come out exact and correctly localised, duplicates
are refused, and each new enemy arrives with an empty line ready to write.

`/imi add` and the **Add target** button in Edit do the same thing.

Boss names for the three returning dungeons — Kings' Rest, Temple of Sethraliss
and Ruby Life Pools — are filled in already. Worth checking: they are old
content and unlikely to have changed, but unlikely is not verified.

### Run

Lists your dungeons. Selecting one writes every button and opens the pages.
`<` returns to the list; `<` and `>` at the top right step through pages.

Selecting a dungeon, and going back, are refused in combat. Everything you do
*inside* a dungeon — pressing buttons, flipping pages — works in combat.

### Edit

**Enemies** — a text area over every enemy in the category. Click a line and it
loads above; edit and save. The counter shows characters remaining out of 255.
`+ line` adds a line to an enemy, `+ enemy` adds a new one. The small number
button cycles how many lines sit per row: 1 stacks them, higher fills across,
which is the boss layout.

**Pages** — add enemies to the current page, reorder them, remove them. Removing
is scoped to the page; the definition survives and stays on other pages.
Deleting an enemy outright is on the Enemies tab.

An enemy on several pages is **one definition**. Edit it anywhere and every page
follows.

### Settings

Opacity, and three independent scales: overall, buttons, and text. All apply out
of combat only.

### Backing up

**Export** copies one dungeon as a string, short enough to paste into a chat
message. **Backup all** does the whole profile — that one belongs in a text
file. **Import** never overwrites: it lands as a new category or profile.

SavedVariables is only written on logout or `/reload`, so a crash loses
everything since. After a real editing session, `/reload`. Once enough has
changed, Edit shows how many edits are unbacked.

## Commands

| | |
| ------------- | -------------------------------- |
| `/imi`        | toggle the panel |
| `/imi starter`| create the eight Season 2 dungeons |
| `/imi add`    | add your current target as an enemy |
| `/imi demo`   | create the sample dungeon |
| `/imi edit`   | open Edit |
| `/imi settings`| open Settings |
| `/imi wipe`   | delete everything (no confirm) |

## Tests

`./tests/run.sh` syntax-checks every file and runs the pure-Lua suites: the data
model, the length guard, and export/import round trips including the ways a
paste goes wrong. Requires `lua5.1`.

Everything touching the WoW API can only be verified in a live client, which is
what `InomrahsMIProbe/` was for.
