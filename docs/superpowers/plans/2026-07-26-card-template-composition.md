# Card Template Composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three pre-composed card face PNGs with two reusable frame templates that `CardView` composes at runtime from illustration + frame + four data-driven text zones.

**Architecture:** A new `scripts/ui/card_template.gd` owns card-face geometry as normalized 0–1 zones plus typography constants. `CardArt` grows two convention-based lookups — illustrations by card id, frames by variant. `CardView`'s single art `TextureRect` becomes a six-layer stack it positions from the template. The badge number derives from the card's own effects, so it cannot disagree with the rules.

**Tech Stack:** Godot 4.5.1, typed GDScript. No new dependencies, no new fonts.

## Global Constraints

Copied from the spec and `CLAUDE.md`. Every task's requirements implicitly include this section.

- **Typed GDScript.** Explicit parameter and return types on every function.
- **`PascalCase` class names, `snake_case` members, leading `_` for private.**
- **Integer helpers `mini()` / `maxi()` / `floori()`** — never the float versions.
- **UI text is ASCII.** The default font renders no emoji or symbol glyphs.
- **`scripts/core/` never references `Node`, `SceneTree`, or any scene-tree API.** Only `RefCounted`/`Resource`. Only Task 2 touches core, and it adds a pure function.
- **Run tests with `./tests/run_tests.sh`, never `run_tests.gd` directly.** The wrapper runs a mandatory `--import` and fails on engine error markers (`SCRIPT ERROR`, `Parse Error`, `Invalid call`) even when the exit code is 0. Direct invocation reports false PASSes.
- **Baseline is `436 checks, 0 failures` / `PASS`.** Every task must end green. Check counts grow as tasks add tests; they must never shrink except where a task explicitly removes tests.
- **Every suite starts with exactly this preamble:**
  ```gdscript
  extends RefCounted

  const TestRunner := preload("res://tests/run_tests.gd")

  func run(t: TestRunner) -> void:
  ```
  Suites are auto-discovered from `tests/suites/test_*.gd` — there is no registry to edit. The local `preload` const is only for `TestRunner`; game classes are referenced by global name.
- **Commit `.uid` sidecars.** Stage with `git add -A`. A `.uid` tracked on one branch but untracked on another aborts a merge; this has happened twice.
- **Godot binary path contains a space — always quote it:**
  `"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"`
- **Tweens must target `target_position` / `target_rotation` / `target_scale`, never `position` / `rotation` / `scale`.** No task here adds a tween, but Task 5 rewrites `CardView` and must not disturb this.
- **`create_tween()` off-tree pushes an engine error and fails the suite.** Tests build `CardView` detached, so every animation entry point keeps its `is_inside_tree()` guard.

---

### Task 1: Move the assets into place and enable mipmaps

The five new PNGs are sitting untracked at the top of `assets/` under ad-hoc names. Nothing references them yet, so this task is pure asset plumbing and the suite must stay at exactly 436.

**Files:**
- Move: `assets/attack_card_template.png` → `assets/frames/attack.png`
- Move: `assets/defense_card_template.png` → `assets/frames/defense.png`
- Move: `assets/Jab.png` → `assets/illustrations/jab.png`
- Move: `assets/Straight.png` → `assets/illustrations/straight.png`
- Move: `assets/Block.png` → `assets/illustrations/block.png`
- Delete: `assets/attack_card_template.png.import`, `assets/defense_card_template.png.import`

**Interfaces:**
- Consumes: nothing.
- Produces: `res://assets/frames/attack.png`, `res://assets/frames/defense.png`, `res://assets/illustrations/{jab,straight,block}.png`, each with `mipmaps/generate=true`. Task 3 resolves these paths.

- [ ] **Step 1: Move the files**

Plain `mv`, not `git mv` — all five are untracked, so `git mv` errors. The two stale `.import` files must go: they carry the old `source_file` path and would leave Godot importing a file that no longer exists.

```bash
cd "/Users/mihai/Godot games/mma-cards"
mkdir -p assets/frames assets/illustrations
mv assets/attack_card_template.png  assets/frames/attack.png
mv assets/defense_card_template.png assets/frames/defense.png
mv assets/Jab.png                   assets/illustrations/jab.png
mv assets/Straight.png              assets/illustrations/straight.png
mv assets/Block.png                 assets/illustrations/block.png
rm -f assets/attack_card_template.png.import assets/defense_card_template.png.import
```

- [ ] **Step 2: Import, so Godot writes fresh `.import` files at the new paths**

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless --path . --import
```

Expected: exit 0, and five new `.import` files exist.

```bash
ls assets/frames/*.import assets/illustrations/*.import
```

Expected: exactly 5 files.

- [ ] **Step 3: Turn mipmaps on**

Cards render at 200x300 from a 1024-wide frame (5.1x downscale) and a 1448-wide illustration (10.4x downscale), and they sway and rotate continuously. Without mipmaps that is shimmer during motion, not merely softness. The retired composed art had `mipmaps/generate=true`; the fresh imports default to `false`.

```bash
cd "/Users/mihai/Godot games/mma-cards"
perl -pi -e 's{^mipmaps/generate=false$}{mipmaps/generate=true}' \
  assets/frames/*.png.import assets/illustrations/*.png.import
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless --path . --import
```

- [ ] **Step 4: Verify every one of the five took**

```bash
grep -H '^mipmaps/generate=' assets/frames/*.import assets/illustrations/*.import
```

Expected: 5 lines, all `mipmaps/generate=true`. If any still says `false`, the `perl` substitution missed it — fix that file before continuing.

- [ ] **Step 5: Run the suite**

```bash
./tests/run_tests.sh
```

Expected: `436 checks, 0 failures` / `PASS`. Nothing references the new paths yet, so an unchanged count is the correct result here.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Move the card frames and illustrations into place

Five new PNGs land under assets/frames/ and assets/illustrations/ on the
naming convention CardArt will resolve. Mipmaps on: cards draw at a 5x
(frame) and 10x (illustration) downscale while swaying, so without them
the downscale shimmers rather than merely softening."
```

---

### Task 2: `CardData.total_guard()`

The badge number derives from effects rather than a stored field. `total_base_damage()` already exists for the combo maths; this is its sibling.

**Files:**
- Modify: `scripts/core/card_data.gd`
- Test: `tests/suites/test_card_library.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `CardData.total_guard() -> int`. Task 5 calls it.

- [ ] **Step 1: Write the failing test**

Add this function to `tests/suites/test_card_library.gd`, and add `_test_effect_totals(t)` to the existing `run()` body:

```gdscript
## The badge number on a composed card face is derived from these two, never
## stored, so they are what stops a card printing a value the rules disagree
## with. Both must return 0 rather than push_error for a card of the other
## kind -- CardView reads both and shows the one its frame calls for.
func _test_effect_totals(t: TestRunner) -> void:
	var blocker: CardData = CardLibrary.load_card(&"block")
	t.check_eq(blocker.total_guard(), BattleConfig.BLOCK_GUARD,
		"block's total_guard() is BattleConfig.BLOCK_GUARD")
	t.check_eq(blocker.total_base_damage(), 0,
		"a card with no DamageEffect totals zero damage")

	var jab: CardData = CardLibrary.load_card(&"jab")
	t.check_eq(jab.total_guard(), 0, "a card with no GuardEffect totals zero guard")
	t.check_eq(jab.total_base_damage(), BattleConfig.JAB_DAMAGE,
		"jab's total_base_damage() is BattleConfig.JAB_DAMAGE")

	var empty := CardData.new()
	t.check_eq(empty.total_guard(), 0, "a card with no effects at all totals zero guard")
	t.check_eq(empty.total_base_damage(), 0, "a card with no effects at all totals zero damage")
```

- [ ] **Step 2: Run tests to verify it fails**

```bash
./tests/run_tests.sh
```

Expected: FAIL. The wrapper reports `run_tests.sh: FAIL (engine error marker found in output despite exit code 0)` because `total_guard()` does not exist — an `Invalid call` marker. That marker, not a check failure, is the expected signal here.

- [ ] **Step 3: Implement**

In `scripts/core/card_data.gd`, directly below `total_base_damage()`:

```gdscript
## Total guard this card grants. Mirrors total_base_damage(), and exists for
## the same reason: the composed card face derives its badge number from the
## effects rather than from a stored field, so the printed value cannot drift
## from what the card actually does.
func total_guard() -> int:
	var total: int = 0
	for effect: CardEffect in effects:
		if effect is GuardEffect:
			total += (effect as GuardEffect).amount
	return total
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./tests/run_tests.sh
```

Expected: `442 checks, 0 failures` / `PASS`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add CardData.total_guard() beside total_base_damage()

The composed card face derives its badge number from the card's effects
rather than a stored field, so the two totals are the whole mechanism
that keeps a printed number from disagreeing with the rules."
```

---

### Task 3: `CardArt` resolves illustrations and frames

Two conventions replace one. Illustrations are per card id; frames are per variant, so a new card needs only an illustration — its frame already exists.

**Files:**
- Modify: `scripts/ui/card_art.gd` (full rewrite)
- Test: `tests/suites/test_card_art.gd` (full rewrite)

**Interfaces:**
- Consumes: the asset paths from Task 1.
- Produces: `CardArt.illustration_for(card_id: StringName) -> Texture2D`, `CardArt.frame_for(variant: StringName) -> Texture2D`. Both return `null` for a missing file, without `push_error`. `CardArt.texture_for()` is **removed**. Task 5 calls both.

- [ ] **Step 1: Write the failing tests**

Replace the whole body of `tests/suites/test_card_art.gd` below the preamble:

```gdscript
func run(t: TestRunner) -> void:
	_test_illustrations_load(t)
	_test_frames_load(t)
	_test_missing_illustration_returns_null(t)
	_test_results_are_cached(t)
	_test_illustrations_and_frames_do_not_collide(t)

func _test_illustrations_load(t: TestRunner) -> void:
	for card_id: StringName in [&"jab", &"straight", &"block"]:
		var texture: Texture2D = CardArt.illustration_for(card_id)
		t.check(texture != null, "%s resolves to an illustration texture" % card_id)

func _test_frames_load(t: TestRunner) -> void:
	# Frames are looked up per variant, not per card, which is what lets a new
	# card ship with only an illustration.
	t.check(CardArt.frame_for(&"attack") != null, "the attack frame resolves to a texture")
	t.check(CardArt.frame_for(&"defense") != null, "the defense frame resolves to a texture")

func _test_missing_illustration_returns_null(t: TestRunner) -> void:
	# A card authored before its art exists is a legitimate state -- it renders
	# a complete frame around an empty window -- so this must stay quiet rather
	# than push_error.
	var texture: Texture2D = CardArt.illustration_for(&"no_such_card_id")
	t.check(texture == null, "an id with no matching illustration resolves to null")

func _test_results_are_cached(t: TestRunner) -> void:
	# Godot's `==` on Objects is reference equality, so this is a real identity
	# check: the same object twice proves the second call served the cache
	# rather than reloading the file.
	var first: Texture2D = CardArt.illustration_for(&"block")
	var second: Texture2D = CardArt.illustration_for(&"block")
	t.check(first == second, "repeated illustration lookups return the identical cached texture")

	var frame_first: Texture2D = CardArt.frame_for(&"defense")
	var frame_second: Texture2D = CardArt.frame_for(&"defense")
	t.check(frame_first == frame_second, "repeated frame lookups return the identical cached texture")

## The two lookups share one cache. Keying it by card id or variant name alone
## would collide the moment someone adds a card with id "attack": its
## illustration and the attack frame would map to the same key and serve each
## other's texture. Keying by resolved path cannot collide, and this is the
## check that holds that.
func _test_illustrations_and_frames_do_not_collide(t: TestRunner) -> void:
	var attack_frame: Texture2D = CardArt.frame_for(&"attack")
	var attack_illustration: Texture2D = CardArt.illustration_for(&"attack")
	t.check(attack_frame != null, "the attack frame still resolves")
	t.check(attack_illustration == null,
		"no illustration exists for the id 'attack', and the frame of that name does not stand in for one")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./tests/run_tests.sh
```

Expected: FAIL with an `Invalid call` marker — `illustration_for` and `frame_for` do not exist yet.

- [ ] **Step 3: Rewrite `scripts/ui/card_art.gd`**

Replace the file entirely:

```gdscript
class_name CardArt
extends RefCounted

## Two kinds of image, both found by convention rather than a lookup table:
##
##   illustration_for(&"jab")  -> res://assets/illustrations/jab.png
##   frame_for(&"attack")      -> res://assets/frames/attack.png
##
## Illustrations are per card id; frames are per template variant. That
## asymmetry is the point: adding a card means authoring a .tres and dropping
## in one illustration -- the frame it wears already exists, chosen by tag.
##
## Deliberately lives in scripts/ui/ rather than as a field on CardData:
## scripts/core/ has stayed free of presentation concerns for four passes, and
## a texture pointer is presentation.

const ILLUSTRATION_DIR: String = "res://assets/illustrations"
const FRAME_DIR: String = "res://assets/frames"

## Keyed by RESOLVED PATH, not by id or variant. Keying by the bare name would
## collide the day someone adds a card with id "attack": its illustration and
## the attack frame would share a key and serve each other's texture. A missing
## file caches to null too, so a card without an illustration only ever pays
## the ResourceLoader.exists() check once, same as a hit.
static var _cache: Dictionary = {}

## Returns null when no illustration exists for this id. That is a legitimate
## fallback -- an empty window inside an otherwise complete frame, which is
## what a card looks like before its art is painted -- not an error, so this
## never push_errors.
static func illustration_for(card_id: StringName) -> Texture2D:
	return _load("%s/%s.png" % [ILLUSTRATION_DIR, card_id])

## Returns null only if a frame asset is missing, which is a broken install
## rather than a fallback. It still stays quiet: CardView draws a null frame
## the same way it draws a null illustration, and a push_error here would fire
## on every card in the hand every rebuild.
static func frame_for(variant: StringName) -> Texture2D:
	return _load("%s/%s.png" % [FRAME_DIR, variant])

static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_cache[path] = texture
	return texture
```

- [ ] **Step 4: Run tests**

```bash
./tests/run_tests.sh
```

Expected: FAIL — but now with real check failures from `tests/suites/test_card_view.gd`, which still calls `view._art` and expects `CardArt.texture_for()`. That is Task 5's job. To keep this task independently green, temporarily nothing else is needed: `test_card_view.gd` references `_art` (a member, not a method), so it fails as check failures rather than parse errors.

If instead the run reports a `Parse Error` or `Invalid call` marker from `test_card_view.gd`, that means it references `CardArt.texture_for()` directly — it does, on the line asserting `view._art.texture == CardArt.texture_for(&"jab")`. Resolve it by doing Task 5 in the same commit as this one. **Prefer that: land Task 3 and Task 5 together.** They are split here only because the interfaces are worth stating separately.

- [ ] **Step 5: Commit (together with Task 5)**

See Task 5, Step 6.

---

### Task 4: `CardTemplate` — card-face geometry and typography

**Files:**
- Create: `scripts/ui/card_template.gd`
- Test: `tests/suites/test_card_template.gd` (create)

**Interfaces:**
- Consumes: `CardData.has_tag()`.
- Produces:
  - `CardTemplate.ATTACK: StringName`, `CardTemplate.DEFENSE: StringName`
  - `CardTemplate.TITLE_ZONE / WINDOW_ZONE / RULES_ZONE: Rect2` (normalized)
  - `CardTemplate.VALUE_CENTRE / VALUE_BOX / COST_CENTRE: Dictionary` keyed by variant, `COST_BOX: Vector2`
  - `CardTemplate.FONT: Font`, `TITLE_SIZE / VALUE_SIZE / COST_SIZE / RULES_SIZE: int`
  - `CardTemplate.TITLE_COLOR / VALUE_COLOR / COST_COLOR / RULES_COLOR: Color`, `OUTLINE_SIZE: int`, `OUTLINE_COLOR: Color`
  - `CardTemplate.variant_for(card: CardData) -> StringName`
  - `CardTemplate.to_pixels(zone: Rect2, size: Vector2) -> Rect2`
  - `CardTemplate.centred_pixels(centre: Vector2, box: Vector2, size: Vector2) -> Rect2`
  - Task 5 consumes all of it.

> **Deviation from the spec, recorded deliberately:** the spec's rules-zone right edge of `.695` leaves only `0.0045` (0.9px at a 200px card) of clearance from the defense frame's cost circle at `.6995`. This plan tightens it to `.685` — about 3px — which is a real margin rather than a rounding artefact.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_card_template.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_variant_follows_the_defense_tag(t)
	_test_zones_are_normalized(t)
	_test_rules_zone_clears_both_cost_badges(t)
	_test_pixel_conversion(t)

func _test_variant_follows_the_defense_tag(t: TestRunner) -> void:
	# Tag-driven, so a new card needs no registration here.
	t.check_eq(CardTemplate.variant_for(CardLibrary.load_card(&"block")), CardTemplate.DEFENSE,
		"a card tagged defense wears the defense frame")
	t.check_eq(CardTemplate.variant_for(CardLibrary.load_card(&"jab")), CardTemplate.ATTACK,
		"a card without the defense tag wears the attack frame")

	var untagged := CardData.new()
	t.check_eq(CardTemplate.variant_for(untagged), CardTemplate.ATTACK,
		"a card with no tags at all falls to the attack frame rather than erroring")

## Zones are fractions of the card rect, not pixels, so CARD_SIZE can change
## without a re-measure. A value outside 0..1 means someone pasted a raw
## template pixel coordinate in by mistake.
func _test_zones_are_normalized(t: TestRunner) -> void:
	for named_zone: Array in [
		["title", CardTemplate.TITLE_ZONE],
		["window", CardTemplate.WINDOW_ZONE],
		["rules", CardTemplate.RULES_ZONE],
	]:
		var label: String = named_zone[0]
		var zone: Rect2 = named_zone[1]
		t.check(zone.position.x >= 0.0 and zone.position.y >= 0.0,
			"the %s zone starts inside the card" % label)
		t.check(zone.end.x <= 1.0 and zone.end.y <= 1.0,
			"the %s zone ends inside the card" % label)
		t.check(zone.size.x > 0.0 and zone.size.y > 0.0,
			"the %s zone has a positive size" % label)

	for variant: StringName in [CardTemplate.ATTACK, CardTemplate.DEFENSE]:
		var value: Rect2 = CardTemplate.centred_pixels(
			CardTemplate.VALUE_CENTRE[variant], CardTemplate.VALUE_BOX[variant], Vector2.ONE)
		t.check(value.position.x >= 0.0 and value.end.x <= 1.0,
			"the %s value badge sits inside the card horizontally" % variant)
		t.check(value.position.y >= 0.0 and value.end.y <= 1.0,
			"the %s value badge sits inside the card vertically" % variant)

## Measured from the template pixels: the cost circle is centred at x .788
## (attack) and .763 (defense) with a radius of about .065, so its left edge
## is .723 and .700. Rules text running under it would be unreadable, and
## nothing else in the project would catch that -- the layout draws fine, it
## just cannot be read.
func _test_rules_zone_clears_both_cost_badges(t: TestRunner) -> void:
	const COST_RADIUS: float = 0.066
	for variant: StringName in [CardTemplate.ATTACK, CardTemplate.DEFENSE]:
		var circle_left: float = CardTemplate.COST_CENTRE[variant].x - COST_RADIUS
		t.check(CardTemplate.RULES_ZONE.end.x < circle_left,
			"the rules zone ends before the %s cost badge begins" % variant)

func _test_pixel_conversion(t: TestRunner) -> void:
	var size := Vector2(200.0, 300.0)

	var title: Rect2 = CardTemplate.to_pixels(CardTemplate.TITLE_ZONE, size)
	t.check(is_equal_approx(title.position.x, CardTemplate.TITLE_ZONE.position.x * 200.0),
		"to_pixels scales the zone origin by the card size")
	t.check(is_equal_approx(title.size.y, CardTemplate.TITLE_ZONE.size.y * 300.0),
		"to_pixels scales the zone extent by the card size")

	# centred_pixels takes a CENTRE, not an origin: a badge is centred on a
	# drawn icon rather than fitted to a panel, so getting this backwards
	# would offset every number by half a box.
	var badge: Rect2 = CardTemplate.centred_pixels(Vector2(0.5, 0.5), Vector2(0.1, 0.1), size)
	t.check(is_equal_approx(badge.get_center().x, 100.0),
		"centred_pixels centres the box on the given point horizontally")
	t.check(is_equal_approx(badge.get_center().y, 150.0),
		"centred_pixels centres the box on the given point vertically")
	t.check(is_equal_approx(badge.size.x, 20.0), "centred_pixels scales the box width")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./tests/run_tests.sh
```

Expected: FAIL. `CardTemplate` does not exist, so the suite dies on an unresolved identifier and the wrapper catches the engine error marker.

- [ ] **Step 3: Create `scripts/ui/card_template.gd`**

```gdscript
class_name CardTemplate
extends RefCounted

## Where every element of a composed card face sits, and how it is styled.
##
## Zones are stored NORMALIZED as 0-1 fractions of the card rect, never in
## pixels. CardView.CARD_SIZE has already changed once (the bigger-readable-
## layout pass), and normalized zones survive that without a re-measure.
## Multiply by CardView.CARD_SIZE via to_pixels() / centred_pixels().
##
## Card-face geometry is layout, and CLAUDE.md keeps layout constants with
## their owner -- this file is that owner, the way card geometry lives in
## card_view.gd and fan geometry in hand_view.gd. Durations and curves belong
## in juice.gd; balance numbers belong in BattleConfig. Neither belongs here.
##
## Every number below was measured off the 1024x1536 template PNGs and then
## checked against a render (tools/capture_cards.gd). Re-measure, do not
## guess, if the templates are ever repainted.

const ATTACK: StringName = &"attack"
const DEFENSE: StringName = &"defense"

## Identical on both frames: the ribbon, the art window and the parchment
## panel are drawn in the same place on each.
const TITLE_ZONE: Rect2 = Rect2(0.146, 0.127, 0.713, 0.094)
const WINDOW_ZONE: Rect2 = Rect2(0.154, 0.253, 0.694, 0.312)
## Right edge stops at .685 to clear the cost circle, whose left edge is .700
## on the defense frame and .723 on the attack frame. Text running under that
## circle draws perfectly and simply cannot be read.
const RULES_ZONE: Rect2 = Rect2(0.175, 0.665, 0.510, 0.195)

## The value and cost badges are the ONLY zones that differ between the two
## frames, and both are centred on a drawn icon rather than fitted to a panel
## -- hence a centre plus a box rather than a rect. On the attack frame the
## number sits in the free red plate to the right of the burst; on the defense
## frame it sits dead centre in the shield.
const VALUE_CENTRE: Dictionary = {
	ATTACK: Vector2(0.591, 0.610),
	DEFENSE: Vector2(0.487, 0.605),
}
const VALUE_BOX: Dictionary = {
	ATTACK: Vector2(0.100, 0.070),
	DEFENSE: Vector2(0.150, 0.090),
}
const COST_CENTRE: Dictionary = {
	ATTACK: Vector2(0.788, 0.815),
	DEFENSE: Vector2(0.763, 0.814),
}
const COST_BOX: Vector2 = Vector2(0.120, 0.070)

## null means the project default font. Every card font routes through this one
## constant so dropping in a display face later is a one-line change rather
## than a hunt through card_view.gd.
const FONT: Font = null
const TITLE_SIZE: int = 17
const VALUE_SIZE: int = 22
const COST_SIZE: int = 18
const RULES_SIZE: int = 11

const TITLE_COLOR: Color = Color(0.98, 0.94, 0.80)
const VALUE_COLOR: Color = Color(1.00, 1.00, 1.00)
const COST_COLOR: Color = Color(1.00, 1.00, 1.00)
## Dark ink on the parchment panel. The only card text that needs no outline:
## it is dark-on-light, where the other three are light-on-saturated.
const RULES_COLOR: Color = Color(0.20, 0.14, 0.08)

const OUTLINE_SIZE: int = 4
const OUTLINE_COLOR: Color = Color(0.05, 0.03, 0.02, 0.9)

## Which frame a card wears. Tag-driven, so it needs no per-card registration:
## anything tagged defense gets the shield, everything else gets the burst.
static func variant_for(card: CardData) -> StringName:
	return DEFENSE if card.has_tag(&"defense") else ATTACK

## Converts a normalized zone to a pixel rect against a card of `size`.
static func to_pixels(zone: Rect2, size: Vector2) -> Rect2:
	return Rect2(zone.position * size, zone.size * size)

## Converts a normalized centre + box to a pixel rect against a card of `size`.
## Takes a CENTRE, not an origin -- a badge is centred on a drawn icon.
static func centred_pixels(centre: Vector2, box: Vector2, size: Vector2) -> Rect2:
	var pixel_box: Vector2 = box * size
	return Rect2(centre * size - pixel_box / 2.0, pixel_box)
```

- [ ] **Step 4: Run tests**

```bash
./tests/run_tests.sh
```

Expected: every `test_card_template` check passes. The run overall still FAILs on `test_card_view.gd` if Task 3 has already landed — that is expected and resolved in Task 5. Confirm by reading the failure lines: every one should be prefixed `[test_card_view]`. A failure prefixed `[test_card_template]` is a real problem in this task.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add CardTemplate: card-face geometry as normalized zones

Zones are 0-1 fractions of the card rect rather than pixels so CARD_SIZE
can change without a re-measure. Only the value and cost badges differ
between the two frames; both are centred on a drawn icon, so they are
stored as a centre plus a box rather than a rect.

The rules zone stops at .685 rather than the spec's .695: the defense
frame's cost circle starts at .700, and 0.9px of clearance is a rounding
artefact, not a margin."
```

---

### Task 5: `CardView` composes the six layers

The core of the pass. Land this together with Task 3.

**Files:**
- Modify: `scripts/ui/card_view.gd`
- Test: `tests/suites/test_card_view.gd`

**Interfaces:**
- Consumes: `CardArt.illustration_for()`, `CardArt.frame_for()` (Task 3); all of `CardTemplate` (Task 4); `CardData.total_guard()` (Task 2).
- Produces: `CardView.debug_text() -> String` (format changed, see below). Members `_illustration`, `_frame`, `_title_label`, `_value_label`, `_rules_label`, `_cost_label`. **Removed:** `_border`, `_background`, `_art`, `_name_label`, `_text_label`, `_has_art`, `_base_color()`, `ATTACK_COLOR`, `DEFENSE_COLOR`, `BORDER_WIDTH`, `BORDER_COLOR`.

- [ ] **Step 1: Rewrite the tests**

In `tests/suites/test_card_view.gd`, replace `run()` and the four art/combo functions. Keep `_test_affordability` and `_test_hand_view_rebuild` exactly as they are — they do not touch the art layers.

```gdscript
func run(t: TestRunner) -> void:
	_test_card_view_text(t)
	_test_affordability(t)
	_test_hand_view_rebuild(t)
	_test_frame_and_illustration_resolve(t)
	_test_badge_value_derives_from_effects(t)
	_test_missing_illustration_keeps_a_complete_frame(t)
	_test_zones_are_laid_out_from_the_template(t)
	_test_combo_armed_idempotent(t)
```

Delete `_no_art_card()` and replace it with:

```gdscript
## A CardData with no matching res://assets/illustrations/<id>.png -- exactly
## what a freshly authored card looks like on day one, .tres written and art
## not painted yet.
func _no_illustration_card() -> CardData:
	var card := CardData.new()
	card.id = &"no_such_card_id"
	card.display_name = "TEST CARD"
	card.cost = 1
	return card
```

Replace `_test_card_view_text` with:

```gdscript
func _test_card_view_text(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"jab")
	var view: CardView = CardView.create(card)
	t.check(view != null, "CardView.create returns a view")
	t.check_eq(view.card.id, &"jab", "the view remembers its card")
	var text: String = view.debug_text()
	t.check(text.contains("JAB"), "the card shows its name")
	t.check(text.contains("1 AP"), "the card shows its cost")
	t.check(text.contains("6"), "the card shows its damage")
	t.check(text.contains("Deal 6 damage."), "the card shows its rules text")
	view.free()
```

Then the new functions:

```gdscript
## Both layers come from CardArt, and they come from different lookups: the
## illustration by card id, the frame by tag-chosen variant. A card that got
## its frame by id would break the moment a card shipped without one.
func _test_frame_and_illustration_resolve(t: TestRunner) -> void:
	var jab: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	t.check_eq(jab._frame.texture, CardArt.frame_for(CardTemplate.ATTACK),
		"an attack card wears the attack frame")
	t.check_eq(jab._illustration.texture, CardArt.illustration_for(&"jab"),
		"the illustration is the one CardArt resolves for this card's id")
	jab.free()

	var blocker: CardView = CardView.create(CardLibrary.load_card(&"block"))
	t.check_eq(blocker._frame.texture, CardArt.frame_for(CardTemplate.DEFENSE),
		"a defense-tagged card wears the defense frame")
	blocker.free()

## The badge number is derived, never stored. This is the check that would
## catch a future regression back to a hardcoded field, and the reason the
## card can no longer print a number the rules disagree with.
func _test_badge_value_derives_from_effects(t: TestRunner) -> void:
	var jab: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	t.check_eq(jab._value_label.text, str(BattleConfig.JAB_DAMAGE),
		"an attack card's badge shows its damage")
	t.check_eq(jab._cost_label.text, str(BattleConfig.JAB_COST),
		"the cost badge shows the card's AP cost as a bare number")
	jab.free()

	var blocker: CardView = CardView.create(CardLibrary.load_card(&"block"))
	t.check_eq(blocker._value_label.text, str(BattleConfig.BLOCK_GUARD),
		"a defense card's badge shows its guard, not its (zero) damage")
	blocker.free()

	# Neither damage nor guard: an empty badge beats a misleading "0".
	var view: CardView = CardView.create(_no_illustration_card())
	t.check_eq(view._value_label.text, "",
		"a card with no damage and no guard shows an empty badge rather than 0")
	view.free()

## The fallback is now an empty WINDOW inside a complete frame, not a coloured
## rectangle. Every card always has a frame -- it is chosen by tag, not looked
## up by id -- so the old coloured-box branch became unreachable and was
## removed rather than left as dead code.
func _test_missing_illustration_keeps_a_complete_frame(t: TestRunner) -> void:
	var view: CardView = CardView.create(_no_illustration_card())

	t.check(view._illustration.texture == null, "a card with no illustration gets no illustration texture")
	t.check(view._frame.texture != null, "it still gets a frame")
	t.check(view._title_label.visible, "the title still renders")
	t.check(view._cost_label.visible, "the cost still renders")
	t.check_eq(view._title_label.text, "TEST CARD", "the title is the card's display name")
	view.free()

## Positions come from CardTemplate, and the two variants must actually differ
## -- if both frames got the attack geometry the defense number would sit off
## the shield, which draws fine and reads wrong.
func _test_zones_are_laid_out_from_the_template(t: TestRunner) -> void:
	var jab: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	var blocker: CardView = CardView.create(CardLibrary.load_card(&"block"))

	var expected_window: Rect2 = CardTemplate.to_pixels(
		CardTemplate.WINDOW_ZONE, CardView.CARD_SIZE)
	t.check(jab._illustration.position.is_equal_approx(expected_window.position),
		"the illustration is positioned at the template's window zone")

	t.check(jab._value_label.get_rect().get_center().x
			> blocker._value_label.get_rect().get_center().x,
		"the attack badge sits right of the burst while the defense badge is centred in the shield")
	t.check(jab._cost_label.position.x != blocker._cost_label.position.x,
		"the two frames' cost circles are in different places and the labels follow")

	jab.free()
	blocker.free()

## Guards the exact regression that shipped once: lerping from the LIVE
## modulate instead of a fixed base drifts the tint further gold on every
## refresh, and refresh_states() runs on every model event.
func _test_combo_armed_idempotent(t: TestRunner) -> void:
	var view: CardView = CardView.create(CardLibrary.load_card(&"straight"))

	view.set_combo_armed(true)
	var once: Color = view._frame.modulate

	view.set_combo_armed(true)
	view.set_combo_armed(true)
	t.check_eq(view._frame.modulate, once,
		"calling set_combo_armed(true) three times matches calling it once")
	t.check(view._frame.modulate != Color.WHITE, "the frame is actually tinted while combo-armed")

	view.set_combo_armed(false)
	t.check_eq(view._frame.modulate, Color.WHITE, "un-arming returns the frame to its untinted colour")

	# The artwork itself must never be tinted -- the gold belongs on the gold
	# frame, and tinting the illustration would misrepresent the art.
	t.check_eq(view._illustration.modulate, Color.WHITE, "the illustration is never tinted")
	view.free()
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./tests/run_tests.sh
```

Expected: FAIL with an engine error marker — `_frame`, `_illustration` and `_value_label` do not exist yet.

- [ ] **Step 3: Rewrite the presentation half of `scripts/ui/card_view.gd`**

Leave `_process`, `_update_idle`, `_update_tilt`, `apply_hover`, `lunge_to`, `spring_to`, `slide_from`, `_animate_to`, `_on_button_down`, `set_rest_transform`, `is_card_hovered` and the mouse handlers **completely untouched** — they are the transform-composition and single-tween-slot machinery, and this task has no business in them.

Replace the constants block:

```gdscript
const CARD_SIZE: Vector2 = Vector2(200, 300)
const COMBO_BORDER_COLOR: Color = Color(1.0, 0.80, 0.20)
const UNAFFORDABLE_ALPHA: float = 0.45

const HOVER_Z: int = 50
const LUNGE_Z: int = 60
```

Replace the node members:

```gdscript
## Bottom to top: illustration, frame, then the four text zones. See _build().
var _illustration: TextureRect
var _frame: TextureRect
var _title_label: Label
var _value_label: Label
var _rules_label: Label
var _cost_label: Label
```

Replace `_build()`, `_make_label()`, `configure()`, `_apply_art()`, `_base_color()`, `set_combo_armed()` and `debug_text()` with:

```gdscript
func _build() -> void:
	# Bottom to top. The frame is drawn OVER the illustration, not under it:
	# the illustration fills a plain rectangle and the frame's own window is
	# what crops it to shape, so a new illustration needs no matching cut-out.
	_illustration = TextureRect.new()
	_illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_illustration.clip_contents = true
	_illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_illustration)

	# STRETCH_SCALE, not KEEP_ASPECT: the frames are 1024x1536, exactly
	# CARD_SIZE's 2:3, so scaling is uniform anyway -- and being explicit means
	# a future frame authored at the wrong aspect distorts visibly instead of
	# quietly letterboxing itself out of alignment with the zones.
	_frame = TextureRect.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_title_label = _make_label(CardTemplate.TITLE_SIZE, CardTemplate.TITLE_COLOR, true)
	add_child(_title_label)

	_value_label = _make_label(CardTemplate.VALUE_SIZE, CardTemplate.VALUE_COLOR, true)
	add_child(_value_label)

	_cost_label = _make_label(CardTemplate.COST_SIZE, CardTemplate.COST_COLOR, true)
	add_child(_cost_label)

	# Dark ink on the parchment: no outline, and the only wrapping label.
	_rules_label = _make_label(CardTemplate.RULES_SIZE, CardTemplate.RULES_COLOR, false)
	_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_rules_label)

	pressed.connect(_on_pressed)

func _make_label(font_size: int, color: Color, outlined: bool) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	if CardTemplate.FONT != null:
		label.add_theme_font_override("font", CardTemplate.FONT)
	label.add_theme_color_override("font_color", color)
	if outlined:
		label.add_theme_constant_override("outline_size", CardTemplate.OUTLINE_SIZE)
		label.add_theme_color_override("font_outline_color", CardTemplate.OUTLINE_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func configure(p_card: CardData) -> void:
	card = p_card
	if card == null:
		return
	var variant: StringName = CardTemplate.variant_for(card)
	_frame.texture = CardArt.frame_for(variant)
	_illustration.texture = CardArt.illustration_for(card.id)
	_title_label.text = card.display_name
	_cost_label.text = str(card.cost)
	_value_label.text = _badge_value_text(variant)
	_rules_label.text = _rules_text()
	_layout_zones(variant)
	set_combo_armed(false)

## The badge number is DERIVED from the card's effects, never stored: a card
## wearing the defense frame shows the guard it grants, everything else the
## damage it deals. This is the whole reason a card can no longer print a
## value the rules disagree with -- there is no second copy of the number to
## fall out of date.
##
## A card with neither shows nothing rather than "0", which would read as a
## card that deals zero damage instead of a card that is not about damage.
func _badge_value_text(variant: StringName) -> String:
	var value: int = card.total_guard() if variant == CardTemplate.DEFENSE \
		else card.total_base_damage()
	return "" if value == 0 else str(value)

## Positions every layer from the template's normalized zones. Called from
## configure() rather than _build() because the value and cost zones depend on
## which frame the card ended up wearing.
##
## These write position/size on CHILD controls directly. That does not violate
## the compose-never-assign rule: _process composes position/rotation/scale of
## the CardView itself, and never touches its children's rects.
func _layout_zones(variant: StringName) -> void:
	_place(_illustration, CardTemplate.to_pixels(CardTemplate.WINDOW_ZONE, CARD_SIZE))
	_place(_title_label, CardTemplate.to_pixels(CardTemplate.TITLE_ZONE, CARD_SIZE))
	_place(_rules_label, CardTemplate.to_pixels(CardTemplate.RULES_ZONE, CARD_SIZE))
	_place_centred(_value_label,
		CardTemplate.VALUE_CENTRE[variant], CardTemplate.VALUE_BOX[variant])
	_place_centred(_cost_label,
		CardTemplate.COST_CENTRE[variant], CardTemplate.COST_BOX)

func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size

## Centres a control on a normalized point. Defers the centring arithmetic to
## CardTemplate.centred_pixels() so there is exactly one copy of it -- the
## bounds tests use the same function, and a second copy here would be free to
## drift away from the one under test.
##
## Reads `size` BACK after assigning it, because Control clamps size up to its
## minimum: a two-digit number at font 22 is wider than the attack frame's 20px
## badge gap, so the label silently becomes bigger than the box it was given.
## Positioning from the requested box instead of the actual size would then
## push every two-digit value half a box off its icon -- and it would look
## almost right, which is the worst kind of wrong.
func _place_centred(control: Control, centre: Vector2, box: Vector2) -> void:
	var rect: Rect2 = CardTemplate.centred_pixels(centre, box, CARD_SIZE)
	control.size = rect.size
	control.position = rect.get_center() - control.size / 2.0

## Idempotent: always computed from a fixed base (Color.WHITE), never lerped
## from whatever modulate currently holds. refresh_states() calls this once per
## model event, and lerping from the live value is exactly the bug that shipped
## once already -- the tint drifted further gold on every refresh.
##
## The FRAME is tinted, not the illustration: the gold belongs on the gold
## frame, and tinting the artwork would misrepresent what it depicts. Tinting
## modulate's RGB only (alpha stays 1.0) keeps this composing with
## set_affordable(false), which dims via modulate.a on the whole Button --
## Godot multiplies a child's modulate into its parent's when drawing, so the
## two combine automatically rather than fighting over one value.
func set_combo_armed(value: bool) -> void:
	if value:
		add_theme_constant_override("outline_size", 3)
	else:
		remove_theme_constant_override("outline_size")
	_frame.modulate = Color.WHITE.lerp(COMBO_BORDER_COLOR, 0.25) if value else Color.WHITE

## Everything the card displays, for tests.
func debug_text() -> String:
	return "%s | %s AP | %s | %s" % [
		_title_label.text, _cost_label.text, _value_label.text, _rules_label.text]
```

Leave `_rules_text()` and `set_affordable()` exactly as they are. Delete `_apply_art()` and `_base_color()` entirely.

Also update the class doc comment at the top of the file:

```gdscript
class_name CardView
extends Button

## One card, composed at runtime: an illustration, a frame chosen by the card's
## tags, and four text zones read from CardData. Knows how to draw a card and
## report clicks; knows nothing about whether playing it is legal.
##
## Nothing about the face is baked into an image, so a balance change is
## reflected on the card the moment the .tres is regenerated. Geometry and
## typography live in CardTemplate.
```

- [ ] **Step 4: Run tests**

```bash
./tests/run_tests.sh
```

Expected: `PASS`. The check count rises well above the 436 baseline; do not treat any particular figure as the target — what matters is zero failures and no engine error markers. Two failure modes to watch for specifically:

- A `_place_centred` failure where `_value_label` sits off-centre means the size read-back is not happening — confirm `control.size` is read after assignment, not the `box` argument.
- `set_combo_armed` failing idempotency means someone reintroduced a lerp from the live modulate.

- [ ] **Step 5: Sanity-check the game actually runs**

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path .
```

Cards should render as framed faces. Do not tune anything yet — Task 7 is where the geometry gets judged against a real render. This step only confirms nothing crashes.

- [ ] **Step 6: Commit Tasks 3 and 5 together**

```bash
git add -A
git commit -m "Compose card faces at runtime from a frame and an illustration

CardView's single art TextureRect becomes six layers: illustration, frame,
and four text zones read from CardData. The frame is chosen by tag, the
illustration by card id, so a new card needs only one PNG.

The badge number derives from the card's own effects -- damage for an
attack frame, guard for a defense one -- so it cannot disagree with the
rules the way a painted number could.

The coloured-rectangle fallback is removed rather than left as dead code:
a frame is chosen by tag rather than looked up by id, so every card always
has one and that branch became unreachable. The degradation path for an
unpainted card is now an empty window inside a complete frame."
```

---

### Task 6: The generator emits the real combo rule

`card_straight.png` printed *"Combo: If Jab was played earlier this turn, deal 50% more damage."* Both halves are wrong: Jab must **immediately** precede, and the bonus is 50% of both cards' **combined** base damage. Generated text cannot drift.

**Files:**
- Modify: `tools/generate_cards.gd`
- Regenerate: `resources/cards/straight.tres`
- Test: `tests/suites/test_card_library.gd`

**Interfaces:**
- Consumes: `ComboRule.jab_straight()`, `ComboRule.evaluate()`, `BattleConfig`.
- Produces: `straight.tres` with `rules_text = "Deal 9 damage. Combo: right after Jab, deal +7."`

- [ ] **Step 1: Write the failing test**

Add to `tests/suites/test_card_library.gd`, and add `_test_straight_rules_text_matches_the_combo_rule(t)` to `run()`:

```gdscript
## Ties the printed sentence to the rule that actually runs. The bonus is
## computed by evaluating ComboRule itself rather than written as a literal,
## so changing COMBO_BONUS_RATIO without regenerating the cards fails here
## instead of leaving the card quietly printing a stale number -- which is
## precisely what the painted card face did for the whole of its life.
func _test_straight_rules_text_matches_the_combo_rule(t: TestRunner) -> void:
	var jab: CardData = CardLibrary.load_card(&"jab")
	var straight: CardData = CardLibrary.load_card(&"straight")

	var rule: ComboRule = ComboRule.jab_straight()
	var bonus: int = rule.evaluate([jab] as Array, straight)
	t.check(bonus > 0, "the jab->straight combo awards a bonus to compare against")
	t.check(straight.rules_text.contains("+%d" % bonus),
		"straight's rules text prints the bonus ComboRule actually awards")

	# The old painted face said "earlier this turn", which is wrong -- any card
	# in between breaks the combo. The wording must say immediately.
	t.check(straight.rules_text.contains("right after Jab"),
		"straight's rules text states the combo needs Jab immediately before")
	t.check(not straight.rules_text.contains("50%"),
		"straight's rules text does not repeat the old face's 50%-of-this-card claim")

	# The other two cards stay single-sentence.
	t.check(not jab.rules_text.contains("Combo"), "jab's rules text mentions no combo")
```

- [ ] **Step 2: Run tests to verify it fails**

```bash
./tests/run_tests.sh
```

Expected: FAIL with check failures reading `straight's rules text prints the bonus ComboRule actually awards` and `...states the combo needs Jab immediately before`. The current text is `"Deal 9 damage."`

- [ ] **Step 3: Update the generator**

In `tools/generate_cards.gd`, replace `_make_straight()`:

```gdscript
func _make_straight() -> CardData:
	var card := CardData.new()
	card.id = &"straight"
	card.display_name = "STRAIGHT"
	card.cost = BattleConfig.STRAIGHT_COST
	card.tags = [&"straight", &"attack"] as Array[StringName]
	# Computed exactly the way ComboRule.evaluate() computes it: 50% of BOTH
	# cards' combined base damage, not 50% of this card's. The hand-painted
	# card face got that wrong and stayed wrong, because nothing regenerated
	# it. This does regenerate, so a balance change produces correct text.
	var combo_bonus: int = floori(
		(BattleConfig.JAB_DAMAGE + BattleConfig.STRAIGHT_DAMAGE) * BattleConfig.COMBO_BONUS_RATIO)
	card.rules_text = "Deal %d damage. Combo: right after Jab, deal +%d." % [
		BattleConfig.STRAIGHT_DAMAGE, combo_bonus]
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.STRAIGHT_DAMAGE
	card.effects = [damage] as Array[CardEffect]
	return card
```

- [ ] **Step 4: Regenerate the card resources**

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless --path . \
  --script res://tools/generate_cards.gd
```

Expected: `Generated 3 card resources in res://resources/cards`. Then confirm only `straight.tres` changed — the generator is deterministic, so `jab.tres` and `block.tres` must rewrite byte-for-byte identical:

```bash
git status --short resources/cards/
```

Expected: exactly one modified file, `resources/cards/straight.tres`. If `jab.tres` or `block.tres` also show as modified, something unrelated changed — investigate before committing.

- [ ] **Step 5: Run tests**

```bash
./tests/run_tests.sh
```

Expected: `PASS`, five checks more than Task 5's total.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Generate Straight's combo text from the rule that runs

The painted face claimed 'if Jab was played earlier this turn, deal 50%
more damage'. Both halves were wrong: Jab must immediately precede, and
the bonus is 50% of both cards' combined base damage (+7, for a 16-damage
Straight), not 50% of the Straight's own.

The test evaluates ComboRule to get the expected number rather than
hardcoding 7, so changing COMBO_BONUS_RATIO without regenerating fails
the suite instead of leaving a stale number printed on the card."
```

---

### Task 7: Look at it, then tune the zones

**This task is the point of the whole plan.** Tests can confirm `_value_label.position` equals the template zone; they cannot confirm the number landed inside the shield. This project has already shipped 387 green tests over an animation that produced literally zero motion. The static equivalent — a layout that is exactly where the constants say and still wrong — is the failure mode here.

**Files:**
- Create: `tools/capture_cards.gd`
- Modify: `scripts/ui/card_template.gd` (tuning only)

**Interfaces:**
- Consumes: `CardView.create()`, `CardLibrary.load_card()`.
- Produces: `/tmp/card-faces.png`.

- [ ] **Step 1: Write the capture tool**

Create `tools/capture_cards.gd`:

```gdscript
extends SceneTree

## Renders the three cards exactly as CardView draws them and writes a
## screenshot, at 1x and at 3x.
##
## Card-face layout is geometry no test can check. An assertion that
## _value_label.position equals CardTemplate's zone proves the code did what
## the code says -- not that the number landed inside the shield. This project
## has been burned by that exact class of green-test-over-broken-visual
## before (see CLAUDE.md, "Verifying animation -- tests cannot see motion").
##
## The 1x row is what the player actually sees and is the row that decides
## whether the layout is right. The 3x row is only for finding WHICH edge is
## off once the 1x row looks wrong.
##
## Run NON-headless -- get_texture() needs a real rendering context:
##   "/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" \
##     --path . --script res://tools/capture_cards.gd

const OUTPUT: String = "/tmp/card-faces.png"
const CARD_IDS: Array[StringName] = [&"jab", &"straight", &"block"]
const GAP: float = 20.0
const ZOOM: float = 3.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.09, 0.12)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	_add_row(Vector2(GAP, GAP), 1.0)
	_add_row(Vector2(GAP, GAP * 2.0 + CardView.CARD_SIZE.y), ZOOM)

	# Let the tree lay out and draw before reading the viewport back.
	for _i: int in range(10):
		await process_frame
	# root.get_texture() can otherwise read a stale render: the viewport's
	# texture is only current as of the last COMPLETED draw, which does not
	# necessarily line up with the process frame that just elapsed.
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	image.save_png(OUTPUT)
	print("wrote %s" % OUTPUT)
	quit(0)

func _add_row(origin: Vector2, zoom: float) -> void:
	var row := Control.new()
	row.position = origin
	row.scale = Vector2(zoom, zoom)
	root.add_child(row)

	var x: float = 0.0
	for card_id: StringName in CARD_IDS:
		var view: CardView = CardView.create(CardLibrary.load_card(card_id))
		view.position = Vector2(x, 0.0)
		row.add_child(view)
		x += CardView.CARD_SIZE.x + GAP
```

- [ ] **Step 2: Capture**

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path . \
  --script res://tools/capture_cards.gd
```

Expected: `wrote /tmp/card-faces.png`. If the run reports a `(0,0)` window size or a null texture, it was launched headless — drop `--headless`.

- [ ] **Step 3: Open the image and judge it**

Read `/tmp/card-faces.png`. Check each of these against the 1x row, and write down which fail:

1. Jab and Straight: is the number in the red plate, clear of the burst's spikes, not clipped by the plate's gold edge?
2. Block: is the number centred in the shield, not riding up onto the gold rim or down into the point?
3. All three: is the title inside the ribbon, not overlapping the gold scrollwork at either end?
4. All three: is the cost number centred in the blue circle?
5. All three: does the rules text sit on the parchment, clear of the badge above and the cost circle to the right, and is it legible at font 11?
6. All three: does the illustration fill the window without an obvious crop through a face?
7. Does the frame's gold read cleanly, or does the 5x downscale shimmer? (Static image — softness only; motion is judged in Step 6.)

- [ ] **Step 4: Tune `CardTemplate` and re-capture**

Adjust only the constants in `scripts/ui/card_template.gd`. Re-run Step 2 and Step 3 after each change. Expect to iterate two or three times — the numbers were measured off template pixels, not judged against a render.

Rules of thumb while tuning:
- Value badge off-centre → move `VALUE_CENTRE[variant]`, not the box.
- Value badge clipped → grow `VALUE_BOX[variant]`; the label centres itself, so a bigger box does not shift it.
- Rules text unreadable → `RULES_SIZE` up to 12, and if it then overflows, widen `RULES_ZONE` leftward (reduce `.position.x`) rather than rightward, which would run under the cost circle.
- If `RULES_ZONE.end.x` moves right at all, re-run the suite: `test_card_template` asserts it clears both cost badges and will catch it.

- [ ] **Step 5: Re-run the suite after tuning**

```bash
./tests/run_tests.sh
```

Expected: `PASS`. `test_card_template`'s bounds and clearance checks are what stop a tuning nudge from pushing a zone off the card or under the cost circle.

- [ ] **Step 6: Check it in motion**

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path .
```

Two things a still cannot show:
- **Shimmer.** Cards sway and rotate constantly. If the gold frame crawls or the illustration sparkles, mipmaps did not take — go back to Task 1, Step 4.
- **The combo tint.** Play a Jab, then look at the Straight in hand. Does gold-on-gold read as *armed*, or does it just look slightly brighter? If it does not read, raise the lerp weight in `set_combo_armed()` from `0.25`, or shift `COMBO_BORDER_COLOR` toward white for more contrast against the gold.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add tools/capture_cards.gd and tune the card zones against it

The zone constants were measured off the template PNGs; this is the pass
that judged them against an actual render. Card-face layout is exactly
the kind of thing that passes every assertion and still looks wrong --
the assertions check the code against the constants, and it is the
constants that are the guess."
```

---

### Task 8: Retire the old faces and bring the docs back into line

Sequenced last, deliberately: the old composed faces stay in the tree, unreferenced, until the new render has been judged in Task 7. That keeps a known-good comparison on hand and means a problem found during tuning does not also require restoring 7.8 MB of art from git.

**Files:**
- Delete: `assets/cards/` (6 files: 3 PNGs + 3 `.import`)
- Modify: `CLAUDE.md`
- Modify: `project.godot`

**Interfaces:**
- Consumes: nothing. `CardArt` stopped referencing `assets/cards/` in Task 3.

- [ ] **Step 1: Confirm nothing references them**

```bash
cd "/Users/mihai/Godot games/mma-cards"
grep -rn "assets/cards\|card_jab\|card_block\|card_straight" \
  --include='*.gd' --include='*.tres' --include='*.tscn' --include='*.godot' . \
  | grep -v '^./docs/'
```

Expected: **no output.** Any hit is a live reference — resolve it before deleting. Hits under `docs/` are historical spec text and are fine.

- [ ] **Step 2: Delete**

```bash
git rm -r assets/cards
```

Expected: 6 files removed.

- [ ] **Step 3: Run the suite**

```bash
./tests/run_tests.sh
```

Expected: `PASS`, same count as Task 7. If anything fails now, Step 1's grep missed a reference.

- [ ] **Step 4: Restore `project.godot`'s comments**

Importing the new PNGs made the editor rewrite `project.godot`, dropping every comment plus `window/size/viewport_width`, `viewport_height` and `window/stretch/aspect`. The dropped keys each equalled a Godot default, so this is functionally inert — but the comments explained non-obvious choices. Restore both the keys and the comments:

```ini
[application]

config/name="mma-cards"
config/features=PackedStringArray("4.5", "Forward Plus")
config/icon="res://icon.svg"
run/main_scene="res://level.tscn"

[display]

; The HUD is laid out in absolute pixels against a 1152x648 design space.
; Rather than re-position every element, the window opens at 2560x1440 and the
; whole canvas is scaled up to fill it. Both are exactly 16:9, so "keep" gives a
; clean 2.222x magnification with no letterboxing and no distortion -- and the
; layout coordinates in battle_hud.gd stay valid.
window/size/viewport_width=1152
window/size/viewport_height=648
window/size/window_width_override=2560
window/size/window_height_override=1440
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[rendering]

; ScreenFx.shake() offsets the CanvasLayer that holds the only background
; (BattleHud's full-rect ColorRect), so a big hit can briefly expose a sliver
; of whatever the engine clears to underneath it. Left at the engine default
; of mid-grey (0.3, 0.3, 0.3), that sliver reads as a visible grey flash at
; the screen edge on every big hit. Matching it to the HUD's own background
; colour means anything the shake exposes is indistinguishable from the HUD.
environment/defaults/default_clear_color=Color(0.09, 0.09, 0.12, 1)
```

Note: opening the project in the editor will strip these comments again. That is a Godot behaviour, not a mistake — restore them when it happens.

- [ ] **Step 5: Rewrite `CLAUDE.md`'s card art section**

Three things in `CLAUDE.md` are now false and must be **deleted, not softened**:

1. The whole **"Known discrepancy — the Straight card's art describes the combo rule incorrectly"** block. The card now generates its combo text from `ComboRule`'s own arithmetic, and `test_card_library.gd` asserts it against a live `ComboRule.evaluate()` call.
2. In **"Change balance"**, the paragraph beginning *"These same five constants are also baked into the card art as printed numbers"* and its "check it by eye after any balance change" instruction. Nothing is baked into art any more.
3. In **"Card art"**, the description of the images as *"fully composed card faces"* whose labels `CardView` hides, and the note about not cropping them.

Replace the **"Card art"** section with:

```markdown
## Card art

Card faces are composed at runtime, not painted. `CardView` stacks six layers
— illustration, frame, then title, value, rules and cost text — and every
number on the card is read from `CardData`. Nothing is baked into an image, so
a balance change shows up on the card as soon as the `.tres` is regenerated.

Two lookups, both by convention, both in `scripts/ui/card_art.gd`:

- **Illustration**, per card id: a card with id `jab` uses
  `res://assets/illustrations/jab.png`.
- **Frame**, per variant: a card tagged `defense` gets
  `res://assets/frames/defense.png`, everything else `attack.png`.

That asymmetry is the point. Adding a card means authoring a `.tres` and
dropping in **one** illustration — the frame it wears already exists, chosen by
tag. A card with no illustration yet renders a complete, correct frame around
an empty window: a real degradation path, not a bug.

`CardArt`'s cache is keyed by resolved path rather than by id or variant name.
Keying by the bare name would collide the day someone adds a card with id
`attack` — its illustration and the attack frame would share a key and serve
each other's texture.

**Geometry and typography live in `scripts/ui/card_template.gd`**, as zones
normalized to 0–1 fractions of the card rect rather than pixels — `CARD_SIZE`
has changed once already, and normalized zones survive that without a
re-measure. Only two zones differ between the frames: the value badge (right of
the burst on attack, centred in the shield on defense) and the cost badge.
`RULES_ZONE`'s right edge is load-bearing: past about `.69` the text runs under
the cost circle, where it draws perfectly and cannot be read.
`test_card_template.gd` asserts that clearance.

**Card-face layout cannot be verified by tests.** An assertion that
`_value_label.position` equals the template zone proves the code matches the
constants — and it is the constants that are the guess. Judge it from a render:

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path . \
  --script res://tools/capture_cards.gd
```

writes `/tmp/card-faces.png` with all three cards at 1x and 3x. Run it
**non-headless** — `get_texture()` needs a rendering context. This is the
static sibling of the lesson in "Verifying animation" below, and it has the
same shape: green tests, wrong picture.

Frame and illustration `.import` files must keep `mipmaps/generate=true`. Cards
draw at a 5x (frame) and 10x (illustration) downscale while swaying and
rotating; without mipmaps that shimmers rather than merely softening.
```

Also update **"State of the project"**: the check count, and the line about the fighters being *"now the only unfinished-looking element"* still holds — leave it. Update the count to whatever the suite actually reports.

- [ ] **Step 6: Verify the docs match reality**

```bash
grep -n "assets/cards\|Known discrepancy\|baked into the card art" CLAUDE.md
```

Expected: **no output.**

- [ ] **Step 7: Final full verification**

```bash
./tests/run_tests.sh
```

Expected: `PASS`. Record the check count and make sure `CLAUDE.md`'s "State of the project" quotes that same number.

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless --path . \
  --script res://tools/generate_cards.gd
git status --short resources/cards/
```

Expected: no output from `git status` — the generator is deterministic and re-running it on an unchanged tree must leave it clean.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Retire the pre-composed card faces

Deletes assets/cards/ (7.8 MB), unreferenced since the composition pass
landed and kept until the new render had been judged.

CLAUDE.md loses two standing warnings that stopped being true: the
Straight card's combo text is now generated from ComboRule's own
arithmetic, and no balance constant is baked into an image any more.
Adds the card-face section's own lesson: layout, like motion, is not
something the suite can see.

Restores the comments the editor stripped from project.godot when it
imported the new assets."
```

---

## Notes for the implementer

**The two things most likely to go wrong, and neither one fails a test:**

1. **`_place_centred` reading the wrong size.** Godot clamps `Control.size` up to the control's minimum. A two-digit number at font 22 is wider than the attack frame's 20px badge gap, so the label becomes bigger than the box it was handed. Position must be computed from `control.size` *after* assignment, not from the `box` argument. Get this wrong and every two-digit value drifts half a box to the left — which looks almost right.

2. **Trusting the zone table.** Every number in `CardTemplate` was measured off the template PNGs by inspecting pixels. That is a good starting point and not an answer. Task 7 exists because the difference between "measured correctly" and "looks right" is real, and the suite cannot tell them apart.

**What not to touch.** `CardView`'s `_process`, the `target_*` composition, and the single `_tween` slot are untouched by this plan. If a change here seems to need one of them, it does not — those govern animation, and nothing in this pass animates.
