class_name MenuNetwork
extends Control

# Decorative title-screen network: plain circles and lines arranged around the
# edges of the screen. Positions are generated from a fixed seed and have no
# relation to any scenario, hidden state, solution, or study condition. Nothing
# here is logged, uploaded, or sent to a model.
#
# Protected areas are read from the live global rects of registered controls on
# every frame and again at draw time, so they follow resizing, language changes
# and stage changes. Circles are pushed out of those areas (with room for the
# hover/spring enlargement) and any line that would cross one is not drawn.

const SEED := 20261008
const EDGE_MARGIN := 20.0
const MAX_GROW := 1.6 # largest visual scale (hover + spring overshoot)
const KEEP_GAP := 6.0 # extra clearance beyond the enlarged circle
const HIT_SLOP := 14.0
const SPRING := 26.0
const DAMPING := 7.5
const SCALE_SPRING := 210.0
const SCALE_DAMPING := 13.0

const IDLE_EDGE := Color(0.94,0.91,0.81,0.13)
const NEAR_EDGE := Color(0.95,0.77,0.47,0.30)
const HOT_EDGE := Color(0.95,0.77,0.47,0.78)
const TONES := [Color("7d8e9c"),Color("d9d1bb"),Color("f2c477")]
const TONE_ALPHA := [0.62,0.5,0.86]

class Dot:
	var home := Vector2.ZERO
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var radius := 6.0
	var tone := 0
	var phase := Vector2.ZERO
	var freq := Vector2.ONE
	var amp := 8.0
	var scale := 1.0
	var scale_vel := 0.0
	var hidden := false
	var neighbors: Array[int] = []

var dots: Array[Dot] = []
var edges: Array[Vector2i] = []
# [{node: Control, pad: float}] — real interface bounds to keep clear.
var protected: Array = []
var hovered := -1
var dragging := -1
var drag_offset := Vector2.ZERO
var drag_velocity := Vector2.ZERO
var last_drag_time := 0
var paused := false
var time := 0.0
var fade := 0.0
var signature := ""
var built_size := Vector2.ZERO
var physical_scale := 1.0
# Test/inspection counters from the most recent draw.
var drawn_dots := 0
var drawn_edges := 0
var violations := 0

func _init() -> void:
	name = "MenuNetwork"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func protect(control: Control, pad: float = 28.0) -> void:
	for entry in protected:
		if entry.node == control:
			entry.pad = pad
			return
	protected.append({"node":control,"pad":pad})

func clear_protected() -> void:
	protected.clear()
	signature = ""

func set_paused(value: bool) -> void:
	if paused == value: return
	paused = value
	mouse_filter = Control.MOUSE_FILTER_IGNORE if paused else Control.MOUSE_FILTER_STOP
	_end_drag()
	hovered = -1
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	signature = "" # rebuild around any overlay; snapped while paused
	queue_redraw()

func motion_reduced() -> bool:
	return UIkit.reduced_motion

func protected_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var to_local := get_global_transform().affine_inverse()
	for entry in protected:
		var control = entry.node
		if not is_instance_valid(control) or not control.is_visible_in_tree(): continue
		var rect: Rect2 = to_local * control.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0: continue
		result.append(rect.grow(entry.pad))
	return result

func _keep_radius(dot: Dot) -> float:
	return dot.radius*MAX_GROW + KEEP_GAP

func _process(delta: float) -> void:
	delta = minf(delta,0.05)
	var rects := protected_rects()
	_refresh_layout(rects)
	if dots.is_empty():
		queue_redraw()
		return
	var still := motion_reduced() or paused
	if not paused: fade = 1.0 if motion_reduced() else minf(1.0,fade+delta/0.6)
	if not still: time += delta
	for i in dots.size():
		var dot := dots[i]
		var target_scale := 1.35 if (i == hovered or i == dragging) and not paused else 1.0
		if i == dragging:
			dot.scale = target_scale if still else dot.scale
			if not still: _scale_step(dot,target_scale,delta)
			continue
		var target := dot.home + _sympathy(i)
		if still:
			# Static network: no drift, spring or overshoot.
			dot.pos = target
			dot.vel = Vector2.ZERO
			dot.scale = target_scale
			dot.scale_vel = 0.0
		else:
			target += Vector2(sin(time*dot.freq.x+dot.phase.x),cos(time*dot.freq.y+dot.phase.y))*dot.amp
			dot.vel += (target-dot.pos)*SPRING*delta
			dot.vel -= dot.vel*minf(1.0,DAMPING*delta)
			dot.pos += dot.vel*delta
			_scale_step(dot,target_scale,delta)
		dot.pos = _keep_out(dot.pos,_keep_radius(dot),rects)
	queue_redraw()

func _scale_step(dot: Dot, target: float, delta: float) -> void:
	dot.scale_vel += (target-dot.scale)*SCALE_SPRING*delta
	dot.scale_vel -= dot.scale_vel*minf(1.0,SCALE_DAMPING*delta)
	dot.scale = clampf(dot.scale+dot.scale_vel*delta,0.7,MAX_GROW)

# Neighbors lean slightly toward a dragged node so the web feels connected.
func _sympathy(index: int) -> Vector2:
	if dragging < 0 or dragging >= dots.size() or not dots[dragging].neighbors.has(index): return Vector2.ZERO
	var held := dots[dragging]
	return (held.pos-held.home).limit_length(160.0)*0.16

# Rebuild homes whenever the viewport or any protected bound changes.
func _refresh_layout(rects: Array[Rect2]) -> void:
	if size.x < 64 or size.y < 64 or rects.is_empty(): return
	var parts := PackedStringArray([str(Vector2i(size))])
	for rect in rects: parts.append("%d,%d,%d,%d" % [roundi(rect.position.x/8),roundi(rect.position.y/8),roundi(rect.size.x/8),roundi(rect.size.y/8)])
	var key := "|".join(parts)
	if key == signature: return
	signature = key
	_rebuild(rects)

func _window_scale() -> float:
	var logical := get_viewport_rect().size
	if not is_inside_tree() or logical.x <= 0: return 1.0
	var window := Vector2(get_tree().root.size)
	if window.x <= 0: return 1.0
	return clampf(minf(window.x/logical.x,window.y/logical.y),0.15,4.0)

func _rebuild(rects: Array[Rect2]) -> void:
	physical_scale = _window_scale()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var bounds := Rect2(Vector2.ZERO,size).grow(-EDGE_MARGIN)
	# Estimate free area (logical) by sampling, then size the network by
	# physical area so small embeds get a sparser, calmer web.
	var free_hits := 0
	var probes := 400
	for n in probes:
		var p := Vector2(rng.randf_range(bounds.position.x,bounds.end.x),rng.randf_range(bounds.position.y,bounds.end.y))
		if not _inside_any(p,24.0,rects): free_hits += 1
	var free_area := bounds.get_area()*float(free_hits)/probes
	var physical_free := free_area*physical_scale*physical_scale
	var count := clampi(int(physical_free/15000.0),8,30)
	if physical_free < 60000.0: count = clampi(int(physical_free/9000.0),0,8)
	var spacing := sqrt(maxf(free_area,1.0)/maxf(count,1))*0.72
	var homes: Array[Vector2] = []
	var radii: Array[float] = []
	# Keep earlier homes that are still clear so a stage or language change only
	# moves the nodes it has to; new ones fill the remaining space.
	var ratio := size/(built_size if built_size != Vector2.ZERO else size)
	var sources: Array[int] = []
	for source in dots.size():
		var old := dots[source]
		if homes.size() >= count: break
		var kept: Vector2 = old.home*ratio
		var keep_old := old.radius*MAX_GROW+KEEP_GAP
		if not bounds.grow(-keep_old).has_point(kept) or _inside_any(kept,keep_old+10.0,rects): continue
		var close := false
		for other in homes:
			if other.distance_to(kept) < spacing*0.6:
				close = true
				break
		if close: continue
		homes.append(kept)
		radii.append(old.radius)
		sources.append(source)
	var attempts := 0
	while homes.size() < count and attempts < 3000:
		attempts += 1
		if attempts % 500 == 0: spacing *= 0.85
		var radius := rng.randf_range(4.5,9.5) if rng.randf() < 0.75 else rng.randf_range(10.0,13.0)
		var keep := radius*MAX_GROW+KEEP_GAP
		var p := Vector2(rng.randf_range(bounds.position.x+keep,bounds.end.x-keep),rng.randf_range(bounds.position.y+keep,bounds.end.y-keep))
		if _inside_any(p,keep+10.0,rects): continue
		var crowded := false
		for other in homes:
			if other.distance_to(p) < spacing:
				crowded = true
				break
		if crowded: continue
		homes.append(p)
		radii.append(radius)
		sources.append(-1)
	var previous := dots
	var old_size := built_size if built_size != Vector2.ZERO else size
	var snap := paused or motion_reduced() or previous.is_empty()
	var spare: Array[int] = []
	for j in previous.size():
		if not sources.has(j): spare.append(j)
	var new_dragging := -1
	var new_hovered := -1
	dots = []
	for i in homes.size():
		var dot := Dot.new()
		dot.home = homes[i]
		dot.radius = radii[i]
		dot.tone = 2 if rng.randf() < 0.18 else (1 if rng.randf() < 0.45 else 0)
		dot.phase = Vector2(rng.randf()*TAU,rng.randf()*TAU)
		dot.freq = Vector2(rng.randf_range(0.18,0.34),rng.randf_range(0.16,0.3))
		dot.amp = rng.randf_range(4.0,10.0)
		var source := sources[i]
		if source < 0 and not spare.is_empty():
			# A new home is reached by the nearest displaced node, which migrates there.
			var best := 0
			for k in spare.size():
				if previous[spare[k]].pos.distance_to(dot.home) < previous[spare[best]].pos.distance_to(dot.home): best = k
			source = spare[best]
			spare.remove_at(best)
			dot.radius = previous[source].radius
		if source >= 0:
			var old := previous[source]
			dot.tone = old.tone
			dot.phase = old.phase
			dot.freq = old.freq
			dot.amp = old.amp
			if source == dragging: new_dragging = i
			if source == hovered: new_hovered = i
			if not snap or source == dragging:
				dot.pos = old.pos*(size/old_size)
				dot.vel = old.vel
				dot.scale = old.scale
			else:
				dot.pos = dot.home
		else:
			dot.pos = dot.home
		dots.append(dot)
	built_size = size
	# An active drag survives a rebuild while its node does.
	if dragging >= 0 and new_dragging < 0: drag_velocity = Vector2.ZERO
	dragging = new_dragging
	if dragging >= 0: dots[dragging].pos = _keep_out(dots[dragging].pos,_keep_radius(dots[dragging]),rects)
	hovered = new_hovered
	_connect(rects,spacing)

# Up to two nearest neighbors each, degree ≤ 3, and never across protected areas.
func _connect(rects: Array[Rect2], spacing: float) -> void:
	edges.clear()
	var degree: Array[int] = []
	degree.resize(dots.size())
	degree.fill(0)
	var limit := spacing*2.3
	for i in dots.size():
		var order: Array = []
		for j in dots.size():
			if j != i: order.append([dots[i].home.distance_to(dots[j].home),j])
		order.sort_custom(func(a,b): return a[0] < b[0])
		var added := 0
		for pair in order:
			if added >= 2 or pair[0] > limit: break
			var j: int = pair[1]
			var key := Vector2i(mini(i,j),maxi(i,j))
			if edges.has(key):
				added += 1
				continue
			if degree[i] >= 3 or degree[j] >= 3: continue
			if _segment_blocked(dots[i].home,dots[j].home,rects): continue
			edges.append(key)
			degree[i] += 1
			degree[j] += 1
			added += 1
	# A lone dot links to its nearest clear neighbor so no circle floats unattached.
	for i in dots.size():
		if degree[i] > 0: continue
		var best := -1
		var best_distance := spacing*3.5
		for j in dots.size():
			var distance := dots[i].home.distance_to(dots[j].home)
			if j != i and distance < best_distance and degree[j] < 4 and not _segment_blocked(dots[i].home,dots[j].home,rects):
				best = j
				best_distance = distance
		if best >= 0:
			edges.append(Vector2i(mini(i,best),maxi(i,best)))
			degree[i] += 1
			degree[best] += 1
	for dot in dots: dot.neighbors.clear()
	for edge in edges:
		dots[edge.x].neighbors.append(edge.y)
		dots[edge.y].neighbors.append(edge.x)

func _inside_any(p: Vector2, radius: float, rects: Array[Rect2]) -> bool:
	for rect in rects:
		if rect.grow(radius).has_point(p): return true
	return false

func _keep_out(p: Vector2, radius: float, rects: Array[Rect2]) -> Vector2:
	var bounds := Rect2(Vector2.ZERO,size).grow(-radius)
	for attempt in 4:
		var moved := false
		for rect in rects:
			var area := rect.grow(radius)
			if not area.has_point(p): continue
			var left := p.x-area.position.x
			var right := area.end.x-p.x
			var top := p.y-area.position.y
			var bottom := area.end.y-p.y
			var nearest := minf(minf(left,right),minf(top,bottom))
			if nearest == left: p.x = area.position.x-0.5
			elif nearest == right: p.x = area.end.x+0.5
			elif nearest == top: p.y = area.position.y-0.5
			else: p.y = area.end.y+0.5
			moved = true
		if bounds.size.x > 0 and bounds.size.y > 0:
			p = p.clamp(bounds.position,bounds.end)
		if not moved: break
	return p

func _segment_blocked(a: Vector2, b: Vector2, rects: Array[Rect2]) -> bool:
	for rect in rects:
		var area := rect.grow(2.0)
		if area.has_point(a) or area.has_point(b): return true
		var corners := [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]
		for k in 4:
			if Geometry2D.segment_intersects_segment(a,b,corners[k],corners[(k+1)%4]) != null: return true
	return false

func _hit(point: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for i in dots.size():
		var dot := dots[i]
		if dot.hidden: continue
		var distance := dot.pos.distance_to(point)
		if distance <= maxf(dot.radius*1.35,dot.radius+HIT_SLOP) and distance < best_distance:
			best = i
			best_distance = distance
	return best

func _gui_input(event: InputEvent) -> void:
	if paused or dots.is_empty(): return
	if event is InputEventMouseMotion:
		if dragging >= 0:
			var dot := dots[dragging]
			var before := dot.pos
			dot.pos = _keep_out(event.position+drag_offset,_keep_radius(dot),protected_rects())
			var now := Time.get_ticks_msec()
			var elapsed := maxf((now-last_drag_time)/1000.0,0.008)
			drag_velocity = drag_velocity.lerp((dot.pos-before)/elapsed,0.5)
			last_drag_time = now
			accept_event()
		else:
			_set_hover(_hit(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var index := _hit(event.position)
			if index < 0: return
			dragging = index
			hovered = index
			var dot := dots[index]
			drag_offset = dot.pos-event.position
			drag_velocity = Vector2.ZERO
			last_drag_time = Time.get_ticks_msec()
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			if not motion_reduced():
				# Small spring reaction: the node pops and its neighbors twitch away.
				dot.scale_vel += 7.0
				for other in dot.neighbors:
					var away := (dots[other].pos-dot.pos).normalized()
					dots[other].vel += away*70.0
			accept_event()
		elif dragging >= 0:
			_end_drag()
			_set_hover(_hit(event.position))
			accept_event()

func _end_drag() -> void:
	if dragging >= 0 and dragging < dots.size() and not motion_reduced() and not paused:
		dots[dragging].vel = drag_velocity.limit_length(700.0)
	dragging = -1
	drag_velocity = Vector2.ZERO
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hovered >= 0 else Control.CURSOR_ARROW

func _set_hover(index: int) -> void:
	if index == hovered: return
	hovered = index
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if index >= 0 else Control.CURSOR_ARROW
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and dragging < 0: _set_hover(-1)
	elif what == NOTIFICATION_RESIZED: queue_redraw()

func _draw() -> void:
	drawn_dots = 0
	drawn_edges = 0
	violations = 0
	if dots.is_empty() or fade <= 0.0: return
	var rects := protected_rects()
	# Final guard at draw time with the latest layout: anything that cannot be
	# placed clear of the interface is simply not drawn this frame.
	for dot in dots:
		dot.pos = _keep_out(dot.pos,_keep_radius(dot),rects)
		dot.hidden = _inside_any(dot.pos,dot.radius*MAX_GROW+1.0,rects)
	var focus := dragging if dragging >= 0 else hovered
	for edge in edges:
		var a := dots[edge.x]
		var b := dots[edge.y]
		if a.hidden or b.hidden or _segment_blocked(a.pos,b.pos,rects): continue
		var hot := focus >= 0 and (edge.x == focus or edge.y == focus)
		var color: Color = HOT_EDGE if hot else IDLE_EDGE
		draw_line(a.pos,b.pos,Color(color,color.a*fade),2.0 if hot else 1.25,true)
		drawn_edges += 1
	for i in dots.size():
		var dot := dots[i]
		if dot.hidden: continue
		var tone: Color = TONES[dot.tone]
		var alpha: float = TONE_ALPHA[dot.tone]
		var lit := i == focus
		var near := focus >= 0 and dots[focus].neighbors.has(i)
		if lit: alpha = 1.0
		elif near: alpha = minf(1.0,alpha+0.2)
		var radius := dot.radius*clampf(dot.scale,0.7,MAX_GROW)
		draw_circle(dot.pos,radius,Color(tone,alpha*fade),true,-1.0,true)
		if lit: draw_circle(dot.pos,radius+4.0,Color(UIkit.AMBER,0.8*fade),false,1.5,true)
		drawn_dots += 1
		if _inside_any(dot.pos,radius+(5.5 if lit else 0.0),rects): violations += 1

# Strict check used by tests: drawn geometry against the unpadded control rects.
func content_violations() -> int:
	var count := 0
	var raw: Array[Rect2] = []
	var to_local := get_global_transform().affine_inverse()
	for entry in protected:
		var control = entry.node
		if is_instance_valid(control) and control.is_visible_in_tree(): raw.append(to_local*control.get_global_rect())
	for dot in dots:
		if not dot.hidden and _inside_any(dot.pos,dot.radius*MAX_GROW+5.5,raw): count += 1
	for edge in edges:
		var a := dots[edge.x]
		var b := dots[edge.y]
		if a.hidden or b.hidden: continue
		# Lines that are drawn must clear the padded areas, hence the raw ones.
		if not _segment_blocked(a.pos,b.pos,protected_rects()) and _segment_blocked(a.pos,b.pos,raw): count += 1
	return count
