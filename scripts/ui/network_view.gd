class_name NetworkView
extends Control

signal shelter_selected(id: String)
signal edge_selected(id: String)

var scenario: ScenarioData
var state: GameState
var dev_mode := false
var reveal_truth := false
var selected_shelter := ""
var selected_edge := ""
var hover_target := ""
var supply_path: Array[String] = []
var preview_edge := ""
var preview_lost: Array[String] = []
var reachable: Array[String] = []
var positions: Dictionary = {}
var radius := 31.0

func _ready() -> void:
	custom_minimum_size = Vector2(470, 340)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hover_target = ""; queue_redraw())

func configure(data: ScenarioData, current_state: GameState, debug: bool = false) -> void:
	scenario = data
	state = current_state
	dev_mode = debug
	reachable = SupplyManager.new(state).stocked_reachability()
	queue_redraw()

func _draw() -> void:
	if scenario == null or state == null: return
	positions.clear()
	var bounds := Rect2(Vector2(10, 28), size - Vector2(20, 65))
	radius = clampf(size.x * 0.045, 24, 34)
	for id in scenario.node_positions:
		var point: Array = scenario.node_positions[id]
		positions[id] = bounds.position + Vector2(point[0], point[1]) * bounds.size
	# Quiet coordinate grid, entirely procedural.
	for x in range(16, int(size.x), 28):
		for y in range(16, int(size.y), 28):
			draw_circle(Vector2(x,y), 0.8, Color("1d3243"))
	for edge: EdgeState in state.edges.values(): _draw_edge(edge)
	for id in positions: _draw_shelter(id)

func _draw_edge(edge: EdgeState) -> void:
	var start: Vector2 = positions[edge.from]
	var finish: Vector2 = positions[edge.to]
	var direction := (finish-start).normalized()
	start += direction * (radius+8)
	finish -= direction * (radius+8)
	var selected := edge.id == selected_edge or edge.id == hover_target
	var color := UIkit.RED if edge.isolated else (UIkit.ACCENT if selected else Color("527089"))
	var is_path := false
	for index in maxi(0, supply_path.size()-1):
		if (supply_path[index] == edge.from and supply_path[index+1] == edge.to) or (supply_path[index] == edge.to and supply_path[index+1] == edge.from):
			is_path = true
	if is_path: draw_line(start, finish, Color("2e625c"), 10, true)
	if edge.isolated or edge.id == preview_edge:
		draw_dashed_line(start, finish, color, 2, 7, true)
		var center := (start+finish)/2
		draw_circle(center, 12, UIkit.BG)
		draw_line(center-Vector2(6,6),center+Vector2(6,6),UIkit.RED,3,true)
		draw_line(center-Vector2(6,-6),center+Vector2(6,-6),UIkit.RED,3,true)
	else:
		draw_line(start,finish,color,3 if selected else 2,true)
	# Arrowheads at the destination; supply direction is deliberately not encoded here.
	var normal := direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([finish,finish-direction*13+normal*6,finish-direction*13-normal*6]), color)
	if selected or dev_mode:
		var middle := (start+finish)/2 + Vector2(0,-13)
		_text(middle, "%s>%s%s" % [edge.from,edge.to," CLOSED" if edge.isolated else ""], 12, color)

func _draw_shelter(id: String) -> void:
	var shelter: ShelterState = state.shelters[id]
	var center: Vector2 = positions[id]
	var color := UIkit.RED if shelter.is_overrun else UIkit.MUTED
	if reachable.has(id) and not shelter.is_overrun:
		draw_circle(center, radius+5, Color("264639"), false, 2, true)
	if preview_lost.has(id): draw_circle(center,radius+8,UIkit.AMBER,false,3,true)
	if shelter.shielded_this_round: draw_arc(center,radius+10,0,TAU,64,UIkit.TEAL,3,true)
	if id == selected_shelter or id == hover_target: draw_circle(center,radius+3,UIkit.ACCENT,false,2,true)
	draw_circle(center,radius,Color("382731") if shelter.is_overrun else UIkit.INNER,true,-1,true)
	draw_circle(center,radius,color,false,1.5,true)
	_text(center+Vector2(0,0 if state.depots.has(id) else 7), id, 25, UIkit.TEXT)
	if shelter.is_overrun:
		_text(center+Vector2(0,radius+20),"OVERRUN",11,UIkit.RED)
	elif not _has_road_below(id):
		_text(center+Vector2(0,radius+20),shelter.display_name,11,UIkit.MUTED)
	if state.depots.has(id):
		var depot: SupplyDepot = state.depots[id]
		var badge := Rect2(center+Vector2(-23,10),Vector2(46,16))
		draw_style_box(UIkit.box(Color("293929"),UIkit.ACCENT,4,0),badge)
		_text(badge.get_center()+Vector2(0,4),"%d / %d" % [depot.supply_remaining,depot.capacity],11,UIkit.ACCENT)
	var markers := ""
	if shelter.is_monitored: markers += "M "
	if not shelter.verified_history.is_empty(): markers += "V "
	if shelter.shielded_this_round: markers += "S"
	if not markers.is_empty(): _text(center+Vector2(0,-radius-7),markers,11,UIkit.TEAL)
	if dev_mode or reveal_truth: _text(center+Vector2(radius+15,0),"P%d" % shelter.zombie_pressure,14,UIkit.AMBER)

func _has_road_below(id: String) -> bool:
	# Keep captions clear of vertical arrows for any scenario layout.
	for edge: EdgeState in state.edges.values():
		var neighbor := edge.to if edge.from==id else (edge.from if edge.to==id else "")
		if neighbor.is_empty(): continue
		var offset: Vector2=positions[neighbor]-positions[id]
		if offset.y>radius*2 and absf(offset.x)<radius*1.5: return true
	return false

func _text(at: Vector2, value: String, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,at-Vector2(width/2,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func hit_test(point: Vector2) -> String:
	for id in positions:
		if point.distance_to(positions[id]) < radius+13: return id
	for edge: EdgeState in state.edges.values():
		var nearest := Geometry2D.get_closest_point_to_segment(point,positions[edge.from],positions[edge.to])
		if nearest.distance_to(point) < 12: return edge.id
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var next := hit_test(event.position)
		if next != hover_target:
			hover_target = next
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var target := hit_test(event.position)
		if state.shelters.has(target): shelter_selected.emit(target)
		elif state.edges.has(target): edge_selected.emit(target)
		accept_event()
