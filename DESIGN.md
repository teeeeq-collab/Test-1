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
- title: the category name at or just left of centre, with the page name
  slightly smaller to its right — `Den of Nalorakk    Boss 1: Ra'Vi`. The
  category name is edited under Edit, the page name under Edit page.
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

## Profiles, export and data safety

### What SavedVariables actually guarantees

The game holds addon data in memory and writes it to disk at three moments
only: clean logout, `/reload`, and a normal exit. Not continuously.

So a client crash loses everything since the last logout or reload. The file is
not corrupted; it was simply never written. Two lesser risks: a malformed
SavedVariables file is silently discarded rather than repaired, and two clients
logged in at once means the last to log out overwrites the other.

SavedVariables is therefore a working store, not a backup. Export strings are
the real safety net, which is why they are in from the start rather than bolted
on later.

Three mitigations:

- **`/reload` is the flush.** No API can force a save, so the UI says this
  rather than assuming it is remembered.
- **Export-staleness marker.** Edits since the last export are counted, and a
  quiet indicator appears in Edit once the count is meaningful.
- **Rolling snapshots** of the last few states, kept alongside the live data.
  These protect against user error — a category deleted by accident, a bad
  import — and explicitly **not** against a crash or file loss, since they live
  in the same file.

### Profiles

A profile is a named set of categories. Display settings stay global, since they
describe the monitor rather than the content. Data is account-wide, so callouts
follow every character, and profiles cover the cases where variants are wanted.

Export covers either a whole profile or a single category, the latter being what
gets passed to a teammate.

### Format

Plain readable text, no libraries. Compression via LibDeflate would produce
strings roughly a quarter the size, but adds dependencies, and a corrupted
compressed blob tells you nothing while a plain-text export can be opened in an
editor and read. A dungeon lands around 5-15 KB, which is fine for a file and
awkward for Discord's 2000-character limit; compression can be added later if
sharing that way matters, since backup is the primary job.

### Import safety

Import uses a **strict parser, never `loadstring`**. Many addons evaluate import
strings as Lua, which means a profile string from another person can execute
arbitrary code. Since passing strings between teammates is the point, the parser
reads data and refuses anything that is not data.

Import never overwrites in place: the whole string is parsed and validated
first, then lands as a new profile, or a new category with a suffix on a name
clash. A bad paste cannot destroy existing work.

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

1. Auto-wrap of enemy cards, or manual row placement? Recommended: auto-wrap,
   which preserves left-to-right order and only chooses where to break.

Assumed unless corrected: pages are created, deleted and reordered from controls
at the top of **Edit page**, where they are also renamed.

## Not yet settled

The probe (`MythicMacrosProbe/`) has not been run. Its results decide the
execution layer only: what a button does when pressed, and whether macros need
materialising at all. Everything above is independent of it.

## Enemy layout

Every enemy has a **buttons per row** setting, default 1, so its lines stack
vertically like a trash card.

Raising it makes buttons fill horizontally first and then wrap, with the single
name header sitting above the top-left button. That is the boss layout: a boss
with six lines set to 3 per row becomes a compact 2x3 block instead of a tall
thin column.

There is no boss type and no rule about what may share a page. The layout itself
shows that an enemy is a boss, and the same control is available to a trash mob
that happens to need four lines.

## Button labels

A line has an optional short caption. When set, the button shows it (`Strat`,
`Panic`). When empty, the button falls back to showing the macro text itself,
with the leading chat command stripped, so `/p Prio kick <Piercing Hiss>` reads
as `Prio kick <Piercing Hiss>`.

## The 255 limit

Macro bodies cap at **255 bytes**, not characters. `SetMaxLetters` counts
characters, so a body of 255 characters containing an accented letter or a
pasted smart quote is over 255 bytes and would be silently truncated by
`CreateMacro` — the exact failure the counter is supposed to prevent, arriving
in the form the counter called safe.

Three layers, because this has to be foolproof:

1. `SetMaxLetters(255)` — the client itself refuses further typing
2. a byte-length check on every text change (`#text` is byte length in Lua);
   a paste that lands over 255 bytes is trimmed to the last whole character,
   cursor restored
3. validation on save — a body over 255 bytes is refused, never written

The counter displays **bytes** remaining, so it is accurate in every case. Under
normal typing layers 2 and 3 never fire.
