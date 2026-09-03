# Inomrah's Mythic Instructions — design

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

Compressed and print-encoded, like a Plater profile or an MDT route: serialise
with LibSerialize, compress with LibDeflate, encode with `EncodeForPrint`.

The libraries are vendored under `Libs/` so the addon stays one folder to
install. They do not weaken the isolation principle: all three are pure Lua
doing string and arithmetic work, touching no game API, so no patch can break
them. Isolation is about code that reads game state.

Measured on generated data with no repeated text for deflate to exploit:

| Export                       | Encoded length | |
| ---------------------------- | -------------- | --- |
| one dungeon, 18 enemies      | ~1,460 chars   | fits one Discord message |
| large dungeon, 40 enemies    | ~2,480 chars   | needs a file |
| full profile, 8 dungeons     | ~5,700 chars   | needs a file |
| 12 dungeons x 25 enemies     | ~10,200 chars  | needs a file |

The unit that gets shared — one dungeon — pastes into a chat message. The unit
that gets backed up — a whole profile — goes to a file, which is where a backup
belongs.

### Envelope

The payload is wrapped rather than exported bare:

```
!IMI1:<adler>!<encoded>
```

The prefix identifies format and version, so a future format change is detected
rather than misparsed. Inside, the serialised table carries an Adler-32 of its
own contents.

This exists because a truncated paste — the commonest import failure, since
people miss the last characters when selecting — does **not** reliably throw.
Testing confirmed it can pass decode and decompress without an error. The
checksum turns that into "this string looks truncated, check you copied all of
it" instead of a confusing failure deeper in.

### Import safety

LibSerialize deserialises a **binary format**; it never evaluates Lua. Many
addons import by running the string as code, which lets a profile string from
another person execute anything on the machine that imports it. Since passing
strings between teammates is the point of the feature, that route is closed by
construction.

Beyond that, the decoded table is **shape-validated** before anything is
applied — expected keys, expected types, sane sizes — because deserialising
safely still says nothing about whether the contents make sense.

Import never overwrites in place: the whole string is parsed and validated
first, then lands as a new profile, or a new category with a suffix on a name
clash. A bad paste cannot destroy existing work.

## Undo

Snapshots, not inverse operations.

Twenty-seven functions in `Core` change stored data. An inverse-operation undo
means writing an opposite for each, and the opposites are where the edge cases
hide: deleting an enemy also strips it from every page that referenced it, so
un-deleting has to put it back at its old index *and* back into each of those
pages, in their old positions. Copying the whole thing before the change cannot
get that wrong, and it is one piece of code rather than twenty-seven. The test
for exactly that case is in `tests/history_test.lua`.

Recording hangs off `Core`'s own `edited()`, which every mutator already calls.
That makes coverage automatic rather than a list of call sites in the UI that a
later change could quietly fall outside of.

The cost is memory: thirty steps, each a deep copy of every profile. A fully
written-out season is tens of kilobytes, so the ceiling is a couple of megabytes
and typically far less. None of it is saved — history is a session-lifetime
editing convenience, and `Export` is the thing that survives a logout.

Each step carries the editor's position at the moment of the change — dungeon,
variant, tab, page — and undo restores that too. Reversing a change you cannot
see happen is most of the way to no undo at all.

Settings are outside history, and combat refuses a step: undoing can delete the
dungeon Run has built, and hiding secure buttons mid-fight is blocked.

## Measured behaviour (12.1.0)

Verified by effect on the live client, not inferred. Earlier drafts of this
document recorded the opposite of several rows, taken from public reporting.

| Behaviour | Result |
| --------- | ------ |
| `macrotext` attribute executes | **works**, in and out of combat |
| Real character macro executes | works, in and out of combat |
| Chat sent from `macrotext`, in combat, in an instance | **delivered** |
| Chat sent from a real macro, in combat, in an instance | delivered |
| `SetAttribute` in combat | **blocked** |
| `EditMacro` / `CreateMacro` in combat | blocked |
| `SetScale` in combat | blocked |
| Plain `Hide()` on a frame with a protected child, in combat | blocked |
| Secure-handler page flip in combat, **hardware click** | **works** |
| Secure-handler page flip, **scripted** `:Click()` | refused, "Invalid 'self' frame handle" |
| Macro body cap | **256 characters**, not bytes |
| Macro name length | at least 32 |
| Macro slots | `Constants.MacroConsts.MAX_ACCOUNT_MACROS` = 120, `MAX_CHARACTER_MACROS` = 30 |
| Reading chat contents inside an instance | **refused** — Secret Value |

A blocked operation returns **no error**. `pcall` succeeding proves nothing,
which is why each row was checked by writing a value and reading it back; an
earlier version of these tests reported everything as permitted purely because
nothing threw.

Chat received inside an instance arrives as a Secret Value: the message is
delivered, but an addon touching its contents throws. Messages the addon sent
itself read normally, which is how the echo checks worked at all. This cannot
affect Inomrah's Mythic Instructions, which only sends chat, but it rules out any future feature
needing to see what was said.

### During a boss encounter: sending works, observing does not

A controlled comparison inside one raid, same buttons, same instance:

| Run | combat | encounter | echo recorded | message visible on screen |
| --- | ------ | --------- | ------------- | ------------------------- |
| K3  | true   | false     | RECEIVED      | yes |
| K4  | true   | **true**  | none          | — |
| K5  | true   | **true**  | none          | **yes** |

The missing echo in K4 and K5 looked like the restriction biting. It was not.
A screenshot of the chat frame during the encounter shows both messages
delivered to instance chat, interleaved with the run-5 click records:

```
IMIProbe B.click.macrotext.chat.5 = CLICKED (in combat)
08:36 [Instance] [Inomrah]: IMIProbe-MT check
IMIProbe B.click.realmacro.chat.5 = CLICKED (in combat)
08:36 [Instance] [Inomrah]: IMIProbe-RM check
```

So during an active boss encounter, in combat: **chat from a macro is sent and
seen by the group.** What an addon loses is the ability to *observe* chat —
either the event stops being delivered or its contents become a Secret Value.

That distinction matters because the two are indistinguishable from inside Lua,
and reading the absent echo as a block would have condemned the whole design on
the strength of missing bookkeeping.

Inomrah's Mythic Instructions only ever sends. It never reads chat. So the restriction that does
exist is one it never touches.

### In a live keystone

Sampled at last, on a +9 in The Blinding Vale: `keyActive=true`, `keyLevel=9`,
`combat=true`, party of five, `/p`.

Both chat buttons clicked. No echo recorded — the same signature as the boss
encounter, where a screenshot confirmed the messages were delivered regardless.
Every combat restriction held identically inside the key.

So all three conditions Blizzard's restriction is reported to cover — combat, an
active boss encounter, and an active keystone — have now been sampled, and in
each one a macro-driven button sends chat while the addon cannot observe it.

## Design principle: isolation

The addon reads as little from the game as it can get away with. No zone
detection, no instance events, no combat log, no keystone state. It is a button
grid that runs macros; the fewer game systems it touches, the fewer ways a patch
can break it, and the maintainer cannot patch Lua themselves.

The cost is accepted deliberately: **the category is selected by hand**, so
nothing can auto-select wrongly and nothing resets after a death or a
disconnect.

## Runtime model

Each line's macro text lives on its button as a `macrotext` attribute. No
character macros are created, so no slots are consumed, nothing needs cleaning
up, and the 69 macros already on the account are untouched.

What the measurements force:

- **Buttons are built out of combat.** `SetAttribute` is blocked in combat, so a
  category's buttons and their text are written when the category is selected.
- **Selecting a category in combat is refused**, with a message saying why.
  Nothing can be half-written, because nothing is written until it succeeds.
- **Play works in combat.** Pressing a button runs its macro; flipping a page
  shows one pre-built frame and hides another through a secure handler. Both
  confirmed in combat.
- **Page arrows must be real clicks.** A scripted `:Click()` on a secure handler
  is refused. This costs nothing — the arrows are pressed by hand.
- **Settings apply out of combat.** `SetScale` is blocked in combat. Scale and
  opacity are prep-time work anyway.

### What this replaced

An earlier design created a character macro per line, materialised on selecting
a category and released on leaving, with a lock button guarding the writes and
an all-or-nothing slot check. All of it existed to work around `macrotext` being
unavailable. It is available, so none of it is needed.

The lock's second rationale — that a mid-key press of *back* must not leave the
addon half-configured — survives without the lock: rebuilding in combat is
refused by the game, so the addon refuses and explains.

## Open questions

1. Auto-wrap of enemy cards, or manual row placement? Recommended: auto-wrap,
   which preserves left-to-right order and only chooses where to break.

Assumed unless corrected: pages are created, deleted and reordered from controls
at the top of **Edit page**, where they are also renamed.

## Not yet settled

One question remains, and only one: whether chat sent from a button survives an
**active boss encounter or keystone**. See "Still unverified" above. Everything
else in this document is measured.

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

## The macro length limit

Macro bodies cap at **256 characters**, not bytes. Measured: 300 ASCII
characters were stored as 256, while 120 multi-byte characters occupying 360
bytes were stored untouched. A byte cap would have cut the 360-byte body.

An earlier draft had this backwards and counted bytes, which would have silently
truncated a legal 200-character callout containing accented text to roughly 85
characters — the precise failure the guard exists to prevent.

`SetMaxLetters` also counts characters, so it agrees with the cap and one layer
suffices:

1. `SetMaxLetters(255)` — the client refuses further typing. 255 rather than the
   observed 256, because a spare character costs nothing and being wrong at the
   boundary costs a corrupted macro.
2. Validation on save, as a backstop against a path that bypasses the edit box.

The counter displays **characters** remaining.
