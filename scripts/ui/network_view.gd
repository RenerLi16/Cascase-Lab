class_name NetworkView
extends Control

signal shelter_selected(id: String)
signal edge_selected(id: String)
signal view_changed

var scenario: ScenarioData
var state: GameState
var dev_mode := false
var selected_shelter := ""
var selected_edge := ""
var hover_target := ""
var supply_paths: Array = []
var preview_edge := ""
var preview_lost: Array[String] = []
var reachable: Array[String] = []
var positions: Dictionary = {}
var road_geometry: Dictionary = {}
var zoom := 1.0
var pan := Vector2.ZERO
var radius := 25.0
var dragging := false
var press_position := Vector2.ZERO
var press_pan := Vector2.ZERO
var drag_button := 0
var animation_progress := 0.0
var animation_kind := ""
var animation_paths: Array = []
var flash_nodes: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(500,360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hover_target = ""; queue_redraw())

func configure(data: ScenarioData, current_state: GameState, debug: bool = false) -> void:
	scenario = data
	state = current_state
	dev_mode = debug
	reachable = SupplyManager.new(state).stocked_reachability()
	queue_redraw()

func _process(_delta: float) -> void:
	if animation_kind != "": queue_redraw()

func map_scale() -> float:
	if scenario == null: return 1.0
	return minf((size.x-80.0)/float(scenario.world_size[0]),(size.y-70.0)/float(scenario.world_size[1])) * zoom

func world_center() -> Vector2:
	return Vector2(scenario.world_size[0],scenario.world_size[1])*0.5

func to_screen(point: Vector2) -> Vector2:
	return (point-world_center())*map_scale()+size*0.5+pan

func to_world(point: Vector2) -> Vector2:
	return (point-size*0.5-pan)/map_scale()+world_center()

func zoom_at(factor: float, anchor: Vector2) -> void:
	var world_anchor := to_world(anchor)
	zoom = clampf(zoom*factor,0.5,2.0)
	pan = anchor-size*0.5-(world_anchor-world_center())*map_scale()
	_clamp_pan()
	view_changed.emit()
	queue_redraw()

func center_map() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	view_changed.emit()
	queue_redraw()

func _clamp_pan() -> void:
	pan.x = clampf(pan.x,-size.x*0.8,size.x*0.8)
	pan.y = clampf(pan.y,-size.y*0.8,size.y*0.8)

func _refresh_geometry() -> void:
	positions.clear()
	road_geometry.clear()
	for id in scenario.node_positions:
		var point: Array = scenario.node_positions[id]
		positions[id] = to_screen(Vector2(point[0],point[1]))
	for id in state.edges:
		var points := PackedVector2Array()
		for point in scenario.road_points(id): points.append(to_screen(point))
		road_geometry[id] = points
	radius = clampf(27*map_scale(),20,36)

func _draw() -> void:
	if scenario == null or state == null: return
	_refresh_geometry()
	draw_rect(Rect2(Vector2.ZERO,size),Color("e7e3d7"))
	_draw_city()
	for edge: EdgeState in state.edges.values(): _draw_road(edge)
	for id in positions: _draw_shelter(id)
	_draw_animation()
	_text(Vector2(105,size.y-24),scenario.scenario_title.to_upper(),11,Color("787d6b"))
	# Compass and scale belong to the planning map, not the gameplay graph.
	draw_line(Vector2(size.x-35,48),Vector2(size.x-35,84),UIkit.MUTED,1.5,true)
	draw_line(Vector2(size.x-42,57),Vector2(size.x-35,48),UIkit.MUTED,1.5,true)
	draw_line(Vector2(size.x-28,57),Vector2(size.x-35,48),UIkit.MUTED,1.5,true)
	_text(Vector2(size.x-35,38),"N",12,UIkit.MUTED)

func _draw_city() -> void:
	# Decorative geometry is fixed and never participates in simulation or pathfinding.
	var river := PackedVector2Array()
	for point in [Vector2(570,-100),Vector2(595,160),Vector2(570,320),Vector2(630,560),Vector2(600,800),Vector2(655,800),Vector2(680,555),Vector2(620,320),Vector2(645,160),Vector2(620,-100)]:
		river.append(to_screen(point))
	draw_colored_polygon(river,Color("bdcbc2"))
	for x in range(30,1000,65):
		for y in range(20,700,60):
			var offset := Vector2((y/60 % 3)*9,(x/65 % 3)*8)
			var world := Vector2(x,y)+offset
			if world.x>550 and world.x<690: continue
			var near_node := false
			for node_position: Array in scenario.node_positions.values():
				if world.distance_to(Vector2(node_position[0],node_position[1]))<50: near_node=true
			if near_node: continue
			var rectangle := Rect2(to_screen(world),Vector2(36+(y%17),25+(x%11))*map_scale())
			draw_rect(rectangle,Color("d7d4c8"))
			draw_rect(rectangle,Color("c9c9bb"),false,1)
			if (x+y)%3==0:
				draw_line(rectangle.position,rectangle.end,Color("c4c4b6"),1,true)
	for y in [85,205,550,650]:
		draw_dashed_line(to_screen(Vector2(20,y)),to_screen(Vector2(990,y+17)),Color("cccabd"),1,8,true)
	_text(to_screen(Vector2(215,65)),"WEST BOROUGH",18,Color("929880"))
	_text(to_screen(Vector2(805,180)),"RIVERSIDE",18,Color("929880"))

func _draw_road(edge: EdgeState) -> void:
	var points: PackedVector2Array = road_geometry[edge.id]
	var selected := edge.id == selected_edge or edge.id == hover_target
	var closed := edge.isolated or edge.id == preview_edge
	var color := UIkit.RED if closed else (UIkit.ACCENT if selected else Color("858978"))
	draw_polyline(points,Color("f2eee2"),13,true)
	draw_polyline(points,color,7 if selected else 5,true)
	if not closed:
		for index in points.size()-1: draw_dashed_line(points[index],points[index+1],Color("dedbca"),1,6,true)
	else:
		var center := _point_on_path(points,0.5)
		draw_style_box(UIkit.box(Color("e8decb"),UIkit.RED,2,0),Rect2(center-Vector2(17,10),Vector2(34,20)))
		for offset in [-10,0,10]: draw_line(center+Vector2(offset-3,7),center+Vector2(offset+3,-7),UIkit.RED,4,true)
	for path: Array in supply_paths:
		for index in maxi(0,path.size()-1):
			if edge.other_endpoint(path[index]) == path[index+1]: draw_polyline(points,UIkit.TEAL,3,true)
	if dev_mode:
		_text(_point_on_path(points,0.5)+Vector2(0,-13),edge.id+ (" CLOSED" if edge.isolated else ""),12,UIkit.TEXT)

func _draw_shelter(id: String) -> void:
	var shelter: ShelterState = state.shelters[id]
	var center: Vector2 = positions[id]
	var selected := selected_shelter == id or hover_target == id
	if shelter.is_overrun:
		draw_circle(center,radius+12,Color(0.66,0.25,0.20,0.16),true,-1,true)
	if reachable.has(id): draw_circle(center,radius+5,Color("7c8b68"),false,2,true)
	if preview_lost.has(id): draw_circle(center,radius+10,UIkit.AMBER,false,3,true)
	if shelter.shielded_this_round:
		var pulse := 2.0*sin(animation_progress*PI) if animation_kind == "outbreak" else 0.0
		draw_circle(center,radius+9+pulse,UIkit.TEAL,false,3,true)
	if selected: draw_circle(center,radius+7,UIkit.TEXT,false,2,true)
	draw_circle(center+Vector2(1,3),radius,Color(0.22,0.25,0.20,0.18),true,-1,true)
	draw_circle(center,radius,UIkit.RED if shelter.is_overrun else UIkit.PANEL,true,-1,true)
	draw_circle(center,radius,UIkit.RED if shelter.is_overrun else Color("6d795f"),false,1.5,true)
	_text(center+Vector2(0,0 if state.depots.has(id) else 6),id,23,UIkit.PANEL if shelter.is_overrun else UIkit.TEXT)
	if state.depots.has(id):
		_text(center+Vector2(0,17),"%d / 3" % state.depots[id].supply_remaining,11,UIkit.PANEL if shelter.is_overrun else UIkit.ACCENT)
	if zoom >= 0.7 or selected:
		var title := "OVERRUN" if shelter.is_overrun else shelter.display_name
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
		var at := center+Vector2(0,radius+21)
		draw_rect(Rect2(at-Vector2(width/2+4,13),Vector2(width+8,18)),Color("e7e3d7"))
		_text(at,title,13,UIkit.RED if shelter.is_overrun else UIkit.TEXT)
	var markers := ""
	if shelter.is_monitored: markers += "M "
	if not shelter.verified_history.is_empty(): markers += "V "
	if shelter.shielded_this_round: markers += "S"
	if markers != "":
		var at := center+Vector2(0,-radius-12)
		draw_rect(Rect2(at-Vector2(21,12),Vector2(42,17)),UIkit.PANEL)
		_text(at,markers,12,UIkit.TEAL)
	if dev_mode: _text(center+Vector2(radius+19,0),"P%d" % shelter.zombie_pressure,16,UIkit.RED)

func hit_test(point: Vector2) -> String:
	_refresh_geometry()
	for id in positions:
		if point.distance_to(positions[id])<radius+8: return id
	for id in road_geometry:
		var points: PackedVector2Array=road_geometry[id]
		for index in points.size()-1:
			if Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1]).distance_to(point)<10: return id
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.15,event.position)
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				drag_button = event.button_index
				press_position = event.position
				press_pan = pan
				dragging = false
			elif drag_button != 0:
				if not dragging and drag_button == MOUSE_BUTTON_LEFT:
					var target := hit_test(event.position)
					if state.shelters.has(target): shelter_selected.emit(target)
					elif state.edges.has(target): edge_selected.emit(target)
				drag_button = 0
				dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		if drag_button != 0:
			if event.position.distance_to(press_position)>5: dragging = true
			if dragging:
				pan = press_pan+event.position-press_position
				_clamp_pan()
				view_changed.emit()
		else: hover_target = hit_test(event.position)
		queue_redraw()

func world_path_for_nodes(nodes: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	if nodes.size()==1:
		var point: Array=scenario.node_positions[nodes[0]]
		points.append(Vector2(point[0],point[1]))
	for index in maxi(0,nodes.size()-1):
		var edge_id := NetworkManager.new(state).road_between(nodes[index],nodes[index+1])
		var segment := scenario.road_points(edge_id)
		if state.edges[edge_id].from != nodes[index]: segment.reverse()
		if not points.is_empty(): segment.remove_at(0)
		points.append_array(segment)
	return points

func _point_on_path(points: PackedVector2Array, progress: float) -> Vector2:
	if points.is_empty(): return Vector2.ZERO
	var length := 0.0
	for index in points.size()-1: length += points[index].distance_to(points[index+1])
	var distance := progress*length
	for index in points.size()-1:
		var segment := points[index].distance_to(points[index+1])
		if distance <= segment: return points[index].lerp(points[index+1],distance/maxf(segment,0.001))
		distance -= segment
	return points[points.size()-1]

func play_deliveries(deliveries: Array) -> void:
	animation_paths.clear()
	var longest := 0.0
	for delivery in deliveries:
		var path := world_path_for_nodes(delivery.path)
		animation_paths.append(path)
		var length := 0.0
		for index in path.size()-1: length += path[index].distance_to(path[index+1])
		longest = maxf(longest,length)
	await _animate("delivery",clampf(0.5+longest/900.0,0.5,1.5))

func play_outbreak(movements: Array) -> void:
	animation_paths.clear()
	for movement in movements:
		animation_paths.append(world_path_for_nodes([movement.from,movement.to]))
	await _animate("outbreak",0.85)

func play_reveal(newly: Array) -> void:
	flash_nodes = newly
	await _animate("reveal",0.65)
	flash_nodes.clear()

func _animate(kind: String, seconds: float) -> void:
	animation_kind = kind
	animation_progress = 0.0
	var tween := create_tween()
	tween.tween_property(self,"animation_progress",1.0,seconds)
	await tween.finished
	animation_kind = ""
	queue_redraw()

func _draw_animation() -> void:
	if animation_kind == "delivery":
		for path: PackedVector2Array in animation_paths:
			var at := to_screen(_point_on_path(path,animation_progress))
			var next := to_screen(_point_on_path(path,minf(1.0,animation_progress+0.02)))
			draw_set_transform(at,(next-at).angle())
			draw_rect(Rect2(-13,-8,26,16),UIkit.ACCENT)
			draw_rect(Rect2(4,-6,6,12),Color("b8c7b1"))
			draw_rect(Rect2(-11,-5,10,10),UIkit.PANEL)
			for wheel in [Vector2(-8,-9),Vector2(-8,9),Vector2(8,-9),Vector2(8,9)]: draw_circle(wheel,3,UIkit.TEXT)
			draw_set_transform(Vector2.ZERO)
	elif animation_kind == "outbreak":
		for path: PackedVector2Array in animation_paths:
			for offset in [0.0,0.06,0.12]:
				var at := to_screen(_point_on_path(path,clampf(animation_progress-offset,0.0,1.0)))
				draw_circle(at,3,UIkit.RED,true,-1,true)
	elif animation_kind == "reveal":
		for id in flash_nodes:
			draw_circle(positions[id],radius+8+22*animation_progress,Color(0.66,0.25,0.20,1.0-animation_progress),false,3,true)

func _text(at: Vector2, value: String, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,at-Vector2(width/2,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
