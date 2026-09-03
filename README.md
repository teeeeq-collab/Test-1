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

### The dungeon list

The list on the left is the same in Run and Edit, but only Edit lets you change
it. In Edit each row can be:

- **renamed** — double-click the name and type over it. Enter or clicking away
  keeps the change, Escape abandons it.
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
