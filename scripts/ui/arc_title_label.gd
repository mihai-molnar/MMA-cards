class_name ArcTitleLabel
extends Control

## The card's name, drawn along the master template's banner instead of on a
## straight line. The banner is a shallow arch -- measured off the template,
## its midline is highest mid-span and sags toward both ends -- and a flat
## Label across it reads as pasted on rather than painted on. Each glyph is
## therefore offset down a parabola anchored at the apex; at this bow the
## slope stays shallow enough that rotating glyphs to the tangent would move
## nothing visibly, so glyphs stay upright, which is also what Slay the
## Spire's own ribbons do.
##
## Styling comes from CardTemplate (display font, size, colour, outline),
## same as the labels CardView builds -- this control only owns the arc.

var text: String = "":
	set(value):
		if text == value:
			return
		text = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Downward sag, in pixels, at normalized span position t (-1 at the left
## edge, 0 at the apex mid-span, +1 at the right edge). Parabolic, scaled by
## the control's own width so the curve survives a CARD_SIZE change the same
## way normalized zones do.
func arc_offset(t: float) -> float:
	return CardTemplate.TITLE_ARC_BOW * size.x * t * t

func _draw() -> void:
	if text.is_empty():
		return
	var font: Font = CardTemplate.DISPLAY_FONT if CardTemplate.DISPLAY_FONT != null \
		else ThemeDB.fallback_font
	var font_size: int = CardTemplate.TITLE_SIZE

	# Advance-summed width, so the run centres the way a Label centres it.
	var total_width: float = 0.0
	for i: int in range(text.length()):
		total_width += font.get_char_size(text.unicode_at(i), font_size).x

	var x: float = (size.x - total_width) / 2.0
	var apex_baseline: float = (size.y - font.get_height(font_size)) / 2.0 \
		+ font.get_ascent(font_size)
	var half_span: float = size.x / 2.0
	for i: int in range(text.length()):
		var code: int = text.unicode_at(i)
		var advance: float = font.get_char_size(code, font_size).x
		# Each glyph rides the arc at its own CENTRE, so wide glyphs do not
		# lean on their leading edge.
		var t_norm: float = clampf((x + advance / 2.0 - half_span) / half_span, -1.0, 1.0)
		var pos := Vector2(x, apex_baseline + arc_offset(t_norm))
		font.draw_char_outline(get_canvas_item(), pos, code, font_size,
			CardTemplate.OUTLINE_SIZE, CardTemplate.OUTLINE_COLOR)
		font.draw_char(get_canvas_item(), pos, code, font_size, CardTemplate.TITLE_COLOR)
		x += advance
