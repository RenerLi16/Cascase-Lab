class_name UIkit
extends RefCounted

# Light operations board: one built-in face, four text levels, square stock.
const BG := Color("ffffff")
const PANEL := Color("ffffff")
const INNER := Color("f5f7f8")
const MAP := Color("ffffff")
const LINE := Color("afc0c6")
const TEXT := Color("21363f")
const MUTED := Color("516873")
const ACCENT := TEXT
const TEAL := Color("007f7a")
const RED := Color("c93c32")
const AMBER := Color("bd6712")
const INFRA := Color("8199a3")
const DISPLAY := 32
const SECTION := 20
const BODY := 16
const CAPTION := 13
const METRIC := 48
const XS := 4
const SM := 8
const MD := 12
const LG := 16
const XL := 24
const XXL := 32

static func box(color: Color = PANEL, border: Color = LINE, radius: int = 0, padding: int = LG) -> StyleBoxFlat:
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

static func rule(parent: Node, strong: bool = false) -> void:
	var line := HSeparator.new()
	var style := StyleBoxLine.new()
	style.color = TEXT if strong else LINE
	style.thickness = 3 if strong else 1
	line.add_theme_stylebox_override("separator",style)
	parent.add_child(line)

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = BODY
	result.set_color("font_color","Label",TEXT)
	result.set_color("default_color","RichTextLabel",TEXT)
	result.set_constant("line_spacing","Label",4)
	result.set_constant("line_separation","RichTextLabel",6)
	result.set_constant("separation","VBoxContainer",MD)
	result.set_constant("separation","HBoxContainer",MD)
	result.set_stylebox("panel","PanelContainer",box())
	for kind in ["Button","OptionButton"]:
		result.set_stylebox("normal",kind,box(PANEL,LINE,1,MD))
		result.set_stylebox("hover",kind,box(INNER,TEXT,1,MD))
		result.set_stylebox("pressed",kind,box(BG,TEXT,1,MD))
		var focus := box(Color.TRANSPARENT,AMBER,1,MD)
		focus.set_border_width_all(2)
		result.set_stylebox("focus",kind,focus)
		result.set_stylebox("disabled",kind,box(INNER,LINE,1,MD))
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: result.set_color(state,kind,TEXT)
		result.set_color("font_disabled_color",kind,MUTED)
	result.set_stylebox("panel","PopupMenu",box())
	result.set_font_size("font_size","PopupMenu",BODY)
	result.set_constant("v_separation","PopupMenu",MD)
	result.set_color("font_color","PopupMenu",TEXT)
	result.set_stylebox("hover","PopupMenu",box(INNER,LINE,0,SM))
	result.set_color("font_hover_color","PopupMenu",TEXT)
	result.set_color("font_disabled_color","PopupMenu",MUTED)
	result.set_stylebox("panel","TooltipPanel",box(PANEL,LINE,0,SM))
	result.set_color("font_color","TooltipLabel",TEXT)
	result.set_font_size("font_size","TooltipLabel",CAPTION)
	var track := box(INNER,INNER,0,0)
	track.content_margin_left = 4
	track.content_margin_right = 4
	result.set_stylebox("scroll","VScrollBar",track)
	for state in ["grabber","grabber_highlight","grabber_pressed"]: result.set_stylebox(state,"VScrollBar",box(LINE,LINE,0,0))
	return result

static func label(text: String, size: int = BODY, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	return node

static func paragraph(text: String, size: int = BODY, color: Color = MUTED) -> Label:
	var node := label(text,size,color)
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
		for state in ["normal","hover","pressed"]:
			node.add_theme_stylebox_override(state,box(TEXT if state == "normal" else TEAL,TEXT,1,MD))
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: node.add_theme_color_override(state,PANEL)
	return node

static func quiet(text: String, callback: Callable) -> Button:
	var node := button(text,callback)
	node.add_theme_font_size_override("font_size",CAPTION)
	node.add_theme_stylebox_override("normal",box(Color.TRANSPARENT,Color.TRANSPARENT,0,SM))
	node.custom_minimum_size.y = 36
	return node

static func caution(node: Button) -> Button:
	node.add_theme_stylebox_override("normal",box(PANEL,RED,1,MD))
	node.add_theme_color_override("font_color",RED)
	return node

# One ruled note. Identical structure for all experimental conditions.
static func card(parent: Node, color: Color = PANEL) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := box(color,TEXT,0,LG)
	style.set_border_width_all(0)
	style.border_width_top = 2
	panel.add_theme_stylebox_override("panel",style)
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
	column.add_theme_constant_override("separation",LG)
	scroll.add_child(column)
	return column
