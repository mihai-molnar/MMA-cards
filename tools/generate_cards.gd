extends SceneTree

## Generates resources/cards/*.tres from BattleConfig values.
## Run: godot --headless --path . --script res://tools/generate_cards.gd
##
## Cards are generated rather than hand-written so the .tres format is always
## valid. The output is a normal resource — edit it in the inspector, or
## regenerate it here.
##
## To add a new card: write a _make_*() function below that builds and
## returns a CardData, call _save() on it from _initialize(), and — if it
## should appear in the starting deck — add its id to
## BattleConfig.DECK_COMPOSITION.

const OUTPUT_DIR: String = "res://resources/cards"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	_save(_make_jab())
	_save(_make_straight())
	_save(_make_block())

	print("Generated 3 card resources in %s" % OUTPUT_DIR)
	quit(0)

func _save(card: CardData) -> void:
	var path: String = "%s/%s.tres" % [OUTPUT_DIR, card.id]
	var error: int = ResourceSaver.save(card, path)
	if error != OK:
		printerr("Failed to save %s (error %d)" % [path, error])
		quit(1)
	else:
		print("  wrote %s" % path)

func _make_jab() -> CardData:
	var card := CardData.new()
	card.id = &"jab"
	card.display_name = "JAB"
	card.cost = BattleConfig.JAB_COST
	card.tags = [&"jab", &"attack"] as Array[StringName]
	card.rules_text = "Deal %d damage." % BattleConfig.JAB_DAMAGE
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.JAB_DAMAGE
	card.effects = [damage] as Array[CardEffect]
	return card

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

func _make_block() -> CardData:
	var card := CardData.new()
	card.id = &"block"
	card.display_name = "BLOCK"
	card.cost = BattleConfig.BLOCK_COST
	card.tags = [&"defense"] as Array[StringName]
	card.rules_text = "Gain %d guard." % BattleConfig.BLOCK_GUARD
	var guard := GuardEffect.new()
	guard.amount = BattleConfig.BLOCK_GUARD
	card.effects = [guard] as Array[CardEffect]
	return card
