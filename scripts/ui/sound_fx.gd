class_name SoundFx
extends Node

## Sound effects: the audio sibling of ScreenFx, owned by BattleView. Holds
## every stream the battle fires and a small round-robin pool of players so
## overlapping sounds (a punch over a click over the fan) never cut each
## other off.
##
## Every play() records WHAT it decided -- the sound id and the chosen
## variant -- before the is_inside_tree() guard, so headless tests can
## assert the decision on a detached node (project rule: decision-recording
## happens before tree guards, or tests can no longer see it).

## Multiple recordings of the same hit, picked at random per play so a
## flurry of jabs doesn't sound machine-gunned. Volume and pitch variation
## live in Juice with every other feel magnitude.
const _STREAMS: Dictionary = {
	&"punch": [
		preload("res://assets/audio/punch.wav"),
		preload("res://assets/audio/punch_2.wav"),
		preload("res://assets/audio/punch_3.wav"),
	],
	&"kick": [preload("res://assets/audio/kick.wav")],
	&"card_fan": [preload("res://assets/audio/card_fan.wav")],
	&"click": [preload("res://assets/audio/click_double_on.wav")],
	&"slam": [preload("res://assets/audio/metal_clang.wav")],
}

## Only impact sounds get pitch-varied: a UI click that changes pitch reads
## as a different control, not as variety.
const _PITCH_VARIED: Array[StringName] = [&"punch", &"kick"]

const _POOL_SIZE: int = 6

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _last_played: StringName = &""
var _last_stream: AudioStream = null

func _ready() -> void:
	for i: int in range(_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

## Fires one sound by id. Unknown ids are loud -- a misspelled id at a call
## site should fail the test run, not fall silent.
func play(id: StringName) -> void:
	var variants: Array = variants_for(id)
	if variants.is_empty():
		push_error("SoundFx: unknown sound id %s" % id)
		return
	_last_played = id
	_last_stream = variants.pick_random()
	if not is_inside_tree():
		return
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _last_stream
	player.volume_db = Juice.SFX_VOLUME_DB.get(id, 0.0)
	player.pitch_scale = randf_range(Juice.SFX_PITCH_MIN, Juice.SFX_PITCH_MAX) \
		if _PITCH_VARIED.has(id) else 1.0
	player.play()

func last_played() -> StringName:
	return _last_played

func last_stream() -> AudioStream:
	return _last_stream

static func variants_for(id: StringName) -> Array:
	return _STREAMS.get(id, [])

## The sound a landed card hit warrants, from the card's own data: kicks
## kick, other damaging cards punch, a card with no damage (Block) is
## silent. Pure, so the mapping is testable without a battle.
static func hit_sound_for_card(card: CardData) -> StringName:
	if card == null or card.total_base_damage() <= 0:
		return &""
	if card.has_tag(&"kick"):
		return &"kick"
	return &"punch"

## The enemy-turn analogue, read from the coming turn's moves before
## end_turn() resolves them. Opponent moves have labels, not tags, so a
## damaging move whose label names KICK kicks and any other damaging move
## punches; a turn of pure guard/buff is silent.
static func hit_sound_for_moves(moves: Array) -> StringName:
	for move: OpponentMove in moves:
		for effect: CardEffect in move.effects:
			if effect is DamageEffect:
				return &"kick" if move.label.contains("KICK") else &"punch"
	return &""
