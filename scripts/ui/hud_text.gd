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
