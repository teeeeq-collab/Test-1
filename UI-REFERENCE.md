# Inomrah's Mythic Instructions — complete UI reference

Every screen, every control, every interaction, described from the player's
point of view with the real numbers behind it. Written so that someone who has
never seen the addon can reason about its interface design.

Companion to `BRIEFING.md`, which covers purpose, data model and platform
constraints. This document covers **what is on screen and how it behaves**.

Version described: **addon v0.38**. Every measurement below is read from the
source, not estimated.

> **A note on judging this interface.** It is a World of Warcraft addon, drawn
> with WoW's frame API. There is no CSS, no flexbox, no layout engine: every
> widget is positioned by anchoring one of its nine points to one of another
> widget's nine points with a pixel offset. Text does not reflow; a font string
> is exactly as wide as its text unless bounded, and a bounded one either wraps
> or ends in an ellipsis. There is no hover delay, no transition, no animation
> unless hand-written per frame. Suggestions that assume a modern layout system
> will not translate. Suggestions about *hierarchy, grouping, affordance,
> labelling, error recovery and information density* translate perfectly.

---

## 0. Contents

1. The visual system — colours, type, the five widget kinds
2. The window frame — title bar, resize, collapse, opacity
3. The dungeon list (left column)
4. The Run screen
5. The Edit screen — header
6. The Edit screen — Enemies tab
7. The Edit screen — Pages tab
8. The Edit screen — bottom row
9. The Settings screen
10. Dialogs — confirm, name prompt, colour picker, keybinds, string window, help
11. Interaction patterns used throughout
12. State, feedback and error handling
13. Where the interface is known to be weak

---

## 1. The visual system

### 1.1 The palette

Dark, near-black, with a gold/amber accent. Defined once and drawn from
everywhere; nothing hard-codes a colour at a call site.

| Role | RGB (0–1) | Where it is used |
| --- | --- | --- |
| `window` | 0.055, 0.055, 0.075 @ 96% | Main window ground |
| `panel` | 0.085, 0.085, 0.115 @ 98% | Content panel ground |
| `bar` | 0.10, 0.09, 0.13 @ 100% | Title bar |
| `dialog` | 0.07, 0.07, 0.095 @ **100%** | Dialog grounds — deliberately opaque |
| `gold` | 0.78, 0.63, 0.30 | Panel edges, borders |
| `goldText` | 1.00, 0.82, 0.20 | Headings, key badges |
| `row` | 0.135, 0.135, 0.175 | Button and row ground |
| `rowHover` | 0.185, 0.185, 0.235 | Button ground on hover |
| `rowEdge` | 0.26, 0.26, 0.33 | Button and box borders |
| `accent` | 0.88, 0.54, 0.12 | Selection, active tab, checked box |
| `accentHover` | 0.95, 0.62, 0.18 | Selected button on hover |
| `onAccent` | 0.10, 0.08, 0.05 | Text on an accent ground |
| `text` | 0.88, 0.88, 0.91 | Body text |
| `textDim` | 0.55, 0.55, 0.60 | Disabled text, hints |
| `danger` | 0.85, 0.32, 0.28 | Delete buttons, error messages |

**Three layers of palette override**, resolved into one live table that
everything reads:

1. **As shipped** — the table above.
2. **The player's own colours** (Settings → Colours) — five keys may be
   overridden: `gold`, `goldText`, `accent`, `text`, `textDim`. Everything else
   is structural and not exposed.
3. **The open dungeon's colour** (Edit → Dungeon UI Color) — tints headings,
   panel edges and selection so you can tell at a glance which dungeon is open.
   It deliberately does **not** touch callout buttons or the dungeon list, so
   the thing you press during a pull never changes colour under you.

**Opacity** (Settings slider, 0.2–1.0) fades **grounds only** — never text and
never borders. This was a deliberate correction: fading everything made a
half-transparent window unreadable rather than unobtrusive.

### 1.2 Type

Four Blizzard font objects, all scaled by one setting:

| Object | Size | Used for |
| --- | --- | --- |
| `GameFontNormalLarge` | 16pt | Screen titles ("Altar of Fangs") |
| `ChatFontNormal` | 14pt | Every editable box — the text you write callouts in |
| `GameFontHighlight` | 12pt | — |
| `GameFontNormalSmall` | 10pt | Buttons, labels, hints, key badges |

**Text scale** (Settings, 0.6–1.6) multiplies every registered font string.
The base size is remembered at creation, so repeated rescaling cannot compound
— an earlier version read the current size and multiplied, and text grew
13 → 16.9 → 22 → 28.6 across rebuilds.

Editable boxes are 14pt while their surroundings are 10pt. That is intentional
and was arrived at the hard way: they were dropped to panel size once, and were
too small to write callouts in comfortably.

### 1.3 The five widget kinds

Everything on screen is one of these. Knowing which one you are talking about
removes most ambiguity.

**1. Button.** A rectangle with a ground, a 1px border and a centred label.
Three exclusive visual states plus hover:

| State | Ground | Label | Border |
| --- | --- | --- | --- |
| normal | `row` | `text` | `rowEdge` |
| hovered | `rowHover` | `text` | `rowEdge` |
| selected | `accent` (hover: `accentHover`) | `onAccent` | `accent` |
| disabled | `row` | `textDim` | `rowEdge` |
| danger | `row` | `danger` | `rowEdge` |

Labels are held to one line and end in an ellipsis. A caller that has made room
may allow two — Run's callout buttons do, nothing else does. This exists
because an unbounded label wraps, and a fixed-height button then spills its
extra lines over whatever is beneath it. That shipped once, with a long dungeon
name overrunning the two rows below it.

**2. Edit box.** A ground, a border, and text you can type into. Border turns
`accent` while focused. Every box releases the keyboard when hidden. Boxes with
a hard limit show a live character counter while focused.

**3. Dropdown.** A button showing the current value; clicking opens a bordered
list directly beneath it. Rows are ordinary buttons, so they get the standard
hover highlight for free. Choosing closes the list. Clicking the button again
closes it. **There is no click-outside-to-close.**

**4. Slider.** Blizzard's `OptionsSliderTemplate`, 190px wide, with the low/high
labels blanked. Always paired with a typed value box and a Reset button.

**5. Check box.** 16×16, addon-coloured rather than Blizzard's art: a bordered
square that fills with `accent` when on. Border lights `accent` on hover.

**Tooltips.** Almost every control has one — a bold title line and an optional
grey detail line, appearing above the control. They are *hooked* onto the
existing hover scripts rather than replacing them, so the hover colour survives.
Tooltips are the primary way this interface explains itself; there is no
onboarding, no tour, and only one help screen.

**Key badges.** A small bordered box in the top-left corner of any button with a
keybind, showing the key in `goldText`. Width fits the text with an 18px floor —
"E" and "CTRL+E" are very different widths, and a box sized for the longer
wastes a third of a small button. Never drawn empty. Can be shown or hidden
independently for Run and for Edit.

### 1.4 Scrolling

Six scrolling regions: the dungeon list, the Run callout panel, the Edit
enemies list, the Edit pages list, Settings, and the export/import text box.

All answer the **mouse wheel** (24px per notch, clamped at both ends), and all
show a scrollbar **only when there is something to scroll**. The Run panel
reserves its 28px gutter whether the bar is showing or not, so cards do not
reflow the moment content grows past the bottom.

---

## 2. The window frame

Default **760 × 380**. Minimum **560 × 300**. Position and size are remembered
between sessions. It clamps to the screen and cannot be dragged off.

### 2.1 The title bar (24px tall)

Left to right:

| Control | Size | Behaviour |
| --- | --- | --- |
| `-` | 22×20 | Collapses the window to just the bar. Becomes `+`. |
| **Run** | 60×20 | Switches to Run. Highlighted (`accent`) when active. |
| **Edit** | 60×20 | Switches to Edit. Highlighted when active. |
| *title* | centred | "Inomrah's Mythic Instructions" |
| `?` | 22×20 | Opens the help text. |
| `*` | 22×20 | Opens Settings. |
| `X` | 22×20 | Closes the window. |

**Run/Edit are tabs, not buttons** — mutually exclusive, current one
highlighted. Settings is *not* a third tab: it opens over the whole body and
hides the dungeon list. This asymmetry is deliberate (Settings is not a place
you work) but is the kind of thing a UI review might reasonably question.

`X` is special: it is a **secure button**, so it works during combat. The other
bar buttons do not — switching views mid-fight is refused by the game, and the
addon says so and performs the switch the moment combat ends.

### 2.2 Dragging and resizing

Drag the title bar to move. Three invisible 6px grips resize: the right edge
(width), the bottom edge (height), the bottom-right corner (both).

**Both are refused during combat** and say so. This is a platform limit, not a
choice: the restricted environment that can run code in combat has no
`StartMoving` or `StartSizing`. This was assumed to exist for six versions and
was not, which broke dragging entirely.

---

## 3. The dungeon list (left column)

168px wide, present in Run and Edit, hidden in Settings.

- **Heading** "Dungeons" with an invisible full-width hover target behind it, so
  the tooltip explaining rename/reorder/delete is easy to catch.
- **The list** — one row per dungeon, 22px tall on a 24px pitch, scrolling.
  Rows are 132px wide, deliberately narrower than the column so the delete
  button is never drawn under the scrollbar. (It was, once.)
- Pinned at the bottom, in order upward: a hint, a name box (hidden until
  needed), **New dungeon**, **Back**.

### Row behaviour

| Gesture | Run | Edit |
| --- | --- | --- |
| single click | select | select |
| double click | — | rename in place |
| drag | — | reorder |
| red `x` at the right | hidden | delete, with confirmation |

Rearranging and deleting exist **only in Edit**. In Run the list is a way in and
nothing else: a slipped drag mid-key must not be able to cost you a dungeon.

The selected row is highlighted with `accent`, so which dungeon the right panel
is showing never has to be inferred from its heading.

**Rename** turns the row into an edit box in place, pre-selected. Enter commits;
clicking away commits; Escape abandons. **Reorder** shows a 2px accent line
where the row would land and fades the dragged row to 50% — the row itself does
not move, so the list never reflows under the cursor while you are aiming.

A two-line hint sits above the buttons — *"Double-click a name to rename it. /
Drag a row to reorder."* — shown only in Edit and only when there is a list.
Neither gesture leaves a mark on the panel otherwise.

---

## 4. The Run screen

What you look at during a key. Everything here is designed around one
constraint: **you are playing the game while using it.**

Top strip: the dungeon name centred, a **variant chooser** at the left if the
dungeon has more than one, and `<` `>` page arrows at the right (26×20).

Below that, scrolling: the current page's enemy cards.

### Enemy cards

Each card is a heading (the enemy's name, 16px, gold, one line, truncated) with
its callout buttons beneath.

- Buttons are **150×22** at scale 1, growing taller if their label needs a
  second line, and truncating past two.
- Labels are left-justified. The caption is used if there is one; otherwise the
  macro text with its chat command stripped, so `/p Prio kick the Envenom`
  reads as `Prio kick the Envenom`.
- **per row** decides how many sit side by side: 1 stacks, 2+ fills across.
- One height is used for every button in a card, taken from its longest label,
  so a card stays a grid rather than a ragged stack.
- Cards flow left to right and wrap when the next would overhang.
- A card gap of 10px separates cards; 3px separates buttons within one.

**Hovering a callout** shows the enemy name and the full macro text, so a
truncated label is still readable.

**Pressing a callout** posts it immediately. There is no confirmation, no
cooldown, no visual "sent" acknowledgement beyond the message appearing in chat.
This is intentional — during a pull the chat frame *is* the feedback — but it is
a legitimate design question.

**Page arrows** step the route. They are secure buttons and work in combat.

**Scale.** Button scale (0.6–1.8) and text scale (0.6–1.6) are separate
settings, deliberately: a bigger hit target and a bigger caption are different
needs, and one should not force the other.

---

## 5. The Edit screen — header

Top-right, directly under the bar's icons: `<-` **undo** and `->` **redo**
(26×20 each). Multi-step, and they take you back to the screen, tab and page
where the change was made rather than leaving you to find it. Greyed when there
is nothing to undo.

The dungeon name is centred, 16pt, gold.

Then, top-left downward:

**Row 1 — Dungeon UI Color** (122×20) plus an 18×18 swatch showing the current
colour. Opens the colour picker.

**Row 2 — Override chat channel**: a 16×16 check box, its label, and a 66px
dropdown that **appears only when the box is checked**. See §11.4.

**Row 3 — Variant**: label, a 120px dropdown, and right-aligned **New** (42),
**Rename** (62), **Delete** (56). The three are anchored right-to-left from the
panel edge so the row cannot overrun at a narrow window.

**Row 4 — the tabs**: **Enemies** and **Pages**, side by side at the left,
selected one highlighted with `accent`. At the right of the same line: a
character counter (only while typing into a box) and an "N edits unbacked"
warning (only past 20 edits).

Below that, the tab's panel.

---

## 6. The Edit screen — Enemies tab

A hint line at the top: *"Plain text is sent to /i (this dungeon). Start a line
with /cast, /i or any command to run it as written."* — it names the **level**
the channel came from, not just the channel.

Beneath it, three sort controls:
- **Order: manual / Order: A-Z** (110×18) — toggles.
- **normal / reversed** (90×18) — direction.
- **Keep this order** (110×18) — appears only when a sort is active; bakes the
  displayed order into the stored order.

Under alphabetical sort the reorder arrows go **disabled** rather than doing
something arbitrary, because "up" has no stable meaning there.

### The enemy card (the main working surface)

Each enemy is a bordered panel containing:

```
┌────────────────────────────────────────────────┐
│ [ Enemy name box                ]  [^] [v] [x] │
│                                                │
│    [ callout line box                   ] [-]  │
│    [ callout line box                   ] [-]  │
│                                                │
│    [+ line]  [per row: 1]                      │
└────────────────────────────────────────────────┘
```

- The **name box** is edited in place. Enter commits; clicking away commits.
- `^` `v` reorder among enemies; `x` deletes with confirmation.
- **Line boxes** are multi-line and grow to fit their text — always, whether
  focused or not. They cannot truncate (an edit box has no ellipsis), so a box
  one line short would paint its last line over the row below. Height comes
  from the client's own wrapped measurement, not from dividing widths.
- Enter inside a line box commits and releases rather than inserting a newline,
  because a newline in a macro body would break the macro.
- `-` deletes that line.
- A **key badge** appears in a line box's corner if a key is bound to it, and
  hovering it lists every page that line is bound on.
- **+ line** adds an empty line. **per row** cycles 1 → 2 → 3 → 4 → 1.

Spacing is deliberate: 6px under the name, 4px between lines, **16px between
cards**, plus the border. Even spacing inside and a wide gap outside is what
makes a card read as one thing.

---

## 7. The Edit screen — Pages tab

**The page row**, anchored from both ends so it cannot overrun:

```
[<]  [ page name box            ]  [>]  page 1 of 3   [Keybinds] [Delete page]
```

Everything is a fixed size except the name box, which takes whatever is left.
Laid out left-to-right from a fixed-width box, this row ran off the panel at a
narrow window and drew "page 1 of 3" through the Keybinds button.

The name box is also **the list of pages**: single click opens a dropdown of all
pages, double click puts the cursor in it to rename. See §11.3.

**Row 2** — the page-level Override chat channel control, identical to the
dungeon's.

**Below** — two lists, scrolling:

| Section | Row contents |
| --- | --- |
| enemies **on** this page | name + line count, `^`, `v`, **remove** |
| *"Not on this page"* | name in grey, **add** |

Removing from a page never deletes the enemy. Deleting an enemy is on the
Enemies tab only, so tidying a route cannot destroy text.

Row labels are bounded on the right by the first button, word-wrap off, so a
long enemy name ends in an ellipsis instead of running through the buttons.

---

## 8. The Edit screen — bottom row

Pinned to the bottom of the Edit panel, right-aligned:

```
Name an enemy and press Enter, or use Add
[ name box                  ] [Add] [Add target] [Export]
```

- The label changes with the tab: *"Name an enemy…"* / *"Name a page…"*.
- **Add** (50×20) creates whatever the current tab is about.
- **Add target** (78×20) adds your current in-game target by its exact name.
  There is also a keybind for this. It is the one place the addon reads game
  state, and only when asked.
- **Export** (54×20) produces a string for the open dungeon.

---

## 9. The Settings screen

A single scrolling column. Takes the whole body; the dungeon list is hidden.

**Send plain text to** — a button that cycles `/p → /i → /raid → /say → /rw →
/y`. Cycling rather than a dropdown is an inconsistency with the override
controls, which use dropdowns for the same choice.

Then four **slider rows**, each: label, 190px slider, typed value box, **Reset**.

| Row | Range | Applies |
| --- | --- | --- |
| Opacity | 0.2–1.0 | live |
| Window scale | 0.6–1.6 | on release |
| Button scale | 0.6–1.8 | live |
| Text scale | 0.6–1.6 | live |

Window scale commits on release, alone among them: scaling the window moves the
slider out from under the cursor, which makes it nearly impossible to aim. The
number still updates as you drag, so there is feedback.

**Keybinds** — Open/close addon (click, then press a key; right-click clears),
plus two check-style toggles for whether key badges show in Run and in Edit.

**Colours** — five rows, each a swatch, a named button opening the picker, and
per-row reset inside the picker. Plus **Reset colours**.

**Profile** — two rows:

```
Loaded  [ profile dropdown        ]  [Save as...]
        [Rename] [Delete] [Export] [Import] [As sheet]
```

- **Save as** names and keeps a copy of everything as it is now, and loads it.
- **Import** replaces the loaded profile — see §11.5.
- **As sheet** writes the profile out as tab-separated rows.

**Reset all** at the bottom, with a note that scale and opacity apply out of
combat only. It deliberately does **not** clear keybinds: resetting sliders
should not silently take away a binding.

---

## 10. Dialogs

All are **modal**: a full-window blocker swallows clicks aimed at the panel
underneath, so what is being asked about cannot be changed or deleted twice
while the question is up. All have opaque grounds — a question you must answer
should not show the thing it is asking about faintly through itself.

### 10.1 Confirmation (320×140, or 440 with three answers)

Title, body text, and buttons along the bottom right. The destructive answer
sits **rightmost**, away from where the cursor lands coming off the button that
opened the dialog. Cancel is to its left. A third answer, when there is one,
goes left of Cancel.

Used for: deleting a dungeon, deleting a profile, importing over a profile.

### 10.2 Name prompt (340×130)

Title, one edit box, **Cancel** and an accept button. Enter submits. Escape
closes. Used for saving and renaming profiles.

### 10.3 Colour picker

```
┌──────────────────────────────────────────────────┐
│                Dungeon UI Color                  │
│  ┌────────────────────┐ ┌─┐  ┌──────────┐        │
│  │ saturation ▸       │ │h│  │ result   │        │
│  │ brightness ▾       │ │u│  └──────────┘        │
│  │        ▪ marker    │ │e│  Hue    [───] [117]  │
│  └────────────────────┘ └─┘  Sat    [───] [ 62]  │
│                              Bright [───] [ 78]  │
│  [Reset]                              [Done]     │
└──────────────────────────────────────────────────┘
```

- A **24×16 grid** of 9px swatches: saturation across, brightness down.
- A **32-step hue strip** beside it.
- Both carry a **marker** — a white outline on a black outline, so it stays
  visible on any colour underneath.
- Three sliders with typed boxes for exact values.
- Built from flat swatches rather than gradients on purpose: `SetGradient`
  changed signature in 10.0 and the addon cannot verify from outside the game
  which form a client wants. A grid of solid colours needs no such API and is
  exact to click.
- Changes apply **live** as you move, so the colour is judged on the interface
  it will be used on rather than on a swatch.

### 10.4 Keybind dialog (430 wide)

Opened from Keybinds on the Pages tab. Lists every callout on the current page,
each row showing the enemy name in that dungeon's colour, the callout text, and
a button reading the current key or **Set**.

Click the button → it reads "press a key" and the help line turns gold: *"Press
a key. Escape cancels."* Press any key to bind. Escape cancels. There is a
**10-second timeout** that releases the keyboard regardless.

A conflicting key is refused with a message naming what already holds it.
**Clear all** at the bottom left.

The timeout exists because an earlier version could hold the keyboard forever if
its release path was missed — the game stopped responding to every key,
including Escape, and only Alt-F4 recovered it. Anything touching keyboard
capture in this addon is treated as high-risk.

### 10.5 String window (560×300)

Used for export, import and help. A scrolling multi-line box, plus:

- **Done typing** — releases the keyboard.
- **Select all** — selects the contents for copying.
- an action button, **Import** when importing.

It never takes focus by itself. An earlier version auto-selected the text on
open, which pulls focus into a multi-line edit box, which then receives every
key you press — indistinguishable from the game breaking.

### 10.6 Help

The string window in read-only use, listing what each screen does, what combat
blocks, how saving works, the character limit, the spreadsheet format, the
channel override rules, and the slash commands.

---

## 11. Interaction patterns

These recur, and are worth understanding as patterns rather than per-control.

### 11.1 Edit in place

Names are not edited in dialogs. Double-click a dungeon row, or click an enemy
name, and you are typing in the thing itself. **Enter commits. Clicking away
commits. Escape abandons.** Committing on lost focus is consistent everywhere —
a name typed and then clicked away from is kept, not quietly dropped.

### 11.2 Confirm before destroying

Every destructive action asks: deleting a dungeon, an enemy, a profile,
importing over a profile. Deleting a *line* or removing an enemy *from a page*
does not ask — they are small and undoable.

Undo/redo covers everything Edit changes, up to 30 steps, and returns you to
where the change happened.

### 11.3 Click to pick, double-click to rename

Where a box shows the name of one of several things — currently the page name —
a single click opens the whole list and a double click lets you rename. The
click is taken by an invisible button covering the box, because an edit box
takes focus the instant it is clicked and cannot be asked not to.

The dungeon list uses the same double-click-to-rename gesture.

### 11.4 Toggle plus chooser

An override is a check box *and* a dropdown, with the dropdown hidden while the
box is unchecked. Off means "follow the level above" — which is why it cannot
just be a chooser: picking `/p` is not the same as saying nothing, because the
level above can change later.

### 11.5 Three answers where there are three

Importing over a profile offers **Save and import** / **Don't save, import** /
**Cancel**. Keeping the old profile and throwing it away are different
decisions; folding them into one button would make the safe answer and the
destructive answer the same click, on the one action in the addon with no undo.

The string is decoded and validated **before** the question is asked, so a bad
paste says so instead of offering to destroy a profile for nothing.

### 11.6 Refuse loudly rather than fail silently

Anything combat forbids prints a red message saying so. A view switch requested
in combat is remembered and made when combat ends. The failure mode this avoids
— the game silently ignoring the call — once produced half a screen switch, with
Edit drawn underneath Run's callouts and both sets of text on screen at once.

---

## 12. State, feedback and error handling

**Selection** is shown by an accent-filled button: the current dungeon row, the
current tab, the current view.

**Disabled** is a dimmed label, not a hidden control — undo/redo when there is
nothing to undo, the reorder arrows under alphabetical sort.

**Absent** is a hidden control: the variant row when no dungeon is open, the
override dropdown when the toggle is off, the "Keep this order" button when
there is nothing to keep, a key badge with no key.

**Feedback** is chat messages, in the addon's own purple prefix. Errors are red.
There is no toast, no status bar, no inline validation.

**The staleness warning** — "N edits unbacked" appears in the Edit header past
20 edits. WoW writes addon data on logout or `/reload`, not continuously, so a
crash takes everything since. Exporting resets the counter.

**Character counter** — appears in the Edit header while a line box has focus,
counting down from the limit. The limit is the composed length including the
channel prefix, so a line cannot be typed into a length that only fails on
write.

**Empty states** — "Nothing yet." in the dungeon list, "Pick a dungeon on the
left." in Run, "Pick a dungeon on the left, or make one with New dungeon." in
Edit.

**Errors the player sees** are all in plain language, never a code: *"the string
is damaged or incomplete — check you copied all of it"*, *"that name is taken,
or empty"*, *"can't change keys in combat"*.

---

## 13. Where the interface is known to be weak

Stated honestly, because a review that rediscovers these is a wasted review.

1. **Two different controls for the same choice.** Settings picks a channel with
   a **cycling button**; the dungeon and page overrides pick one with a
   **dropdown**. Same six options, two mechanics.
2. **No click-outside-to-close on dropdowns.** They close on selection or on
   clicking the button again. Nothing else dismisses them.
3. **Settings is not responsive.** It is a fixed-width scrolling page that
   scrolls vertically only. It fits at the minimum window width today, but
   nothing prevents a future row from reaching past the right edge, where a
   control is not merely ugly but unclickable.
4. **Settings is a modal-ish screen, not a tab.** It replaces the body and hides
   the dungeon list, unlike Run and Edit which are peers.
5. **No visible confirmation that a callout was sent.** The chat frame is the
   feedback. Reasonable during a pull, questionable when testing.
6. **Discovery relies entirely on tooltips.** There is no first-run experience.
   Double-click-to-rename and click-to-pick are announced in one hint line and a
   tooltip respectively.
7. **"per row" is opaque.** It now has a tooltip explaining it, but the label
   itself still says nothing about what it does.
8. **The variant feature is barely surfaced.** It occupies a whole header row
   for something most players will never use.
9. **Undo has no visible history.** Two arrows and no indication of what the
   next press will undo.
10. **The dungeon list is not searchable or filterable.** With eight dungeons it
    scrolls; with thirty it would be unusable.
11. **No keyboard navigation between controls.** No tab order, no focus ring.
    Everything is mouse-driven except the callout keybinds themselves.
12. **Colour is used for meaning in places** — the danger red on delete buttons,
    the accent on selection — with no secondary cue such as an icon or a shape.

---

## 14. What advice can and cannot be applied

**Applies well:** grouping and hierarchy, labelling and wording, affordance,
where confirmations belong, progressive disclosure, error message quality,
spacing and rhythm, consistency between controls that do the same job,
information density, reducing the number of steps to a goal.

**Applies with care:** anything about size or spacing, because the window is
resizable from 560×300 upward with three independent scale settings, and any
fixed number has to hold across all of that.

**Does not apply:** animation and transitions, hover delays, drop shadows,
gradients, rounded corners, custom fonts, responsive breakpoints, modal overlays
that dim the rest of the screen, anything depending on a layout engine. The
platform has none of these, and several would need hand-written per-frame code
that runs during combat, which is the one time the addon must not do extra work.

**Never applies:** anything requiring the addon to know what is happening in the
fight. It reads almost nothing from the game on purpose. Suggestions of the form
"it could detect X and automatically Y" are a change of direction, not a
refinement, and should be raised as such.
