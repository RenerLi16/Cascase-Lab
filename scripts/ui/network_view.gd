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
# Screen positions of each location piece: exactly on its network junction.
var positions: Dictionary = {}
# Name plates (title_rects) and full name + status blocks (label_rects).
var title_rects: Dictionary = {}
var label_rects: Dictionary = {}
var status_positions: Dictionary = {}
var annotation_key := ""
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
var delivery_targets: Array[String] = []
# Brief "pop" when a piece is selected. One tween at a time; never stacked.
var pop_id := ""
var pop_t := 1.0
var pop_tween: Tween
# Keyboard browsing of pieces and roads (arrow keys, Enter/Space to select).
var key_cursor := ""
var key_active := false
# QA can inspect the terrain without operational annotations.
var show_annotations := true
# Name plate geometry: plate height, status baseline, and total block height.
const NAME_PLATE := 28
const STATUS_BASELINE := 47
const NAME_BLOCK := 52
const CHIP_HEIGHT := 22
const PIECE_DEPTH := 3.0

func _ready() -> void:
	custom_minimum_size = Vector2(500,360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(func(): _update_camera(); queue_redraw())
	mouse_exited.connect(func(): hover_target = ""; queue_redraw())
	focus_exited.connect(func(): key_active = false; queue_redraw())

func has_city_art() -> bool:
	return CityMapProfiles.has_profile(scenario.scenario_id)

# Layout footprint of the original landmark (kept for registration and clearance).
func world_building(id: String) -> Rect2:
	if has_city_art(): return CityMapProfiles.building(scenario,id)
	var point: Array = scenario.node_positions[id]
	return Rect2(Vector2(point[0],point[1])-Vector2(28,25),Vector2(56,50))

func configure(data: ScenarioData, current_state: GameState, debug: bool = false) -> void:
	if scenario != data:
		if camera_tween: camera_tween.kill()
		selected_shelter = ""
		selected_edge = ""
		hover_target = ""
		key_cursor = ""
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
	queue_redraw()

func _process(_delta: float) -> void:
	if animation_kind != "" or pop_t < 1.0: queue_redraw()

func map_scale() -> float:
	if scenario == null: return 1.0
	# Frame the playable district; only outer scenery is cropped on wide screens.
	return minf((size.x-80.0)/float(scenario.world_size[0]),(size.y-48.0)/float(scenario.world_size[1])) * zoom

func world_center() -> Vector2:
	return Vector2(scenario.world_size[0],scenario.world_size[1])*0.5

func to_screen(point: Vector2) -> Vector2:
	return (point-camera_center)*map_scale()+size*0.5

func to_world(point: Vector2) -> Vector2:
	return (point-size*0.5)/map_scale()+camera_center

func focus_building(id: String, animated: bool = true) -> void:
	if not scenario.node_positions.has(id): return
	focus_id = id
	_move_camera(network_anchor(id),2.6,animated)

func center_map(animated: bool = true) -> void:
	focus_id = ""
	_move_camera(world_center(),1.0,animated)

func _move_camera(target: Vector2, scale_target: float, animated: bool) -> void:
	if camera_tween: camera_tween.kill()
	var seconds := UIkit.motion(0.5) if animated else 0.0
	if seconds > 0.0:
		camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		camera_tween.tween_property(self,"camera_center",target,seconds)
		camera_tween.tween_property(self,"zoom",scale_target,seconds)
		camera_tween.tween_method(func(_value: float): _update_camera(),0.0,1.0,seconds)
	else:
		camera_center = target
		zoom = scale_target
		_update_camera()

func _update_camera() -> void:
	pan = (world_center()-camera_center)*map_scale() if scenario != null else Vector2.ZERO
	view_changed.emit()
	queue_redraw()

func visual_road(id: String) -> PackedVector2Array:
	if has_city_art(): return CityMapProfiles.road(scenario,id)
	return scenario.road_points(id)

func network_anchor(id: String) -> Vector2:
	if has_city_art(): return CityMapProfiles.anchor(scenario,id)
	return CityMapProfiles.vector(scenario.node_positions[id])

func closure_fraction(id: String) -> float:
	return CityMapProfiles.layout(scenario).edges[id].closure_fraction if has_city_art() else 0.5

# Location pieces keep one readable screen size while the camera zooms.
func token_half() -> float:
	return clampf(16.0+7.0*map_scale(),22.0,31.0)

func token_rect(id: String) -> Rect2:
	var h := token_half()
	return Rect2(to_screen(network_anchor(id))-Vector2(h,h),Vector2(h,h)*2.0)

# Compatibility name: the selectable "building" is now the piece on the junction.
func building_rect(id: String) -> Rect2:
	return token_rect(id)

func _refresh_geometry() -> void:
	positions.clear()
	road_geometry.clear()
	for id in scenario.node_positions:
		positions[id] = to_screen(network_anchor(id))
	for id in state.edges:
		var points := PackedVector2Array()
		for point in visual_road(id): points.append(to_screen(point))
		road_geometry[id] = points
	radius = token_half()
	_place_annotations()

func _place_annotations() -> void:
	var public_status: Array = []
	for id in positions: public_status.append(_public_tags(id))
	var key := str([scenario.scenario_id,camera_center,zoom,size,public_status])
	if key == annotation_key: return
	annotation_key = key
	title_rects.clear()
	label_rects.clear()
	status_positions.clear()
	var occupied: Array[Rect2] = []
	for id in positions: occupied.append(token_rect(id).grow(6))
	# Place each name/status block beside its piece, clear of roads and other pieces.
	var ids: Array = positions.keys()
	ids.sort()
	for id in ids:
		var piece := token_rect(id)
		if not Rect2(Vector2.ZERO,size).intersects(piece): continue
		var name_width := _plate_width(state.shelters[id].display_name)
		var width := maxf(name_width,_chips_width(_status_chips(id)))
		var preferred := Rect2(Vector2(piece.end.x+10,piece.get_center().y-NAME_BLOCK*0.5),Vector2(width,NAME_BLOCK))
		var block := _free_annotation(preferred,occupied,piece.get_center())
		label_rects[id] = block
		title_rects[id] = Rect2(block.position,Vector2(name_width,NAME_PLATE))
		status_positions[id] = Vector2(block.position.x,block.position.y+NAME_PLATE+3)
		occupied.append(block.grow(4))

func _free_annotation(preferred: Rect2, occupied: Array[Rect2], landmark: Vector2) -> Rect2:
	var best := preferred
	var best_distance := INF
	var candidates: Array[Rect2] = []
	# Right, left, above, and below the piece first; then a widening search.
	var h := token_half()
	for offset in [Vector2.ZERO,Vector2(-(preferred.size.x+2*h+20),0),Vector2(-preferred.size.x*0.5-h-10,-(NAME_BLOCK*0.5+h+8)),Vector2(-preferred.size.x*0.5-h-10,NAME_BLOCK*0.5+h+8)]:
		var c := preferred
		c.position += offset
		candidates.append(c)
	for dy in range(-10,11):
		for dx in range(-10,11):
			var c := preferred
			c.position += Vector2(dx,dy)*18
			candidates.append(c)
	for candidate in candidates:
		candidate.position.x = clampf(candidate.position.x,6,maxf(6,size.x-candidate.size.x-6))
		candidate.position.y = clampf(candidate.position.y,6,maxf(6,size.y-candidate.size.y-6))
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

func _draw() -> void:
	if scenario == null or state == null: return
	_refresh_geometry()
	draw_rect(Rect2(Vector2.ZERO,size),UIkit.MAP)
	_draw_terrain()
	if not show_annotations: return
	_draw_roads()
	for id in positions: _draw_piece(id)
	for id in positions: _draw_label(id)
	_draw_animation()
	_draw_compass()

func _draw_terrain() -> void:
	var rect := Rect2(to_screen(Vector2.ZERO),Vector2(scenario.world_size[0],scenario.world_size[1])*map_scale())
	var texture := CityMapProfiles.terrain(scenario.scenario_id)
	# The board rests on the table: a thin base edge, then the terrain sheet.
	draw_rect(Rect2(rect.position+Vector2(0,PIECE_DEPTH+1),rect.size),UIkit.EDGE)
	if texture != null: draw_texture_rect(texture,rect,false,Color.WHITE)
	else: draw_rect(rect,UIkit.LAND)
	draw_rect(rect,UIkit.LINE_STRONG,false,1.0)

func _draw_compass() -> void:
	var plate := Rect2(size.x-46,12,34,62)
	draw_style_box(UIkit.box(UIkit.PANEL,UIkit.LINE,4,0),plate)
	var x := plate.get_center().x
	draw_line(Vector2(x,40),Vector2(x,66),UIkit.TEXT,1.5,true)
	draw_colored_polygon(PackedVector2Array([Vector2(x,36),Vector2(x-5,46),Vector2(x+5,46)]),UIkit.TEXT)
	_text(Vector2(x,31),"N",15,UIkit.TEXT)

# Road strokes: a pale casing, then a bold core. Widths are in screen pixels and
# grow modestly with the close-up; geometry and logical lengths are unchanged.
func road_core_width() -> float:
	return clampf(4.5+2.4*map_scale(),7.0,10.0)

func road_casing_width() -> float:
	return road_core_width()+6.0

func road_hit_radius() -> float:
	return maxf(10.0,road_casing_width()*0.5+4.0)

func shelter_ink(id: String) -> Color:
	if state.shelters[id].is_overrun: return UIkit.DANGER
	return UIkit.TEXT

func shelter_status_ink(id: String) -> Color:
	var shelter: ShelterState = state.shelters[id]
	if not shelter.is_overrun and shelter.monitor_known_pressure < 0: return UIkit.SECONDARY
	return UIkit.DANGER if shelter.is_overrun else UIkit.PROTECT

func _road_style(edge: EdgeState) -> Dictionary:
	var closed := edge.isolated
	var no_supply: bool = state.shelters[edge.from].is_overrun or state.shelters[edge.to].is_overrun or not (reachable.has(edge.from) and reachable.has(edge.to))
	var selected := edge.id == selected_edge
	var hovered := edge.id == hover_target or (key_active and has_focus() and edge.id == key_cursor)
	var ink := UIkit.DANGER if closed else (UIkit.ACTION if selected else (UIkit.ROAD_HOVER if hovered else UIkit.ROAD))
	return {"closed":closed,"no_supply":no_supply and not closed,"ink":ink,"selected":selected or hovered}

func _draw_roads() -> void:
	var width := road_core_width()
	for edge: EdgeState in state.edges.values():
		var points: PackedVector2Array = road_geometry[edge.id]
		var casing := UIkit.ACTION_TINT if edge.id == selected_edge else UIkit.ROAD_CASING
		draw_polyline(points,casing,road_casing_width()+(4.0 if edge.id == selected_edge else 0.0),true)
		for point in [points[0],points[points.size()-1]]: draw_circle(point,road_casing_width()*0.5,casing,true,-1,true)
	for edge: EdgeState in state.edges.values():
		var points: PackedVector2Array = road_geometry[edge.id]
		var style := _road_style(edge)
		if style.closed:
			for index in points.size()-1: draw_dashed_line(points[index],points[index+1],style.ink,width,14.0,true,true)
		elif style.no_supply:
			_dotted(points,style.ink,width*0.42,width*1.7)
		else: draw_polyline(points,style.ink,width,true)
		for path: Array in supply_paths:
			for index in maxi(0,path.size()-1):
				if edge.other_endpoint(path[index]) == path[index+1]:
					draw_polyline(points,UIkit.ACTION,width,true)
					_route_arrows(points,path[index] != edge.from)
		if edge.id == selected_edge:
			var mid := _point_on_path(points,closure_fraction(edge.id))
			draw_arc(mid,width+6,0,TAU,28,UIkit.ACTION,2.5,true)
		if dev_mode:
			_chip(_point_on_path(points,0.5)+Vector2(0,width+10),edge.id,UIkit.PANEL,UIkit.DANGER,UIkit.DANGER)
	for edge: EdgeState in state.edges.values():
		if edge.isolated or edge.id == preview_edge or edge.id == closing_edge: _draw_barricade(edge)

func _dotted(points: PackedVector2Array, color: Color, dot: float, gap: float) -> void:
	var total := 0.0
	for index in points.size()-1: total += points[index].distance_to(points[index+1])
	var steps := maxi(1,int(total/gap))
	for step in steps+1: draw_circle(_point_on_path(points,float(step)/steps),dot,color,true,-1,true)

func _route_arrows(points: PackedVector2Array, reverse: bool) -> void:
	for fraction in [0.35,0.65]:
		var at := _point_on_path(points,fraction)
		var ahead := _point_on_path(points,fraction+(-0.02 if reverse else 0.02))
		draw_set_transform(at,(ahead-at).angle())
		draw_polyline(PackedVector2Array([Vector2(-4,-4),Vector2(1,0),Vector2(-4,4)]),UIkit.ON_ACTION,2.0,true)
		draw_set_transform(Vector2.ZERO)

func _draw_barricade(edge: EdgeState) -> void:
	var points: PackedVector2Array = road_geometry[edge.id]
	var closed := edge.isolated
	var fraction := closure_fraction(edge.id)
	var center := _point_on_path(points,fraction)
	var direction := (_point_on_path(points,fraction+0.02)-_point_on_path(points,fraction-0.02)).angle()
	var drop := 0.0
	var grow := 1.0
	if edge.id == closing_edge and not UIkit.reduced_motion():
		var t := ease(clampf(animation_progress,0.0,1.0),0.35) # fast in, gentle settle
		drop = 14.0*(1.0-t)
		grow = lerpf(1.08,1.0,t)
	var ink := UIkit.DANGER if closed else UIkit.WARNING
	var piece := clampf(map_scale()*0.8,0.9,1.25)*grow
	draw_set_transform(center-Vector2(0,drop),direction+PI*0.5,Vector2.ONE*piece)
	var body := Rect2(-17,-8,34,16)
	draw_rect(Rect2(body.position+Vector2(0,PIECE_DEPTH),body.size),UIkit.DANGER_EDGE if closed else UIkit.EDGE)
	draw_rect(body,UIkit.PANEL)
	for x in [-11.0,-1.0,9.0]: draw_line(Vector2(x-3,7),Vector2(x+5,-7),ink,4.0,true)
	draw_rect(body,ink,false,2.0)
	draw_set_transform(Vector2.ZERO)
	var label := "Closed" if closed else ("Closing" if edge.id == closing_edge else "Preview")
	_chip(center+Vector2(0,-30*piece)-Vector2(0,drop),label,UIkit.DANGER if closed else UIkit.WARNING_TINT,UIkit.PANEL if closed else UIkit.WARNING,Color.TRANSPARENT,true)

# Public status only. Hidden pressure never reaches these chips.
func _public_tags(id: String) -> Array[String]:
	var tags: Array[String] = []
	for chip in _status_chips(id): tags.append(chip.text)
	return tags

func _status_chips(id: String) -> Array:
	var shelter: ShelterState = state.shelters[id]
	var chips: Array = []
	if shelter.is_overrun: chips.append({"text":"Overrun","fill":UIkit.DANGER,"ink":UIkit.PANEL,"line":Color.TRANSPARENT})
	elif shelter.monitor_known_pressure >= 0: chips.append({"text":"Monitor: %d" % shelter.monitor_known_pressure,"fill":UIkit.PANEL,"ink":UIkit.PROTECT,"line":UIkit.PROTECT})
	else: chips.append({"text":"? Unobserved","fill":UIkit.SUNKEN,"ink":UIkit.SECONDARY,"line":UIkit.LINE})
	if state.depots.has(id): chips.append({"text":"%d supply" % state.depots[id].supply_remaining,"fill":UIkit.PANEL,"ink":UIkit.TEXT,"line":UIkit.LINE_STRONG})
	if shelter.is_monitored and shelter.monitor_known_pressure < 0 and not shelter.is_overrun: chips.append({"text":"Monitor","fill":UIkit.PANEL,"ink":UIkit.PROTECT,"line":UIkit.PROTECT})
	if shelter.shielded_this_round: chips.append({"text":"Shield","fill":UIkit.PROTECT,"ink":UIkit.PANEL,"line":Color.TRANSPARENT})
	if not reachable.has(id) and not shelter.is_overrun: chips.append({"text":"No supply route","fill":UIkit.WARNING_TINT,"ink":UIkit.WARNING,"line":Color.TRANSPARENT})
	return chips

func _chip_width(text: String) -> float:
	return ceilf(UIkit.HEADING_FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,UIkit.MAP_TAG).x)+14.0

func _chips_width(chips: Array) -> float:
	var width := 0.0
	for chip in chips: width += _chip_width(chip.text)+4.0
	return maxf(0.0,width-4.0)

func _plate_width(text: String) -> float:
	return ceilf(UIkit.HEADING_FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,UIkit.MAP_NAME).x)+16.0

# Pieces: shelters are small house tiles, depots square crates. Both sit exactly
# on the junction; roads end beneath them. A thin base gives each piece depth.
func _piece_polygon(id: String, h: float) -> PackedVector2Array:
	if state.depots.has(id):
		return PackedVector2Array([Vector2(-h*0.9,-h*0.86),Vector2(h*0.9,-h*0.86),Vector2(h*0.9,h*0.86),Vector2(-h*0.9,h*0.86)])
	return PackedVector2Array([Vector2(-h*0.86,-h*0.28),Vector2(0,-h),Vector2(h*0.86,-h*0.28),Vector2(h*0.86,h*0.86),Vector2(-h*0.86,h*0.86)])

func _draw_piece(id: String) -> void:
	var rect := token_rect(id)
	if not Rect2(Vector2.ZERO,size).grow(40).intersects(rect): return
	var shelter: ShelterState = state.shelters[id]
	var h := token_half()
	var center := rect.get_center()
	var pop := 1.0
	if id == pop_id and pop_t < 1.0: pop = 1.0+0.1*sin(PI*pop_t)
	var selected := id == selected_shelter
	if selected: _ring(center,h*pop+7,UIkit.ACTION,3.0)
	elif id == hover_target: _ring(center,h+6,Color(UIkit.ACTION,0.6),2.0)
	if key_active and has_focus() and id == key_cursor: _ring(center,h+11,UIkit.ACTION,2.0,true)
	if preview_lost.has(id): _ring(center,h+9,UIkit.WARNING,3.0,true)
	var overrun := shelter.is_overrun
	var face := UIkit.DANGER if overrun else UIkit.PANEL
	var outline := UIkit.DANGER_EDGE if overrun else UIkit.TEXT
	var polygon := _piece_polygon(id,h)
	draw_set_transform(center+Vector2(0,PIECE_DEPTH),0,Vector2.ONE*pop)
	draw_colored_polygon(polygon,UIkit.DANGER_EDGE if overrun else UIkit.EDGE)
	draw_set_transform(center,0,Vector2.ONE*pop)
	draw_colored_polygon(polygon,face)
	var closed_outline := polygon.duplicate()
	closed_outline.append(polygon[0])
	draw_polyline(closed_outline,outline,2.0,true)
	if state.depots.has(id):
		# Crate planks mark a depot without relying on colour.
		draw_line(Vector2(-h*0.9,-h*0.5),Vector2(h*0.9,-h*0.5),outline,1.5,true)
		draw_line(Vector2(-h*0.9,h*0.5),Vector2(h*0.9,h*0.5),outline,1.5,true)
	draw_set_transform(Vector2.ZERO)
	var label_size := int(clampf(h*0.95,20,28))
	var text_center := center+Vector2(0,(h*0.18 if not state.depots.has(id) else 0.0)*pop)
	_text(text_center+Vector2(0,label_size*0.36),id,label_size,UIkit.PANEL if overrun else UIkit.TEXT)
	if overrun: _cross_badge(center+Vector2(h*0.82,-h*0.78)*pop,h*0.36)
	elif shelter.shielded_this_round: _shield_badge(center+Vector2(h*0.82,-h*0.78)*pop,h*0.36)
	if shelter.is_monitored and not overrun: _monitor_badge(center+Vector2(-h*0.82,-h*0.78)*pop,h*0.34)
	if dev_mode: _chip(center+Vector2(0,h+16),"DEV P%d" % shelter.zombie_pressure,UIkit.PANEL,UIkit.DANGER,UIkit.DANGER,true)

func _draw_label(id: String) -> void:
	if not label_rects.has(id): return
	var block: Rect2 = label_rects[id]
	var piece := token_rect(id)
	var plate: Rect2 = title_rects[id]
	# Short leader line only when the label had to move away from its piece.
	if not block.intersects(piece.grow(16)):
		var center := piece.get_center()
		var target := center.clamp(block.position,block.end)
		draw_line(center+(target-center).normalized()*(token_half()+4),target,UIkit.LINE_STRONG,1.5,true)
	draw_style_box(UIkit.box(UIkit.PANEL,UIkit.LINE_STRONG,4,0),Rect2(_pixel_aligned(plate.position),plate.size))
	_draw_caption(UIkit.HEADING_FONT,plate.position+Vector2(8,20),state.shelters[id].display_name,UIkit.MAP_NAME,UIkit.TEXT)
	var at: Vector2 = status_positions[id]
	for chip in _status_chips(id):
		var width := _chip_width(chip.text)
		_chip_at(Rect2(at,Vector2(width,CHIP_HEIGHT)),chip.text,chip.fill,chip.ink,chip.line)
		at.x += width+4

func _chip_at(rect: Rect2, value: String, fill: Color, ink: Color, line: Color) -> void:
	rect.position = _pixel_aligned(rect.position)
	draw_style_box(UIkit.box(fill,line,11,0),rect)
	_draw_caption(UIkit.HEADING_FONT,rect.position+Vector2(7,16),value,UIkit.MAP_TAG,ink)

# Centered chip (used by barricades, deliveries, and dev labels).
func _chip(at: Vector2, value: String, fill: Color, ink: Color, line: Color = Color.TRANSPARENT, large: bool = false) -> void:
	var font_size := UIkit.MAP_NAME if large else UIkit.MAP_TAG
	var width := ceilf(UIkit.HEADING_FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)+14.0
	var rect := Rect2(_pixel_aligned(at-Vector2(width*0.5,CHIP_HEIGHT*0.5)),Vector2(width,CHIP_HEIGHT))
	draw_style_box(UIkit.box(fill,line,11,0),rect)
	_draw_caption(UIkit.HEADING_FONT,rect.position+Vector2(7,16),value,font_size,ink)

func _ring(center: Vector2, r: float, color: Color, width: float, dashed: bool = false) -> void:
	if not dashed:
		draw_arc(center,r,0,TAU,48,color,width,true)
		return
	for segment in 16:
		var a := TAU*segment/16.0
		draw_arc(center,r,a,a+TAU/32.0,6,color,width,true)

func _badge(center: Vector2, r: float, fill: Color, line: Color) -> void:
	draw_circle(center,r+1.5,line,true,-1,true)
	draw_circle(center,r,fill,true,-1,true)

func _cross_badge(center: Vector2, r: float) -> void:
	_badge(center,r,UIkit.PANEL,UIkit.DANGER_EDGE)
	var d := r*0.5
	draw_line(center+Vector2(-d,-d),center+Vector2(d,d),UIkit.DANGER,2.5,true)
	draw_line(center+Vector2(-d,d),center+Vector2(d,-d),UIkit.DANGER,2.5,true)

func _shield_badge(center: Vector2, r: float) -> void:
	_badge(center,r,UIkit.PROTECT,UIkit.PANEL)
	var s := r*0.62
	var shape := PackedVector2Array([center+Vector2(-s,-s*0.8),center+Vector2(s,-s*0.8),center+Vector2(s*0.85,s*0.2),center+Vector2(0,s),center+Vector2(-s*0.85,s*0.2),center+Vector2(-s,-s*0.8)])
	draw_polyline(shape,UIkit.PANEL,1.8,true)

func _monitor_badge(center: Vector2, r: float) -> void:
	_badge(center,r,UIkit.PANEL,UIkit.PROTECT)
	draw_circle(center+Vector2(0,r*0.3),r*0.22,UIkit.PROTECT,true,-1,true)
	draw_arc(center+Vector2(0,r*0.3),r*0.6,PI*1.2,PI*1.8,10,UIkit.PROTECT,1.6,true)

func hit_test(point: Vector2) -> String:
	if scenario == null: return ""
	_refresh_geometry()
	for id in positions:
		if token_rect(id).grow(4).has_point(point): return id
	for id in label_rects:
		if label_rects[id].has_point(point): return id
	var nearest := ""
	var distance := road_hit_radius()
	for id in road_geometry:
		var points: PackedVector2Array = road_geometry[id]
		for index in points.size()-1:
			var candidate := Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1]).distance_to(point)
			if candidate < distance:
				distance = candidate
				nearest = id
	return nearest

func pop_piece(id: String) -> void:
	if pop_tween: pop_tween.kill()
	pop_id = id
	var seconds := UIkit.motion(0.16)
	if seconds <= 0.0:
		pop_t = 1.0
		queue_redraw()
		return
	pop_t = 0.0
	pop_tween = create_tween()
	pop_tween.tween_property(self,"pop_t",1.0,seconds)

func _key_targets() -> Array:
	var ids: Array = state.shelters.keys()
	ids.sort()
	var roads: Array = state.edges.keys()
	roads.sort()
	return ids+roads

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		key_active = false
		if event.pressed: press_position = event.position
		elif event.position.distance_to(press_position)<8:
			var target := hit_test(event.position)
			_emit_selection(target)
		accept_event()
	elif event is InputEventMouseMotion:
		var target := hit_test(event.position)
		if target != hover_target:
			hover_target = target
			queue_redraw()
	elif event is InputEventKey and event.pressed and state != null:
		var step := 0
		if event.is_action("ui_right") or event.is_action("ui_down"): step = 1
		elif event.is_action("ui_left") or event.is_action("ui_up"): step = -1
		if step != 0:
			var targets := _key_targets()
			var index := targets.find(key_cursor)
			key_cursor = targets[posmod(index+step if index >= 0 else 0,targets.size())]
			key_active = true
			queue_redraw()
			accept_event()
		elif event.is_action("ui_accept") and key_cursor != "":
			key_active = true
			_emit_selection(key_cursor)
			accept_event()

func _emit_selection(target: String) -> void:
	if state.shelters.has(target): shelter_selected.emit(target)
	elif state.edges.has(target): edge_selected.emit(target)
	else: background_selected.emit()

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

# Sequence durations are unchanged and identical for every action and condition.
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

func _crate(at: Vector2, s: float) -> void:
	var body := Rect2(at-Vector2(9,8)*s,Vector2(18,16)*s)
	draw_rect(Rect2(body.position+Vector2(0,2.5*s),body.size),UIkit.EDGE)
	draw_rect(body,UIkit.CRATE)
	draw_rect(body,UIkit.TEXT,false,1.5)
	draw_line(Vector2(at.x,body.position.y),Vector2(at.x,body.end.y),UIkit.TEXT,1.5)

func _draw_animation() -> void:
	var still := UIkit.reduced_motion()
	var s := clampf(map_scale()*0.9,1.05,1.4)
	if animation_kind == "delivery":
		for path: PackedVector2Array in animation_paths:
			var route := PackedVector2Array()
			for point in path: route.append(to_screen(point))
			if route.size() > 1: draw_polyline(route,Color(UIkit.ACTION,0.55),3.0,true)
			if still: _crate(route[route.size()-1]+Vector2(0,-token_half()-14),s)
			else: _crate(to_screen(_point_on_path(path,animation_progress)),s)
	elif animation_kind == "arrival":
		var t := 1.0 if still else animation_progress
		for id in delivery_targets:
			var center: Vector2 = positions[id]
			var land := ease(clampf(t/0.4,0.0,1.0),0.4)
			_crate(center+Vector2(0,-token_half()-14+(1.0-land)*-12.0),s)
			if not still: _ring(center,token_half()+6+t*12,Color(UIkit.ACTION,1.0-t),2.5)
			else: _ring(center,token_half()+7,UIkit.ACTION,2.0)
			_chip(center+Vector2(0,token_half()+18),"Delivered",UIkit.PANEL,UIkit.TEXT,UIkit.LINE_STRONG)
	elif animation_kind == "outbreak":
		for path: PackedVector2Array in animation_paths:
			var source := to_screen(path[0])
			_ring(source,token_half()+9,UIkit.DANGER,2.5)
			if still:
				var route := PackedVector2Array()
				for point in path: route.append(to_screen(point))
				for index in route.size()-1: draw_dashed_line(route[index],route[index+1],UIkit.DANGER,3.0,8.0,true,true)
			elif animation_progress < 0.98:
				var at := to_screen(_point_on_path(path,animation_progress))
				var ahead := to_screen(_point_on_path(path,minf(1,animation_progress+0.03)))
				draw_set_transform(at,(ahead-at).angle())
				draw_polyline(PackedVector2Array([Vector2(-8,-6),Vector2(1,0),Vector2(-8,6)]),UIkit.DANGER,3.5,true)
				draw_set_transform(Vector2.ZERO)
			# Only react to the public installed shield, never to a hidden calculation.
			for id in positions:
				if state.shelters[id].shielded_this_round and network_anchor(id).distance_to(path[path.size()-1]) < 0.01 and (still or animation_progress > 0.7):
					var center: Vector2 = positions[id]
					_ring(center,token_half()+7,UIkit.PROTECT,3.0)
					_chip(center+Vector2(0,-token_half()-22),"Blocked",UIkit.PROTECT,UIkit.PANEL,Color.TRANSPARENT,true)
	elif animation_kind == "reveal":
		for id in flash_nodes:
			var at: Vector2 = positions[id]
			_draw_overrun_mark(at,token_half()+6,1.0 if still else animation_progress)
			_chip(at+Vector2(0,-token_half()-22),"Overrun",UIkit.DANGER,UIkit.PANEL,Color.TRANSPARENT,true)

func _draw_overrun_mark(at: Vector2, extent: float, progress: float = 1.0) -> void:
	var end := lerpf(-extent,extent,progress)
	draw_line(at-Vector2(extent,extent),at+Vector2(end,end),UIkit.DANGER,4.0,true)
	draw_line(at+Vector2(-extent,extent),at+Vector2(end,-end),UIkit.DANGER,4.0,true)

# Round captions in render-target pixels, not logical map units. Camera geometry
# stays continuous, and font size stays independent of zoom.
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
