class_name UIkit
extends RefCounted

const BG := Color("d4cebf")
const PANEL := Color("f3efe4")
const INNER := Color("e6e1d4")
const LINE := Color("b9b5a6")
const TEXT := Color("343c32")
const MUTED := Color("65695c")
const ACCENT := Color("596c47")
const TEAL := Color("637c6e")
const RED := Color("a44336")
const AMBER := Color("94652d")

static func box(color: Color = PANEL, border: Color = LINE, radius: int = 5, padding: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_constant("separation", "HBoxContainer", 12)
	theme.set_stylebox("panel", "PanelContainer", box())
	for kind in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", kind, box(INNER, LINE, 8, 12))
		theme.set_stylebox("hover", kind, box(Color("d8dece"), TEAL, 8, 12))
		theme.set_stylebox("pressed", kind, box(Color("c2cdb6"), ACCENT, 8, 12))
		theme.set_stylebox("focus", kind, box(Color(0,0,0,0), TEAL, 8, 12))
		theme.set_stylebox("disabled", kind, box(Color("e0ddd3"), Color("c4c2b8"), 8, 12))
		theme.set_color("font_color", kind, TEXT)
		theme.set_color("font_hover_color", kind, TEXT)
		theme.set_color("font_pressed_color", kind, ACCENT)
		theme.set_color("font_disabled_color", kind, Color("7a7d70"))
	theme.set_stylebox("panel", "PopupMenu", box())
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_stylebox("hover", "PopupMenu", box(INNER, LINE, 3, 8))
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_color("font_disabled_color", "PopupMenu", MUTED)
	return theme

static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node

static func paragraph(text: String, size: int = 16, color: Color = MUTED) -> Label:
	var node := label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

static func rich(text: String) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.text = text
	node.fit_content = true
	node.scroll_active = false
	node.selection_enabled = true
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

static func button(text: String, callback: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 44
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	if primary:
		node.add_theme_stylebox_override("normal", box(ACCENT, ACCENT, 8, 12))
		node.add_theme_stylebox_override("hover", box(Color("6a7f55"), ACCENT, 8, 12))
		node.add_theme_color_override("font_color", PANEL)
		node.add_theme_color_override("font_hover_color", PANEL)
	return node

static func card(parent: Node, color: Color = PANEL) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(color))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	return column

static func scroll_column(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	return column
