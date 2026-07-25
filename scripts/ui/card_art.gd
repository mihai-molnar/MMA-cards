class_name CardArt
extends RefCounted

## Card art is found by convention: a card with id `jab` uses
## res://assets/cards/card_jab.png. That keeps the project's promise that
## adding a card means authoring a .tres and dropping in a matching PNG --
## no code change, and no lookup table to keep in sync.
##
## Deliberately lives in scripts/ui/ rather than as a field on CardData:
## scripts/core/ has stayed free of presentation concerns for three passes
## (verified by tree hash), and a texture pointer is presentation.

const ART_DIR: String = "res://assets/cards"

## Keyed by card id. A missing file caches to null too, so a card without art
## only ever pays the ResourceLoader.exists() check once, same as a hit.
static var _cache: Dictionary = {}

## Returns null when no file exists for this id -- a legitimate fallback (see
## CardView), not an error, so this never push_errors.
static func texture_for(card_id: StringName) -> Texture2D:
	if _cache.has(card_id):
		return _cache[card_id]
	var path: String = "%s/card_%s.png" % [ART_DIR, card_id]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_cache[card_id] = texture
	return texture
