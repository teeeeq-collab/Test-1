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

The root of the addon is a slim **collapsible bar**, not a main window. It holds
the entries that lead everywhere else:

- **Run** — into the key interface (the Play view)
- **Edit** — writing callouts
- **Settings**

Collapsed, it is close to invisible; that is its resting state during a key.
The `<` at the top left of the Play view returns here.

Each view auto-sizes to its content, so Play stays compact enough to sit in a
corner while Edit gets the room it needs. Each remembers its own size and
position, and the frame is drag-positioned.

## Settings

- **Opacity**
- **Overall scale** — grows and shrinks the whole addon by percentage
- **Button scale** — independent, so buttons stay large enough to hit without
  aiming carefully, which is the point of the addon during a pull
- **Text scale** — independent again, so a bigger caption does not force a
  bigger button

Scale and opacity changes apply out of combat. Frame scaling is restricted on
protected frames during combat, and settings are prep-time work anyway.

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

1. Is Build a third entry on the bar, or a sub-view inside Edit? The bar was
   described as Run / Edit / Settings, with no Build.
2. Where is a category chosen — on the bar, or inside Run?
3. Does zoning into a dungeon auto-select its category, and jump to page 1 or
   resume the last page used?
4. How are pages created, renamed, reordered and deleted?
5. Auto-wrap of enemy cards, or manual row placement?

## Not yet settled

The probe (`MythicMacrosProbe/`) has not been run. Its results decide the
execution layer only: what a button does when pressed, and whether macros need
materialising at all. Everything above is independent of it.
