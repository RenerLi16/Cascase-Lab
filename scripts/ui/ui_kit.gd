class_name UIkit
extends RefCounted

# Light paper-board interface: warm off-white paper, opaque reading surfaces,
# charcoal text, and a few restrained piece colours. Barlow for body text and
# controls, Barlow Semi Condensed for short headings; every face falls back to
# a weight-matched Noto Sans SC for Simplified Chinese (1.5 line height).
const BODY_FONT := preload("res://assets/fonts/UiBody.tres") # Barlow Regular
const MEDIUM_FONT := preload("res://assets/fonts/UiMedium.tres") # Barlow Medium
const STRONG_FONT := preload("res://assets/fonts/UiSemiBold.tres") # Barlow SemiBold
const HEADING_FONT := preload("res://assets/fonts/UiHeading.tres") # Barlow Semi Condensed SemiBold

# Paper surfaces
const BG := Color("f4f0e6") # table / page
const PANEL := Color("fffcf5") # cards, sheets, piece faces
const SUNKEN := Color("efe9dc") # quiet hover, neutral chips, note wells
const MAP := Color("f4f0e6") # the table around the board (same as page)
const LINE := Color("ccc5b7") # structural rules and panel edges
const LINE_STRONG := Color("8f887b") # control outlines (3:1 against paper)
const EDGE := Color("b9b1a1") # the thin base under raised keys and pieces
# Text
const TEXT := Color("292a26")
const SECONDARY := Color("55574f")
const DISABLED := Color("6e6f67")
const DISABLED_FACE := Color("ebe6da")
# Primary interaction accent (muted blue) with paper-coloured text.
const ACTION := Color("315f78")
const ACTION_EDGE := Color("1f4252")
const ACTION_TINT := Color("dce6ea")
const ON_ACTION := Color("fffcf5")
# States. Every state also has a symbol or label; colour is never the only cue.
const WARNING := Color("855a00") # dark ochre: privacy, route-loss, no supply route
const WARNING_TINT := Color("f3e7cc")
const DANGER := Color("a23b2e") # muted brick: confirmed Overrun, closed roads
const DANGER_EDGE := Color("72281f")
const PROTECT := Color("3e6b48") # shield and monitor
const ROAD := Color("57584f") # open playable road core
const ROAD_CASING := Color("fffcf5")
const ROAD_HOVER := Color("3b5f72")
const LAND := Color("e9e2ce") # fallback board sheet when no terrain exists
const CRATE := Color("d8bd8c") # supply crate face (every action uses the same crate)

# Type scale at the 1440 x 900 reference layout.
const DISPLAY := 34 # main screen headings
const TITLE := 28 # panel headings
const BODY := 20 # body, instructions, survey questions, AI messages
const BUTTON := 20
const SMALL := 17 # necessary secondary labels
const METRIC := 30 # live numerical readouts
const METRIC_LARGE := 36 # results headline
const TIMER := 32
const MAP_NAME := 17 # location name plates on the map
const MAP_TAG := 16 # status chips on the map
const XS := 4
const SM := 8
const MD := 12
const LG := 16
const XL := 24
const XXL := 32

static var _figures: FontVariation
static var _reduced_motion := -1 # -1 = follow system/project setting
static var _web_preference := -1

# Tabular figures keep timers and readouts from shifting as digits change.
static func figures() -> Font:
	if _figures == null:
		_figures = FontVariation.new()
		_figures.base_font = HEADING_FONT
		_figures.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"):1}
	return _figures

# Reduced motion: the project setting, an in-game toggle, or the browser's
# prefers-reduced-motion. Durations of research-paced sequences never change;
# only movement inside them is replaced by immediate, restrained highlighting.
static func reduced_motion() -> bool:
	if _reduced_motion >= 0: return _reduced_motion == 1
	if bool(ProjectSettings.get_setting("cascade/reduced_motion",false)): return true
	if OS.has_feature("web"):
		if _web_preference < 0:
			var result = JavaScriptBridge.eval("!!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches)",true)
			_web_preference = 1 if result == true else 0
		return _web_preference == 1
	return false

static func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = 1 if enabled else 0

static func motion(seconds: float) -> float:
	return 0.0 if reduced_motion() else seconds

static func box(color: Color = PANEL, border: Color = Color.TRANSPARENT, radius: int = 4, padding: int = LG) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(0 if border.a == 0.0 else 1)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func control_box(color: Color, border: Color) -> StyleBoxFlat:
	var style := box(color,border,6,LG)
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

static func focus_ring() -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = ACTION
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(8)
	ring.set_expand_margin_all(3)
	ring.anti_aliasing = true
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

# Small drawn icons replace Godot's default light-on-dark arrow and switch art.
static func _icon(size: Vector2i, painter: Callable) -> ImageTexture:
	var image := Image.create_empty(size.x,size.y,false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	painter.call(image)
	return ImageTexture.create_from_image(image)

static func _disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var d := Vector2(x+0.5,y+0.5).distance_to(center)
			var a := clampf(radius+0.5-d,0.0,1.0)
			if a > 0.0: image.set_pixel(x,y,image.get_pixel(x,y).blend(Color(color,color.a*a)))

static func _pill(image: Image, rect: Rect2, color: Color) -> void:
	var r := rect.size.y*0.5
	for y in image.get_height():
		for x in image.get_width():
			var p := Vector2(x+0.5,y+0.5)
			var cx := clampf(p.x,rect.position.x+r,rect.end.x-r)
			var d := p.distance_to(Vector2(cx,rect.position.y+r))
			var a := clampf(r+0.5-d,0.0,1.0)
			if a > 0.0: image.set_pixel(x,y,image.get_pixel(x,y).blend(Color(color,color.a*a)))

static func arrow_icon(color: Color) -> ImageTexture:
	return _icon(Vector2i(16,16),func(image: Image):
		for row in 6:
			for x in range(2+row,14-row): image.set_pixel(x,5+row,color))

static func switch_icon(on: bool, enabled: bool = true) -> ImageTexture:
	return _icon(Vector2i(44,26),func(image: Image):
		var track := (ACTION if on else LINE_STRONG) if enabled else LINE
		_pill(image,Rect2(1,3,42,20),track)
		_pill(image,Rect2(2,4,40,18),track if on else SUNKEN)
		_disc(image,Vector2(33 if on else 11,13),7.0,PANEL if on else (LINE_STRONG if enabled else LINE)))

static func radio_icon(on: bool) -> ImageTexture:
	return _icon(Vector2i(18,18),func(image: Image):
		_disc(image,Vector2(9,9),7.0,ACTION if on else LINE_STRONG)
		_disc(image,Vector2(9,9),5.5,PANEL)
		if on: _disc(image,Vector2(9,9),3.5,ACTION))

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
	result.set_color("selection_color","RichTextLabel",ACTION_TINT)
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
	# Plain buttons and form pickers: flat paper fields with a clear outline.
	for kind in ["Button","OptionButton"]:
		result.set_stylebox("normal",kind,control_box(PANEL,LINE_STRONG))
		result.set_stylebox("hover",kind,control_box(PANEL,TEXT))
		result.set_stylebox("pressed",kind,control_box(SUNKEN,TEXT))
		result.set_stylebox("hover_pressed",kind,control_box(SUNKEN,TEXT))
		result.set_stylebox("disabled",kind,control_box(DISABLED_FACE,LINE))
	result.set_icon("arrow","OptionButton",arrow_icon(TEXT))
	result.set_constant("h_separation","OptionButton",MD)
	result.set_constant("arrow_margin","OptionButton",MD)
	for kind in ["CheckButton","CheckBox"]:
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			var flat := box(Color.TRANSPARENT,Color.TRANSPARENT,6,SM)
			if state.begins_with("hover"): flat.bg_color = SUNKEN
			result.set_stylebox(state,kind,flat)
	result.set_icon("checked","CheckButton",switch_icon(true))
	result.set_icon("unchecked","CheckButton",switch_icon(false))
	result.set_icon("checked_disabled","CheckButton",switch_icon(true,false))
	result.set_icon("unchecked_disabled","CheckButton",switch_icon(false,false))
	var popup := box(PANEL,LINE_STRONG,6,SM)
	result.set_stylebox("panel","PopupMenu",popup)
	result.set_font("font","PopupMenu",BODY_FONT)
	result.set_font_size("font_size","PopupMenu",BODY)
	result.set_constant("v_separation","PopupMenu",MD)
	result.set_constant("item_start_padding","PopupMenu",MD)
	result.set_constant("item_end_padding","PopupMenu",MD)
	result.set_color("font_color","PopupMenu",TEXT)
	result.set_color("font_hover_color","PopupMenu",TEXT)
	result.set_color("font_disabled_color","PopupMenu",DISABLED)
	result.set_stylebox("hover","PopupMenu",box(ACTION_TINT,Color.TRANSPARENT,4,SM))
	for pair in [["radio_checked",true],["radio_unchecked",false],["checked",true],["unchecked",false]]:
		result.set_icon(pair[0],"PopupMenu",radio_icon(pair[1]))
	result.set_icon("radio_checked_disabled","PopupMenu",radio_icon(false))
	result.set_icon("radio_unchecked_disabled","PopupMenu",radio_icon(false))
	var separator := StyleBoxLine.new()
	separator.color = LINE
	result.set_stylebox("separator","PopupMenu",separator)
	result.set_stylebox("panel","TooltipPanel",box(PANEL,LINE_STRONG,4,MD))
	result.set_font("font","TooltipLabel",BODY_FONT)
	result.set_font_size("font_size","TooltipLabel",SMALL)
	result.set_color("font_color","TooltipLabel",TEXT)
	result.set_font("font","LineEdit",BODY_FONT)
	result.set_font_size("font_size","LineEdit",BODY)
	result.set_color("font_color","LineEdit",TEXT)
	result.set_color("font_placeholder_color","LineEdit",SECONDARY)
	result.set_color("caret_color","LineEdit",TEXT)
	result.set_color("selection_color","LineEdit",ACTION_TINT)
	result.set_color("font_selected_color","LineEdit",TEXT)
	result.set_stylebox("normal","LineEdit",control_box(PANEL,LINE_STRONG))
	var field_focus := control_box(PANEL,ACTION)
	field_focus.set_border_width_all(2)
	result.set_stylebox("focus","LineEdit",field_focus)
	var track := box(SUNKEN,Color.TRANSPARENT,4,0)
	track.content_margin_left = 5
	track.content_margin_right = 5
	result.set_stylebox("scroll","VScrollBar",track)
	result.set_stylebox("scroll_focus","VScrollBar",track)
	for pair in [["grabber",Color("b3ab9b")],["grabber_highlight",LINE_STRONG],["grabber_pressed",SECONDARY]]:
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

# Raised paper key. Primary keys are blue with paper text; all keys share the
# same lift/press feedback, so no action type gets a more exciting response.
static func button(text: String, callback: Callable, primary: bool = false) -> Button:
	var node := TactileButton.new(TactileButton.Kind.PRIMARY if primary else TactileButton.Kind.NORMAL)
	node.text = text
	node.custom_minimum_size.y = 48
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	if primary: node.add_theme_font_override("font",STRONG_FONT)
	return node

# Low-emphasis text button (close, overview, language). Hover shows a surface.
static func quiet(text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 40
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	node.add_theme_font_size_override("font_size",SMALL+1)
	node.add_theme_color_override("font_color",SECONDARY)
	for state in ["font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]: node.add_theme_color_override(state,TEXT)
	var flat := box(Color.TRANSPARENT,Color.TRANSPARENT,6,MD)
	flat.content_margin_top = 6
	flat.content_margin_bottom = 6
	node.add_theme_stylebox_override("normal",flat)
	var hover := box(SUNKEN,Color.TRANSPARENT,6,MD)
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6
	node.add_theme_stylebox_override("hover",hover)
	var pressed := hover.duplicate()
	pressed.bg_color = DISABLED_FACE
	node.add_theme_stylebox_override("pressed",pressed)
	node.add_theme_stylebox_override("hover_pressed",pressed)
	return node

static func caution(node: Button) -> Button:
	if node is TactileButton:
		node.kind = TactileButton.Kind.CAUTION
		node._apply_colors()
	return node

# One opaque note surface. Identical structure for all experimental conditions.
static func card(parent: Node, color: Color = SUNKEN) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",box(color,LINE if color == PANEL else Color.TRANSPARENT,6,XL-4))
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
