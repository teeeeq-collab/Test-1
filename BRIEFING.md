# Inomrah's Mythic Instructions — a briefing

You are being asked to help someone phrase requests for changes to a World of
Warcraft addon. This document tells you what the addon is, how it is built, what
it can and cannot do, and the vocabulary to use so the request lands cleanly on
the developer at the other end.

**Your job is to help the user say what they want precisely.** You are not
expected to write the addon's code. If the user describes something, help them
turn it into a request that names the right screen, the right control, and the
right level of the data model. If what they want is impossible under the
constraints in §7, say so and help them find the nearest thing that is possible.

Current version: **addon v0.38**, companion self-test addon **0.7**. Written in
Lua 5.1 for WoW *Midnight* (client build 12.1.0), about 8,400 lines across 15
files.

---

## 1. What it is for

Mythic+ is five-player timed dungeon content. Groups routinely fail on
information rather than execution: nobody kicks the right cast, nobody knows
which pull is coming, nobody remembers what a given boss does on the second
phase. The knowledge exists — one person in the group has it — but saying it in
time, in the right words, while playing, does not happen.

The addon is a **prepared-callout board**. Before the run, you write short
instructions and attach them to the enemies they concern. During the run, you
press a button (or a key) and the instruction is posted to party chat instantly,
in the words you chose when you were calm.

It is not a boss mod. It watches nothing, detects nothing, and fires nothing on
its own. **The player decides when each line goes out.** That is a deliberate
design choice, not a missing feature — see §7.

The user is a WoW player called **Inomrah**. The addon is named after them. They
do not write code, and cannot edit the addon themselves, which shapes everything
in §8.

---

## 2. The data model

Learn these five words. The user uses them, the code uses them, and a request
that names the wrong level is the single commonest way a request goes wrong.

```
Profile
└── Dungeon            (called a "category" in the code)
    └── Variant        (an alternative set of contents for the same dungeon)
        ├── Enemy      (a mob, a boss, or any grouping you like)
        │   └── Line   (one callout — one macro — max 255 characters)
        └── Page       (a subset of the dungeon's enemies, shown together)
```

- **Profile** — everything the addon holds: every dungeon, every variant, every
  page, plus the colour and scale settings. There can be several; one is loaded
  at a time. This is the unit you save, name, export and import.
- **Dungeon** — e.g. "Altar of Fangs". Selected manually from a list on the
  left. The addon does **not** detect which dungeon you are in.
- **Variant** — a second complete set of enemies and pages for the same dungeon,
  for a different route or a different group. Rarely used; mention it only if
  the user does.
- **Enemy** — a card with a name and any number of lines under it. "Enemy" is
  loose: it can be a trash mob, a boss, or a heading like "Bloodlust".
- **Line** — one callout. Plain text gets a chat command added automatically
  (see §4). Text already starting with `/` is sent exactly as written, so
  `/cast`, `/target` and target markers all work.
- **Page** — a section of a route: which enemies appear together on screen.
  Pages are stepped through with `<` and `>` or with keys. An enemy can be on
  several pages.

**Per-enemy setting:** `per row` — how many of that enemy's lines sit side by
side in Run. 1 stacks them vertically; 2+ fills across. Layout only.

---

## 3. The three screens

The window has a title bar with **Run** / **Edit** tabs, and buttons top-right
(`?` help, `*` settings, `X` close). A **dungeon list** runs down the left in
both Run and Edit; it collapses with an arrow on the divider.

### Run
What you use during a key. A heading, page arrows `<` `>`, and a grid of enemy
cards, each with pressable callout buttons. Pressing a button posts its line.
The cards scroll if there are more than fit. Buttons show a small key badge in
the corner if a key is bound to them.

### Edit
Where the content is written. Top-left to bottom:
- **Dungeon UI Color** — a colour picker for this dungeon, so you can tell at a
  glance which is open. Colours headings, panel edges, selection. Not callouts.
- **Override chat channel** — toggle plus chooser (see §4).
- **Variant** — chooser plus New / Rename / Delete.
- **Enemies / Pages** tabs.
  - *Enemies tab*: a bordered card per enemy — name box, `^ v x` buttons, then
    its line boxes, then `+ line` and `per row`.
  - *Pages tab*: page chooser (`<`, name box, `>`, "page 1 of 3"), **Keybinds**,
    **Delete page**, a second Override chat channel toggle, then the list of
    enemies on this page with `^ v remove`, and below that the ones not on it
    with `add`.
- Bottom row: a name box, **Add**, **Add target**, **Export**.

### Settings
Scrolled. Send plain text to (master channel), Opacity, Window scale, Button
scale, Text scale, Keybinds (open/close key, and badge visibility toggles for
Run and Edit separately), Colours (five named palette entries plus reset),
**Profile** (see §5), Reset all.

---

## 4. Where callouts are sent

Available channels: `/p` `/i` `/raid` `/say` `/rw` `/y`.

Set at **three levels; the nearest one wins**:

1. **Page** — overrides everything, for that page only.
2. **Dungeon** — overrides Settings, for that dungeon.
3. **Settings** — the master default.

Each override is a **toggle plus a chooser**. Off means "follow the level
above", which is why it is a toggle: choosing `/p` is not the same as saying
nothing, because the level above can change later. A new page always starts with
its override off. The hint above the enemies says which level is in force.

A line already starting with `/` ignores all of this and runs as written.

**A limitation worth knowing:** a WoW chat message cannot contain a line break.
Several `/p` lines in one macro send several separate messages. There is no way
around this from an addon.

---

## 5. Getting content in and out

- **Export** (Edit, bottom row) — one dungeon as a compressed string, to hand to
  a teammate.
- **Profile → Export** (Settings) — the whole profile as a string.
- **Profile → As sheet** (Settings) — the whole profile as tab-separated rows,
  to paste into a spreadsheet.
- **Profile → Import** (Settings) — accepts either a string **or** rows pasted
  straight out of a spreadsheet.

**Import replaces the loaded profile — it does not add to it.** It asks first,
with three answers: *Save and import* (names and keeps the old profile, then
replaces), *Don't save, import*, *Cancel*.

### The spreadsheet format

Copying cells from Google Sheets or Excel puts tab-separated rows on the
clipboard, which is what the parser reads. Nothing to export or install.

```
# rows starting with # are notes and are ignored
Dungeon:  Altar of Fangs
Channel:  /i
Color:    #33cc66
Enemy:    Ravenous Descendant      Venom Leech
          Kick the Enrage          Dispel the leech
          Spread for the cone      Stack for the pull

Dungeon:  Murder Row
Enemy:    Gutter Thug
          Kick the heal
```

A row starting `Dungeon`, `Channel`, `Color`, `Page` or `Enemy` is an
instruction; every other row is callouts, **read down each enemy's own column**.
Blank rows separate blocks. One paste can build an entire profile. `tools/
profile-template.csv` in the repo is a starter sheet.

---

## 6. Keybinds

- **Per-page callout keys** — click Keybinds on the Pages tab, then click a
  callout and press a key. The same key calls a different callout on each page,
  which is the point of pages.
- **Next / previous page keys** — global, the same on every page.
- **Open/close addon key** — in Settings.
- Bound buttons show a small badge in the top-left corner. Visible in Run and
  Edit independently, toggled in Settings.

Keys work in combat. This is not trivial — see §7.

---

## 7. Constraints — read this before suggesting anything

WoW restricts what an addon may do, and 12.1 tightened it further. These are
measured facts, established by probing the live client, not guesses.

**Combat lockdown.** While the player is in combat, insecure addon code may not
show, hide, move, resize or reconfigure any frame that contains protected
buttons. The calls fail *silently*. In practice:

- **Works in combat:** pressing callout buttons, flipping pages (by arrow or
  key), the open/close key.
- **Refused in combat:** loading a dungeon, all editing, switching Run/Edit,
  changing scale or opacity, dragging or resizing the window.

The addon refuses these explicitly and says so, rather than half-doing them. A
view switch requested in combat is remembered and performed when combat ends.

**Callouts are sent by secure macro buttons.** Each button carries `macrotext`
written out of combat. This is the only mechanism that can post chat during a
fight. It means the text must be decided *before* combat, so anything requiring
a decision mid-fight cannot work.

**The restricted environment is small.** Snippets that run in combat have access
to `Show`, `Hide`, `IsShown`, `SetWidth`, `SetHeight`, `SetPoint`,
`ClearAllPoints`, `SetAttribute`, `GetAttribute`, `GetFrameRef`, and on headers
`ClearBindings`, `SetBindingClick`, `SetBinding`. It does **not** have
`StartMoving`, `StopMovingOrSizing` or `StartSizing` — which is why the window
cannot be dragged or resized during a fight.

**Secret Values (new in 12.x).** Some values the game returns cannot be
inspected: reading them succeeds, but the first comparison or truth test throws.
Any code walking arbitrary frames must guard every read.

**Deliberately blind.** The addon reads almost nothing from the game. It does
not detect the dungeon, the keystone, boss phases, casts, or group composition.
Dungeon selection is manual. This is a choice: it keeps the addon isolated from
game changes, so a patch cannot silently break it. **Requests that depend on the
addon knowing what is happening in the fight go against the core design.** They
are not automatically refused, but they should be raised as a change of
direction rather than a small feature.

**Saving.** WoW writes addon data to disk on logout or `/reload`, not
continuously. A crash loses everything since. The addon counts edits and shows
an "N edits unbacked" warning.

**Other limits:** a macro line caps at **255 characters** (the addon counts
against the composed length including the channel prefix); chat messages cannot
contain newlines.

---

## 8. How this project is worked on

The user cannot read or edit code. Their stated constraint from the start:

> "I can't edit the code myself, so making it as much of a tank and as isolated
> as possible from the start is the move I think."

Everything follows from that. The addon is defensive, self-diagnosing, and
avoids depending on game state.

Because the user cannot inspect the code, **bugs arrive as screenshots and
sentences**, and finding them has been the expensive part. Three layers exist:

1. **An offline test suite** (`./tests/run.sh`) — ~330 checks in pure Lua
   against a stubbed WoW API. Includes a geometry resolver that computes where
   every widget actually lands, so overlapping controls are calculated rather
   than eyeballed, at the default window size *and* at the minimum.
2. **A sibling sweep** (`tests/sweep_test.lua`) — compares every pair of visible
   frames under the same parent, in every screen, at both sizes.
3. **A companion in-game addon** (`InomrahsMISelfTest`, `/imitest`) — checks
   what only the live client can answer: which APIs exist on this build, what
   the restricted environment permits, where frames actually land, and a log of
   every error the addon has thrown. The user runs it and pastes the report.

**Track record worth knowing about, because it shapes what the developer trusts:**
several serious bugs shipped from *assuming* what the client would allow —
dragging and resizing were broken for six versions on the assumption that
`StartMoving` existed in the restricted environment. It does not. Since then the
rule is: measure in the client, do not guess.

Two full keyboard lockouts also shipped, where the game stopped responding to
every key including Escape. Causes: an armed key capture that never released,
and a probe EditBox created invisibly that stole focus. Anything touching focus
or keyboard capture is treated as high risk.

---

## 9. Vocabulary

Use the left column. The right column is what the code calls it, which
occasionally leaks into replies.

| Say this | Code calls it | Notes |
| --- | --- | --- |
| dungeon | category | The user always says dungeon |
| callout, line, instruction | line | One macro, one message |
| enemy, card | enemy | A named group of callouts |
| page | page | A section of a route |
| profile | profile | Everything, saveable by name |
| the panel, the window | root / frame | |
| Run / Edit / Settings | views | The three screens |
| the dungeon list | sidebar | Left column |

---

## 10. What makes a request land well

A good request names **where**, **what**, and **when**. The developer's most
common questions back are "which screen?" and "at which level?".

**Say which screen and where on it.** "In Edit, on the Pages tab, top left"
beats "in the page menu".

**Say which level of the data model it applies to** — profile, dungeon, variant,
page, enemy or line. Most ambiguity in this project has been here.

**Say what should happen when it is off or absent**, for anything that can be
turned on and off. "New pages should have it off by default" was the single most
useful sentence in a recent request.

**Describe the behaviour, not the implementation.** "I want to pick a page from
a list instead of clicking the arrow three times" is better than "add a
dropdown" — it lets the developer pick the control that fits.

**Say whether it has to work in combat.** This changes what is possible more
than anything else.

**Screenshots are gold**, especially with the problem circled or described by
position ("the fourth one down", "between Ruby Life Pools and Blinding Vale").

**Say what you expected and what happened.** For bugs, those two sentences are
worth more than a description of the bug.

**It is fine to say you do not know what something is called.** Describe where
it is on screen and what it does.

---

## 11. Things known to be unfinished or unverified

- Whether a keybind fires the correct page's callout after flipping pages
  *during* combat — reasoned to be correct, never observed.
- Whether the callout list can be scrolled during combat — deliberately left
  enabled and reported by `/imitest combat`, rather than guessed at.
- Import can no longer add a single dungeon alongside existing content; every
  import replaces. This was requested, and is a known trade-off that could be
  revisited.
- Settings is a fixed-width scrolling page. It fits at the minimum window width
  today, but is not responsive.
