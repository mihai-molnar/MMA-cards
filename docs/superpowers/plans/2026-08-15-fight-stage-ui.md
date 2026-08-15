# Fight Stage UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The fight screen becomes a fighting game: arena background, two half-screen fighter portraits that slam together at every fight start, HP/AP icon readouts with the numbers inside, and outlined Kreon text legible over the art.

**Architecture:** A new `FightStage` control owns all scenery (BG, portrait halves, slam animation, portrait hit feedback) as the HUD's bottom layer. `FighterPanel` keeps its diff-driven feedback brain but its face becomes icon readouts in the top corners. `BattleView` sequences fight start as slam → impact (screenshake) → settle → `battle.start()`. All new tunables live in `Juice`; all asset lookups go through `CardArt` by convention.

**Tech Stack:** Godot 4.5.1, typed GDScript, project's headless test runner + non-headless capture tools.

**Spec:** `docs/superpowers/specs/2026-08-15-fight-stage-ui-design.md`

## Global Constraints

- Godot binary path contains a space — always quote `"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"`.
- Tests ONLY via `./tests/run_tests.sh` (its `--import` step is what makes new classes and assets resolve). Never assert an absolute total check count in code or docs during this plan — a parallel fixes change moved the baseline; assert "0 failures / PASS" and report the count.
- Every Bash call: single invocation starting `cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && ...`, no redirects, no subshells, no other cd. A wedged "worktree isolation" shell = STOP, report BLOCKED.
- `scripts/ui/` only — `scripts/core/` is untouched by this entire plan.
- Typed GDScript; ASCII UI text; every `Button` keeps `focus_mode = Control.FOCUS_NONE`.
- House animation rules: any node's animation goes through a single owned tween slot (kill before create); every animation entry point guards `is_inside_tree()` with decisions recorded BEFORE the guard; anything that animates away from rest returns to a STORED home value, never accumulates.
- Design space is 1152x648 (`window/stretch/mode="canvas_items"` upscales to the 2560x1440 window). Each portrait half is 576x648.
- New texture `.import` files must carry `mipmaps/generate=true` (portraits/BG draw at ~0.5x; icons far smaller) — same requirement as card frames; the project's Linear-Mipmap filter samples them.
- Card-face/HUD layout cannot be verified by tests — capture renders and LOOK at them (house lesson).
- Commit with `git add -A` (stages `.uid` sidecars AND `.import` files). Every commit message ends with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- The six new assets currently live ONLY in the main checkout at `/Users/mihai/Godot games/mma-cards/assets/` (untracked). Task 1 copies them INTO this worktree. Reading from that path is allowed; never run git there and never cd there (cp with absolute source paths from a worktree cwd is fine).

---

### Task 1: Assets in place + `CardArt` lookups

**Files:**
- Create: `assets/backgrounds/octagon.png`, `assets/portraits/player.png`, `assets/portraits/brawler.png`, `assets/portraits/kickboxer.png`, `assets/ui/hp.png`, `assets/ui/ap.png` (copied, then imported)
- Modify: `scripts/ui/card_art.gd`
- Test: `tests/suites/test_card_art.gd` (extend)

**Interfaces:**
- Consumes: existing `CardArt._load(path)` cache (keyed by resolved path).
- Produces: `CardArt.portrait_for(fighter_id: StringName) -> Texture2D`, `CardArt.background_for(name: StringName) -> Texture2D`, `CardArt.ui_icon_for(name: StringName) -> Texture2D` — null for missing files (legitimate fallback, no push_error), same contract as `illustration_for`.

- [ ] **Step 1: Copy the assets in**

```bash
cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && mkdir -p assets/backgrounds assets/portraits assets/ui && cp "/Users/mihai/Godot games/mma-cards/assets/BG.png" assets/backgrounds/octagon.png && cp "/Users/mihai/Godot games/mma-cards/assets/portrait_player.png" assets/portraits/player.png && cp "/Users/mihai/Godot games/mma-cards/assets/portrait_enemy_1.png" assets/portraits/brawler.png && cp "/Users/mihai/Godot games/mma-cards/assets/portrait_enemy_2.png" assets/portraits/kickboxer.png && cp "/Users/mihai/Godot games/mma-cards/assets/icon_HP.png" assets/ui/hp.png && cp "/Users/mihai/Godot games/mma-cards/assets/icon_AP.png" assets/ui/ap.png
```

Mapping is deliberate: `portrait_enemy_1` (mohawk) = brawler, `portrait_enemy_2` (moustache) = kickboxer, portraits keyed by fighter/opponent id so opponent 3 is one more file.

- [ ] **Step 2: Write the failing tests**

Read `tests/suites/test_card_art.gd` first and match its style. Add:

```gdscript
func _test_portrait_lookup(t: TestRunner) -> void:
	t.check(CardArt.portrait_for(&"player") != null, "the player portrait resolves")
	t.check(CardArt.portrait_for(&"brawler") != null, "the brawler portrait resolves")
	t.check(CardArt.portrait_for(&"kickboxer") != null, "the kickboxer portrait resolves")
	t.check(CardArt.portrait_for(&"nobody") == null, "a missing portrait is a null fallback, not an error")

func _test_stage_asset_lookups(t: TestRunner) -> void:
	t.check(CardArt.background_for(&"octagon") != null, "the octagon background resolves")
	t.check(CardArt.ui_icon_for(&"hp") != null, "the hp icon resolves")
	t.check(CardArt.ui_icon_for(&"ap") != null, "the ap icon resolves")
	t.check(CardArt.ui_icon_for(&"mp") == null, "a missing ui icon is a null fallback")
```

Register both in the suite's `run()`.

- [ ] **Step 3: Run to verify failure**

Run: `./tests/run_tests.sh`
Expected: FAIL — the new checks die on missing `portrait_for` (engine `Invalid call` marker caught by the wrapper, or check failures), exit 1.

- [ ] **Step 4: Implement the lookups**

In `scripts/ui/card_art.gd`, after `ICON_DIR`:

```gdscript
const PORTRAIT_DIR: String = "res://assets/portraits"
const BACKGROUND_DIR: String = "res://assets/backgrounds"
const UI_DIR: String = "res://assets/ui"
```

After `status_icon_for`:

```gdscript
## Fighter portraits, keyed by fighter id: the player is &"player", an
## opponent's id is its OpponentData.id. Null when missing -- the stage
## renders a dark half instead, a legitimate degradation like a card
## without an illustration.
static func portrait_for(fighter_id: StringName) -> Texture2D:
	return _load("%s/%s.png" % [PORTRAIT_DIR, fighter_id])

static func background_for(name: StringName) -> Texture2D:
	return _load("%s/%s.png" % [BACKGROUND_DIR, name])

## HUD chrome (hp/ap value frames). assets/icons/ stays reserved for STATUS
## icons keyed by status id -- these are not statuses.
static func ui_icon_for(name: StringName) -> Texture2D:
	return _load("%s/%s.png" % [UI_DIR, name])
```

- [ ] **Step 5: Run to verify pass**

Run: `./tests/run_tests.sh`
Expected: PASS, 0 failures (the wrapper's `--import` generates the six `.import` files on this run).

- [ ] **Step 6: Turn mipmaps on in the six generated `.import` files**

Each new file at `assets/**/*.png.import` has `mipmaps/generate=false` in its `[params]`. Edit all six to `mipmaps/generate=true` (use the Edit tool; compare with `assets/frames/card_master_template.png.import` which already carries `true`). Then re-run the importer so the compressed textures regenerate:

Run: `./tests/run_tests.sh`
Expected: PASS (the run's `--import` step re-imports; no test changes).

- [ ] **Step 7: Commit**

```bash
cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && git add -A && git commit -m "Stage assets in convention-keyed homes with CardArt lookups

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `FightStage` + slam constants in `Juice`

**Files:**
- Create: `scripts/ui/fight_stage.gd`
- Modify: `scripts/ui/juice.gd` (append constants + one helper)
- Test: `tests/suites/test_fight_stage.gd` (new)

**Interfaces:**
- Consumes: `CardArt.portrait_for/background_for` (Task 1), `Juice` constants (this task).
- Produces (Tasks 4-5 rely on these exact signatures):
  - `FightStage.set_portraits(player_id: StringName, enemy_id: StringName) -> void`
  - `FightStage.slam_in(on_impact: Callable, on_settled: Callable) -> void`
  - `FightStage.flash_hit(side: StringName) -> void` and `FightStage.shake(side: StringName, amplitude: float) -> void` (`side` is `&"player"` or `&"enemy"`; `&"none"` is a silent no-op)
  - `FightStage.player_centre() -> Vector2` = `(288, 324)`, `FightStage.enemy_centre() -> Vector2` = `(864, 324)`
  - Test hooks: `debug_slam_count: int`, `debug_portrait_ids: Array`, `debug_last_hit_side: StringName`, `debug_portrait_positions() -> Array` (left home, right home as `[Vector2, Vector2]`)
  - `Juice.portrait_shake_amplitude(amount: int) -> float`

- [ ] **Step 1: Append the Juice constants**

At the end of `scripts/ui/juice.gd`'s constants (before the helper functions), add:

```gdscript
# --- Portrait slam (fight start) ------------------------------------------
## Two metal plates colliding: a fast ease-IN travel (accelerating into the
## impact, not cushioning it), a hard screen kick at contact, then a small
## outward recoil that resettles. The recoil is what sells the mass.
const SLAM_TIME: float = 0.45
const SLAM_TRANS: Tween.TransitionType = Tween.TRANS_QUART
const SLAM_RECOIL_PX: float = 12.0
const SLAM_RECOIL_TIME: float = 0.16
const SLAM_SHAKE_AMPLITUDE: float = 18.0
const SLAM_HIT_STOP: float = 0.10

# --- Portrait hit feedback ------------------------------------------------
const PORTRAIT_FLASH_TIME: float = 0.14
const PORTRAIT_FLASH_COLOR: Color = Color(1.0, 0.45, 0.45, 0.35)
const PORTRAIT_SHAKE_TIME: float = 0.22
const PORTRAIT_SHAKE_STEPS: int = 5
const PORTRAIT_SHAKE_BASE: float = 4.0
const PORTRAIT_SHAKE_PER_DAMAGE: float = 0.8
const PORTRAIT_SHAKE_MIN: float = 5.0
const PORTRAIT_SHAKE_MAX: float = 16.0
```

And with the other static helpers:

```gdscript
## How far a struck portrait half kicks sideways. Between the rect shake
## (small) and the screen kick (large) -- the portrait is the fighter now.
static func portrait_shake_amplitude(amount: int) -> float:
	return clampf(PORTRAIT_SHAKE_BASE + amount * PORTRAIT_SHAKE_PER_DAMAGE,
		PORTRAIT_SHAKE_MIN, PORTRAIT_SHAKE_MAX)
```

- [ ] **Step 2: Write the failing tests**

Create `tests/suites/test_fight_stage.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_set_portraits_records_ids(t)
	_test_detached_slam_snaps_and_fires_callbacks(t)
	_test_hit_side_recorded_before_tree_guard(t)
	_test_centres(t)
	_test_none_side_is_silent(t)

func _test_set_portraits_records_ids(t: TestRunner) -> void:
	var stage := FightStage.new()
	stage.set_portraits(&"player", &"kickboxer")
	t.check_eq(stage.debug_portrait_ids, [&"player", &"kickboxer"], "the stage records which portraits it was given")
	stage.set_portraits(&"player", &"brawler")
	t.check_eq(stage.debug_portrait_ids, [&"player", &"brawler"], "swapping the enemy portrait re-records")
	stage.free()

func _test_detached_slam_snaps_and_fires_callbacks(t: TestRunner) -> void:
	var stage := FightStage.new()
	stage.set_portraits(&"player", &"brawler")
	var fired: Array = []
	stage.slam_in(func() -> void: fired.append(&"impact"), func() -> void: fired.append(&"settled"))
	t.check_eq(stage.debug_slam_count, 1, "the slam decision is recorded before the tree guard")
	t.check_eq(fired, [&"impact", &"settled"], "detached, the slam snaps and fires impact then settled synchronously")
	var homes: Array = stage.debug_portrait_positions()
	t.check_eq(homes[0], Vector2.ZERO, "detached, the left half rests at its home")
	t.check_eq(homes[1], Vector2(576, 0), "detached, the right half rests at its home")
	stage.free()

func _test_hit_side_recorded_before_tree_guard(t: TestRunner) -> void:
	var stage := FightStage.new()
	stage.set_portraits(&"player", &"brawler")
	stage.flash_hit(&"enemy")
	t.check_eq(stage.debug_last_hit_side, &"enemy", "the hit side is recorded even detached")
	stage.shake(&"player", 8.0)
	t.check_eq(stage.debug_last_hit_side, &"player", "shake records its side too")
	stage.free()

func _test_centres(t: TestRunner) -> void:
	var stage := FightStage.new()
	t.check_eq(stage.player_centre(), Vector2(288, 324), "the player half centres at (288, 324)")
	t.check_eq(stage.enemy_centre(), Vector2(864, 324), "the enemy half centres at (864, 324)")
	stage.free()

func _test_none_side_is_silent(t: TestRunner) -> void:
	var stage := FightStage.new()
	stage.set_portraits(&"player", &"brawler")
	stage.flash_hit(&"none")
	stage.shake(&"none", 8.0)
	t.check_eq(stage.debug_last_hit_side, &"", "a &\"none\" side is ignored, not recorded")
	stage.free()
```

- [ ] **Step 3: Run to verify failure**

Run: `./tests/run_tests.sh`
Expected: FAIL — suite-load failure on `Identifier "FightStage" not declared`, exit 1.

- [ ] **Step 4: Implement `FightStage`**

Create `scripts/ui/fight_stage.gd`:

```gdscript
class_name FightStage
extends Control

## The scenery layer: arena background plus the two half-screen fighter
## portraits that ARE the scene once a fight starts. Sits at the bottom of
## the HUD's z-order; every readout draws over it.
##
## House animation rules apply throughout: one owned tween slot per animated
## concern (killed before reuse), decisions recorded BEFORE is_inside_tree()
## guards, and every departure from rest returns to a STORED home value.

const DESIGN_SIZE: Vector2 = Vector2(1152, 648)
const HALF_SIZE: Vector2 = Vector2(576, 648)

## Test hooks -- written before any tree guard, so headless suites can
## assert the decisions the animations would act on.
var debug_slam_count: int = 0
var debug_portrait_ids: Array = []
var debug_last_hit_side: StringName = &""

var _background: TextureRect
var _left: TextureRect
var _right: TextureRect
var _left_flash: ColorRect
var _right_flash: ColorRect
## Stored homes -- the only positions shakes and slams ever return to.
var _left_home: Vector2 = Vector2.ZERO
var _right_home: Vector2 = Vector2(HALF_SIZE.x, 0.0)

var _slam_tween: Tween
var _flash_tweens: Dictionary = {}
var _shake_tweens: Dictionary = {}

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_background = TextureRect.new()
	_background.texture = CardArt.background_for(&"octagon")
	_background.size = DESIGN_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_left = _make_half(_left_home)
	_right = _make_half(_right_home)
	_left_flash = _make_flash(_left)
	_right_flash = _make_flash(_right)

## KEEP_ASPECT_COVERED crops the 3:4 portrait to the 576x648 half -- faces
## stay centred, headroom is what gets cropped.
func _make_half(home: Vector2) -> TextureRect:
	var half := TextureRect.new()
	half.position = home
	half.size = HALF_SIZE
	half.clip_contents = true
	half.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	half.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	half.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(half)
	return half

## The hit flash is a child of its portrait so slams and shakes carry it.
func _make_flash(parent: TextureRect) -> ColorRect:
	var flash := ColorRect.new()
	flash.size = HALF_SIZE
	flash.color = Color(Juice.PORTRAIT_FLASH_COLOR, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(flash)
	return flash

func set_portraits(player_id: StringName, enemy_id: StringName) -> void:
	debug_portrait_ids = [player_id, enemy_id]
	_left.texture = CardArt.portrait_for(player_id)
	_right.texture = CardArt.portrait_for(enemy_id)

## Both halves fly in from offscreen and collide at the centre seam.
## on_impact fires at contact (the view hooks screenshake/hit-stop there);
## on_settled fires once the recoil resettles (the view starts the battle
## there, so the hand deals only after the stage is at rest). Detached
## (tests), snaps to home and fires both synchronously -- the decision is
## recorded either way.
func slam_in(on_impact: Callable, on_settled: Callable) -> void:
	debug_slam_count += 1
	_left.position = _left_home + Vector2(-HALF_SIZE.x, 0.0)
	_right.position = _right_home + Vector2(HALF_SIZE.x, 0.0)
	if not is_inside_tree():
		_left.position = _left_home
		_right.position = _right_home
		on_impact.call()
		on_settled.call()
		return
	if _slam_tween != null and _slam_tween.is_valid():
		_slam_tween.kill()
	_slam_tween = create_tween()
	_slam_tween.set_parallel(true)
	_slam_tween.tween_property(_left, "position", _left_home, Juice.SLAM_TIME) \
		.set_trans(Juice.SLAM_TRANS).set_ease(Tween.EASE_IN)
	_slam_tween.tween_property(_right, "position", _right_home, Juice.SLAM_TIME) \
		.set_trans(Juice.SLAM_TRANS).set_ease(Tween.EASE_IN)
	_slam_tween.set_parallel(false)
	_slam_tween.tween_callback(on_impact)
	_slam_tween.tween_property(_left, "position",
		_left_home + Vector2(-Juice.SLAM_RECOIL_PX, 0.0), Juice.SLAM_RECOIL_TIME)
	_slam_tween.parallel().tween_property(_right, "position",
		_right_home + Vector2(Juice.SLAM_RECOIL_PX, 0.0), Juice.SLAM_RECOIL_TIME)
	_slam_tween.tween_property(_left, "position", _left_home, Juice.SLAM_RECOIL_TIME)
	_slam_tween.parallel().tween_property(_right, "position", _right_home, Juice.SLAM_RECOIL_TIME)
	_slam_tween.tween_callback(on_settled)

func flash_hit(side: StringName) -> void:
	var half: TextureRect = _half_for(side)
	if half == null:
		return
	debug_last_hit_side = side
	if not is_inside_tree():
		return
	var flash: ColorRect = _left_flash if half == _left else _right_flash
	var old: Tween = _flash_tweens.get(side)
	if old != null and old.is_valid():
		old.kill()
	var tween := create_tween()
	tween.tween_property(flash, "color", Juice.PORTRAIT_FLASH_COLOR,
		Juice.PORTRAIT_FLASH_TIME * 0.35)
	tween.tween_property(flash, "color", Color(Juice.PORTRAIT_FLASH_COLOR, 0.0),
		Juice.PORTRAIT_FLASH_TIME)
	_flash_tweens[side] = tween

func shake(side: StringName, amplitude: float) -> void:
	var half: TextureRect = _half_for(side)
	if half == null:
		return
	debug_last_hit_side = side
	if not is_inside_tree():
		return
	var home: Vector2 = _left_home if half == _left else _right_home
	var old: Tween = _shake_tweens.get(side)
	if old != null and old.is_valid():
		old.kill()
		half.position = home
	var step: float = Juice.PORTRAIT_SHAKE_TIME / float(Juice.PORTRAIT_SHAKE_STEPS + 1)
	var tween := create_tween()
	for i: int in range(Juice.PORTRAIT_SHAKE_STEPS):
		var direction: float = -1.0 if i % 2 == 0 else 1.0
		tween.tween_property(half, "position", home + Vector2(direction * amplitude, 0.0), step)
	tween.tween_property(half, "position", home, step)
	_shake_tweens[side] = tween

func player_centre() -> Vector2:
	return _left_home + HALF_SIZE / 2.0

func enemy_centre() -> Vector2:
	return _right_home + HALF_SIZE / 2.0

func debug_portrait_positions() -> Array:
	return [_left.position, _right.position]

func _half_for(side: StringName) -> TextureRect:
	if side == &"player":
		return _left
	if side == &"enemy":
		return _right
	return null
```

- [ ] **Step 5: Run to verify pass**

Run: `./tests/run_tests.sh`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && git add -A && git commit -m "FightStage: arena background, portrait halves, slam and hit feedback

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Outlined HUD text helper

Small shared unit both `FighterPanel` and `BattleHud` need next.

**Files:**
- Create: `scripts/ui/hud_text.gd`
- Test: `tests/suites/test_hud_text.gd` (new)

**Interfaces:**
- Consumes: `res://assets/fonts/kreon_display.tres` (exists; the cards' display font).
- Produces: `HudText.style(label: Label, font_size: int) -> void` — Kreon display font, white fill, black outline (size scales with font size), on any Label. Tasks 4-5 call it for every label drawn over portraits.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_hud_text.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_style_applies_font_fill_and_outline(t)

func _test_style_applies_font_fill_and_outline(t: TestRunner) -> void:
	var label := Label.new()
	HudText.style(label, 20)
	t.check_eq(label.get_theme_font_size("font_size"), 20, "the requested size is applied")
	t.check_eq(label.get_theme_color("font_color"), Color.WHITE, "fill is white")
	t.check_eq(label.get_theme_color("font_outline_color"), Color.BLACK, "outline is black")
	t.check(label.get_theme_constant("outline_size") >= 3, "the outline is thick enough to read over art")
	t.check(label.get_theme_font("font") != null, "a font override is applied")
	label.free()
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run_tests.sh`
Expected: FAIL — suite-load failure on `Identifier "HudText" not declared`, exit 1.

- [ ] **Step 3: Implement**

Create `scripts/ui/hud_text.gd`:

```gdscript
class_name HudText
extends RefCounted

## One styling for every HUD label drawn over the portraits: Kreon (the
## cards' display font, so the game stays one type family), white fill,
## black outline -- the fighting-game legibility standard the user asked
## for. Outline thickness scales with the type size so small labels don't
## drown and large ones don't go thin.

const FONT: Font = preload("res://assets/fonts/kreon_display.tres")

static func style(label: Label, font_size: int) -> void:
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(3, font_size / 5))
```

- [ ] **Step 4: Run to verify pass**

Run: `./tests/run_tests.sh`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && git add -A && git commit -m "HudText: outlined Kreon styling for labels over portraits

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `FighterPanel` becomes icon readouts

The panel keeps its diff/pulse/suppress brain and test hooks verbatim; the coloured rectangle, name label, and combined name-hp text row are replaced by the HP heart (numbers inside, centre-overflow rule), optional AP bolt, guard `+n`, and the existing status rows.

**Files:**
- Modify: `scripts/ui/fighter_panel.gd`
- Test: `tests/suites/test_fighter_panel.gd` (update), `tests/suites/test_battle_hud.gd` (unchanged — verify), `tests/suites/test_hand_arc.gd` (one test retargets)

**Interfaces:**
- Consumes: `CardArt.ui_icon_for(&"hp")` / `(&"ap")` (Task 1), `HudText.style` (Task 3).
- Produces (Task 5 relies on):
  - `FighterPanel.create(display_name: String, p_align_right: bool, p_show_ap: bool) -> FighterPanel` (the `rect_color` parameter is GONE)
  - `update(fighter: Fighter) -> void` (unchanged signature; hp value text becomes `"%d / %d"`)
  - `update_ap(current: int, maximum: int) -> void` (no-op on a panel built with `p_show_ap = false`)
  - `set_fighter_name(p_name)` / `fighter_name()` — name is now STORED (uppercased), no label renders it
  - Unchanged: `suppress_next_guard_pulse()`, `debug_last_pulse_kind/amount`, `debug_status_icons()`, `debug_status_text()`, `debug_hp_text()` (now `"38 / 50"` form), `centre_point()` (now the hp icon's centre in parent space), `shake_amplitude()`
  - New hooks: `debug_value_overflowed() -> bool`, `debug_ap_text() -> String` (`""` when no AP)

Layout inside the 210x176 panel (constants at top of file): `ICON_SIZE := 72.0`, hp icon at x `0` (left panel) / `PANEL_SIZE.x - ICON_SIZE` (right panel), y `0`; guard label row y `74`; AP icon y `96` size `56` (player only); status icon row y `150`; status text line y `150` shifted to `120` when no AP icon (enemy). Panel positions in the HUD are unchanged, so the existing hand-clearance arithmetic still holds.

- [ ] **Step 1: Update the tests first**

Read `tests/suites/test_fighter_panel.gd` fully. Apply:
- Everywhere `FighterPanel.create("X", SOME_COLOR, bool)` appears, drop the colour argument and pass the new third parameter (`true` for panels standing in for the player, `false` otherwise — match what each test exercises).
- `_test_*` assertions on `debug_hp_text()`: `"48"`-style containment checks stay; DELETE the `contains("ENEMY")` name assertion and replace with `t.check_eq(panel.fighter_name(), "ENEMY", "the name is stored, not painted on the hp row")`.
- Add two new tests:

```gdscript
func _test_hp_value_overflow_rule(t: TestRunner) -> void:
	var panel := FighterPanel.create("Player", false, true)
	var fighter := Fighter.new("Player", 50)
	panel.update(fighter)
	t.check(not panel.debug_value_overflowed(), "a short hp value centres in the icon window")
	var big := Fighter.new("Player", 5000)
	big.hp = 5000
	panel.update(big)
	t.check(panel.debug_value_overflowed(), "an overlong value anchors at the icon centre and grows right")
	panel.free()

func _test_ap_only_on_player_panel(t: TestRunner) -> void:
	var player := FighterPanel.create("Player", false, true)
	player.update_ap(2, 3)
	t.check_eq(player.debug_ap_text(), "2 / 3", "the player panel shows AP inside the bolt")
	var enemy := FighterPanel.create("Enemy", true, false)
	enemy.update_ap(2, 3)
	t.check_eq(enemy.debug_ap_text(), "", "the enemy panel has no AP readout")
	player.free()
	enemy.free()
```

- In `tests/suites/test_hand_arc.gd`, `_test_clear_of_ap_label` measured hand clearance against the bottom-left AP text label, which Task 5 deletes. Retarget it against the draw-pile label row (`BattleHud.DRAW_LABEL_AT`, y 596 — same rotated-silhouette method, new row), and rename it `_test_clear_of_draw_label` (update `run()`).

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run_tests.sh`
Expected: FAIL, exit 1 (create-arity mismatches and missing hooks).

- [ ] **Step 3: Rework `FighterPanel`**

In `scripts/ui/fighter_panel.gd`, keeping the file's diff/pulse/suppress/floater/status-icon code intact except where named:

a) Constants: delete `RECT_SIZE`; add `const ICON_SIZE: float = 72.0`, `const AP_ICON_SIZE: float = 56.0`. Keep `PANEL_SIZE`, flashes, `STATUS_*`.

b) Members: delete `_rect`, `_name_label`, `_rect_home`, `_rect_colour_home`, `_flash_tween` usage against `_rect`. Add:

```gdscript
var _fighter_name: String = ""
var _show_ap: bool = false
var _icon_cluster: Control
var _hp_icon: TextureRect
var _hp_value: Label
var _guard_label: Label
var _ap_icon: TextureRect
var _ap_value: Label
## The cluster's rest position -- what every shake returns to.
var _cluster_home: Vector2 = Vector2.ZERO
var _cluster_tween: Tween
```

c) `create`:

```gdscript
static func create(display_name: String, p_align_right: bool, p_show_ap: bool) -> FighterPanel:
	var panel := FighterPanel.new()
	panel.align_right = p_align_right
	panel._show_ap = p_show_ap
	panel._fighter_name = display_name.to_upper()
	panel._build()
	return panel
```

d) `_build()` (replaces the old rect construction; keep `_make_row_label` for the status text line):

```gdscript
func _build() -> void:
	var icon_x: float = PANEL_SIZE.x - ICON_SIZE if align_right else 0.0

	# Everything that shakes on a hit lives in one cluster with one stored
	# home -- the icon stands in for the old fighter rectangle.
	_icon_cluster = Control.new()
	_icon_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.size = PANEL_SIZE
	_cluster_home = _icon_cluster.position
	add_child(_icon_cluster)

	_hp_icon = _make_icon(&"hp", Vector2(icon_x, 0.0), ICON_SIZE)
	_hp_value = Label.new()
	HudText.style(_hp_value, 16)
	_hp_value.position = Vector2(icon_x, ICON_SIZE * 0.36)
	_hp_value.size = Vector2(ICON_SIZE, 22.0)
	_hp_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.add_child(_hp_value)

	_guard_label = Label.new()
	HudText.style(_guard_label, 14)
	_guard_label.add_theme_color_override("font_color", GUARD_FLASH)
	_guard_label.position = Vector2(icon_x, 74.0)
	_guard_label.size = Vector2(ICON_SIZE, 20.0)
	_guard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guard_label.visible = false
	_guard_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.add_child(_guard_label)

	if _show_ap:
		var ap_x: float = icon_x + (ICON_SIZE - AP_ICON_SIZE) / 2.0
		_ap_icon = _make_icon(&"ap", Vector2(ap_x, 96.0), AP_ICON_SIZE)
		_ap_value = Label.new()
		HudText.style(_ap_value, 13)
		_ap_value.position = Vector2(ap_x, 96.0 + AP_ICON_SIZE * 0.36)
		_ap_value.size = Vector2(AP_ICON_SIZE, 18.0)
		_ap_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ap_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon_cluster.add_child(_ap_value)

	var rows_y: float = 150.0 if _show_ap else 120.0
	_status_label = _make_row_label(14, rows_y + 26.0)
	HudText.style(_status_label, 14)
	_status_label.add_theme_color_override("font_color", STATUS_COLOR)

	_status_icon_row = HBoxContainer.new()
	_status_icon_row.add_theme_constant_override("separation", int(STATUS_ICON_GAP))
	_status_icon_row.position = Vector2(0.0, rows_y)
	_status_icon_row.size = Vector2(PANEL_SIZE.x, STATUS_ICON_SIZE)
	_status_icon_row.alignment = BoxContainer.ALIGNMENT_END if align_right \
		else BoxContainer.ALIGNMENT_BEGIN
	_status_icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.add_child(_status_icon_row)

func _make_icon(icon_name: StringName, at: Vector2, icon_size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = CardArt.ui_icon_for(icon_name)
	icon.position = at
	icon.size = Vector2.ONE * icon_size
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.add_child(icon)
	return icon
```

Delete the old `_hp_label` member; everywhere else in the file that referenced `_hp_label` (the `_punch` rest colour, the floater anchor) now uses `_hp_value`. The `_status_label` modulate line in the old build is replaced by the font-color override above.

e) `update(fighter)` — only the display lines change; the diff/pulse block below them stays byte-identical except `_hp_label` → `_hp_value`:

```gdscript
	_hp_value.text = "%d / %d" % [fighter.hp, fighter.max_hp]
	_layout_value_label(_hp_value, _hp_icon.position.x, ICON_SIZE)
	_guard_label.text = "+%d" % fighter.guard
	_guard_label.visible = fighter.guard > 0
	_status_label.text = _status_line(fighter)
	_rebuild_status_icons(fighter)
```

And `_status_line(fighter)` drops its `GUARD %d` part (guard has its own label now) — delete the `if fighter.guard > 0` block from it.

f) The overflow rule + hooks:

```gdscript
var _value_overflowed: bool = false

## The user-specified fitting rule: the value centres in the icon's dark
## window; when it is too wide it anchors at the icon's horizontal centre
## and grows rightward instead.
func _layout_value_label(label: Label, icon_x: float, icon_size: float) -> void:
	var font: Font = label.get_theme_font("font")
	var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, label.get_theme_font_size("font_size")).x
	var window: float = icon_size * 0.62
	_value_overflowed = width > window
	if _value_overflowed:
		label.position.x = icon_x + icon_size / 2.0
		label.size.x = width + 4.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		label.position.x = icon_x + (icon_size - window) / 2.0
		label.size.x = window
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func debug_value_overflowed() -> bool:
	return _value_overflowed

func update_ap(current: int, maximum: int) -> void:
	if not _show_ap:
		return
	_ap_value.text = "%d / %d" % [current, maximum]
	_layout_value_label(_ap_value, _ap_icon.position.x, AP_ICON_SIZE)

func debug_ap_text() -> String:
	return "" if _ap_value == null else _ap_value.text

func set_fighter_name(p_name: String) -> void:
	_fighter_name = p_name.to_upper()

func fighter_name() -> String:
	return _fighter_name
```

(`_ap_value` must be declared `var _ap_value: Label = null` for the null check.)

g) Feedback plumbing: `_pulse_damage` keeps its shape but `_flash_rect` and the rect shake retarget the cluster — `_flash_rect(colour)` is DELETED (the portrait flash in `FightStage` replaces it; Task 5 wires it), and `_shake(amplitude)` becomes:

```gdscript
func _shake(amplitude: float) -> void:
	if _cluster_tween != null and _cluster_tween.is_valid():
		_cluster_tween.kill()
		_icon_cluster.position = _cluster_home
	var step_time: float = Juice.SHAKE_TIME / float(Juice.SHAKE_STEPS + 1)
	_cluster_tween = create_tween()
	for i: int in range(Juice.SHAKE_STEPS):
		var direction: float = -1.0 if i % 2 == 0 else 1.0
		_cluster_tween.tween_property(_icon_cluster, "position",
			_cluster_home + Vector2(direction * amplitude, 0.0), step_time)
	_cluster_tween.tween_property(_icon_cluster, "position", _cluster_home, step_time)
```

`_pulse_damage` drops its `_flash_rect(DAMAGE_FLASH)` line and its `ParticleBurst.spawn` anchor becomes `_cluster_home + _hp_icon.position + Vector2.ONE * ICON_SIZE / 2.0`. `centre_point()` becomes:

```gdscript
## Centre of the hp icon in the panel's parent space -- the floater/particle
## anchor. Card lunges now aim at the PORTRAITS (FightStage centres).
func centre_point() -> Vector2:
	return position + _cluster_home + _hp_icon.position + Vector2.ONE * ICON_SIZE / 2.0
```

Also delete `_label_rest_color`'s `Color.WHITE` fallback dependency on the old label — replace the function body with `return STATUS_COLOR if label == _status_label else Color.WHITE` (unchanged logic, just verify it still compiles against `_hp_value`).

- [ ] **Step 4: Run to verify pass**

Run: `./tests/run_tests.sh`
Expected: PASS, 0 failures. If a `test_fighter_panel` case still references removed members, fix the TEST to the new surface (the hooks above), never by resurrecting the rect.

- [ ] **Step 5: Commit**

```bash
cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && git add -A && git commit -m "FighterPanel: icon readouts replace the placeholder rectangle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `BattleHud` + `BattleView` integration — the stage goes live

**Files:**
- Modify: `scripts/ui/battle_hud.gd`, `scripts/ui/battle_view.gd`, `scripts/ui/hand_view.gd`
- Test: `tests/suites/test_battle_hud.gd` (extend), `tests/suites/test_hand_play.gd` / `test_hand_refan.gd` (verify only)

**Interfaces:**
- Consumes: `FightStage` (Task 2), `HudText` (Task 3), reworked `FighterPanel` (Task 4).
- Produces:
  - `BattleHud.stage() -> FightStage`; `enemy_centre()`/`player_centre()` now return the stage's half centres `(864, 324)` / `(288, 324)`
  - `BattleHud.update_ap(current, maximum)` routes to the player panel (the bottom-left AP text label is GONE; `AP_LABEL_AT` const deleted)
  - `BattleHud.last_damage_side() -> StringName` (`&"player"` / `&"enemy"` / `&"none"`)
  - `HandView.clear() -> void` — frees all card views (extracted from `rebuild`'s clearing pass; `rebuild` calls it)
  - `BattleView._start_fight()` sequences: set portraits → clear hand + tooltip → `slam_in(impact → ScreenFx kick, settled → battle.start())`

- [ ] **Step 1: Write/extend the failing tests**

In `tests/suites/test_battle_hud.gd` add (and register):

```gdscript
func _test_stage_is_bottom_layer(t: TestRunner) -> void:
	var hud := BattleHud.new()
	t.check(hud.stage() != null, "the hud owns a FightStage")
	t.check_eq(hud.get_child(0), hud.stage(), "the stage is the first child -- everything draws over it")
	hud.free()

func _test_lunge_anchors_are_portrait_centres(t: TestRunner) -> void:
	var hud := BattleHud.new()
	t.check_eq(hud.enemy_centre(), Vector2(864, 324), "attacks fly at the enemy portrait's centre")
	t.check_eq(hud.player_centre(), Vector2(288, 324), "block pulls back to the player portrait's centre")
	hud.free()

func _test_ap_routes_to_player_panel(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.update_ap(2, 3)
	t.check_eq(hud.debug_player_panel().debug_ap_text(), "2 / 3", "AP renders inside the player's bolt icon")
	hud.free()

func _test_last_damage_side(t: TestRunner) -> void:
	var hud := BattleHud.new()
	t.check_eq(hud.last_damage_side(), &"none", "no update yet, no side")
	hud.free()
```

(`debug_player_panel()` is a new hook mirroring `debug_enemy_panel()`.)

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run_tests.sh`
Expected: FAIL, exit 1 (missing `stage()` etc.).

- [ ] **Step 3: Implement the `BattleHud` changes**

In `scripts/ui/battle_hud.gd`:

a) Member `var _stage: FightStage`. In `_build()`, REPLACE the background `ColorRect` block with:

```gdscript
	_stage = FightStage.new()
	add_child(_stage)
```

b) Panels — new `create` calls:

```gdscript
	_player_panel = FighterPanel.create("Player", false, true)
	_player_panel.position = PLAYER_PANEL_AT
	add_child(_player_panel)

	_enemy_panel = FighterPanel.create("Enemy", true, false)
	_enemy_panel.position = ENEMY_PANEL_AT
	add_child(_enemy_panel)
```

(`PLAYER_COLOR`/`ENEMY_COLOR` consts are now unused — delete them.)

c) Turn label becomes top-centre and styled; intent, draw and discard labels styled. In `_build()`:

```gdscript
	_turn_label = _add_label("TURN 1", Vector2(0, 16), 20)
	_turn_label.size = Vector2(1152, 28)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudText.style(_turn_label, 20)
```

(replacing the old `(24, 20)` turn label line), and after each of the intent/draw/discard label constructions add `HudText.style(<label>, <its existing font size>)`. Delete the `_intent_label.modulate` amber line — the intent is white-with-black-outline now (user-requested). Delete the `_ap_label` member, its construction, and `AP_LABEL_AT`; `update_ap` becomes:

```gdscript
func update_ap(current: int, maximum: int) -> void:
	_player_panel.update_ap(current, maximum)
```

d) New surface:

```gdscript
func stage() -> FightStage:
	return _stage

func debug_player_panel() -> FighterPanel:
	return _player_panel

## Which side the most recent fighter update hurt -- drives the portrait
## flash/shake. Mirrors last_damage_amount()'s larger-pulse-wins rule.
func last_damage_side() -> StringName:
	var player_hit: int = _player_panel.debug_last_pulse_amount if _player_panel.debug_last_pulse_kind == &"damage" else 0
	var enemy_hit: int = _enemy_panel.debug_last_pulse_amount if _enemy_panel.debug_last_pulse_kind == &"damage" else 0
	if player_hit == 0 and enemy_hit == 0:
		return &"none"
	return &"player" if player_hit >= enemy_hit else &"enemy"
```

And `enemy_centre()`/`player_centre()` delegate to `_stage.enemy_centre()` / `_stage.player_centre()`.

- [ ] **Step 4: Implement `HandView.clear()` and the `BattleView` sequencing**

In `scripts/ui/hand_view.gd`: read `rebuild()`; extract its free-all-card-views pass into

```gdscript
## Empties the hand immediately -- fight transitions call this so a dead
## battle's cards aren't still fanned while the next fight's portraits slam.
func clear() -> void:
```

and have `rebuild()` call `clear()` where the inline pass was (behavior identical — the suites covering rebuild/refan must still pass untouched).

In `scripts/ui/battle_view.gd`, replace `_start_fight()` with:

```gdscript
## One call per fight: a fresh BattleState against the run's current
## opponent, seeded with the carried hp. The old BattleState (and its
## signal connections) is dropped with the reassignment -- deferred
## timers that fire afterwards re-read `battle` and see the new fight.
## The stage slams first; battle.start() -- and with it the deal -- waits
## for the collision to settle, so the fight opens on the impact, not
## under it. Model state is never gated on animation: nothing exists to
## input into until start() runs.
func _start_fight() -> void:
	var opponent: OpponentData = run.current_opponent()
	battle = BattleState.new(0, opponent, run.player_hp)
	_connect_battle()
	hud.set_enemy_name(battle.enemy.display_name)
	hand_view.clear()
	status_tooltip.hide_tooltip()
	hud.stage().set_portraits(&"player", opponent.id)
	hud.stage().slam_in(_on_slam_impact, _on_slam_settled)

## The collision frame: the metal-plates hit the user asked for.
func _on_slam_impact() -> void:
	screen_fx.hit_stop(Juice.SLAM_HIT_STOP)
	screen_fx.shake(Juice.SLAM_SHAKE_AMPLITUDE)
	screen_fx.flash()

func _on_slam_settled() -> void:
	battle.start()
```

And in `_land_fighter_update()`, after the existing `_fire_impact(amount)` call, route the portrait feedback:

```gdscript
		var side: StringName = hud.last_damage_side()
		hud.stage().flash_hit(side)
		hud.stage().shake(side, Juice.portrait_shake_amplitude(amount))
```

(inside the same `if amount > 0:` block).

- [ ] **Step 5: Run to verify pass**

Run: `./tests/run_tests.sh`
Expected: PASS, 0 failures. Pay attention to `test_hand_play` / `test_hand_refan` / `test_hand_deal` — the `clear()` extraction must not change `rebuild()` behavior; if one fails, the extraction dropped something (fix the extraction, not the test).

- [ ] **Step 6: Commit**

```bash
cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && git add -A && git commit -m "Fight stage goes live: slam-gated fight starts and portrait hit routing

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Render verification — captures, then eyes

Layout and motion cannot be verified by tests (house lesson). This task produces the renders and fixes what they reveal.

**Files:**
- Create: `tools/capture_stage.gd`
- Possibly modify: `scripts/ui/juice.gd` / layout constants, per what the renders show

**Interfaces:**
- Consumes: the full composed game (level.tscn boots `BattleView`).
- Produces: `/tmp/fight-stage.png` (settled composition) and slam motion frames via the existing `tools/capture_frames.gd` pattern.

- [ ] **Step 1: Write the static capture tool**

Read `tools/capture_cards.gd` and `tools/capture_frames.gd` first — match their SceneTree-script structure, real-time pacing, and non-headless requirements. Create `tools/capture_stage.gd` that: loads `res://scenes/level.tscn` (confirm the scene path by reading `project.godot`'s `run/main_scene`), instantiates it, waits ~1.5 REAL seconds (past slam + settle + deal; pace by elapsed time, not frame count — this machine runs at 100Hz), captures the viewport to `/tmp/fight-stage.png`, and quits.

- [ ] **Step 2: Run both captures (non-headless)**

```bash
cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && timeout 30 "/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path . --script res://tools/capture_stage.gd
```

Then adapt/run the frame capture for the slam window (first ~0.9s). If `tools/capture_frames.gd` captures the main scene, run it as-is; otherwise extend `capture_stage.gd` to also tile ~12 frames across the first 0.9 real seconds into `/tmp/fight-stage-frames.png`.

- [ ] **Step 3: LOOK at the renders (Read tool) and verify every line**

Static (`/tmp/fight-stage.png`):
- BG invisible behind portraits; the two portraits meet at x=576 with no gap and no visible background strip
- Player faces right from the left half; enemy (Brawler) faces left from the right half
- HP hearts top corners, numbers legible inside the dark window, white with black outline
- AP bolt under the player's heart only; `3 / 3` readable
- Turn counter top-centre; intent top-right legible over the portrait
- Card fan, END TURN, draw/discard all readable over the art
Motion (frames sheet):
- Frames are NOT pixel-identical; portraits visibly accelerate inward, contact, recoil outward a few px, resettle
- The hand deals only in frames after the portraits are at rest

- [ ] **Step 4: Fix what the renders reveal**

Adjust layout constants (`FighterPanel` rows, label positions) or `Juice` slam values and re-capture until every line above holds. Record what changed and why in the commit message body.

- [ ] **Step 5: Full suite still green**

Run: `./tests/run_tests.sh`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && git add -A && git commit -m "Stage capture tool and render-verified layout polish

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Docs and closeout

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Content requirements (keep the file's explanatory voice):
1. "The presentation layer" area gains a short **Fight stage** paragraph: `FightStage` owns BG/portraits/slam/portrait-hit-feedback as the HUD's bottom layer; fight starts are slam-gated (`battle.start()` waits for `on_settled`); portraits keyed by fighter id via `CardArt.portrait_for` (`assets/portraits/<id>.png` — adding an opponent's portrait is one file); HP/AP icons are HUD chrome in `assets/ui/`, NOT `assets/icons/` (status-only).
2. `FighterPanel` description updated: icon readouts, no rectangle; the diff/pulse/suppress machinery unchanged and still the feedback brain; the value-overflow rule (centre until too wide, then grow right from icon centre).
3. `HudText` one-liner: every label over portraits is Kreon white/black-outline through it.
4. Mipmaps paragraph: extend the frame/illustration requirement to backgrounds, portraits, and ui icons.
5. "State of the project": the flat-rectangle placeholder note is RESOLVED — fighters are portraits now; sound remains the top absence (the slam begs for it).
6. Update the expected check count in Commands to the final number the suite prints.

- [ ] **Step 2: Final suite + smoke boot**

Run: `./tests/run_tests.sh` → PASS; note the count for Step 1's item 6.
Run: `cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && timeout 15 "/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path . --quit-after 700`
Expected: no `SCRIPT ERROR` / `Parse Error` / `Invalid call` in output.

- [ ] **Step 3: Commit**

```bash
cd "/Users/mihai/Godot games/mma-cards/.claude/worktrees/fight-stage-and-fixes" && git add -A && git commit -m "Document the fight stage layer and icon readouts

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
