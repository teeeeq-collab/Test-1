# MythicMacros — design

Personal Mythic+ callout addon. A small window of labelled buttons; each button
fires a real macro, typically one line of instruction to the party. Built so
callouts can be pressed by sight rather than recalled as numpad positions.

## Concepts

- **Category** — a dungeon, or a user-made custom category. Owns everything below.
- **Enemy** — a name plus an ordered list of lines. Defined once per category.
- **Line** — a caption (what the button reads, e.g. `Strat`, `Panic`) and a macro
  body (what actually runs). Typically 1 per enemy, up to ~5.
- **Page** — a named section of the route (`Opening trash`, `To first boss`),
  holding an ordered list of *references* to enemies.

The enemy name is only a label. Nothing matches it against the mob you are
targeting, so no NPC IDs are involved and localisation is irrelevant.

### Shared enemies

An enemy is defined once per category. A page holds a reference, not a copy, so
an enemy appearing on four pages is one definition: edit it anywhere and every
page reflects it, and it consumes one macro slot rather than four.

## Windows

One frame with a main menu and three views. The frame auto-sizes to its view, so
Play stays compact enough to sit in a corner while Edit and Build get the room
they need. Each view remembers its own size and position. Scale and opacity are
user-set; the frame is drag-positioned.

### Play

The only view open during a key. It carries no edit affordances at all — nothing
on it can be misclicked into changing your text.

- top left: back to main menu
- top right: previous / next page
- title: current page name
- body: enemy cards, each a name header over its line buttons

### Edit

Writing the callouts. A text area at the top edits the currently selected line.
Below it, **every enemy in the category** as cards, regardless of which page they
sit on — so a whole dungeon's callouts can be written in one sitting.

- selecting a line in a card loads it into the text area
- `+` within a card adds a line to that enemy
- `+` at the end of the row adds a new enemy

### Build

Composing pages. Enemies are added to the current page as cards laid out
horizontally, drawn from those already defined in the category.

## Runtime model

Constrained by Midnight's 12.0 addon rules (see README for the probe that
measures these).

- Each line is backed by a real character macro, since the `macrotext` attribute
  is reported protected in 12.0.
- Macros for a category are **materialised on zone-in** and released on exit.
  Loading screens guarantee we are out of combat at that moment, which is
  exactly when the write has to happen. One category resident at a time keeps
  well inside the macro slot cap.
- **Play works in combat.** Pressing buttons and flipping pages are show/hide
  operations through secure handlers, not attribute writes.
- **Edit and Build are out of combat only.** Writing macros and creating buttons
  are both blocked in combat. This is why the modes are separate.

## Open questions

1. What sits on the main menu beyond category selection?
2. Does zoning into a dungeon auto-select its category, and jump to page 1 or
   resume the last page used?
3. How are pages created, renamed, reordered and deleted — in Build?
4. Auto-wrap of enemy cards, or manual row placement?

## Not yet settled

The probe (`MythicMacrosProbe/`) has not been run. Its results decide the
execution layer only: what a button does when pressed, and whether macros need
materialising at all. Everything above is independent of it.
