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
var terrain_texture: Texture2D
var terrain_surface: Sprite2D
# Visible bridge decks, derived from ScenarioData.bridges only: edge ID -> world spans.
var bridge_edges: Dictionary = {}
# Flat list of every deck span (all belong to designated bridge edges).
var bridges: Array = []
var bridge_fractions: Dictionary = {}
var source_mode := false
var source_destinations: Array[String] = []
var eligible_sources: Array[String] = []
var chosen_sources: Array[String] = []
# Explicitly opt-in QA overlay, never enabled by participant/dev mode.
var debug_anchors := false
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
	return tower_world_rect(id)

func configure(data: ScenarioData, current_state: GameState, debug: bool = false) -> void:
	if scenario != data:
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
	var paths_by_id := {}
	for id in data.node_positions: roofs.append(tower_world_rect(id))
	for id in state.edges:
		paths.append(visual_road(id))
		paths_by_id[id] = visual_road(id)
	terrain_texture = WoodlandArt.terrain(data,roofs,paths)
	bridge_edges = WoodlandArt.bridge_spans(data,paths_by_id)
	bridges.clear()
	bridge_fractions.clear()
	for id in bridge_edges:
		bridges.append_array(bridge_edges[id])
		bridge_fractions[id] = _bridge_fraction(paths_by_id[id],bridge_edges[id])
	if terrain_surface == null:
		terrain_surface = Sprite2D.new()
		terrain_surface.show_behind_parent = true
		terrain_surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var lighting := ShaderMaterial.new()
		lighting.shader = preload("res://scripts/ui/forest_light.gdshader")
		terrain_surface.material = lighting
		add_child(terrain_surface)
	terrain_surface.texture = terrain_texture
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
	if source_mode:
		var bounds := graph_bounds()
		return minf((size.x-200.0)/bounds.size.x,(size.y-510.0)/bounds.size.y)*zoom
	# Frame the playable district; only outer scenery is cropped on wide screens.
	return minf((size.x-140.0)/float(scenario.world_size[0]),(size.y-240.0)/float(scenario.world_size[1])) * zoom

func graph_bounds() -> Rect2:
	var bounds := tower_world_rect(scenario.node_positions.keys()[0])
	for id in scenario.node_positions: bounds = bounds.merge(tower_world_rect(id))
	return bounds.grow(28)

func focus_sources() -> void:
	focus_id = ""
	_move_camera(graph_bounds().get_center(),1.0,false)

func screen_origin() -> Vector2:
	return Vector2(size.x*0.5,(166+size.y-344)*0.5) if source_mode else size*0.5+Vector2(0,35)

func world_center() -> Vector2:
	return Vector2(scenario.world_size[0],scenario.world_size[1])*0.5

func to_screen(point: Vector2) -> Vector2:
	return (point-camera_center)*map_scale()+screen_origin()

func to_world(point: Vector2) -> Vector2:
	return (point-screen_origin())/map_scale()+camera_center

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
	if not source_mode: camera_center = camera_center.clamp(world_center().lerp(Vector2(-70,-40),freedom),world_center().lerp(Vector2(scenario.world_size[0]+70,scenario.world_size[1]+40),freedom))
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
	# A bridge's barricade, selection brackets and bubble anchor sit at mid-deck.
	if bridge_fractions.has(id): return bridge_fractions[id]
	return CityMapProfiles.layout(scenario).edges[id].closure_fraction if has_city_art() else 0.5

func _bridge_fraction(path: PackedVector2Array, spans: Array) -> float:
	if spans.is_empty(): return 0.5
	var longest: PackedVector2Array = spans[0]
	for span: PackedVector2Array in spans:
		if span[0].distance_to(span[1]) > longest[0].distance_to(longest[1]): longest = span
	var middle := (longest[0]+longest[1])*0.5
	var total := 0.0
	var before := 0.0
	var best := INF
	for index in path.size()-1:
		var closest := Geometry2D.get_closest_point_to_segment(middle,path[index],path[index+1])
		if closest.distance_to(middle) < best:
			best = closest.distance_to(middle)
			before = total+path[index].distance_to(closest)
		total += path[index].distance_to(path[index+1])
	return before/maxf(total,0.001)

func building_rect(id: String) -> Rect2:
	var rect: Rect2 = world_building(id)
	return Rect2(to_screen(rect.position),rect.size*map_scale())

func _refresh_geometry() -> void:
	positions.clear()
	road_geometry.clear()
	for id in scenario.node_positions:
		positions[id] = to_screen(network_anchor(id))
	for id in state.edges:
		var points := PackedVector2Array()
		for point in visual_road(id): points.append(to_screen(point))
		road_geometry[id] = points
	radius = clampf(32*map_scale(),28,36)
	_place_annotations()

func _place_annotations() -> void:
	var public_status: Array = []
	for id in positions: public_status.append(_public_tags(id))
	var key := str([scenario.scenario_id,camera_center,zoom,size,inspection_inset,source_mode,source_destinations,eligible_sources,chosen_sources,public_status])
	if key == annotation_key: return
	annotation_key = key
	title_rects.clear()
	status_positions.clear()
	var occupied: Array[Rect2] = []
	for id in positions: occupied.append(tower_screen_rect(id).grow(4))
	# Place each public name/status together, near its building, avoiding streets.
	var order := positions.keys()
	if selected_shelter in order:
		order.erase(selected_shelter)
		order.push_front(selected_shelter)
	for id in order:
		if source_mode and id not in source_destinations and id not in eligible_sources and id not in chosen_sources: continue
		var rect := tower_screen_rect(id)
		var safe := Rect2(6,152,size.x-inspection_inset-12,size.y-256)
		if not safe.encloses(rect): continue
		var title: String = _node_title(id)
		var width := UIkit.HEADING_FONT.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,UIkit.MAP_NAME).x+14
		var status := " · ".join(_public_tags(id))
		width = maxf(width,UIkit.HEADING_FONT.get_string_size(status,HORIZONTAL_ALIGNMENT_LEFT,-1,_stamp_size(status,UIkit.MAP_TAG)).x+8)
		var preferred := Rect2(Vector2(rect.get_center().x-width/2,rect.end.y+8),Vector2(width,NAME_BLOCK))
		var label := _free_annotation(preferred,occupied,rect)
		title_rects[id] = Rect2(label.position,Vector2(width,NAME_PLATE))
		status_positions[id] = Vector2(label.get_center().x,label.position.y+STATUS_BASELINE)
		occupied.append(label.grow(3))

func _free_annotation(preferred: Rect2, occupied: Array[Rect2], landmark: Rect2) -> Rect2:
	var best := preferred
	var best_distance := INF
	for dy in range(-20,11):
		for dx in range(-20 if source_mode else -10,21 if source_mode else 11):
			var candidate := preferred
			candidate.position += Vector2(dx,dy)*14
			candidate.position.x = clampf(candidate.position.x,6,maxf(6,size.x-candidate.size.x-6))
			candidate.position.y = clampf(candidate.position.y,152,maxf(152,size.y-candidate.size.y-(344 if source_mode else 104)))
			if inspection_inset > 0 and candidate.end.x > size.x-inspection_inset: continue
			var gap := Vector2(maxf(0,maxf(landmark.position.x-candidate.end.x,candidate.position.x-landmark.end.x)),maxf(0,maxf(landmark.position.y-candidate.end.y,candidate.position.y-landmark.end.y)))
			var distance := gap.length_squared()*4+candidate.get_center().distance_squared_to(landmark.get_center())*0.15
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

func _draw_bridges() -> void:
	# Complete decks span water or ravine AND both banks. Only designated bridge edges
	# (ScenarioData.bridges) receive a deck; every closable edge therefore shows one.
	for id in bridge_edges:
		for span: PackedVector2Array in bridge_edges[id]:
			var a := span[0]
			var b := span[1]
			var length := a.distance_to(b)
			var ravine := WoodlandArt.obstacle_kind(scenario,a.lerp(b,0.5)) == "ravine"
			draw_set_transform(to_screen(a),(b-a).angle(),Vector2.ONE*map_scale())
			if ravine:
				# Long drop shadow into the ravine floor and stone abutments on each rim.
				draw_rect(Rect2(4,14,length-8,8),Color("070c0e"))
				for x in [-8,length-4]: draw_rect(Rect2(x,-20,12,40),Color("5d6156"))
				for x in [-8,length-4]: draw_rect(Rect2(x,-20,12,3),Color("8b8d7b"))
			draw_rect(Rect2(-3,-16,length+6,32),Color("343d37"))
			for step in range(0,ceili(length)+1,5):
				draw_rect(Rect2(step,-14,4,28),Color("a08b60"))
				draw_rect(Rect2(step,-12,2,24),Color("78694c"))
			for y in [-16,13]: draw_rect(Rect2(-3,y,length+6,3),Color("b6a171"))
			for x in [-4,length-2]:
				for y in [-19,13]: draw_rect(Rect2(x,y,6,6),Color("8b947e"))
			if ravine:
				for x in range(12,int(length)-8,18):
					for y in [-19,16]: draw_rect(Rect2(x,y,3,3),Color("6f6448"))
			draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if scenario == null or state == null: return
	_refresh_geometry()
	if terrain_texture == null: draw_rect(Rect2(Vector2.ZERO,size),UIkit.MAP)
	_draw_city()
	_draw_bridges()
	if not show_annotations: return
	for edge: EdgeState in state.edges.values(): _draw_road(edge)
	for id in positions: _draw_shelter(id)
	_draw_animation()
	if debug_anchors: _draw_anchor_overlay()

func tower_world_rect(id: String) -> Rect2:
	return Rect2(network_anchor(id)-sprite_metadata(id).ground,Vector2(64,96))

func sprite_metadata(id: String) -> Dictionary:
	return WoodlandArt.metadata(posmod(id.unicode_at(0)-65,8))

func lamp_world_position(id: String) -> Vector2:
	return tower_world_rect(id).position+sprite_metadata(id).lamp

func _draw_anchor_overlay() -> void:
	for id in positions:
		var anchor: Vector2 = positions[id]
		draw_rect(tower_screen_rect(id),Color.CYAN,false,1)
		draw_circle(anchor,4,Color.MAGENTA)
		draw_circle(to_screen(tower_world_rect(id).position+sprite_metadata(id).ground),2,Color.WHITE)
		draw_circle(to_screen(lamp_world_position(id)),3,Color.YELLOW)
		for edge: EdgeState in state.edges.values():
			if id not in [edge.from,edge.to]: continue
			var endpoint: Vector2 = road_geometry[edge.id][0 if edge.from == id else -1]
			draw_rect(Rect2(endpoint-Vector2.ONE*6,Vector2.ONE*12),Color.GREEN,false,1)

func tower_screen_rect(id: String) -> Rect2:
	var rect := tower_world_rect(id)
	return Rect2(to_screen(rect.position),rect.size*map_scale())

func _draw_city() -> void:
	var padding := float(WoodlandArt.PAD)
	var rect := Rect2(to_screen(Vector2(-padding,-padding)),(Vector2(scenario.world_size[0],scenario.world_size[1])+Vector2.ONE*padding*2)*map_scale())
	if terrain_surface:
		terrain_surface.position = rect.get_center()
		terrain_surface.scale = rect.size/terrain_texture.get_size()
		var lights := PackedVector3Array()
		for id in positions:
			var at := network_anchor(id)
			lights.append(Vector3(at.x,at.y,1.0 if beacon_lit(id) else 0.0))
		while lights.size() < 8: lights.append(Vector3.ZERO)
		terrain_surface.material.set_shader_parameter("beacons",lights)
		terrain_surface.material.set_shader_parameter("world_extent",Vector2(scenario.world_size[0],scenario.world_size[1])+Vector2.ONE*padding*2)
	var frame := 0 if UIkit.reduced_motion else ambient_frame
	for ripple: Array in WoodlandArt.ripples(scenario,frame):
		draw_rect(Rect2(to_screen(ripple[0]),ripple[1]*map_scale()),Color("3b5964"))
# Screen-space widths: 7–13px stone core, with 2px dark casing.
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
		var gate_ink := UIkit.RED if closed else UIkit.AMBER
		draw_set_transform(center-Vector2(0,drop),direction,Vector2.ONE*clampf(map_scale()*0.9,0.85,2.2))
		# Closed bridge gate: stone posts on both rails, a timber barricade across the deck
		# and a cross brace in the closure ink. Permanent once both deliveries arrive.
		draw_rect(Rect2(-12,-24,24,48),UIkit.MAP)
		draw_rect(Rect2(-8,-20,16,40),Color("5b4b32"))
		for y in [-14,-6,2,10]: draw_rect(Rect2(-8,y,16,2),Color("3c3224"))
		draw_line(Vector2(-6,-18),Vector2(6,18),gate_ink,4,true)
		draw_line(Vector2(6,-18),Vector2(-6,18),gate_ink,4,true)
		for y in [-26,18]:
			draw_rect(Rect2(-6,y,12,8),Color("8b947e"))
			draw_rect(Rect2(-6,y,12,2),Color("b4ad88"))
		draw_rect(Rect2(-9,-21,18,42),gate_ink,false,2)
		draw_set_transform(Vector2.ZERO)
		_stamp(center+Vector2(0,-24),"CLOSED" if closed else ("CLOSING" if edge.id == closing_edge else "PREVIEW"),UIkit.RED if closed else UIkit.AMBER)
	if dev_mode:
		_text(_point_on_path(points,0.5)+Vector2(0,27),edge.id,UIkit.MAP_TAG,UIkit.TEXT)

func _draw_shelter(id: String) -> void:
	var shelter: ShelterState = state.shelters[id]
	var rect := tower_screen_rect(id)
	if not Rect2(Vector2.ZERO,size).intersects(rect): return
	var selected := not source_mode and (selected_shelter == id or hover_target == id)
	var ink := shelter_ink(id)
	var variant := id.unicode_at(0)-65
	var frame := 0 if UIkit.reduced_motion else ambient_frame
	var lit := beacon_lit(id)
	var artwork := WoodlandArt.tower(posmod(variant,8),zoom > 1.45,lit,frame,state.depots.has(id))
	draw_texture_rect(artwork,rect,false)
	if lit:
		var core := to_screen(lamp_world_position(id))
		draw_texture_rect(WoodlandArt.light_texture(true),Rect2(core-Vector2.ONE*36*map_scale(),Vector2.ONE*72*map_scale()),false)
	# Short visible road mouths meet the forecourt, including north approaches.
	# They reuse only the terminal section of a real edge (never a driveway).
	for edge: EdgeState in state.edges.values():
		if id not in [edge.from,edge.to]: continue
		var road := visual_road(edge.id)
		if edge.to == id: road.reverse()
		var mouth := road[0].move_toward(road[1],10)
		draw_line(to_screen(mouth),positions[id],UIkit.RED if edge.isolated else Color("9aab92"),road_core_width(),false)
	# Cool corner brackets indicate selection; warm lamp light is never selection.
	if selected or id in eligible_sources or id in source_destinations:
		var selection := rect.grow(5)
		for corner in [selection.position,Vector2(selection.end.x,selection.position.y),selection.end,Vector2(selection.position.x,selection.end.y)]:
			var direction: Vector2 = (selection.get_center()-corner).sign()
			draw_line(corner,corner+Vector2(direction.x*12,0),UIkit.AMBER if id in source_destinations else Color("d3eaf6"),2)
			draw_line(corner,corner+Vector2(0,direction.y*12),UIkit.AMBER if id in source_destinations else Color("d3eaf6"),2)
	if id in chosen_sources: draw_line(rect.position+Vector2(0,rect.size.y),rect.end,UIkit.TEAL,3)
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
	var title := _node_title(id)
	var font := UIkit.HEADING_FONT
	var label_width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,UIkit.MAP_NAME).x+14
	var at := _pixel_aligned(title_rects[id].position if title_rects.has(id) else Vector2(rect.get_center().x-label_width/2,rect.end.y+8))
	var label_block := Rect2(title_rects[id].position,Vector2(title_rects[id].size.x,NAME_BLOCK))
	var leader_start := label_block.get_center().clamp(rect.position,rect.end)
	var leader_end := leader_start.clamp(label_block.position,label_block.end)
	if leader_start.distance_to(leader_end) > 36:
		draw_line(leader_start,leader_end,Color("687c73"),1)
	draw_rect(Rect2(at,Vector2(label_width,NAME_PLATE)),UIkit.PANEL)
	draw_line(at+Vector2(0,NAME_PLATE),at+Vector2(label_width,NAME_PLATE),ink,1)
	_draw_caption(font,at+Vector2(7,20),title,UIkit.MAP_NAME,ink)
	var status_at: Vector2 = status_positions.get(id,Vector2(rect.get_center().x,rect.end.y+47))
	_stamp(status_at," · ".join(_public_tags(id)),shelter_status_ink(id),UIkit.MAP_TAG)
	if preview_lost.has(id): draw_rect(rect.grow(8),UIkit.AMBER,false,3)
	if dev_mode: _stamp(rect.get_center(),"DEV P%d" % shelter.zombie_pressure,UIkit.RED)

func _node_title(id: String) -> String:
	if source_mode and (id in eligible_sources or id in chosen_sources):
		return FirstPlayText.choose("Depot ","仓库 ")+id
	return id+" / "+state.shelters[id].display_name

func _public_tags(id: String) -> Array[String]:
	var shelter: ShelterState = state.shelters[id]
	if source_mode and (id in eligible_sources or id in chosen_sources):
		return [FirstPlayText.choose("%d SUPPLY","%d 份物资") % state.depots[id].supply_remaining]
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
		var selection := tower_world_rect(id)
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
		if source_mode and hover_target not in eligible_sources: hover_target = ""
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
