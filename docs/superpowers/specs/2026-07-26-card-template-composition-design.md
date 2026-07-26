# Card template composition

Replace the three pre-composed card faces with two reusable frame templates
that `CardView` composes at runtime: illustration, frame, and four text zones
drawn from `CardData`.

## Why

Today `assets/cards/card_<id>.png` is a finished card face — title, artwork,
value badge, rules text and cost badge all painted in. That has three costs the
project already documents and works around:

1. **The printed numbers can lie.** `JAB_DAMAGE`, `STRAIGHT_DAMAGE`,
   `BLOCK_GUARD`, `JAB_COST`, `STRAIGHT_COST` are baked into the art. Changing
   one makes the card disagree with the game until someone repaints it.
   `CLAUDE.md` carries a standing "check it by eye after any balance change"
   warning for exactly this.
2. **One face is already wrong.** `card_straight.png` prints *"Combo: If Jab was
   played earlier this turn, deal 50% more damage."* The real rule requires Jab
   to *immediately* precede, and adds 50% of both cards' *combined* base damage
   (+7, for a 16-damage Straight). `CLAUDE.md` documents this as a known
   discrepancy the code wins.
3. **Every new card needs a full painted face**, not just an illustration.

Composing at runtime removes all three. The number on the card becomes the
number the game uses, by construction.

## Decisions

| Question | Decision |
|---|---|
| Where does the badge number come from? | Derived from effects — no new data |
| What does Straight's description say? | The real combo rule, generated from `BattleConfig` |
| Typography | Project default font; sizes and colours behind one constant block |
| Fate of the old faces | Deleted, but only after the new path is verified on screen |

### Badge value is derived, never stored

Attack cards show the sum of their `DamageEffect` amounts; defense cards show
the sum of their `GuardEffect` amounts. `CardData.total_base_damage()` already
exists in core for the combo maths; `total_guard()` joins it.

A second `badge_value` field was rejected: it is a second source of truth that
can drift from the effects, which is the precise failure mode this pass exists
to eliminate. A card with neither effect renders an empty badge.

### Straight's rules text states the real rule

`tools/generate_cards.gd` computes the bonus the same way `ComboRule` does:

```gdscript
floori((BattleConfig.JAB_DAMAGE + BattleConfig.STRAIGHT_DAMAGE)
       * BattleConfig.COMBO_BONUS_RATIO)   # == 7
```

and emits `"Deal 9 damage. Combo: right after Jab, deal +7."` Because it is
generated, a balance change regenerates correct text rather than stale text.

## Assets

```
assets/frames/attack.png            <- attack_card_template.png
assets/frames/defense.png           <- defense_card_template.png
assets/illustrations/jab.png        <- Jab.png
assets/illustrations/straight.png   <- Straight.png
assets/illustrations/block.png      <- Block.png
assets/cards/                       deleted last (see Sequencing)
```

Frames are 1024x1536 — exactly `CARD_SIZE`'s 2:3, so no cropping. Illustrations
are 1448x1086 (4:3) against a 1.48:1 window, so `KEEP_ASPECT_COVERED` trims
about 5% from top and bottom; all three have the headroom.

Both frame `.import` files must set `mipmaps/generate=true`. The previous
composed art had it; the templates as imported do not. Cards render at 200x300
from a 1024-wide source — a 5.1x downscale — and they sway and rotate
continuously, so missing mipmaps produce shimmer, not merely softness.

## Rendering

`CardView`'s single `_art` `TextureRect` becomes six layers, bottom to top:

| # | Node | Content |
|---|---|---|
| 1 | `_illustration` | window rect, `KEEP_ASPECT_COVERED`, clipped |
| 2 | `_frame` | full rect, selected by `card.has_tag(&"defense")` |
| 3 | `_title` | `display_name`, on the ribbon |
| 4 | `_value` | derived number, in the badge |
| 5 | `_rules` | rules text, on the parchment |
| 6 | `_cost` | `cost`, in the blue circle |

### `scripts/ui/card_template.gd` (new)

Owns frame paths, zone rects, font sizes and colours for the two variants.
Card-face geometry is layout, and `CLAUDE.md` keeps layout constants with their
owner — this file is that owner. Juice (durations, curves, magnitudes) stays in
`juice.gd`; balance stays in `BattleConfig`.

Zones are stored **normalized to 0–1** fractions of the card rect so they
survive a `CARD_SIZE` change. Measured from the template pixels:

| Zone | Attack | Defense | @200x300 |
|---|---|---|---|
| title | (.146,.127)–(.859,.221) | same | 143x28 |
| window | (.154,.253)–(.848,.565) | same | 139x94 |
| value centre | **(.591,.610)** | **(.487,.605)** | (118,183) / (97,182) |
| value box | **.100 x .070** | **.150 x .090** | 20x21 / 30x27 |
| rules | (.175,.665)–(.695,.860) | same | 104x59 |
| cost centre | **(.788,.815)** | **(.763,.814)** | (158,245) / (153,244) |

Title, rules and window are stored as rects; value and cost are stored as a
centre plus a box, because both are centred on a drawn icon rather than fitted
to a panel. The two frame variants are keyed `attack` and `defense`.

Only the value and cost zones differ between variants; title, window and rules
are identical on both frames. Attack's value sits in the free red
plate to the right of the burst icon; defense's is centred in the shield. The
rules box stops at x .695 to clear the cost circle on both frames — attack's
begins at .723, defense's at .699.

Typography constants live in one block so a display font can be dropped in
later as a one-line change:

```gdscript
const FONT: Font = null   # null = project default
const TITLE_SIZE := 17
const VALUE_SIZE := 22
const COST_SIZE  := 18
const RULES_SIZE := 11
```

Title, value and cost get a dark outline (they sit on red, red and blue). Rules
text is dark brown on parchment and needs none.

### The coloured-rectangle fallback is removed

`CardView` currently falls back to a coloured rectangle with labels when
`CardArt.texture_for()` finds no file, and `CLAUDE.md` calls this an intentional
degradation path. It becomes unreachable: a frame is selected by tag, not looked
up by id, so every card always has one.

The degradation path for a card whose art is not painted yet becomes an **empty
illustration window** inside a complete, correct frame — still real, still
visibly different, and strictly more useful than a coloured box. `debug_text()`
survives, reporting title, value, rules and cost.

### Combo highlight

`set_combo_armed()` tints `_frame.modulate` where it previously tinted
`_art.modulate`. Idempotency is unchanged and non-negotiable: always computed
from a fixed base (`Color.WHITE`), never lerped from the live value — the
progressive gold drift bug must not return. The illustration stays untinted so
the artwork reads true.

## Changes

- **new** `scripts/ui/card_template.gd`
- `scripts/ui/card_art.gd` — resolves illustrations by id
  (`assets/illustrations/<id>.png`) and frames by variant
  (`assets/frames/<variant>.png`); keeps the cache and the
  null-on-missing-without-`push_error` contract
- `scripts/ui/card_view.gd` — six-layer composition; fallback rectangle removed
- `scripts/core/card_data.gd` — `total_guard()`
- `tools/generate_cards.gd` — combo line in Straight's `rules_text`
- `resources/cards/straight.tres` — regenerated
- `tests/suites/test_card_art.gd`, `tests/suites/test_card_view.gd` — updated;
  **new** `tests/suites/test_card_template.gd`
- `CLAUDE.md` — Card art section rewritten
- `project.godot` — comments restored (see below)

### `project.godot`

Importing the new PNGs made the editor rewrite `project.godot`, stripping every
comment plus the viewport and stretch keys. This is functionally inert — each
dropped key equalled a Godot default — but the comments explained the
1152x648-design-space-scaled-to-2560x1440 arrangement and the clear-colour
choice that keeps `ScreenFx.shake()` from flashing grey. Restore them.

## Verification

Automated checks (headless suite):

- `total_guard()` / `total_base_damage()` produce 5 / 6 / 9 for block / jab /
  straight
- template selection follows the `defense` tag
- both frame textures and all three illustrations resolve; an unknown id
  resolves to null
- every zone rect lies inside the card rect
- the rules box does not overlap either variant's cost circle

What automated checks **cannot** establish is whether the number actually lands
inside the shield. This project's most expensive lesson is that 387 green tests
sat on top of an animation that produced no motion, because the assertion
checked the target value rather than the rendered result. The same trap applies
here in its static form: a test asserting `_value.position == zone.position`
proves the code did what the code says, not that the layout is right.

So the acceptance step is a **screenshot of all three cards at 200x300**,
checked by eye, with the zone numbers tuned against it. The table above is
measured-and-plausible, not final; expect one round of nudging.

Two things to look at specifically:

- whether a gold tint on an already-gold frame reads as *combo armed*
- whether font 11 rules text is legible at 104x59

## Sequencing

The old faces in `assets/cards/` are deleted **last**, after the composed
rendering is verified on screen — not as part of the cutover. Until then they
remain in the tree, unreferenced. This keeps a known-good card render available
for comparison while the new one is being tuned, and means a problem found
during verification does not also require restoring 7.8 MB of art from git.
