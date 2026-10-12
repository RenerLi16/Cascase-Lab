class_name TowerActionButton
extends Button

# The fixed console rim never moves. Only the inset face and its contents travel.
var kind := "VERIFY"
var selected := false
var reason := ""
var face: Control
var hovering := false
var travel := 0.0
var flash := 0.0
var glint := 0.0
var animation: Tween

func setup(action: String, unavailable: String = "", choosing: bool = false) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	kind = action
	reason = unavailable
	selected = choosing
	disabled = not reason.is_empty()
	text = PresentationText.action_name(kind)
	tooltip_text = PresentationText.unavailable_text(reason) if disabled else PresentationText.action_description(kind)
	custom_minimum_size = Vector2(320,106)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled or selected else Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","disabled","focus","hover_pressed"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for state in ["font_color","font_hover_color","font_pressed_color","font_disabled_color","font_focus_color","font_hover_pressed_color"]:
		add_theme_color_override(state,Color.TRANSPARENT)
	add_theme_font_size_override("font_size",1)
	face = Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)
	var title := UIkit.strong(text,20,UIkit.TEXT)
	title.position = Vector2(103,12)
	face.add_child(title)
	var cost := UIkit.strong(FirstPlayText.choose("1 supply","1 份物资"),16,Color("c6b58b"))
	cost.name = "Cost"
	face.add_child(cost)
	var description := UIkit.paragraph(PresentationText.unavailable_text(reason) if disabled else FirstPlayText.choose("Selected · choose supply source.","已选择 · 请选择补给仓库。") if selected else PresentationText.action_description(kind),17,Color("dfc79a") if disabled or selected else Color("c4c9ba"))
	description.name = "Description"
	description.position = Vector2(103,39)
	face.add_child(description)
	for child in face.get_children(): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	mouse_entered.connect(func(): hovering = true; _ready_light())
	mouse_exited.connect(func(): hovering = false; queue_redraw())
	focus_entered.connect(_ready_light)
	focus_exited.connect(queue_redraw)
	button_down.connect(func(): travel = 3; flash = 1; _layout(); queue_redraw())
	button_up.connect(func(): travel = 0; flash = 0; _layout(); queue_redraw())
	_layout.call_deferred()

func _layout() -> void:
	if face == null: return
	face.position.y = travel
	face.size = size
	var cost: Label = face.get_node("Cost")
	cost.position = Vector2(size.x-cost.get_minimum_size().x-19,15)
	for key in ["Description"]:
		var label: Label = face.get_node(key)
		label.size.x = maxf(100,size.x-119)

func _ready_light() -> void:
	queue_redraw()
	if disabled or selected or UIkit.reduced_motion: return
	if animation: animation.kill()
	glint = 0
	animation = create_tween()
	animation.tween_method(func(value: float): glint = value; queue_redraw(),0.0,1.0,0.24)
	animation.tween_callback(func(): glint = 0; queue_redraw())

func _draw() -> void:
	var ready := (hovering or has_focus()) and not disabled and not selected
	var rim := Color("b4ab80") if ready else Color("756b50")
	# Iron housing, stepped brass bevel, dark seam and worn corner fasteners.
	draw_rect(Rect2(Vector2(0,2),size-Vector2(0,2)),Color("080d0e"))
	draw_rect(Rect2(Vector2.ZERO,size-Vector2(0,4)),Color("363d37"))
	draw_rect(Rect2(Vector2(2,2),size-Vector2(4,8)),rim,false,2)
	draw_line(Vector2(4,5),Vector2(size.x-5,5),Color("aaa07b"),2)
	draw_line(Vector2(4,size.y-7),Vector2(size.x-5,size.y-7),Color("272c26"),3)
	for x in [7.0,size.x-10]:
		for y in [9.0,size.y-15]:
			draw_rect(Rect2(x-1,y-1,6,6),Color("584835"))
			draw_rect(Rect2(x,y,4,4),Color("9a9272"))
			draw_rect(Rect2(x,y+2,3,1),Color("313630"))
	var inset := Rect2(13,10,size.x-26,size.y-24)
	draw_rect(inset.grow(2),Color("070d0e"))
	draw_rect(Rect2(inset.position+Vector2(0,5),inset.size),Color("020505"))
	inset.position.y += travel
	draw_rect(inset,Color("111b1d") if not disabled else Color("1b2221"))
	draw_rect(inset,Color("8fae9c") if ready else Color("515c50"),false,1)
	draw_line(inset.position+Vector2(1,1),Vector2(inset.end.x-1,inset.position.y+1),rim,1)
	draw_line(Vector2(97,inset.position.y+9),Vector2(97,inset.end.y-9),Color("343e37"),1)
	var lit := ready or flash > 0 or selected
	draw_texture_rect(ActionIcon.texture(kind,lit),Rect2(25,21+travel,60,60),false,Color(1.18,1.18,1.18) if flash > 0 else Color.WHITE)
	# A single highlight sweep per entry/focus, never a continuous pulse.
	if glint > 0 and not UIkit.reduced_motion and ready:
		var gleam := Color(0.95,0.92,0.75,sin(glint*PI)*0.8)
		match kind:
			"VERIFY": draw_rect(Rect2(39+floorf(glint*8),35+travel,2,10),gleam)
			"MONITOR": draw_rect(Rect2(53,43+travel,5,10),gleam)
			"SHIELD":
				var y := floorf(glint*36)
				draw_rect(Rect2(73-maxf(0,y-20),33+y+travel,3,5),gleam)
	# Indicator has a word and a shape: selected never means installed.
	draw_rect(Rect2(39,85+travel,32,5),Color("b7a471") if selected else Color("35443d"))
	if disabled:
		draw_rect(Rect2(45,83,18,10),Color("8c8164"),false,2)
		draw_rect(Rect2(50,87,8,2),UIkit.TEXT)
	if has_focus(): draw_rect(Rect2(4,4,size.x-8,size.y-12),UIkit.TEXT,false,2)
