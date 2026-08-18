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
	_save(_make_low_kick())
	_save(_make_one_two())
	_save(_make_strength_up())
	_save(_make_prepared())
	_save(_make_high_kick())
	_save(_make_flying_knee())
	_save(_make_elbow())

	print("Generated 10 card resources in %s" % OUTPUT_DIR)
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
	# The card names the KEYWORD and its trigger; the mechanic (the bonus
	# ratio, the strictly-consecutive requirement) lives in the Combo
	# tooltip via ComboRule.keyword_description(), derived from the live
	# config -- so no number is printed here that a rebalance could leave
	# stale, which is precisely what the old painted face did. "right after"
	# is load-bearing wording: any card in between breaks the combo, and an
	# earlier phrasing ("earlier this turn") lied about that.
	card.rules_text = "Deal %d damage. Combo right after Jab." % BattleConfig.STRAIGHT_DAMAGE
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.STRAIGHT_DAMAGE
	card.effects = [damage] as Array[CardEffect]
	return card

func _make_low_kick() -> CardData:
	var card := CardData.new()
	card.id = &"low_kick"
	card.display_name = "LOW KICK"
	card.cost = BattleConfig.LOW_KICK_COST
	card.tags = [&"kick", &"attack"] as Array[StringName]
	# "Leg Injury" is a KEYWORD: CardTemplate colours it yellow and the hover
	# tooltip explains what it does, so the card itself stays short -- the
	# mechanics (50% weaker attacks) live in the status description, not here.
	card.rules_text = "Deal %d damage. If unblocked, causes Leg Injury for %d turn." % [
		BattleConfig.LOW_KICK_DAMAGE, BattleConfig.LEG_INJURY_TURNS]
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.LOW_KICK_DAMAGE
	var injury := ApplyStatusEffect.new()
	injury.status_id = LegInjuryStatus.ID
	injury.stacks = 1
	injury.turns = BattleConfig.LEG_INJURY_TURNS
	injury.target_self = false
	# A second kick keeps the leg hurt a turn longer, not hurt twice as much.
	injury.extend_duration = true
	# A fully blocked kick lands no hp damage, so it injures nothing.
	injury.require_hp_damage = true
	card.effects = [damage, injury] as Array[CardEffect]
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

func _make_one_two() -> CardData:
	var card := CardData.new()
	card.id = &"one_two"
	card.display_name = "ONE-TWO"
	card.cost = BattleConfig.ONE_TWO_COST
	card.tags = [&"attack"] as Array[StringName]
	# One number only, in the damage sentence (red). The second sentence is a
	# pure CONDITION -- "hits twice", no repeated 5 -- because an earlier
	# wording ("Breaks guard: deal 5 damage again.") read as if the card had
	# a guard-breaking ability rather than a conditional second hit, flagged
	# by Mihai from play. The break rule itself lives in the effect.
	card.rules_text = "Deal %d damage. If it breaks guard, hits twice." % \
		BattleConfig.ONE_TWO_DAMAGE
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.ONE_TWO_DAMAGE
	var bonus := GuardBreakBonusEffect.new()
	bonus.amount = BattleConfig.ONE_TWO_DAMAGE
	card.effects = [damage, bonus] as Array[CardEffect]
	return card

func _make_strength_up() -> CardData:
	var card := CardData.new()
	card.id = &"strength_up"
	card.display_name = "STRENGTH UP"
	card.cost = BattleConfig.STRENGTH_UP_COST
	# Not tagged defense: a damage buff wears the ATTACK (red) frame under
	# the two-colourway system.
	card.tags = [&"buff"] as Array[StringName]
	# "STR" keyword-matches the strength status (word-bounded, so STRAIGHT
	# stays safe); "Burn" is the second rule-keyword after Combo -- the
	# mechanics live in the tooltips, no number here can go stale.
	card.rules_text = "Gain %d STR. Burn." % BattleConfig.STRENGTH_UP_STACKS
	card.burn = true
	var buff := ApplyStatusEffect.new()
	buff.status_id = StrengthStatus.ID
	buff.stacks = BattleConfig.STRENGTH_UP_STACKS
	buff.turns = BattleConfig.STATUS_PERMANENT
	buff.target_self = true
	card.effects = [buff] as Array[CardEffect]
	return card

func _make_prepared() -> CardData:
	var card := CardData.new()
	card.id = &"prepared"
	card.display_name = "PREPARED"
	card.cost = BattleConfig.PREPARED_COST
	card.tags = [&"defense"] as Array[StringName]
	# "Prepared" is a status keyword: yellow, tooltip-explained. Both 4s sit
	# in sentences naming "guard", so they colour guard-blue.
	card.rules_text = "Gain %d guard. Prepared: gain %d guard next turn." % [
		BattleConfig.PREPARED_GUARD, BattleConfig.PREPARED_GUARD]
	var guard := GuardEffect.new()
	guard.amount = BattleConfig.PREPARED_GUARD
	var delayed := ApplyStatusEffect.new()
	delayed.status_id = PreparedStatus.ID
	delayed.stacks = BattleConfig.PREPARED_GUARD
	delayed.turns = BattleConfig.PREPARED_STATUS_TURNS
	delayed.target_self = true
	card.effects = [guard, delayed] as Array[CardEffect]
	return card

func _make_high_kick() -> CardData:
	var card := CardData.new()
	card.id = &"high_kick"
	card.display_name = "HIGH KICK"
	card.cost = BattleConfig.HIGH_KICK_COST
	card.tags = [&"kick", &"attack"] as Array[StringName]
	# "KO" is a game-rule keyword like Combo and Burn: yellow and
	# tooltip-explained (the only-when-it-deals-hp-damage rule lives in the
	# tooltip, not here). The percentage is a chance, not damage --
	# CardTemplate._number_color keeps it plain.
	card.rules_text = "Deal %d damage. %d%% chance to KO." % [
		BattleConfig.HIGH_KICK_DAMAGE, roundi(BattleConfig.HIGH_KICK_KO_CHANCE * 100.0)]
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.HIGH_KICK_DAMAGE
	var ko := KOChanceEffect.new()
	ko.chance = BattleConfig.HIGH_KICK_KO_CHANCE
	card.effects = [damage, ko] as Array[CardEffect]
	return card

func _make_flying_knee() -> CardData:
	var card := CardData.new()
	card.id = &"flying_knee"
	card.display_name = "FLYING KNEE"
	card.cost = BattleConfig.FLYING_KNEE_COST
	# A knee reads as a kick impact, not a punch -- the kick tag picks the
	# hit sound.
	card.tags = [&"kick", &"attack"] as Array[StringName]
	card.rules_text = "Deal %d damage. %d%% chance to KO." % [
		BattleConfig.FLYING_KNEE_DAMAGE, roundi(BattleConfig.FLYING_KNEE_KO_CHANCE * 100.0)]
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.FLYING_KNEE_DAMAGE
	var ko := KOChanceEffect.new()
	ko.chance = BattleConfig.FLYING_KNEE_KO_CHANCE
	card.effects = [damage, ko] as Array[CardEffect]
	return card

func _make_elbow() -> CardData:
	var card := CardData.new()
	card.id = &"elbow"
	card.display_name = "ELBOW"
	card.cost = BattleConfig.ELBOW_COST
	card.tags = [&"attack"] as Array[StringName]
	# "Bleed" is a status keyword: the mechanics (damage per turn, guard
	# piercing, the deals-damage-past-guard requirement) live in its tooltip.
	card.rules_text = "Deal %d damage. %d%% chance to KO. %d%% chance to cause Bleed." % [
		BattleConfig.ELBOW_DAMAGE, roundi(BattleConfig.ELBOW_KO_CHANCE * 100.0),
		roundi(BattleConfig.ELBOW_BLEED_CHANCE * 100.0)]
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.ELBOW_DAMAGE
	var ko := KOChanceEffect.new()
	ko.chance = BattleConfig.ELBOW_KO_CHANCE
	var bleed := ApplyStatusEffect.new()
	bleed.status_id = BleedStatus.ID
	bleed.stacks = 1
	bleed.turns = BattleConfig.BLEED_TURNS
	bleed.target_self = false
	# A second elbow keeps the cut open longer, not deeper.
	bleed.extend_duration = true
	# A fully blocked elbow cuts nothing -- same rule as Low Kick's injury.
	bleed.require_hp_damage = true
	bleed.chance = BattleConfig.ELBOW_BLEED_CHANCE
	card.effects = [damage, ko, bleed] as Array[CardEffect]
	return card
