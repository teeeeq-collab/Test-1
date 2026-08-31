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

### Run

Selecting a category, then playing it. Pressing **Run** lists the categories,
one button each. Choosing one opens its pages, starting at the first.

The view carries no edit affordances at all — nothing on it can be misclicked
into changing your text.

- top left: back to category selection, and the lock
- top right: previous / next page
- title: current page name
- body: enemy cards, each a name header over its line buttons

#### The lock

Macros are written and deleted **only** on lock and unlock, and lock and unlock
are possible **only** out of combat. Everything else — paging, pressing buttons,
returning to selection — either does not touch the macro system or is gated
behind unlocking first. No code path can attempt an operation combat forbids.

That invariant exists because an unguarded back button had three failure modes:

- releasing macros needs `DeleteMacro`, blocked in combat, so a mid-pull back
  press could delete half the set
- switching category repoints every button through `SetAttribute`, also blocked
  in combat
- macro indices shift when a macro is deleted, so anything caching an index goes
  stale (everything looks up by name instead)

Behaviour:

- choosing a category shows its pages with buttons **inert** — nothing written
- **Lock** materialises the macros; buttons go live
- **Unlock** releases them; buttons go inert
- while locked, back is disabled; paging stays available, being only show/hide

Inert buttons render dimmed and live buttons full colour, so load state is seen
rather than read. This replaces a text label naming the loaded category.

Loading is all-or-nothing: if fewer slots are free than the category needs,
locking fails with the shortfall named, rather than writing a partial set and
leaving silent buttons.

`/reload` mid-key is safe. The macros are real, persistent objects, so they
survive; the addon restores its lock state on load. A crash leaves recoverable
state rather than orphans — leftover macros are detected on next load.

### Edit

Writing the callouts. Category first, then its contents:

1. pick a dungeon, or create a custom category
2. **Edit enemies** — add an enemy by giving it a name, then add text boxes
   holding the macro text (`/p Prio kick <Piercing Hiss>`). Further boxes stack
   underneath.
3. **Edit page** — a second page under Edit, where enemies already defined are
   added to a page as cards, then removed or reordered. Cards show each enemy's
   text boxes beneath its name, so the page is laid out as it will actually
   appear rather than as a list of names

Composing pages is therefore not a third entry on the bar; it lives under Edit,
alongside editing enemies. Both are prep-time, out-of-combat work.

A text area at the top edits the currently selected line. Below it sits **every
enemy in the category**, regardless of page, so a whole dungeon can be written
in one sitting.

- selecting a line in a card loads it into the text area
- `+` within a card adds a line to that enemy
- `+` at the end of the row adds a new enemy

### Build

Composing pages. Enemies are added to the current page as cards laid out
horizontally, drawn from those already defined in the category.

## Design principle: isolation

The addon reads as little from the game as it can get away with. No zone
detection, no instance events, no combat log, no keystone state. It is a button
grid that runs macros; the fewer game systems it touches, the fewer ways a patch
can break it, and the maintainer cannot patch Lua themselves.

The cost is accepted deliberately: **the category is selected by hand**, so
nothing can auto-select wrongly and nothing resets after a death or a
disconnect.

## Runtime model

Constrained by Midnight's 12.0 addon rules (see README for the probe that
measures these).

- Each line is backed by a real character macro, since the `macrotext` attribute
  is reported protected in 12.0.
- Macros for a category are **materialised when you select that category** under
  Run, and released when another is selected. Selection is a deliberate act
  taken before the key, so it is reliably out of combat — which is exactly when
  the write has to happen. One category resident at a time keeps well inside the
  macro slot cap.
- Load state is shown by dimming inert buttons, so "did I load it?" is
  answerable at a glance rather than by pressing a button and seeing nothing
  happen.
- **Play works in combat.** Pressing buttons and flipping pages are show/hide
  operations through secure handlers, not attribute writes.
- **Edit and Build are out of combat only.** Writing macros and creating buttons
  are both blocked in combat. This is why the modes are separate.

## Open questions

1. How are pages created, renamed, reordered and deleted?
2. Auto-wrap of enemy cards, or manual row placement?
3. Bosses — a distinct type, or just an enemy with more lines? Open; see below.

## Not yet settled

The probe (`MythicMacrosProbe/`) has not been run. Its results decide the
execution layer only: what a button does when pressed, and whether macros need
materialising at all. Everything above is independent of it.

## Bosses — undecided

A boss needs more lines than a trash mob, and a card of six stacked lines is a
tall thin column that makes the window an awkward shape.

One option is a **boss flag** set when the enemy is created: flagged enemies lay
their lines out in a grid rather than a column, and may not share a page with
unflagged ones.

The alternative avoids the type entirely: give **every** enemy a *lines per row*
setting, default 1. A boss with six lines is then set to 2 or 3 per row and
becomes a compact block. No boss concept, no rule about what may share a page,
and the same control is available to a trash mob that happens to need four
lines.

Preferred: the second. A layout preference is being expressed as a type, and the
mixing restriction only exists to protect the layout.
