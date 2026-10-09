class_name WoodlandArt
extends RefCounted

# Pure presentation. Inputs are public geometry, a stable A–H ID and public
# flags; this artist has no access to pressure, AI conditions or game logic.
const PAD := 800
const SCENERY_PAD := 320
static var terrain_cache: Dictionary = {}
static var sprites: Dictionary = {}
static var lamp: Texture2D
static var halo: Texture2D

# Sprite-local ground/lantern coordinates. Shared by art, camera, hit targets,
# lights and the QA overlay; none are legacy building/driveway coordinates.
static func metadata(variant: int) -> Dictionary:
	var grounds := [Vector2(32,87),Vector2(32,87),Vector2(32,88),Vector2(32,87),Vector2(32,87),Vector2(32,88),Vector2(32,87),Vector2(32,87)]
	var lamps := [Vector2(32,17),Vector2(32,10),Vector2(32,12),Vector2(32,17),Vector2(32,17),Vector2(32,10),Vector2(32,17),Vector2(32,17)]
	return {"ground":grounds[variant],"lamp":lamps[variant]}

# Presentation terrain lives with the authoritative visual node/road mapping.
# One definition drives filled surfaces, shorelines, exclusion and bridge spans.
# Path scales form narrowing gullies; polygon features form complete lake basins.
static func terrain_definition(data: ScenarioData) -> Dictionary:
	if CityMapProfiles.has_profile(data.scenario_id):
		var layout := CityMapProfiles.layout(data)
		if layout.has("terrain"):
			var definition: Dictionary = layout.terrain.duplicate(true)
			for feature in definition.features:
				var points: Array = []
				for point in feature.points: points.append(CityMapProfiles.vector(point))
				feature.points = points
			for land in definition.get("landforms",[]):
				var points: Array = []
				for point in land.points: points.append(CityMapProfiles.vector(point))
				land.points = points
			return definition
	if data.scenario_id.begins_with("practice_demo"):
		return {"version":4,"seed":943,"stones":true,"features":[
			{"mode":"column","kind":"water","width":22.0,"bank":30.0,"points":[Vector2(488,-PAD),Vector2(490,160),Vector2(504,300),Vector2(490,420),Vector2(470,700+PAD)]}]}
	# Riverside keeps the original continuous river and scenery inside the old bounds.
	return {"version":4,"seed":943,"stones":false,"features":[
		{"mode":"column","kind":"water","width":30.0,"bank":38.0,"points":[],"sine":true}]}

static var feature_cache: Dictionary = {}

static func features(data: ScenarioData) -> Array:
	var key := str([data.scenario_id,data.world_size])
	if not feature_cache.has(key): feature_cache[key] = terrain_definition(data).features
	return feature_cache[key]

static func column_x(feature: Dictionary, data: ScenarioData, y: float) -> float:
	var curve: Array = feature.points
	if curve.is_empty(): return float(data.world_size[0])*0.63+sin(y/118.0)*22.0
	for i in curve.size()-1:
		if y <= curve[i+1].y:
			return lerpf(curve[i].x,curve[i+1].x,clampf((y-curve[i].y)/(curve[i+1].y-curve[i].y),0,1))
	return curve[-1].x

# Compatibility helper: x of the first column river (or the scenario's main obstacle line).
static func river_x(data: ScenarioData, y: float) -> float:
	for feature: Dictionary in features(data):
		if feature.mode == "column": return column_x(feature,data,y)
	return float(data.world_size[0])*0.5

static func feature_distance(feature: Dictionary, data: ScenarioData, at: Vector2, radius: float) -> float:
	if feature.mode == "column": return absf(at.x-column_x(feature,data,at.y))-radius
	var points: Array = feature.points
	var best := INF
	var polygon: bool = feature.mode == "polygon"
	for i in points.size() if polygon else points.size()-1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i+1)%points.size()]
		var closest := Geometry2D.get_closest_point_to_segment(at,a,b)
		var scale := 1.0
		if feature.has("scales"):
			scale = lerpf(feature.scales[i],feature.scales[i+1],a.distance_to(closest)/a.distance_to(b))
		best = minf(best,closest.distance_to(at)-(0.0 if polygon else radius*scale))
	if polygon:
		if Geometry2D.is_point_in_polygon(at,PackedVector2Array(points)): best = -best
		best -= radius
	return best

# Signed distance to solid ground: <= 0 inside water/ravine or its banks.
static func bank_distance(data: ScenarioData, at: Vector2) -> float:
	var best := INF
	for feature: Dictionary in features(data):
		best = minf(best,feature_distance(feature,data,at,float(feature.bank)))
	return best

static func obstacle_kind(data: ScenarioData, at: Vector2) -> String:
	var best := INF
	var kind := ""
	for feature: Dictionary in features(data):
		var d := feature_distance(feature,data,at,float(feature.bank))
		if d < best:
			best = d
			kind = feature.kind
	return kind

# Crossings of one road polyline: each span begins and ends on dry ground.
static func crossing_spans(data: ScenarioData, path: PackedVector2Array) -> Array:
	var spans: Array = []
	for i in path.size()-1:
		var a := path[i]
		var b := path[i+1]
		var steps := maxi(1,ceili(a.distance_to(b)/2.0))
		var start := -1
		for step in steps+1:
			var at := a.lerp(b,float(step)/steps)
			var on_bank := bank_distance(data,at) <= 10
			if on_bank and start < 0: start = maxi(0,step-1)
			if start >= 0 and (not on_bank or step == steps):
				spans.append(PackedVector2Array([a.lerp(b,float(start)/steps),at]))
				start = -1
	return spans

# Bridges come only from scenario data (ScenarioData.bridges). Geometry decides where the
# deck sits on that edge; it never decides whether an edge is a bridge.
static func bridge_spans(data: ScenarioData, paths: Dictionary) -> Dictionary:
	var output := {}
	for id in data.bridges:
		if paths.has(id): output[id] = crossing_spans(data,paths[id])
	return output

static func stamp(im: Image, centre: Vector2, radius: float, color: Color) -> void:
	# Pixel-art disc built from the same 4px rows as the legacy river.
	var r := maxf(radius,2.0)
	var y := -r
	while y < r:
		var half := sqrt(maxf(0.0,r*r-(y+2.0)*(y+2.0)))
		patch(im,Vector2(snappedf(centre.x-half,2),snappedf(centre.y+y,2)),Vector2(snappedf(half*2,2),4),color)
		y += 4.0

static func walk(feature: Dictionary, spacing: float) -> Array:
	# Evenly spaced [point, tangent] samples along a path feature.
	var out: Array = []
	var points: Array = feature.points
	var carry := 0.0
	for i in points.size()-1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i+1]
		var length := a.distance_to(b)
		var t := carry
		while t < length:
			out.append([a.lerp(b,t/length),(b-a).normalized(),lerpf(feature.scales[i],feature.scales[i+1],t/length) if feature.has("scales") else 1.0])
			t += spacing
		carry = t-length
	if not points.is_empty(): out.append([points[-1],(points[-1]-points[maxi(0,points.size()-2)]).normalized(),feature.scales[-1] if feature.has("scales") else 1.0])
	return out

static func paint_feature(im: Image, data: ScenarioData, feature: Dictionary, layer: int, noise: RandomNumberGenerator) -> void:
	var w := float(feature.width)
	var bank := float(feature.bank)
	var water: bool = feature.kind == "water"
	var h := int(data.world_size[1])
	if feature.mode == "polygon":
		var colors := [Color("263c3c"),Color("1d3134"),Color("102b36"),Color("193945")]
		paint_polygon(im,PackedVector2Array(feature.points),[bank,bank*0.4,0.0,-12.0][layer],colors[layer])
		return
	if feature.mode == "column":
		if layer != 0: return
		for y in range(-PAD,h+PAD,4):
			var x := snappedf(column_x(feature,data,y),2)
			patch(im,Vector2(x-bank,y),Vector2(bank*2,4),Color("263c3c"))
			patch(im,Vector2(x-w,y),Vector2(w*2,4),Color("102b36"))
			patch(im,Vector2(x-w*0.7,y),Vector2(w*1.4,4),Color("193945"))
			if y%24 == 0: patch(im,Vector2(x-18,y),Vector2(23,2),Color("315361"))
		return
	for sample in walk(feature,3.0):
		var p: Vector2 = sample[0]
		var jitter := noise.randf_range(-1.5,1.5)*float(sample[2])
		w = float(feature.width)*float(sample[2])
		bank = float(feature.bank)*float(sample[2])
		match layer:
			0: stamp(im,p,bank+jitter,Color("263c3c") if water else Color("3a3d35"))
			1: stamp(im,p,w+(bank-w)*0.45+jitter,Color("1d3134") if water else Color("252b2a"))
			2: stamp(im,p,w,Color("102b36") if water else Color("141b1d"))
			3: stamp(im,p+(Vector2(0,1.5) if water else Vector2(0,3)),w*(0.62 if water else 0.45),Color("193945") if water else Color("0b1113"))
	if layer == 1 and not water:
		# Rim rubble and lit north-facing ledge give the dry ravine a rocky edge.
		for sample in walk(feature,9.0):
			var p: Vector2 = sample[0]
			var n: Vector2 = Vector2(-sample[1].y,sample[1].x)
			bank = float(feature.bank)*float(sample[2])
			w = float(feature.width)*float(sample[2])
			for side in [-1.0,1.0]:
				var at: Vector2 = p+n*side*(bank-3.0+noise.randf_range(-2,2))
				patch(im,at,Vector2(noise.randi_range(2,4)*2,4),Color("4c4f45") if noise.randf() < 0.6 else Color("5d5d50"))
			patch(im,p-n*(w+2.0)+Vector2(0,-2),Vector2(6,2),Color("5a5a4c"))

# Pixel scanlines keep shore contours filled, including irregular concave basins.
static func paint_polygon(im: Image, points: PackedVector2Array, margin: float, color: Color) -> void:
	var bounds := Rect2(points[0],Vector2.ZERO)
	for p in points: bounds = bounds.expand(p)
	bounds = bounds.grow(maxf(0,margin)+2)
	for y in range(int(bounds.position.y),int(bounds.end.y),4):
		var start := -INF
		for x in range(int(bounds.position.x),int(bounds.end.x)+4,2):
			var at := Vector2(x,y)
			var inside := Geometry2D.is_point_in_polygon(at,points)
			var distance := INF
			for i in points.size(): distance = minf(distance,at.distance_to(Geometry2D.get_closest_point_to_segment(at,points[i],points[(i+1)%points.size()])))
			var filled := (-distance if inside else distance) <= margin
			if filled and start == -INF: start = x
			if start != -INF and (not filled or x+2 >= bounds.end.x):
				patch(im,Vector2(start,y),Vector2(x-start,4),color)
				start = -INF

static func terrain(data: ScenarioData, buildings: Array[Rect2], paths: Array) -> Texture2D:
	var definition := terrain_definition(data)
	var cache_key := str([data.scenario_id,data.world_size,definition,buildings,paths])
	if terrain_cache.has(cache_key): return terrain_cache[cache_key]
	var w := int(data.world_size[0])
	var h := int(data.world_size[1])
	var im := Image.create((w+PAD*2)/2,(h+PAD*2)/2,false,Image.FORMAT_RGBA8)
	im.fill(Color("102328"))
	var rng := RandomNumberGenerator.new()
	rng.seed = definition.seed # Independent of experimental/hidden state.
	# A separate stream keeps legacy tree/stone placement identical for column rivers.
	var noise := RandomNumberGenerator.new()
	noise.seed = int(definition.seed)*31+7
	for land in definition.get("landforms",[]):
		paint_polygon(im,PackedVector2Array(land.points),18,Color(land.color).darkened(0.12))
		paint_polygon(im,PackedVector2Array(land.points),0,Color(land.color))
	# Broad dry valley flanks climb to narrower rocky heads. The slopes are traversable.
	for feature: Dictionary in definition.features:
		if feature.kind != "ravine": continue
		for sample in walk(feature,4):
			stamp(im,sample[0],(float(feature.bank)+22)*float(sample[2]),Color("29372f"))
			stamp(im,sample[0],(float(feature.bank)+10)*float(sample[2]),Color("343c32"))
	for i in 2600:
		var p := Vector2(rng.randf_range(-SCENERY_PAD,w+SCENERY_PAD),rng.randf_range(-SCENERY_PAD,h+SCENERY_PAD))
		patch(im,p,Vector2(rng.randi_range(2,9)*2,2),Color("182e30") if i%3 else Color("1c3231"))
	for layer in 4:
		for feature: Dictionary in definition.features: paint_feature(im,data,feature,layer,noise)
	# Scree at tributary heads makes the narrowing incisions read as uphill landforms.
	for feature: Dictionary in definition.features:
		if feature.kind != "ravine" or not feature.has("scales") or feature.scales[-1] > 0.1: continue
		var tip: Vector2 = feature.points[-1]
		var uphill: Vector2 = (tip-feature.points[-2]).normalized()
		for i in 14:
			var at: Vector2 = tip+uphill*noise.randf_range(-8,25)+uphill.orthogonal()*noise.randf_range(-12,12)
			patch(im,at,Vector2(noise.randi_range(2,4)*2,4),Color("495046") if i%3 else Color("606354"))
	# Sort trunks by depth, then exclude the entire canopy from playable roads.
	var trees: Array[Vector2] = []
	for i in 1250:
		var p := Vector2(rng.randf_range(-SCENERY_PAD,w+SCENERY_PAD),rng.randf_range(-SCENERY_PAD,h+SCENERY_PAD))
		if bank_distance(data,p) < 22: continue
		if sin(p.x/91.0)+cos(p.y/73.0) > 1.25: continue
		var canopy := Rect2(p-Vector2(24,54),Vector2(48,65))
		var blocked := false
		for building in buildings:
			if canopy.intersects(building.grow(23)):
				blocked = true
				break
		if blocked: continue
		for path: PackedVector2Array in paths:
			for j in path.size()-1:
				if Geometry2D.get_closest_point_to_segment(canopy.get_center(),path[j],path[j+1]).distance_to(canopy.get_center()) < 49:
					blocked = true
					break
			if blocked: break
		if not blocked: trees.append(p)
	var border_rng := RandomNumberGenerator.new()
	border_rng.seed = int(definition.seed)+9001
	for i in 1900:
		var p := Vector2(border_rng.randf_range(-PAD,w+PAD),border_rng.randf_range(-PAD,h+PAD))
		if Rect2(-SCENERY_PAD,-SCENERY_PAD,w+SCENERY_PAD*2,h+SCENERY_PAD*2).grow(55).has_point(p): continue
		if bank_distance(data,p) > 45: trees.append(p)
	trees.sort_custom(func(a: Vector2,b: Vector2): return a.y < b.y)
	for p in trees:
		var variant := posmod(int(p.x*17+p.y*31),3) if absf(p.x-w*0.5)>w*0.5+SCENERY_PAD or absf(p.y-h*0.5)>h*0.5+SCENERY_PAD else rng.randi_range(0,2)
		var shade: Color = [Color("213e3b"),Color("1b3434"),Color("27423c")][variant]
		patch(im,p+Vector2(-17,0),Vector2(38,8),Color("0b1c22"))
		patch(im,p+Vector2(-2,-15),Vector2(4,22),Color("3a3c31"))
		for tier in range(3+variant%2):
			var span := 8+tier*8+variant*2
			var y := -44-variant%2*10+tier*11
			patch(im,p+Vector2(-span/2,y),Vector2(span,7),shade)
			patch(im,p+Vector2(-span/2-4,y+7),Vector2(span+8,7),Color("152e30"))
			patch(im,p+Vector2(-span/2,y+3),Vector2(4,5),shade.lightened(0.05))
	# Small bank stones use the same terrain geometry, avoiding every playable road.
	if definition.stones:
		for i in 46:
			var p := Vector2.ZERO
			var feature: Dictionary = definition.features[i%definition.features.size()]
			if feature.mode == "column":
				var y := rng.randf_range(-PAD,h+PAD)
				p = Vector2(column_x(feature,data,y)+(float(feature.bank)+rng.randf_range(4,15))*(-1 if i%2 else 1),y)
			else:
				var samples := walk(feature,6.0)
				var sample: Array = samples[rng.randi_range(0,samples.size()-1)]
				p = sample[0]+Vector2(-sample[1].y,sample[1].x)*(float(feature.bank)+rng.randf_range(4,15))*(-1 if i%2 else 1)
			var blocked := bank_distance(data,p) < 2
			for building in buildings:
				if building.grow(20).has_point(p): blocked = true
			for path: PackedVector2Array in paths:
				for j in path.size()-1:
					if Geometry2D.get_closest_point_to_segment(p,path[j],path[j+1]).distance_to(p) < 26: blocked = true
			if not blocked:
				patch(im,p,Vector2(10,6),Color("354748"))
				patch(im,p+Vector2(2,-2),Vector2(6,2),Color("50605b"))
	for r in buildings:
		patch(im,r.position-Vector2(10,-r.size.y+2),Vector2(r.size.x+20,12),Color("28352f"))
		for i in 7: patch(im,Vector2(r.position.x-6+i*10,r.end.y+7+(i%2)*2),Vector2(6,2),Color("46504a"))
	var texture := ImageTexture.create_from_image(im)
	terrain_cache[cache_key] = texture
	return texture

# Animated surface ripples for water features only; ravines stay still.
static func ripples(data: ScenarioData, frame: int) -> Array:
	var out: Array = []
	for feature: Dictionary in features(data):
		if feature.kind != "water": continue
		if feature.mode == "polygon":
			for y in range(0,int(data.world_size[1]),28):
				for x in range(0,int(data.world_size[0]),52):
					var at := Vector2(x+posmod(y,17)+frame*3,y+frame*2)
					if feature_distance(feature,data,at,0) < -15: out.append([at,Vector2(12,2)])
			continue
		if feature.mode == "column":
			for y in range(-100,int(data.world_size[1])+100,48):
				out.append([Vector2(column_x(feature,data,y)-8+frame*3,y+frame*2),Vector2(15,2)])
		else:
			for sample in walk(feature,48.0):
				var t: Vector2 = sample[1]
				var size := Vector2(clampf(float(feature.width)*0.8,6,15),2)
				out.append([sample[0]-Vector2(size.x*0.5,0)+t*frame*3,size])
	return out

static func patch(im: Image, at: Vector2, extent: Vector2, color: Color) -> void:
	im.fill_rect(Rect2i(Vector2i((at+Vector2.ONE*PAD)/2),Vector2i(extent/2)).intersection(Rect2i(0,0,im.get_width(),im.get_height())),color)

# 64x96 master artwork. Overview uses the same pixel grid; inspection unlocks
# additional carved stones, mortar, roof tiles, hinges and lantern lattice.
static func tower(variant: int, detail: bool, lit: bool, frame: int, depot: bool) -> Texture2D:
	var key := str([variant,detail,lit,frame,depot])
	if sprites.has(key): return sprites[key]
	var im := Image.create(64,96,false,Image.FORMAT_RGBA8)
	im.fill(Color.TRANSPARENT)
	var r := func(x: int,y: int,w: int,h: int,c: String): im.fill_rect(Rect2i(x,y,w,h),Color(c))
	var left := 17 if variant%2 == 0 else 14
	var span := 64-left*2
	var top := 35 if variant in [2,5] else 30
	r.call(8,86,48,7,"09191e")
	r.call(11,81,42,7,"56615a")
	r.call(left,top,span,53,"727b70")
	r.call(37,top,64-left-37,53,"3f5353")
	r.call(left+2,top+2,4,48,"919684")
	if variant%2 == 0:
		r.call(left-3,top+4,3,44,"4d625c")
		r.call(64-left,top+4,3,44,"283f45")
	for y in range(top+8,80,8):
		r.call(left,y,span,2,"354d4e")
		if detail:
			for x in range(left+3+(y/8%2)*5,64-left-3,10):
				r.call(x,y+2,1,6,"3b5251")
				r.call(x+2,y+3,4,1,"a1a087")
	r.call(26,68,12,15,"152c32")
	r.call(28,69,8,14,"493e2d")
	if detail:
		r.call(30,70,1,12,"7f6841")
		r.call(35,75,2,2,"d0aa66")
	# Eight silhouettes from the same masonry and roof palette.
	match variant:
		0: # Split crenellated parapet, square buttresses.
			for x in [10,44]:
				r.call(x,45,8,38,"5a6d64")
				r.call(x,44,8,3,"a5a78c")
			parapet(r,11,26,42)
		1: # Round watchtower with a copper conical roof.
			for tier in 6: r.call(29-tier*4,10+tier*3,6+tier*8,4,"455f58" if tier%2 else "718373")
			r.call(9,29,46,4,"aaa386")
		2: # Timber gallery with a stepped gable.
			r.call(8,28,48,15,"765b3b")
			for x in range(10,56,9): r.call(x,29,3,18,"b39a68")
			for tier in 5: r.call(12+tier*4,26-tier*3,40-tier*8,3,"4a625c")
		3: # Crown lantern housing, tall narrow windows.
			parapet(r,9,27,46)
			for x in [18,40]: r.call(x,46,5,15,"18323a")
			r.call(24,10,16,18,"655e40")
			r.call(20,8,24,4,"a29870")
		4: # Twin shoulder turrets and central saddle roof.
			for x in [8,44]:
				r.call(x,22,12,48,"5e7269")
				r.call(x-2,20,16,4,"a6a98d")
				r.call(x+2,14,8,6,"455f59")
			r.call(22,25,20,5,"657b6b")
		5: # Wide slate hip roof and timber braces.
			for tier in 5: r.call(12+tier*3,31-tier*4,40-tier*6,4,"49615d" if tier%2 else "758071")
			for x in [12,47]: r.call(x,44,5,39,"645539")
		6: # Octagonal lantern turret with a stone belt.
			parapet(r,13,25,38)
			r.call(11,54,42,5,"91947c")
			r.call(23,10,18,16,"485b52")
			r.call(20,8,24,4,"ab9b70")
		7: # Stepped battlements and projecting timber bay.
			parapet(r,10,25,44)
			r.call(5,49,17,21,"745c3d")
			r.call(3,46,21,4,"999376")
			for x in [7,17]: r.call(x,51,2,21,"b2a37c")
	# Each housing's artwork and glow use the same per-sprite lamp anchor.
	var lamp_at: Vector2 = metadata(variant).lamp
	var lx := int(lamp_at.x)-32
	var ly := int(lamp_at.y)-17
	r.call(25+lx,22+ly,14,3,"b09d64" if lit else "485955")
	r.call(27+lx,13+ly,10,9,"dd9343" if lit else "263d42")
	if lit:
		r.call(29+lx,10+ly-frame,6,11+frame,"f5c165")
		r.call(31+lx+frame%2,12+ly,3,7,"fff0b4")
		r.call(left+3,35,span-8,2,"af9b68")
		r.call(23,49,6,9,"e5b865")
		r.call(25,50,2,6,"ffe5a0")
	if detail:
		for x in [26,36]: r.call(x+lx,13+ly,1,9,"7c6a43")
		r.call(26+lx,19+ly,12,1,"8c784b")
		for y in [57,64]: r.call(19,y,4,2,"a2a389")
	# A small cloth pennant: cosmetic frame, never strategic state.
	if variant in [1,4,7]:
		r.call(48,31,2,20,"988b65")
		r.call(50,33,8,9+frame%2,"637c7c")
		r.call(50,33,8,2,"a0ad94")
	if depot:
		r.call(43,76,17,14,"947244")
		r.call(45,78,13,10,"5b4b32")
		r.call(49,76,2,14,"c2a26b")
		r.call(43,81,17,2,"b39a65")
	if not lit:
		r.call(33,40,2,16,"1c3237")
		r.call(35,54,4,2,"1c3237")
		r.call(8,83,7,4,"7a6654")
	var texture := ImageTexture.create_from_image(im)
	sprites[key] = texture
	return texture

static func parapet(r: Callable,x: int,y: int,w: int) -> void:
	r.call(x,y,w,8,"8c9682")
	r.call(x,y+7,w,3,"b4ad88")
	for dx in range(0,w-3,10): r.call(x+dx,y-6,6,7,"a1a78d")

static func light_texture(core: bool = false) -> Texture2D:
	if core and halo != null: return halo
	if not core and lamp != null: return lamp
	var im := Image.create(128,128,false,Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var d := Vector2(x-63.5,y-63.5).length()/64.0
			var strength := pow(maxf(0,1-d),2.6)*(0.72 if core else 0.26)
			im.set_pixel(x,y,Color(1.0,0.70,0.30,strength))
	var texture := ImageTexture.create_from_image(im)
	if core: halo = texture
	else: lamp = texture
	return texture
