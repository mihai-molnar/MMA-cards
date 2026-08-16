class_name StatusTooltip
extends PanelContainer

## Explains the status keywords a hovered card names: "Leg Injury" on the
## card is yellow (CardTemplate colours it), and this panel is where the
## player learns what it means -- name in the keyword yellow, description
## from StatusRegistry, one pair per keyword the card mentions.
##
## Owned by BattleView, NOT by the card: CardView clips its contents, and a
## tooltip must escape the card rect. It reads CardData and the registry and
## computes no rules. Layout constants live here, with their owner, per the
## house rule; colours and fonts come from CardTemplate so the tooltip reads
## as part of the card it explains.

const ANCHOR_GAP: float = 10.0
const PANEL_PAD: float = 8.0
const NAME_SIZE: int = 12
const BODY_SIZE: int = 12
## Descriptions wrap at this width; without it a long keyword explanation
## (Combo's) renders as one screen-wide line.
const BODY_WIDTH: float = 260.0
## Above the hovered card (HOVER_Z 50) and a lunging one (LUNGE_Z 60).
const TOOLTIP_Z: int = 70

var _rows: VBoxContainer

func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = TOOLTIP_Z

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.95)
	style.border_color = CardTemplate.RULES_KEYWORD_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(PANEL_PAD)
	add_theme_stylebox_override("panel", style)

	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)

## Shows the tooltip for `card` with its bottom edge ANCHOR_GAP above
## `anchor_top_centre` (the hovered card's top-centre), horizontally centred
## on it. A card naming no registered status hides the tooltip instead --
## an empty explanation panel is worse than none.
func show_for_card(card: CardData, anchor_top_centre: Vector2) -> void:
	var ids: Array[StringName] = CardTemplate.keywords_in(card)
	if ids.is_empty():
		hide_tooltip()
		return
	_populate(ids)
	visible = true
	reset_size()
	position = anchor_top_centre - Vector2(size.x / 2.0, size.y + ANCHOR_GAP)
	_clamp_to_viewport()

## The chip variant: one status, hanging BELOW its anchor (the chip's
## bottom-centre) -- the chips sit at the top of the screen under the hp
## readout, and a panel above the anchor would cover exactly what it
## explains. An unregistered id hides the tooltip, mirroring show_for_card.
func show_for_status(id: StringName, anchor_bottom_centre: Vector2) -> void:
	if StatusRegistry.description(id) == "":
		hide_tooltip()
		return
	_populate([id] as Array[StringName])
	visible = true
	reset_size()
	position = anchor_bottom_centre + Vector2(-size.x / 2.0, ANCHOR_GAP)
	_clamp_to_viewport()

## A bare one-line label -- the End Turn button's art carries no words, so
## its hover shows them here, above the button like a card tooltip.
func show_label(text: String, anchor_top_centre: Vector2) -> void:
	_clear_rows()
	_rows.add_child(_make_row_label(text,
		CardTemplate.RULES_KEYWORD_COLOR, CardTemplate.DISPLAY_FONT, NAME_SIZE))
	visible = true
	reset_size()
	position = anchor_top_centre - Vector2(size.x / 2.0, size.y + ANCHOR_GAP)
	_clamp_to_viewport()

func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.free()

func _populate(ids: Array[StringName]) -> void:
	_clear_rows()
	for id: StringName in ids:
		_rows.add_child(_make_row_label(CardTemplate.keyword_title(id),
			CardTemplate.RULES_KEYWORD_COLOR, CardTemplate.DISPLAY_FONT, NAME_SIZE))
		var body: Label = _make_row_label(CardTemplate.keyword_description(id),
			CardTemplate.RULES_COLOR, CardTemplate.FONT, BODY_SIZE)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(BODY_WIDTH, 0.0)
		_rows.add_child(body)

## Keep the panel on screen when an edge chip or fan-edge card is hovered.
## Only possible in a tree -- tests build the tooltip detached, where there
## is no viewport to clamp against.
func _clamp_to_viewport() -> void:
	if is_inside_tree():
		var limit: float = get_viewport_rect().size.x
		position.x = clampf(position.x, 0.0, maxf(0.0, limit - size.x))

func hide_tooltip() -> void:
	visible = false

## Everything the tooltip displays, for tests.
func debug_text() -> String:
	var parts: Array[String] = []
	for child: Node in _rows.get_children():
		parts.append((child as Label).text)
	return " | ".join(parts)

func _make_row_label(text: String, color: Color, font: Font, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font != null:
		label.add_theme_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
