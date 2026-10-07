class_name TactileButton
extends Button

# Lifts slightly on hover, presses down while held, and settles on release.
# One tween per button is replaced (never stacked) whenever the target changes;
# with reduced motion the face moves immediately. Size and hit area are fixed.
enum Kind { NORMAL, PRIMARY, CAUTION }
var kind := Kind.NORMAL
var box := TactileBox.new()
var _tween: Tween
var _target := -1.0
var _was_disabled := false

func _init(style: Kind = Kind.NORMAL) -> void:
	kind = style
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:
		add_theme_stylebox_override(state,box)
	_apply_colors()
	box.set_raise(TactileBox.REST)
	_target = TactileBox.REST

func _apply_colors() -> void:
	_was_disabled = disabled
	var ink := UIkit.TEXT
	if disabled:
		box.colors(UIkit.DISABLED_FACE,UIkit.LINE,UIkit.LINE)
		ink = UIkit.DISABLED
	elif kind == Kind.PRIMARY:
		box.colors(UIkit.ACTION,Color.TRANSPARENT,UIkit.ACTION_EDGE)
		ink = UIkit.ON_ACTION
	elif kind == Kind.CAUTION:
		box.colors(UIkit.PANEL,UIkit.DANGER,UIkit.DANGER_EDGE)
		ink = UIkit.DANGER
	else:
		box.colors(UIkit.PANEL,UIkit.LINE_STRONG,UIkit.EDGE)
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		add_theme_color_override(state,ink)
	add_theme_color_override("font_disabled_color",UIkit.DISABLED)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW: _sync.call_deferred()

func _sync() -> void:
	if not is_inside_tree(): return
	if disabled != _was_disabled: _apply_colors()
	var goal := TactileBox.REST
	match get_draw_mode():
		DRAW_HOVER: goal = TactileBox.DEPTH
		DRAW_PRESSED, DRAW_HOVER_PRESSED: goal = 1.0
		DRAW_DISABLED: goal = 0.0
	if is_equal_approx(goal,_target): return
	var seconds := 0.07 if goal < _target else (0.12 if goal > TactileBox.REST else 0.14)
	_target = goal
	if _tween: _tween.kill()
	seconds = UIkit.motion(seconds)
	if seconds <= 0.0:
		box.set_raise(goal)
		return
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(box.set_raise,box.raise,goal,seconds)
