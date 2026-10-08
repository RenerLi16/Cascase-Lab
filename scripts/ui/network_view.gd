class_name NetworkView
extends Control

signal shelter_selected(id: String)
signal edge_selected(id: String)
signal view_changed
signal background_selected

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
var title_rects: Dictionary = {}
var status_positions: Dictionary = {}
var annotation_key := ""
var road_geometry: Dictionary = {}
var tower_rects: Dictionary = {}
var terrain_texture: Texture2D
var ambient_frame := 0
var ambient_elapsed := 0.0
var dragging := false
var drag_moved := false
var inspection_inset := 0.0
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
var delivery_targets: Array[String] = []
# QA can inspect the city and deterministic streets without operational annotations.
var show_annotations := true
# Map name plate geometry: plate height, status baseline, and total block height.
const NAME_PLATE := 28
const STATUS_BASELINE := 47
const NAME_BLOCK := 52

func _ready() -> void:
	custom_minimum_size = Vector2(500,360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	resized.connect(func(): _update_camera(); queue_redraw())
	mouse_exited.connect(func(): hover_target = ""; queue_redraw())

func has_city_art() -> bool:
	return CityMapProfiles.has_profile(scenario.scenario_id)

func world_building(id: String) -> Rect2:
	if CityMapProfiles.has_profile(scenario.scenario_id): return CityMapProfiles.building(scenario,id)
	var point: Array = scenario.node_positions[id]
	return Rect2(Vector2(point[0],point[1])-Vector2(28,25),Vector2(56,50))

func configure(data: ScenarioData, current_state: GameState, debug: bool = false) -> void:
	if scenario != data:
		tower_rects.clear()
		if camera_tween: camera_tween.kill()
		selected_shelter = ""
		selected_edge = ""
		hover_target = ""
		supply_paths.clear()
		preview_lost.clear()
		preview_edge = ""
		animation_kind = ""
		animation_paths.clear()
		flash_nodes.clear()
		closing_edge = ""
		zoom = 1.0
		camera_center = Vector2(data.world_size[0],data.world_size[1])*0.5
	scenario = data
	state = current_state
	dev_mode = debug
	reachable = SupplyManager.new(state).stocked_reachability()
	var roofs: Array[Rect2] = []
	var paths: Array = []
	for id in data.node_positions: roofs.append(tower_world_rect(id))
	for id in state.edges: paths.append(visual_road(id))
	terrain_texture = WoodlandArt.terrain(data,roofs,paths)
	queue_redraw()

func _process(delta: float) -> void:
	ambient_elapsed += delta
	if ambient_elapsed >= 0.24 and not UIkit.reduced_motion:
		ambient_elapsed = 0
		ambient_frame = (ambient_frame+1)%3
		queue_redraw()
	if animation_kind != "": queue_redraw()

func map_scale() -> float:
	if scenario == null: return 1.0
	# Frame the playable district; only outer scenery is cropped on wide screens.
	return minf((size.x-140.0)/float(scenario.world_size[0]),(size.y-270.0)/float(scenario.world_size[1])) * zoom

func world_center() -> Vector2:
	return Vector2(scenario.world_size[0],scenario.world_size[1])*0.5

func to_screen(point: Vector2) -> Vector2:
	return (point-camera_center)*map_scale()+size*0.5+Vector2(0,45)

func to_world(point: Vector2) -> Vector2:
	return (point-size*0.5-Vector2(0,45))/map_scale()+camera_center

func focus_building(id: String, animated: bool = true) -> void:
	if not scenario.node_positions.has(id): return
	focus_id = id
	var target := world_building(id).get_center()
	# Keep the selected structure in the exposed part of the floating workspace.
	target.x += inspection_inset*0.5/(map_scale()/zoom*2.0)
	_move_camera(target,2.0,animated)

func center_map(animated: bool = true) -> void:
	focus_id = ""
	_move_camera(world_center(),1.0,animated)

func _move_camera(target: Vector2, scale_target: float, animated: bool) -> void:
	if camera_tween: camera_tween.kill()
	if animated and not UIkit.reduced_motion:
		camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		camera_tween.tween_property(self,"camera_center",target,0.28)
		camera_tween.tween_property(self,"zoom",scale_target,0.28)
		camera_tween.tween_method(func(_value: float): _update_camera(),0.0,1.0,0.28)
	else:
		camera_center = target
		zoom = scale_target
		_update_camera()

func _update_camera() -> void:
	if scenario == null: return
	# Allow edge towers to be inspected, while always retaining map context.
	var freedom := clampf(0.12+(zoom-1.0)/0.65,0,1)
	camera_center = camera_center.clamp(world_center().lerp(Vector2(-70,-40),freedom),world_center().lerp(Vector2(scenario.world_size[0]+70,scenario.world_size[1]+40),freedom))
	pan = (world_center()-camera_center)*map_scale() if scenario != null else Vector2.ZERO
	view_changed.emit()
	queue_redraw()

func visual_road(id: String) -> PackedVector2Array:
	if CityMapProfiles.has_profile(scenario.scenario_id): return CityMapProfiles.road(scenario,id)
	return scenario.road_points(id)

func network_anchor(id: String) -> Vector2:
	if has_city_art(): return CityMapProfiles.anchor(scenario,id)
	return CityMapProfiles.vector(scenario.node_positions[id])

func closure_fraction(id: String) -> float:
	return CityMapProfiles.layout(scenario).edges[id].closure_fraction if has_city_art() else 0.5

func building_rect(id: String) -> Rect2:
	var rect: Rect2 = world_building(id)
	return Rect2(to_screen(rect.position),rect.size*map_scale())

func _refresh_geometry() -> void:
	positions.clear()
	road_geometry.clear()
	for id in scenario.node_positions:
		positions[id] = to_screen(world_building(id).get_center())
	for id in state.edges:
		var points := PackedVector2Array()
		for point in visual_road(id): points.append(to_screen(point))
		road_geometry[id] = points
	radius = clampf(32*map_scale(),28,36)
	_place_annotations()

func _place_annotations() -> void:
	var public_status: Array = []
	for id in positions: public_status.append(_public_tags(id))
	var key := str([scenario.scenario_id,camera_center,zoom,size,inspection_inset,public_status])
	if key == annotation_key: return
	annotation_key = key
	title_rects.clear()
	status_positions.clear()
	var occupied: Array[Rect2] = []
	for id in positions: occupied.append(tower_screen_rect(id).grow(4))
	# Place each public name/status together, near its building, avoiding streets.
	for id in positions:
		var rect := tower_screen_rect(id)
		if not Rect2(Vector2.ZERO,size).intersects(rect): continue
		var title: String = id+" / "+state.shelters[id].display_name
		var width := UIkit.HEADING_FONT.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,UIkit.MAP_NAME).x+14
		var status := " · ".join(_public_tags(id))
		width = maxf(width,UIkit.HEADING_FONT.get_string_size(status,HORIZONTAL_ALIGNMENT_LEFT,-1,_stamp_size(status,UIkit.MAP_TAG)).x+8)
		var preferred := Rect2(Vector2(rect.get_center().x-width/2,rect.end.y+8),Vector2(width,NAME_BLOCK))
		var label := _free_annotation(preferred,occupied,rect.get_center())
		title_rects[id] = Rect2(label.position,Vector2(width,NAME_PLATE))
		status_positions[id] = Vector2(label.get_center().x,label.position.y+STATUS_BASELINE)
		occupied.append(label.grow(3))

func _free_annotation(preferred: Rect2, occupied: Array[Rect2], landmark: Vector2) -> Rect2:
	var best := preferred
	var best_distance := INF
	for dy in range(-12,13):
		for dx in range(-12,13):
			var candidate := preferred
			candidate.position += Vector2(dx,dy)*22
			candidate.position.x = clampf(candidate.position.x,6,maxf(6,size.x-candidate.size.x-6))
			candidate.position.y = clampf(candidate.position.y,178,maxf(178,size.y-candidate.size.y-116))
			if inspection_inset > 0 and candidate.end.x > size.x-inspection_inset: continue
			var distance := candidate.get_center().distance_squared_to(landmark)
			if distance >= best_distance: continue
			var collision := false
			for other in occupied:
				if candidate.intersects(other):
					collision = true
					break
			if not collision and not _annotation_hides_road(candidate):
				best = candidate
				best_distance = distance
	return best

func _annotation_hides_road(rect: Rect2) -> bool:
	var area := rect.grow(road_core_width()*0.5+4)
	var corners := [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]
	for points: PackedVector2Array in road_geometry.values():
		for i in points.size()-1:
			if area.has_point(points[i]) or area.has_point(points[i+1]): return true
			for j in 4:
				if Geometry2D.segment_intersects_segment(points[i],points[i+1],corners[j],corners[(j+1)%4]) != null: return true
	return false

# Asphalt, curbs, and intersections are generated from the same paths used by
# clicks and vehicles. All edge borders precede all interiors, avoiding seams.
func _draw_streets() -> void:
	# These existing driveways connect roofs to their authoritative junctions.
	if not has_city_art(): return
	for id in positions:
		var n: Dictionary = CityMapProfiles.node(scenario,id)
		draw_line(to_screen(network_anchor(id)),to_screen(CityMapProfiles.vector(n.entrance)),Color("59665b"),5.0*map_scale(),false)

func _draw_bridges() -> void:
	# Deck boards lie only on the authoritative route where it crosses water.
	for points: PackedVector2Array in road_geometry.values():
		for index in points.size()-1:
			var a := to_world(points[index])
			var b := to_world(points[index+1])
			var steps := maxi(1,ceili(a.distance_to(b)/5.0))
			for step in steps:
				var at := a.lerp(b,float(step)/steps)
				if absf(at.x-WoodlandArt.river_x(at.y,scenario.world_size[0])) > 34: continue
				draw_set_transform(to_screen(at),(b-a).angle(),Vector2.ONE*map_scale())
				draw_rect(Rect2(-3,-14,6,28),Color("78694c"))
				draw_rect(Rect2(-2,-11,3,22),Color("a08b60"))
				draw_rect(Rect2(-3,-16,6,3),Color("b6a171"))
				draw_rect(Rect2(-3,13,6,3),Color("4f5341"))
				draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if scenario == null or state == null: return
	_refresh_geometry()
	draw_rect(Rect2(Vector2.ZERO,size),UIkit.MAP)
	_draw_city()
	_draw_streets()
	_draw_bridges()
	if not show_annotations: return
	for edge: EdgeState in state.edges.values(): _draw_road(edge)
	for id in positions: _draw_shelter(id)
	_draw_animation()
func tower_world_rect(id: String) -> Rect2:
	if tower_rects.has(id): return tower_rects[id]
	var base := world_building(id)
	if not has_city_art():
		return Rect2(base.get_center()-Vector2(32,86),Vector2(64,96))
	var rect := Rect2(Vector2(base.get_center().x-32,base.end.y-86),Vector2(64,96))
	# Taller cosmetic silhouettes extend away from streets. The authoritative
	# roof/entrance/junction and all route coordinates remain untouched.
	for top in [base.end.y-86,base.position.y-4,base.get_center().y-48]:
		rect.position.y = top
		if not _roof_hides_road(rect.grow(3)): break
	tower_rects[id] = rect
	return rect

func _roof_hides_road(rect: Rect2) -> bool:
	var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	for id in state.edges:
		var path := visual_road(id)
		for i in path.size()-1:
			if rect.has_point(path[i]) or rect.has_point(path[i+1]): return true
			for j in 4:
				if Geometry2D.segment_intersects_segment(path[i],path[i+1],corners[j],corners[(j+1)%4]) != null: return true
	return false

func tower_screen_rect(id: String) -> Rect2:
	var rect := tower_world_rect(id)
	return Rect2(to_screen(rect.position),rect.size*map_scale())

func _draw_city() -> void:
	var padding := float(WoodlandArt.PAD)
	var rect := Rect2(to_screen(Vector2(-padding,-padding)),(Vector2(scenario.world_size[0],scenario.world_size[1])+Vector2.ONE*padding*2)*map_scale())
	if terrain_texture: draw_texture_rect(terrain_texture,rect,false)
	var frame := 0 if UIkit.reduced_motion else ambient_frame
	for y in range(-100,int(scenario.world_size[1])+100,48):
		var point := Vector2(WoodlandArt.river_x(y,scenario.world_size[0])-8+frame*3,y+frame*2)
		draw_rect(Rect2(to_screen(point),Vector2(15,2)*map_scale()),Color("3b5964"))
	for id in positions:
		if not beacon_lit(id): continue
		var base := tower_world_rect(id)
		var at := Vector2(base.get_center().x,base.end.y-12)
		# The gradient has no boundary, state radius, or range indicator.
		draw_texture_rect(WoodlandArt.light_texture(),Rect2(to_screen(at-Vector2(112,72)),Vector2(224,144)*map_scale()),false)

# Screen-space widths: 4–6px core (previously 1.5px), with 2px dark casing.
# Visual geometry and logical path costs are unchanged.
func road_core_width() -> float:
	return clampf(8.0*map_scale(),7.0,13.0)

func road_hit_radius() -> float:
	return maxf(10.0,(road_core_width()+4.0)*0.5+4.0)

func beacon_lit(id: String) -> bool:
	return not state.shelters[id].is_overrun

func shelter_ink(id: String) -> Color:
	if state.shelters[id].is_overrun: return UIkit.RED
	return UIkit.ACCENT

func shelter_status_ink(id: String) -> Color:
	var shelter: ShelterState = state.shelters[id]
	if not shelter.is_overrun and shelter.monitor_known_pressure < 0: return UIkit.SECONDARY
	return shelter_ink(id)

func _draw_road(edge: EdgeState) -> void:
	var points: PackedVector2Array = road_geometry[edge.id]
	var selected := edge.id == selected_edge or edge.id == hover_target
	var closed := edge.isolated
	var no_supply: bool = state.shelters[edge.from].is_overrun or state.shelters[edge.to].is_overrun or not (reachable.has(edge.from) and reachable.has(edge.to))
	var width := road_core_width()
	# Casing separates the playable overlay from both pale streets and dark roofs.
	draw_polyline(points,UIkit.MAP,width+4.0,true)
	var ink := UIkit.RED if closed else (Color("d2e6ef") if selected else Color("9aab92"))
	if closed or no_supply:
		for index in points.size()-1:
			draw_dashed_line(points[index],points[index+1],ink,width,9.0 if closed else 3.0,true)
	else:
		draw_polyline(points,ink,width,false)
		for index in points.size()-1:
			draw_dashed_line(points[index],points[index+1],Color("c1bda0"),2,7,false)
	if selected:
		_brackets(_point_on_path(points,closure_fraction(edge.id)),13,UIkit.AMBER,2)
	for path: Array in supply_paths:
		for index in maxi(0,path.size()-1):
			if edge.other_endpoint(path[index]) == path[index+1]: draw_polyline(points,UIkit.AMBER,width,true)
	if closed or edge.id == preview_edge or edge.id == closing_edge:
		var fraction := closure_fraction(edge.id)
		var center := _point_on_path(points,fraction)
		var direction := (_point_on_path(points,fraction+0.02)-_point_on_path(points,fraction-0.02)).angle()
		var drop := 10.0*(1.0-animation_progress) if edge.id == closing_edge else 0.0
		draw_set_transform(center-Vector2(0,drop),direction,Vector2.ONE*clampf(map_scale()*0.8,0.85,1.25))
		draw_rect(Rect2(-17,-13,34,26),UIkit.MAP)
		draw_line(Vector2(-13,-14),Vector2(-13,14),UIkit.RED if closed else UIkit.AMBER,5,true)
		draw_line(Vector2(13,-14),Vector2(13,14),UIkit.RED if closed else UIkit.AMBER,5,true)
		for y in [-9,0,9]: draw_line(Vector2(-9,y+3),Vector2(9,y-3),UIkit.RED if closed else UIkit.AMBER,4,true)
		draw_set_transform(Vector2.ZERO)
		_stamp(center+Vector2(0,-24),"CLOSED" if closed else ("CLOSING" if edge.id == closing_edge else "PREVIEW"),UIkit.RED if closed else UIkit.AMBER)
	if dev_mode:
		_text(_point_on_path(points,0.5)+Vector2(0,27),edge.id,UIkit.MAP_TAG,UIkit.TEXT)

func _draw_shelter(id: String) -> void:
	var shelter: ShelterState = state.shelters[id]
	var rect := tower_screen_rect(id)
	if not Rect2(Vector2.ZERO,size).intersects(rect): return
	var selected := selected_shelter == id or hover_target == id
	var ink := shelter_ink(id)
	var variant := id.unicode_at(0)-65
	var frame := 0 if UIkit.reduced_motion else ambient_frame
	var lit := beacon_lit(id)
	var artwork := WoodlandArt.tower(posmod(variant,8),zoom > 1.45,lit,frame,state.depots.has(id))
	draw_texture_rect(artwork,rect,false)
	if lit:
		var core := rect.position+Vector2(32,17)*map_scale()
		draw_texture_rect(WoodlandArt.light_texture(true),Rect2(core-Vector2.ONE*29*map_scale(),Vector2.ONE*58*map_scale()),false)
	# Cool corner brackets indicate selection; warm lamp light is never selection.
	if selected:
		var selection := rect.grow(5)
		for corner in [selection.position,Vector2(selection.end.x,selection.position.y),selection.end,Vector2(selection.position.x,selection.end.y)]:
			var direction: Vector2 = (selection.get_center()-corner).sign()
			draw_line(corner,corner+Vector2(direction.x*12,0),Color("d3eaf6"),2)
			draw_line(corner,corner+Vector2(0,direction.y*12),Color("d3eaf6"),2)
	if shelter.is_overrun: _draw_overrun_mark(rect.get_center(),12*map_scale())
	if shelter.shielded_this_round:
		var c := rect.position+Vector2(54,56)*map_scale()
		var shield := PackedVector2Array([c+Vector2(-9,-11),c+Vector2(9,-11),c+Vector2(8,4),c+Vector2(0,12),c+Vector2(-8,4),c+Vector2(-9,-11)])
		draw_colored_polygon(shield,UIkit.PANEL)
		draw_polyline(shield,UIkit.TEAL,2)
	if shelter.is_monitored:
		var c := rect.position+Vector2(2,64)*map_scale()
		draw_line(c,c-Vector2(0,26),UIkit.SECONDARY,2)
		draw_arc(c-Vector2(0,28),8,PI,TAU,8,UIkit.TEAL,2)
	if not title_rects.has(id): return
	var title := id+" / "+shelter.display_name
	var font := UIkit.HEADING_FONT
	var label_width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,UIkit.MAP_NAME).x+14
	var at := _pixel_aligned(title_rects[id].position if title_rects.has(id) else Vector2(rect.get_center().x-label_width/2,rect.end.y+8))
	if at.distance_to(rect.end) > 80:
		draw_line(Vector2(rect.get_center().x,rect.end.y),at+Vector2(label_width/2,0),Color("687c73"),1)
	draw_rect(Rect2(at,Vector2(label_width,NAME_PLATE)),UIkit.PANEL)
	draw_line(at+Vector2(0,NAME_PLATE),at+Vector2(label_width,NAME_PLATE),ink,1)
	_draw_caption(font,at+Vector2(7,20),title,UIkit.MAP_NAME,ink)
	var status_at: Vector2 = status_positions.get(id,Vector2(rect.get_center().x,rect.end.y+47))
	_stamp(status_at," · ".join(_public_tags(id)),shelter_status_ink(id),UIkit.MAP_TAG)
	if preview_lost.has(id): draw_rect(rect.grow(8),UIkit.AMBER,false,3)
	if dev_mode: _stamp(rect.get_center(),"DEV P%d" % shelter.zombie_pressure,UIkit.RED)

func _public_tags(id: String) -> Array[String]:
	var shelter: ShelterState = state.shelters[id]
	var tags: Array[String] = []
	if shelter.is_overrun: tags.append("OVERRUN")
	elif shelter.monitor_known_pressure >= 0: tags.append("M:%d" % shelter.monitor_known_pressure)
	else: tags.append("? UNOBSERVED")
	if state.depots.has(id): tags.append("%d SUPPLY" % state.depots[id].supply_remaining)
	if shelter.is_monitored: tags.append("MONITOR")
	if shelter.shielded_this_round: tags.append("SHIELD")
	if not reachable.has(id) and not shelter.is_overrun: tags.append("NO SUPPLY")
	return tags

func hit_test(point: Vector2) -> String:
	if scenario == null: return ""
	_refresh_geometry()
	for id in positions:
		var selection := CityMapProfiles.rectangle(CityMapProfiles.node(scenario,id).selection) if has_city_art() else world_building(id)
		if selection.has_point(to_world(point)): return id
	var nearest := ""
	var distance := road_hit_radius()
	for id in road_geometry:
		var points: PackedVector2Array = road_geometry[id]
		for index in points.size()-1:
			var candidate := Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1]).distance_to(point)
			if candidate < distance:
				distance = candidate
				nearest = id
	if nearest != "": return nearest
	for id in positions:
		if tower_screen_rect(id).has_point(point) or (title_rects.has(id) and title_rects[id].has_point(point)): return id
	return ""

func change_zoom(amount: float) -> void:
	if camera_tween: camera_tween.kill()
	zoom = clampf(zoom+amount,1.0,2.2 if focus_id != "" else 1.4)
	_update_camera()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			change_zoom(0.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_position = event.position
				dragging = true
				drag_moved = false
			else:
				dragging = false
				if not drag_moved and event.position.distance_to(press_position)<8:
					var target := hit_test(event.position)
					if state.shelters.has(target): shelter_selected.emit(target)
					elif state.edges.has(target): edge_selected.emit(target)
					else: background_selected.emit()
				drag_moved = false
			accept_event()
	elif event is InputEventMouseMotion:
		if dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if event.position.distance_to(press_position) >= 8: drag_moved = true
			if drag_moved:
				if camera_tween: camera_tween.kill()
				camera_center -= event.relative/map_scale()
				_update_camera()
		hover_target = hit_test(event.position) if not drag_moved else ""
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover_target != "" else Control.CURSOR_ARROW
		queue_redraw()
	elif event is InputEventMagnifyGesture:
		change_zoom((event.factor-1)*zoom)
		accept_event()
	elif event is InputEventPanGesture:
		camera_center += event.delta*8/map_scale()
		_update_camera()
		accept_event()

func world_path_for_nodes(nodes: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	if nodes.size()==1:
		points.append(network_anchor(nodes[0]))
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
	delivery_targets.clear()
	var longest := 0.0
	for delivery in deliveries:
		delivery_targets.append(delivery.target)
		var path := world_path_for_nodes(delivery.path)
		animation_paths.append(path)
		var length := 0.0
		for index in path.size()-1: length += path[index].distance_to(path[index+1])
		longest = maxf(longest,length)
	await _animate("delivery",clampf(0.7+longest/900.0,0.7,1.5))
	await _animate("arrival",0.55)

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
	if UIkit.reduced_motion: return # Timers still run unchanged in _animate.
	if animation_kind == "delivery":
		for path: PackedVector2Array in animation_paths:
			var at := to_screen(_point_on_path(path,animation_progress))
			var next_point := to_screen(_point_on_path(path,minf(1.0,animation_progress+0.02)))
			var route := PackedVector2Array()
			for point in path: route.append(to_screen(point))
			if route.size() > 1: draw_polyline(route,Color(0.65,0.40,0.21,0.5),2,true)
			var behind := to_screen(_point_on_path(path,maxf(0.0,animation_progress-0.002)))
			draw_set_transform(at,(next_point-behind).angle(),Vector2.ONE*clampf(map_scale()*0.6,0.65,1.0))
			draw_rect(Rect2(-13,-8,26,16),Color("b29863"))
			draw_rect(Rect2(4,-6,6,12),UIkit.LINE)
			draw_rect(Rect2(-11,-5,10,10),UIkit.PANEL)
			draw_line(Vector2(-6,-5),Vector2(-6,5),UIkit.AMBER,2)
			for wheel in [Vector2(-8,-9),Vector2(-8,9),Vector2(8,-9),Vector2(8,9)]: draw_rect(Rect2(wheel-Vector2(3,2),Vector2(6,4)),Color("373e35"))
			draw_set_transform(Vector2.ZERO)
	elif animation_kind == "arrival":
		for id in delivery_targets:
			_brackets(positions[id],radius+6,UIkit.AMBER,3)
			_stamp(positions[id]+Vector2(0,-radius-12),"DELIVERED",UIkit.AMBER)
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
				if state.shelters[id].shielded_this_round and network_anchor(id).distance_to(path[path.size()-1]) < 0.01 and animation_progress > 0.7:
					var center: Vector2 = positions[id]
					var shield := PackedVector2Array([center+Vector2(-19,-22),center+Vector2(19,-22),center+Vector2(17,5),center+Vector2(0,20),center+Vector2(-17,5),center+Vector2(-19,-22)])
					draw_colored_polygon(shield,UIkit.MAP)
					draw_polyline(shield,UIkit.TEAL,3,true)
					_stamp(center+Vector2(0,-radius-34),"BLOCKED",UIkit.TEAL)
	elif animation_kind == "reveal":
		for id in flash_nodes:
			var at: Vector2 = positions[id]
			_draw_overrun_mark(at,radius+7,animation_progress)
			_stamp(at+Vector2(0,-radius-18),"OVERRUN",UIkit.RED)

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

# Round captions in render-target pixels, not logical map units. Camera geometry
# stays continuous, and font size stays independent of building zoom.
func _pixel_aligned(point: Vector2) -> Vector2:
	var transform := get_viewport_transform() * get_global_transform()
	return transform.affine_inverse() * (transform * point).round()

# Map captions are solid, opaque glyphs on opaque plates: no halo or glow.
func _draw_caption(font: Font, origin: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(font,_pixel_aligned(origin),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _text(at: Vector2, value: String, font_size: int, color: Color) -> void:
	var font := UIkit.HEADING_FONT
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	_draw_caption(font,at-Vector2(width/2,0),value,font_size,color)

# Single important states read larger than combined status lists.
func _stamp_size(value: String, font_size: int) -> int:
	return UIkit.MAP_NAME if value in ["OVERRUN","CLOSED","SHIELD","BLOCKED"] else font_size

func _stamp(at: Vector2, value: String, color: Color, font_size: int = UIkit.MAP_TAG) -> void:
	font_size = _stamp_size(value,font_size)
	var width := UIkit.HEADING_FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_rect(Rect2(_pixel_aligned(at-Vector2(width/2+5,font_size+1)),Vector2(ceilf(width)+10,font_size+6)),UIkit.MAP)
	_text(at,value,font_size,color)

func _brackets(at: Vector2, extent: float, color: Color, weight: float) -> void:
	for x in [-1,1]:
		for y in [-1,1]:
			var corner := at+Vector2(x,y)*extent
			draw_line(corner,corner-Vector2(x*9,0),color,weight,true)
			draw_line(corner,corner-Vector2(0,y*9),color,weight,true)
