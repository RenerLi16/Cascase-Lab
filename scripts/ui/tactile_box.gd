class_name TactileBox
extends StyleBox

# A flat board-game key: an opaque face resting on a thin darker base. `raise` is
# how far the face sits above the base (DEPTH = fully lifted, 0 = pressed flat).
# Content margins move with the face while their sum stays constant, so the
# control's size, position, and hit area never change during the animation.
const DEPTH := 4.0
const REST := 3.0
var face := StyleBoxFlat.new()
var base := StyleBoxFlat.new()
var raise := REST
var pad_top := 8.0
var pad_bottom := 7.0

func _init(face_color: Color = Color.WHITE, border: Color = Color.TRANSPARENT, base_color: Color = Color.GRAY, radius: int = 6) -> void:
	content_margin_left = 16
	content_margin_right = 16
	colors(face_color,border,base_color)
	face.set_corner_radius_all(radius)
	base.set_corner_radius_all(radius)
	face.anti_aliasing = true
	base.anti_aliasing = true
	set_raise(REST)

func colors(face_color: Color, border: Color, base_color: Color) -> void:
	face.bg_color = face_color
	face.border_color = border
	face.set_border_width_all(0 if border.a == 0.0 else 1)
	base.bg_color = base_color
	emit_changed()

func set_raise(value: float) -> void:
	raise = clampf(value,0.0,DEPTH)
	content_margin_top = pad_top + (DEPTH-raise)
	content_margin_bottom = pad_bottom + raise
	emit_changed()

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var body := Rect2(rect.position+Vector2(0,DEPTH),rect.size-Vector2(0,DEPTH))
	if raise > 0.05: base.draw(to_canvas_item,body)
	face.draw(to_canvas_item,Rect2(body.position-Vector2(0,raise),body.size))
