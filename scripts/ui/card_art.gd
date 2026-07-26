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
