extends Button

# A real Button retains keyboard activation, focus, disabling and one pressed
# signal. The polygon is also the hit region, including the entire arrow head.
func _ready() -> void:
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_disabled_color","font_focus_color"]:
		add_theme_color_override(state,Color.TRANSPARENT)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func shape(inset: float = 0) -> PackedVector2Array:
	var w := size.x-inset
	var h := size.y-inset
	return PackedVector2Array([Vector2(inset+4,inset+12),Vector2(w-48,inset+12),Vector2(w-48,inset+2),Vector2(w-40,inset+2),Vector2(w,h/2-4),Vector2(w,h/2+4),Vector2(w-40,h-2),Vector2(w-48,h-2),Vector2(w-48,h-12),Vector2(inset+4,h-12),Vector2(inset,h-16),Vector2(inset,inset+16)])

func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point,shape())

func _draw() -> void:
	var edge := Color("716748") if disabled else Color("ac945d")
	var wood := Color("242c28") if disabled else (Color("17201d") if is_pressed() else (Color("4a4430") if is_hovered() else Color("343627")))
	draw_colored_polygon(shape(),edge)
	draw_colored_polygon(shape(3),wood)
	var shift := 2.0 if is_pressed() else 0.0
	for y in [21,28,49,56]:
		draw_line(Vector2(15,y+shift),Vector2(size.x-64,y+shift),Color("51503a") if not disabled else Color("313a30"),1)
	for x in [12,size.x-58]:
		draw_rect(Rect2(x,18+shift,3,3),edge)
		draw_rect(Rect2(x,size.y-23+shift,3,3),edge)
	var font := UIkit.STRONG_FONT
	var extent := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,UIkit.BUTTON)
	draw_string(font,Vector2((size.x-36-extent.x)/2,(size.y+font.get_ascent(UIkit.BUTTON)-font.get_descent(UIkit.BUTTON))/2+shift),text,HORIZONTAL_ALIGNMENT_LEFT,-1,UIkit.BUTTON,UIkit.DISABLED if disabled else UIkit.TEXT)
	if has_focus():
		var outline := shape(1)
		outline.append(outline[0])
		draw_polyline(outline,Color("eff8e0"),2)
