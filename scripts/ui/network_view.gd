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
var closing_edge := ""

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
	# Authored cartographic underprint only; never used by the network.
	var river := PackedVector2Array()
	for point in [Vector2(570,-100),Vector2(595,160),Vector2(570,320),Vector2(630,560),Vector2(600,800),Vector2(655,800),Vector2(680,555),Vector2(620,320),Vector2(645,160),Vector2(620,-100)]:
		river.append(to_screen(point))
	draw_colored_polygon(river,Color("c5e4e7"))
	for shift in [7.0,18.0]:
		var bank := PackedVector2Array()
		for point in [Vector2(620,-100),Vector2(645,160),Vector2(620,320),Vector2(680,555),Vector2(655,800)]:
			bank.append(to_screen(point+Vector2(shift,0)))
		draw_polyline(bank,Color("9bc9cd"),1,true)
	# A sparse set of irregular municipal blocks replaces the repetitive tile field.
	for block in [Rect2(40,25,95,38),Rect2(175,30,90,26),Rect2(355,40,135,36),
			Rect2(65,125,54,35),Rect2(310,110,86,45),Rect2(450,125,58,40),
			Rect2(35,325,83,45),Rect2(265,240,80,40),Rect2(315,305,40,38),
			Rect2(390,545,103,55),Rect2(70,565,110,32),Rect2(245,595,66,44),
			Rect2(755,50,85,40),Rect2(880,85,60,80),Rect2(745,155,118,36),
			Rect2(815,350,45,70),Rect2(900,320,65,55),Rect2(700,585,110,40)]:
		var rect := Rect2(to_screen(block.position),block.size*map_scale())
		draw_rect(rect,Color("f4f7f8"))
		draw_rect(rect,Color("dfe7ea"),false,1)
		draw_line(rect.position+Vector2(3,4),Vector2(rect.end.x-4,rect.position.y+4),Color("dfe7ea"),1)
	for y in [85,205,550,650]:
		draw_dashed_line(to_screen(Vector2(20,y)),to_screen(Vector2(990,y+17)),Color("d3e1e5"),1,5,true)
	for x in [80,310,820,950]:
		draw_dashed_line(to_screen(Vector2(x,10)),to_screen(Vector2(x+12,690)),Color("e3ecef"),1,3,true)
	_text(to_screen(Vector2(215,75)),"WEST BOROUGH",UIkit.CAPTION,UIkit.INFRA)
	_text(to_screen(Vector2(805,210)),"RIVERSIDE",UIkit.CAPTION,UIkit.INFRA)
	# Sparse, deterministic registration specks; no procedural randomness.
	for index in 85:
		var point := Vector2(18+(index*137)%int(maxf(40,size.x-36)),18+(index*83)%int(maxf(40,size.y-36)))
		draw_line(point,point+Vector2(2,0),Color(0.25,0.35,0.40,0.06),1)

func _draw_road(edge: EdgeState) -> void:
	var points: PackedVector2Array = road_geometry[edge.id]
	var selected := edge.id == selected_edge or edge.id == hover_target
	var closed := edge.isolated
	var no_supply: bool = state.shelters[edge.from].is_overrun or state.shelters[edge.to].is_overrun or not (reachable.has(edge.from) and reachable.has(edge.to))
	if selected: draw_polyline(points,UIkit.AMBER,13,true)
	draw_polyline(points,UIkit.MAP,10,true)
	draw_polyline(points,UIkit.INFRA if no_supply or closed else UIkit.MUTED,6,true)
	for index in points.size()-1:
		draw_dashed_line(points[index],points[index+1],UIkit.MAP,2,3 if no_supply else 9,true)
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
	var center: Vector2 = positions[id]
	var selected := selected_shelter == id or hover_target == id
	var depot := state.depots.has(id)
	var ink := UIkit.RED if shelter.is_overrun else UIkit.TEXT
	var r := radius
	if preview_lost.has(id): _brackets(center,r+15,UIkit.AMBER,1)
	if selected: _brackets(center,r+12,UIkit.AMBER,4)
	if shelter.shielded_this_round:
		var shield := PackedVector2Array([center+Vector2(-r-6,-r-4),center+Vector2(r+6,-r-4),center+Vector2(r+6,r),center+Vector2(0,r+12),center+Vector2(-r-6,r),center+Vector2(-r-6,-r-4)])
		draw_polyline(shield,UIkit.TEAL,4,true)
		_stamp(center+Vector2(0,-r-13),"SHIELD",UIkit.TEAL)
	var polygon := PackedVector2Array()
	for offset in [Vector2(-r,-r+7),Vector2(-r+7,-r),Vector2(r-7,-r),Vector2(r,-r+7),Vector2(r,r-7),Vector2(r-7,r),Vector2(-r+7,r),Vector2(-r,r-7)]:
		polygon.append(center+offset)
	if depot:
		draw_rect(Rect2(center-Vector2(r+3,r),Vector2(2*r+6,2*r)),UIkit.PANEL)
		draw_rect(Rect2(center-Vector2(r+3,r),Vector2(2*r+6,2*r)),ink,false,3)
		draw_line(center+Vector2(-r-3,-r-4),center+Vector2(r+3,-r-4),ink,3)
	else:
		draw_colored_polygon(polygon,UIkit.INNER if shelter.is_overrun else UIkit.PANEL)
		polygon.append(polygon[0])
		draw_polyline(polygon,ink,3,true)
	if shelter.is_overrun:
		for offset in [-18,-6,6,18]:
			draw_line(center+Vector2(-r,offset+5),center+Vector2(r,offset-5),Color(0.58,0.27,0.22,0.30),1,true)
		_draw_overrun_mark(center,r+7)
		_stamp(center+Vector2(0,-r-12),id,ink,UIkit.SECTION)
	else:
		_text(center+Vector2(0,4),id,UIkit.DISPLAY,ink)
	if not shelter.is_overrun:
		_text(center+Vector2(0,21),"?" if shelter.monitor_known_pressure < 0 else "M:%d" % shelter.monitor_known_pressure,UIkit.BODY,UIkit.MUTED)
	if shelter.is_monitored:
		var at := center+Vector2(-r-12,-r+5)
		draw_line(at+Vector2(0,20),at,UIkit.TEAL,4,true)
		draw_line(at-Vector2(8,0),at+Vector2(8,0),UIkit.TEAL,4,true)
		draw_circle(at-Vector2(0,6),3,UIkit.TEAL,true,-1,true)
	var label_y := r+22
	if depot:
		var strip := Rect2(center+Vector2(-r-3,r+2),Vector2(2*r+6,28))
		draw_rect(strip,UIkit.TEXT)
		_text(center+Vector2(0,r+24),"%d / 3" % state.depots[id].supply_remaining,UIkit.SECTION,UIkit.PANEL)
		label_y += 30
	if zoom >= 0.7 or selected:
		_stamp(center+Vector2(0,label_y),"OVERRUN" if shelter.is_overrun else shelter.display_name,ink)
		if not shelter.verified_history.is_empty():
			var record: Dictionary = shelter.verified_history.back()
			_stamp(center+Vector2(0,label_y+20),"OBS R%d · P%d" % [record.round,record.pressure],UIkit.MUTED)
	if not reachable.has(id) and not shelter.is_overrun:
		draw_line(center+Vector2(r-6,-r+4),center+Vector2(r+4,-r-6),UIkit.MUTED,4,true)
	if dev_mode: _stamp(center+Vector2(r+24,0),"P%d" % shelter.zombie_pressure,UIkit.RED)

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
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,at-Vector2(width/2,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _stamp(at: Vector2, value: String, color: Color, font_size: int = UIkit.CAPTION) -> void:
	if value in ["OVERRUN","CLOSED","SHIELD","BLOCKED"]: font_size = UIkit.BODY
	var width := ThemeDB.fallback_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_rect(Rect2(at-Vector2(width/2+4,font_size+1),Vector2(width+8,font_size+6)),UIkit.MAP)
	_text(at,value,font_size,color)

func _brackets(at: Vector2, extent: float, color: Color, weight: float) -> void:
	for x in [-1,1]:
		for y in [-1,1]:
			var corner := at+Vector2(x,y)*extent
			draw_line(corner,corner-Vector2(x*9,0),color,weight,true)
			draw_line(corner,corner-Vector2(0,y*9),color,weight,true)
