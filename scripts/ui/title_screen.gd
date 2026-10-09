extends Control

# Title screen: large pixel title, two lines of orientation, Play and Dev Mode,
# surrounded by a decorative network that never covers the interface.
# Loading this screen creates no session, upload, log entry or model request.

signal start_requested
signal replay_requested
signal dev_requested
signal export_requested
signal status_label_changed(label: Label)

const TITLE_FONT := preload("res://assets/fonts/Silkscreen-Bold.ttf")
const SUBTITLE_FONT := preload("res://assets/fonts/Silkscreen-Regular.ttf")
const BG := Color("070c11")
const TITLE_COLOR := Color("f3ecd8")
# Silkscreen is drawn on a 1/8 em pixel grid; multiples of 8 keep pixels whole.
const TITLE_BASE := 96
const SIDE_MARGIN := 64.0

# Configured by the owner before the node enters the tree.
var replay_available := false
var dev_available := false
var show_recovery := false

var starting := false
var network: MenuNetwork
var layer: Control
var column: VBoxContainer
var corner: HBoxContainer
var footer: VBoxContainer
var title_label: Label
var subtitle_label: Label
var play_button: Button
var dev_button: Button
var language_button: Button
var motion_button: Button
var status_label: Label
var dialog: Control
var dialog_panel: PanelContainer
var password_field: LineEdit
var password_error: Label
var unlock_button: Button
var cancel_button: Button
var layout_key := ""
var title_size := TITLE_BASE
var title_lines := 1
var text_scale := 1.0

func t(en: String, zh: String) -> String:
	return FirstPlayText.choose(en,zh)

func _ready() -> void:
	name = "TitleScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.name = "TitleBackground"
	background.color = BG
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	network = MenuNetwork.new()
	add_child(network)
	layer = Control.new()
	layer.name = "TitleContent"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	_compute_layout()
	_build()
	resized.connect(_on_resized)

# Physical scale of the canvas_items stretch. Small windows and embeds get
# slightly larger logical text so it stays readable after scaling.
func _window_scale() -> float:
	var logical := get_viewport_rect().size
	var window := Vector2(get_tree().root.size)
	if logical.x <= 0 or window.x <= 0: return 1.0
	return minf(window.x/logical.x,window.y/logical.y)

func _compute_layout() -> String:
	var scale := _window_scale()
	text_scale = clampf(0.8/scale,1.0,1.45) if scale < 0.8 else 1.0
	var width := get_viewport_rect().size.x-SIDE_MARGIN*2
	var target := int(round(TITLE_BASE*minf(text_scale,1.25)/8.0))*8
	title_lines = 1
	title_size = target
	while title_size > 40:
		var one := TITLE_FONT.get_string_size("CASCADE LAB",HORIZONTAL_ALIGNMENT_LEFT,-1,title_size).x
		if one <= width: break
		var two := TITLE_FONT.get_string_size("CASCADE",HORIZONTAL_ALIGNMENT_LEFT,-1,title_size).x
		if two <= width:
			title_lines = 2
			break
		title_size -= 8
	return "%d|%d|%.2f" % [title_size,title_lines,text_scale]

func _on_resized() -> void:
	var key := _compute_layout()
	if key != layout_key: _build()

func _px(value: float) -> int:
	return int(round(value*text_scale))

func _build() -> void:
	layout_key = "%d|%d|%.2f" % [title_size,title_lines,text_scale]
	network.clear_protected()
	for child in layer.get_children():
		layer.remove_child(child)
		child.queue_free()
	play_button = null
	dev_button = null
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	column = VBoxContainer.new()
	column.name = "TitleColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation",0)
	center.add_child(column)
	_build_title()
	_build_corner()
	_build_footer()
	network.protect(column,48.0)
	for control in [play_button,dev_button]:
		if is_instance_valid(control): network.protect(control,28.0)
	network.protect(corner,20.0)
	network.protect(footer,20.0)
	if is_instance_valid(dialog_panel): network.protect(dialog_panel,32.0)

func _title_text(size: int, lines: int) -> Label:
	var node := Label.new()
	node.name = "Title"
	node.text = "CASCADE\nLAB" if lines == 2 else "CASCADE LAB"
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_theme_font_override("font",TITLE_FONT)
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",TITLE_COLOR)
	node.add_theme_constant_override("line_spacing",int(size*0.12))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _subtitle(size: int) -> Label:
	var node := Label.new()
	node.name = "Subtitle"
	node.text = "OUTBREAK"
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_theme_font_override("font",SUBTITLE_FONT)
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",UIkit.AMBER)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _centered(text: String, font: Font, size: int, color: Color) -> Label:
	var node := UIkit.text_label(text,font,size,color)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size.x = minf(_px(620),get_viewport_rect().size.x-SIDE_MARGIN*2)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _gap(height: float) -> void:
	UIkit.spacer(column,int(height))

func _build_title() -> void:
	title_label = _title_text(title_size,title_lines)
	column.add_child(title_label)
	_gap(title_size*0.14)
	subtitle_label = _subtitle(maxi(16,int(round(title_size/3.0/8.0))*8))
	column.add_child(subtitle_label)
	_gap(_px(44))
	column.add_child(_centered(t("Three players. Six supplies. Keep the network alive.","三名玩家，六份物资，守住整个网络。"),UIkit.MEDIUM_FONT,_px(23),UIkit.TEXT))
	_gap(_px(6))
	column.add_child(_centered(t("Work together to contain the outbreak.","齐心协力，控制疫情。"),UIkit.BODY_FONT,_px(20),UIkit.SECONDARY))
	_gap(_px(40))
	play_button = _menu_button(t("Play","开始游戏"),_on_play,true)
	play_button.name = "PlayButton"
	play_button.custom_minimum_size = Vector2(_px(300),_px(62))
	play_button.add_theme_font_size_override("font_size",_px(24))
	column.add_child(play_button)
	if dev_available:
		_gap(_px(14))
		dev_button = _menu_button("Dev Mode" if not FirstPlayText.chinese else "Dev Mode · 开发者模式",_on_dev,false)
		dev_button.name = "DevModeButton"
		dev_button.custom_minimum_size = Vector2(_px(196),_px(42))
		dev_button.add_theme_font_size_override("font_size",_px(17))
		dev_button.add_theme_color_override("font_color",UIkit.SECONDARY)
		column.add_child(dev_button)
	if replay_available:
		_gap(_px(12))
		var replay := UIkit.quiet(t("Replay practice","重玩练习"),func():
			if starting: return
			starting = true
			replay_requested.emit())
		replay.name = "ReplayButton"
		replay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(replay)
	_focus_later(play_button)

func _menu_button(text: String, callback: Callable, primary: bool) -> Button:
	var node := UIkit.button(text,callback,primary)
	node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if primary:
		node.add_theme_stylebox_override("disabled",UIkit.control_box(Color("1a1a17"),Color("3a3628")))
		node.add_theme_color_override("font_disabled_color",UIkit.DISABLED)
	# Focus ring sits in the amber accent so keyboard position is obvious.
	var ring := UIkit.focus_ring()
	ring.border_color = UIkit.AMBER
	node.add_theme_stylebox_override("focus",ring)
	return node

func _build_corner() -> void:
	corner = HBoxContainer.new()
	corner.name = "TitleControls"
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("separation",_px(8))
	layer.add_child(corner)
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -_px(24)
	corner.offset_top = _px(20)
	language_button = UIkit.quiet("English" if FirstPlayText.chinese else "简体中文",_toggle_language)
	language_button.name = "LanguageButton"
	language_button.tooltip_text = "Language / 语言"
	motion_button = UIkit.quiet("",_toggle_motion)
	motion_button.name = "MotionButton"
	_update_motion_text()
	for node in [language_button,motion_button]:
		node.add_theme_font_size_override("font_size",_px(17))
		node.custom_minimum_size.y = _px(40)
		var ring := UIkit.focus_ring()
		ring.border_color = UIkit.AMBER
		node.add_theme_stylebox_override("focus",ring)
		corner.add_child(node)

func _update_motion_text() -> void:
	if not is_instance_valid(motion_button): return
	motion_button.set_meta("reduced",UIkit.reduced_motion)
	motion_button.text = (t("Motion: reduced","动画：减少") if UIkit.reduced_motion else t("Motion: on","动画：开启"))
	motion_button.tooltip_text = t("Reduce menu and map motion","减少菜单和地图动画")

func _build_footer() -> void:
	footer = VBoxContainer.new()
	footer.name = "TitleFooter"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation",UIkit.XS)
	layer.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.offset_bottom = -_px(20)
	status_label = UIkit.meta("")
	status_label.name = "SaveStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size",_px(UIkit.SMALL))
	if show_recovery: status_label.set_meta("show_routine",true)
	footer.add_child(status_label)
	if show_recovery:
		var export := UIkit.quiet("Export pending recovery JSON",func(): export_requested.emit())
		export.name = "RecoveryExport"
		export.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		footer.add_child(export)
	status_label_changed.emit(status_label)

func _focus_later(control: Control) -> void:
	(func():
		if is_instance_valid(control) and control.is_inside_tree() and dialog == null: control.grab_focus()).call_deferred()

func _on_play() -> void:
	if starting: return
	starting = true
	play_button.disabled = true
	start_requested.emit()

func _toggle_language() -> void:
	FirstPlayText.chinese = not FirstPlayText.chinese
	_build()
	_focus_later(language_button)

func _toggle_motion() -> void:
	UIkit.reduced_motion = not UIkit.reduced_motion
	_update_motion_text()

func _on_dev() -> void:
	if DevGate.is_open(): dev_requested.emit()
	else: open_dev_dialog()

# Password dialog for instructor/demo builds. Focus stays inside it.
func open_dev_dialog() -> void:
	if is_instance_valid(dialog): return
	network.set_paused(true)
	dialog = Control.new()
	dialog.name = "DevPasswordDialog"
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dialog)
	var shade := ColorRect.new()
	shade.color = Color(0.016,0.027,0.039,0.9)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(center)
	dialog_panel = PanelContainer.new()
	dialog_panel.name = "DevPasswordPanel"
	dialog_panel.custom_minimum_size.x = minf(_px(500),get_viewport_rect().size.x-48)
	dialog_panel.add_theme_stylebox_override("panel",UIkit.box(Color("111b21"),UIkit.LINE,4,_px(28)))
	center.add_child(dialog_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",_px(12))
	dialog_panel.add_child(box)
	box.add_child(UIkit.heading(t("Developer access","开发者访问"),_px(28)))
	var note := UIkit.paragraph(t("Instructor sandbox. Runs are not research data.","教师沙盒，运行记录不计入研究数据。"),_px(18),UIkit.SECONDARY)
	box.add_child(note)
	password_field = LineEdit.new()
	password_field.name = "DevPassword"
	password_field.secret = true
	password_field.placeholder_text = t("Password","密码")
	password_field.max_length = 128
	password_field.custom_minimum_size.y = _px(52)
	password_field.context_menu_enabled = false
	password_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	var ring := UIkit.focus_ring()
	ring.border_color = UIkit.AMBER
	password_field.add_theme_stylebox_override("focus",ring)
	password_field.add_theme_font_size_override("font_size",_px(20))
	box.add_child(password_field)
	password_error = UIkit.meta("",UIkit.RED)
	password_error.name = "DevPasswordError"
	password_error.add_theme_font_size_override("font_size",_px(17))
	box.add_child(password_error)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation",_px(12))
	box.add_child(row)
	cancel_button = _menu_button(t("Cancel","取消"),close_dev_dialog,false)
	cancel_button.name = "DevCancel"
	cancel_button.custom_minimum_size = Vector2(_px(140),_px(50))
	row.add_child(cancel_button)
	unlock_button = _menu_button(t("Unlock","解锁"),submit_password,true)
	unlock_button.name = "DevUnlock"
	unlock_button.custom_minimum_size = Vector2(_px(160),_px(50))
	unlock_button.disabled = true
	row.add_child(unlock_button)
	password_field.text_changed.connect(func(value: String): unlock_button.disabled = value.is_empty())
	password_field.text_submitted.connect(func(_value: String): submit_password())
	# Contained focus cycle: field → Cancel → Unlock → field.
	var cycle: Array[Control] = [password_field,cancel_button,unlock_button]
	for i in cycle.size():
		var current := cycle[i]
		var next := cycle[(i+1)%cycle.size()]
		var previous := cycle[(i-1+cycle.size())%cycle.size()]
		current.focus_next = current.get_path_to(next)
		current.focus_previous = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous)
		if current != password_field:
			current.focus_neighbor_right = current.get_path_to(next)
			current.focus_neighbor_left = current.get_path_to(previous)
	_set_background_focus(false)
	network.protect(dialog_panel,32.0)
	password_field.grab_focus.call_deferred()

func submit_password() -> void:
	if not is_instance_valid(password_field) or password_field.text.is_empty(): return
	var candidate := password_field.text
	password_field.text = ""
	unlock_button.disabled = true
	if DevGate.try_unlock(candidate):
		close_dev_dialog()
		dev_requested.emit()
	else:
		password_error.text = t("Incorrect password.","密码不正确。")
		password_field.grab_focus()

func close_dev_dialog() -> void:
	if not is_instance_valid(dialog): return
	password_field.text = ""
	remove_child(dialog)
	dialog.queue_free()
	dialog = null
	dialog_panel = null
	password_field = null
	_set_background_focus(true)
	network.set_paused(false)
	if is_instance_valid(dev_button): _focus_later(dev_button)

# Background controls cannot be reached with Tab while the dialog is open.
func _set_background_focus(enabled: bool) -> void:
	for node in layer.find_children("*","Control",true,false):
		if node is Button or node is LineEdit:
			if enabled:
				if node.has_meta("prior_focus"):
					node.focus_mode = node.get_meta("prior_focus")
					node.remove_meta("prior_focus")
			else:
				node.set_meta("prior_focus",node.focus_mode)
				node.focus_mode = Control.FOCUS_NONE

func _process(_delta: float) -> void:
	# The motion preference can also change elsewhere (browser setting, map toggle).
	if is_instance_valid(motion_button) and motion_button.has_meta("reduced") and motion_button.get_meta("reduced") != UIkit.reduced_motion: _update_motion_text()
	if is_instance_valid(dialog) and is_instance_valid(password_field):
		var owner_control := get_viewport().gui_get_focus_owner()
		if owner_control == null or not dialog.is_ancestor_of(owner_control): password_field.grab_focus()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_instance_valid(dialog):
			close_dev_dialog()
			get_viewport().set_input_as_handled()

func set_overlay(control: Control) -> void:
	# An owner modal (e.g. an error message) pauses and protects like the dialog.
	if is_instance_valid(control):
		network.set_paused(true)
		network.protect(control,32.0)
	else:
		network.set_paused(is_instance_valid(dialog))
