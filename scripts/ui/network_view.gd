class_name NetworkView
extends Control

signal shelter_selected(id: String)
signal edge_selected(id: String)
signal view_changed
signal background_selected

const CITY := preload("res://assets/maps/riverside.png")
# Artwork registration is presentation-only; simulation coordinates and route costs stay intact.
const BUILDINGS := {
	"A": Rect2(62,140,115,111), "B": Rect2(250,70,94,63),
	"C": Rect2(490,190,56,61), "D": Rect2(153,423,120,112),
	"E": Rect2(424,320,105,103), "F": Rect2(711,441,61,70),
	"G": Rect2(793,253,100,77), "H": Rect2(867,485,123,109)
}
const ROADS := {
	"A-B": [Vector2(120,196),Vector2(65,131),Vector2(149,128),Vector2(192,94),Vector2(240,86),Vector2(297,102)],
	"B-C": [Vector2(297,102),Vector2(355,175),Vector2(447,153),Vector2(518,220)],
	"C-E": [Vector2(518,220),Vector2(498,295),Vector2(548,381),Vector2(477,371)],
	"E-D": [Vector2(477,371),Vector2(401,401),Vector2(266,485),Vector2(213,479)],
	"D-A": [Vector2(213,479),Vector2(122,439),Vector2(119,308),Vector2(46,234),Vector2(120,196)],
	"B-E": [Vector2(297,102),Vector2(355,175),Vector2(396,312),Vector2(401,401),Vector2(477,371)],
	"E-F": [Vector2(477,371),Vector2(548,398),Vector2(655,420),Vector2(751,450),Vector2(742,476)],
	"F-G": [Vector2(742,476),Vector2(751,450),Vector2(771,364),Vector2(793,341),Vector2(843,292)],
	"G-H": [Vector2(843,292),Vector2(904,296),Vector2(933,388),Vector2(952,484),Vector2(929,540)]
}

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
var press_position := Vector2.ZERO
var camera_tween: Tween
var focus_id := ""
var camera_center := Vector2(500,350)
var animation_progress := 0.0
var animation_kind := ""
var animation_paths: Array = []
var flash_nodes: Array = []
var closing_edge := ""

func _ready() -> void:
	custom_minimum_size = Vector2(500,360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(func(): _update_camera(); queue_redraw())
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
	# Frame the playable district; only outer scenery is cropped on wide screens.
	return minf((size.x-80.0)/float(scenario.world_size[0]),(size.y-40.0)/580.0) * zoom

func world_center() -> Vector2:
	return Vector2(scenario.world_size[0],scenario.world_size[1])*0.5

func to_screen(point: Vector2) -> Vector2:
	return (point-camera_center)*map_scale()+size*0.5

func to_world(point: Vector2) -> Vector2:
	return (point-size*0.5)/map_scale()+camera_center

func focus_building(id: String, animated: bool = true) -> void:
	if not BUILDINGS.has(id): return
	focus_id = id
	_move_camera(BUILDINGS[id].get_center(),2.6,animated)

func center_map(animated: bool = true) -> void:
	focus_id = ""
	_move_camera(world_center(),1.0,animated)

func _move_camera(target: Vector2, scale_target: float, animated: bool) -> void:
	if camera_tween: camera_tween.kill()
	if animated:
		camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		camera_tween.tween_property(self,"camera_center",target,0.55)
		camera_tween.tween_property(self,"zoom",scale_target,0.55)
		camera_tween.tween_method(func(_value: float): _update_camera(),0.0,1.0,0.55)
	else:
		camera_center = target
		zoom = scale_target
		_update_camera()

func _update_camera() -> void:
	pan = (world_center()-camera_center)*map_scale() if scenario != null else Vector2.ZERO
	view_changed.emit()
	queue_redraw()

func visual_road(id: String) -> PackedVector2Array:
	return PackedVector2Array(ROADS[id]) if ROADS.has(id) else scenario.road_points(id)

func building_rect(id: String) -> Rect2:
	var rect: Rect2 = BUILDINGS[id]
	return Rect2(to_screen(rect.position),rect.size*map_scale())

func _refresh_geometry() -> void:
	positions.clear()
	road_geometry.clear()
	for id in scenario.node_positions:
		positions[id] = to_screen(BUILDINGS[id].get_center())
	for id in state.edges:
		var points := PackedVector2Array()
		for point in visual_road(id): points.append(to_screen(point))
		road_geometry[id] = points
	radius = clampf(32*map_scale(),28,36)

func _draw() -> void:
	if scenario == null or state == null: return
	_refresh_geometry()
	draw_rect(Rect2(Vector2.ZERO,size),UIkit.MAP)
	_draw_city()
	for edge: EdgeState in state.edges.values(): _draw_road(edge)
	for id in positions: _draw_shelter(id)
	_draw_animation()
	# Fixed survey registration marks, independent of simulation state.
	for x in range(24,int(size.x)-20,80):
		draw_line(Vector2(x,8),Vector2(x,13),UIkit.LINE,1)
		draw_line(Vector2(x,size.y-8),Vector2(x,size.y-13),UIkit.LINE,1)
	draw_line(Vector2(size.x-28,40),Vector2(size.x-28,74),UIkit.MUTED,1.5,true)
	draw_line(Vector2(size.x-34,49),Vector2(size.x-28,40),UIkit.MUTED,1.5,true)
	draw_line(Vector2(size.x-22,49),Vector2(size.x-28,40),UIkit.MUTED,1.5,true)
	_text(Vector2(size.x-28,31),"N",UIkit.CAPTION,UIkit.MUTED)

func _draw_city() -> void:
	var rect := Rect2(to_screen(Vector2.ZERO),Vector2(1000,700)*map_scale())
	draw_texture_rect(CITY,rect,false,Color(0.42,0.54,0.57,1.0))

func _draw_road(edge: EdgeState) -> void:
	var points: PackedVector2Array = road_geometry[edge.id]
	var selected := edge.id == selected_edge or edge.id == hover_target
	var closed := edge.isolated
	var no_supply: bool = state.shelters[edge.from].is_overrun or state.shelters[edge.to].is_overrun or not (reachable.has(edge.from) and reachable.has(edge.to))
	if selected: draw_polyline(points,Color(UIkit.AMBER,0.25),12,true)
	for index in points.size()-1:
		draw_dashed_line(points[index],points[index+1],UIkit.RED if closed else (UIkit.AMBER if selected else Color(UIkit.TEAL,0.55)),2,7,true)
	for path: Array in supply_paths:
		for index in maxi(0,path.size()-1):
			if edge.other_endpoint(path[index]) == path[index+1]: draw_polyline(points,UIkit.AMBER,3,true)
	if closed or edge.id == preview_edge or edge.id == closing_edge:
		var center := _point_on_path(points,0.5)
		var direction := (_point_on_path(points,0.52)-_point_on_path(points,0.48)).angle()
		var drop := 10.0*(1.0-animation_progress) if edge.id == closing_edge else 0.0
		draw_set_transform(center-Vector2(0,drop),direction)
		draw_rect(Rect2(-17,-13,34,26),UIkit.MAP)
		draw_line(Vector2(-13,-14),Vector2(-13,14),UIkit.RED if closed else UIkit.AMBER,5,true)
		draw_line(Vector2(13,-14),Vector2(13,14),UIkit.RED if closed else UIkit.AMBER,5,true)
		for y in [-9,0,9]: draw_line(Vector2(-9,y+3),Vector2(9,y-3),UIkit.RED if closed else UIkit.AMBER,4,true)
		draw_set_transform(Vector2.ZERO)
		_stamp(center+Vector2(0,-24),"CLOSED" if closed else ("CLOSING" if edge.id == closing_edge else "PREVIEW"),UIkit.RED if closed else UIkit.AMBER)
	if dev_mode:
		_text(_point_on_path(points,0.5)+Vector2(0,27),edge.id,UIkit.CAPTION,UIkit.TEXT)

func _draw_shelter(id: String) -> void:
	var shelter: ShelterState = state.shelters[id]
	var rect := building_rect(id)
	var selected := selected_shelter == id or hover_target == id
	var ink := UIkit.RED if shelter.is_overrun else UIkit.ACCENT
	if selected: draw_rect(rect.grow(5),Color(ink,0.12))
	draw_rect(rect,Color(ink,0.65),false,1)
	for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		var direction: Vector2 = (rect.get_center()-corner).sign()
		draw_line(corner,corner+Vector2(direction.x*14,0),ink,3,true)
		draw_line(corner,corner+Vector2(0,direction.y*14),ink,3,true)
	var title := id+" / "+shelter.display_name
	var font := UIkit.MONO
	var label_width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+12
	var at := rect.position-Vector2(0,24)
	draw_rect(Rect2(at,Vector2(label_width,24)),UIkit.PANEL)
	draw_line(at,at+Vector2(label_width,0),ink,1)
	draw_string(font,at+Vector2(6,17),title,HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
	var tags: Array[String] = []
	if shelter.is_overrun:
		_draw_overrun_mark(rect.get_center(),minf(rect.size.x,rect.size.y)*0.35)
		tags.append("OVERRUN")
	elif shelter.monitor_known_pressure >= 0: tags.append("M:%d" % shelter.monitor_known_pressure)
	else: tags.append("? UNOBSERVED")
	if state.depots.has(id): tags.append("%d SUPPLY" % state.depots[id].supply_remaining)
	if shelter.is_monitored: tags.append("MONITOR")
	if shelter.shielded_this_round:
		draw_rect(rect.grow(5),UIkit.TEAL,false,2)
		tags.append("SHIELD")
	if not reachable.has(id) and not shelter.is_overrun: tags.append("NO SUPPLY")
	_stamp(Vector2(rect.get_center().x,rect.end.y+20)," · ".join(tags),ink,11)
	if preview_lost.has(id): draw_rect(rect.grow(8),UIkit.AMBER,false,3)
	if dev_mode: _stamp(rect.get_center(),"DEV P%d" % shelter.zombie_pressure,UIkit.RED)

func hit_test(point: Vector2) -> String:
	if scenario == null: return ""
	_refresh_geometry()
	for id in positions:
		if building_rect(id).grow(4).has_point(point): return id
	for id in road_geometry:
		var points: PackedVector2Array = road_geometry[id]
		for index in points.size()-1:
			if Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1]).distance_to(point)<10: return id
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: press_position = event.position
		elif event.position.distance_to(press_position)<8:
			var target := hit_test(event.position)
			if state.shelters.has(target): shelter_selected.emit(target)
			elif state.edges.has(target): edge_selected.emit(target)
			else: background_selected.emit()
		accept_event()
	elif event is InputEventMouseMotion:
		hover_target = hit_test(event.position)
		queue_redraw()

func world_path_for_nodes(nodes: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	if nodes.size()==1:
		points.append(BUILDINGS[nodes[0]].get_center())
	for index in maxi(0,nodes.size()-1):
		var edge_id := NetworkManager.new(state).road_between(nodes[index],nodes[index+1])
		var segment := visual_road(edge_id)
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
	# Animation owns its working list; never clear the session's round summary.
	flash_nodes = newly.duplicate()
	await _animate("reveal",0.65)
	flash_nodes.clear()

func play_closure(edge_id: String) -> void:
	closing_edge = edge_id
	await _animate("closure",0.22)
	closing_edge = ""

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
			var next_point := to_screen(_point_on_path(path,minf(1.0,animation_progress+0.02)))
			var route := PackedVector2Array()
			for point in path: route.append(to_screen(point))
			if route.size() > 1: draw_polyline(route,Color(0.65,0.40,0.21,0.5),2,true)
			draw_set_transform(at,(next_point-at).angle())
			draw_rect(Rect2(-13,-8,26,16),UIkit.TEXT)
			draw_rect(Rect2(4,-6,6,12),UIkit.LINE)
			draw_rect(Rect2(-11,-5,10,10),UIkit.PANEL)
			draw_line(Vector2(-6,-5),Vector2(-6,5),UIkit.AMBER,2)
			for wheel in [Vector2(-8,-9),Vector2(-8,9),Vector2(8,-9),Vector2(8,9)]: draw_rect(Rect2(wheel-Vector2(3,2),Vector2(6,4)),UIkit.TEXT)
			draw_set_transform(Vector2.ZERO)
	elif animation_kind == "outbreak":
		for path: PackedVector2Array in animation_paths:
			var source := to_screen(path[0])
			_brackets(source,radius+10,UIkit.RED,2)
			var at := to_screen(_point_on_path(path,animation_progress))
			var ahead := to_screen(_point_on_path(path,minf(1,animation_progress+0.03)))
			if animation_progress < 0.98:
				draw_set_transform(at,(ahead-at).angle())
				draw_polyline(PackedVector2Array([Vector2(-8,-5),Vector2(0,0),Vector2(-8,5)]),UIkit.RED,3,true)
				draw_set_transform(Vector2.ZERO)
			# Only react to the public installed shield, never to a hidden calculation.
			for id in positions:
				if state.shelters[id].shielded_this_round and positions[id].distance_to(to_screen(path[path.size()-1])) < 2 and animation_progress > 0.7:
					_stamp(positions[id]+Vector2(0,-radius-34),"BLOCKED",UIkit.TEAL)
	elif animation_kind == "reveal":
		for id in flash_nodes:
			var at: Vector2 = positions[id]
			_draw_overrun_mark(at,radius+7,animation_progress)

func _draw_overrun_mark(at: Vector2, extent: float, progress: float = 1.0) -> void:
	var end := lerpf(-extent,extent,progress)
	_draw_pointed_slash(at-Vector2(extent,extent),at+Vector2(end,end))
	_draw_pointed_slash(at+Vector2(-extent,extent),at+Vector2(end,-end))

func _draw_pointed_slash(start: Vector2, end: Vector2) -> void:
	# Filled blades keep the loss marker bold, with sharp tips instead of flat caps.
	var length := start.distance_to(end)
	if length < 1.0: return
	var direction := (end-start)/length
	var side := direction.orthogonal()*minf(4.0,length*0.25)
	var tip := direction*minf(9.0,length*0.35)
	draw_colored_polygon(PackedVector2Array([start,start+tip+side,end-tip+side,end,end-tip-side,start+tip-side]),UIkit.RED)

func _text(at: Vector2, value: String, font_size: int, color: Color) -> void:
	var font := UIkit.face(value,font_size,true)
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,at-Vector2(width/2,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _stamp(at: Vector2, value: String, color: Color, font_size: int = UIkit.CAPTION) -> void:
	if value in ["OVERRUN","CLOSED","SHIELD","BLOCKED"]: font_size = UIkit.BODY
	var width := UIkit.face(value,font_size,true).get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_rect(Rect2(at-Vector2(width/2+4,font_size+1),Vector2(width+8,font_size+6)),UIkit.MAP)
	_text(at,value,font_size,color)

func _brackets(at: Vector2, extent: float, color: Color, weight: float) -> void:
	for x in [-1,1]:
		for y in [-1,1]:
			var corner := at+Vector2(x,y)*extent
			draw_line(corner,corner-Vector2(x*9,0),color,weight,true)
			draw_line(corner,corner-Vector2(0,y*9),color,weight,true)
