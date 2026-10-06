class_name UIkit
extends RefCounted

# Restrained strategy-game interface: neutral near-black surfaces, opaque reading
# panels, Barlow body text, and Barlow Semi Condensed reserved for headings.
# Every face falls back to a weight-matched Noto Sans SC for Simplified Chinese.
# The fallback sets a 1.5 line height (30px at 20px), so labels add no extra spacing.
const BODY_FONT := preload("res://assets/fonts/UiBody.tres") # Barlow Regular
const MEDIUM_FONT := preload("res://assets/fonts/UiMedium.tres") # Barlow Medium
const STRONG_FONT := preload("res://assets/fonts/UiSemiBold.tres") # Barlow SemiBold
const HEADING_FONT := preload("res://assets/fonts/UiHeading.tres") # Barlow Semi Condensed SemiBold

# Surfaces
const BG := Color("050505")
const PANEL := Color("101010")
const RAISED := Color("191919")
const HOVER := Color("222220")
const PRESSED := Color("0b0b0b")
const MAP := Color("0a0a0a")
const LINE := Color("333330")
const LINE_STRONG := Color("55554f")
# Text: hierarchy comes from size and weight; every glyph core is opaque.
const TEXT := Color("f3f3ee")
const SECONDARY := Color("c7c7c2")
const DISABLED := Color("a3a39e")
# Primary actions and selected controls (dark text on a pale accent).
const ACTION := Color("d6e5a6")
const ACTION_HOVER := Color("e2edbd")
const ACTION_PRESSED := Color("c3d48f")
const ON_ACTION := Color("0b0d07")
# Status colors keep their existing meanings on the map and in notices.
const ACCENT := Color("8fff86") # functioning / playable building
const TEAL := Color("79efa2") # shield and monitor
const RED := Color("ff6b70") # Overrun, loss, countdown
const AMBER := Color("f2c477") # roads, privacy, caution

# Type scale at the 1440 x 900 reference layout.
const DISPLAY := 34 # main screen headings
const TITLE := 28 # panel headings
const BODY := 20 # body, instructions, survey questions, AI messages
const BUTTON := 20
const SMALL := 17 # necessary secondary labels
const METRIC := 30 # live numerical readouts
const METRIC_LARGE := 36 # results headline
const TIMER := 32
const MAP_NAME := 17 # building name plates on the map
const MAP_TAG := 16 # status stamps on the map
const XS := 4
const SM := 8
const MD := 12
const LG := 16
const XL := 24
const XXL := 32

static var _figures: FontVariation

# Tabular figures keep timers and readouts from shifting as digits change.
static func figures() -> Font:
	if _figures == null:
		_figures = FontVariation.new()
		_figures.base_font = HEADING_FONT
		_figures.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"):1}
	return _figures

static func box(color: Color = PANEL, border: Color = Color.TRANSPARENT, radius: int = 2, padding: int = LG) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(0 if border.a == 0.0 else 1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func control_box(color: Color, border: Color) -> StyleBoxFlat:
	var style := box(color,border,3,LG)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func focus_ring() -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = TEXT
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(4)
	ring.set_expand_margin_all(3)
	return ring

static func rule(parent: Node) -> void:
	var line := HSeparator.new()
	var style := StyleBoxLine.new()
	style.color = LINE
	style.thickness = 1
	line.add_theme_stylebox_override("separator",style)
	line.add_theme_constant_override("separation",1)
	parent.add_child(line)

static func spacer(parent: Node, height: int) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = BODY_FONT
	result.default_font_size = BODY
	# Ordinary glyphs have no halo, shadow, outline, or translucent core.
	for kind in ["Label","RichTextLabel","Button","OptionButton","CheckButton","CheckBox","PopupMenu","TooltipLabel","LineEdit"]:
		result.set_constant("outline_size",kind,0)
		result.set_constant("shadow_outline_size",kind,0)
		result.set_color("font_shadow_color",kind,Color.TRANSPARENT)
		result.set_color("font_outline_color",kind,Color.TRANSPARENT)
	result.set_color("font_color","Label",TEXT)
	result.set_constant("line_spacing","Label",0)
	result.set_font("normal_font","RichTextLabel",BODY_FONT)
	result.set_font("bold_font","RichTextLabel",STRONG_FONT)
	result.set_color("default_color","RichTextLabel",TEXT)
	result.set_constant("line_separation","RichTextLabel",0)
	for property in ["normal_font_size","bold_font_size","italics_font_size","bold_italics_font_size","mono_font_size"]:
		result.set_font_size(property,"RichTextLabel",BODY)
	result.set_constant("separation","VBoxContainer",MD)
	result.set_constant("separation","HBoxContainer",MD)
	result.set_stylebox("panel","PanelContainer",box(PANEL,Color.TRANSPARENT,0,LG))
	for kind in ["Button","OptionButton","CheckButton","CheckBox"]:
		result.set_font("font",kind,MEDIUM_FONT)
		result.set_font_size("font_size",kind,BUTTON)
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]: result.set_color(state,kind,TEXT)
		result.set_color("font_disabled_color",kind,DISABLED)
		result.set_stylebox("focus",kind,focus_ring())
	result.set_font("font","OptionButton",BODY_FONT)
	for kind in ["Button","OptionButton"]:
		result.set_stylebox("normal",kind,control_box(RAISED,LINE))
		result.set_stylebox("hover",kind,control_box(HOVER,LINE_STRONG))
		result.set_stylebox("pressed",kind,control_box(PRESSED,LINE_STRONG))
		result.set_stylebox("hover_pressed",kind,control_box(HOVER,LINE_STRONG))
		result.set_stylebox("disabled",kind,control_box(Color("141414"),Color("292927")))
	result.set_constant("h_separation","OptionButton",MD)
	result.set_constant("arrow_margin","OptionButton",MD)
	for kind in ["CheckButton","CheckBox"]:
		for state in ["normal","hover","pressed","hover_pressed","disabled"]: result.set_stylebox(state,kind,box(Color.TRANSPARENT,Color.TRANSPARENT,3,SM))
	var popup := box(RAISED,LINE,3,SM)
	result.set_stylebox("panel","PopupMenu",popup)
	result.set_font("font","PopupMenu",BODY_FONT)
	result.set_font_size("font_size","PopupMenu",BODY)
	result.set_constant("v_separation","PopupMenu",MD)
	result.set_constant("item_start_padding","PopupMenu",MD)
	result.set_constant("item_end_padding","PopupMenu",MD)
	result.set_color("font_color","PopupMenu",TEXT)
	result.set_color("font_hover_color","PopupMenu",TEXT)
	result.set_color("font_disabled_color","PopupMenu",DISABLED)
	result.set_stylebox("hover","PopupMenu",box(Color("2b2b28"),Color.TRANSPARENT,2,SM))
	result.set_stylebox("panel","TooltipPanel",box(RAISED,LINE,3,MD))
	result.set_font("font","TooltipLabel",BODY_FONT)
	result.set_font_size("font_size","TooltipLabel",SMALL)
	result.set_color("font_color","TooltipLabel",TEXT)
	result.set_font("font","LineEdit",BODY_FONT)
	result.set_font_size("font_size","LineEdit",BODY)
	result.set_color("font_color","LineEdit",TEXT)
	result.set_color("font_placeholder_color","LineEdit",SECONDARY)
	result.set_color("caret_color","LineEdit",TEXT)
	result.set_color("selection_color","LineEdit",Color(ACTION,0.35))
	result.set_stylebox("normal","LineEdit",control_box(RAISED,LINE))
	result.set_stylebox("focus","LineEdit",focus_ring())
	var track := box(Color("161616"),Color.TRANSPARENT,4,0)
	track.content_margin_left = 5
	track.content_margin_right = 5
	result.set_stylebox("scroll","VScrollBar",track)
	result.set_stylebox("scroll_focus","VScrollBar",track)
	for pair in [["grabber",Color("5a5a55")],["grabber_highlight",Color("75756e")],["grabber_pressed",Color("8a8a83")]]:
		result.set_stylebox(pair[0],"VScrollBar",box(pair[1],Color.TRANSPARENT,4,0))
	return result

# Plain text in a chosen face. Headings use the condensed face; everything else
# uses Barlow, with weight reserved for important labels.
static func text_label(text: String, font: Font, size: int, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font",font)
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	return node

static func heading(text: String, size: int = TITLE, color: Color = TEXT) -> Label:
	var node := text_label(text,HEADING_FONT,size,color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

static func label(text: String, size: int = BODY, color: Color = TEXT) -> Label:
	return text_label(text,BODY_FONT,size,color)

static func strong(text: String, size: int = BODY, color: Color = TEXT) -> Label:
	return text_label(text,STRONG_FONT,size,color)

# Secondary labels: readable size, medium weight, secondary color by default.
static func meta(text: String, color: Color = SECONDARY) -> Label:
	var node := text_label(text,MEDIUM_FONT,SMALL,color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

static func paragraph(text: String, size: int = BODY, color: Color = TEXT) -> Label:
	var node := label(text,size,color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

static func figure(text: String, size: int = METRIC, color: Color = TEXT) -> Label:
	return text_label(text,figures(),size,color)

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
	node.custom_minimum_size.y = 48
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	if primary:
		node.add_theme_font_override("font",STRONG_FONT)
		for pair in [["normal",ACTION],["hover",ACTION_HOVER],["pressed",ACTION_PRESSED],["hover_pressed",ACTION_HOVER]]:
			node.add_theme_stylebox_override(pair[0],control_box(pair[1],pair[1]))
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]: node.add_theme_color_override(state,ON_ACTION)
	return node

# Low-emphasis text button (close, overview, archive). Hover still shows a surface.
static func quiet(text: String, callback: Callable) -> Button:
	var node := button(text,callback)
	node.custom_minimum_size.y = 40
	node.add_theme_font_size_override("font_size",SMALL+1)
	node.add_theme_color_override("font_color",SECONDARY)
	var flat := box(Color.TRANSPARENT,Color.TRANSPARENT,3,MD)
	flat.content_margin_top = 6
	flat.content_margin_bottom = 6
	node.add_theme_stylebox_override("normal",flat)
	var hover := box(RAISED,Color.TRANSPARENT,3,MD)
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6
	node.add_theme_stylebox_override("hover",hover)
	node.add_theme_stylebox_override("pressed",hover)
	return node

static func caution(node: Button) -> Button:
	node.add_theme_stylebox_override("normal",control_box(RAISED,RED))
	node.add_theme_stylebox_override("hover",control_box(HOVER,RED))
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]: node.add_theme_color_override(state,RED)
	return node

# One opaque note surface. Identical structure for all experimental conditions.
static func card(parent: Node, color: Color = RAISED) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",box(color,Color.TRANSPARENT,3,XL-4))
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
