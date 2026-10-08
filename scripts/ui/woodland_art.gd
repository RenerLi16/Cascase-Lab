class_name WoodlandArt
extends RefCounted

# Pure presentation. Inputs are public geometry, a stable A–H ID and public
# flags; this artist has no access to pressure, AI conditions or game logic.
const PAD := 320
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

static func river_x(y: float, width: float) -> float:
	return width*0.63+sin(y/118.0)*22.0

static func terrain(data: ScenarioData, buildings: Array[Rect2], paths: Array) -> Texture2D:
	if terrain_cache.has(data.scenario_id): return terrain_cache[data.scenario_id]
	var w := int(data.world_size[0])
	var h := int(data.world_size[1])
	var im := Image.create((w+PAD*2)/2,(h+PAD*2)/2,false,Image.FORMAT_RGBA8)
	im.fill(Color("102328"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 943 # Independent of experimental/hidden state.
	for i in 2600:
		var p := Vector2(rng.randf_range(-PAD,w+PAD),rng.randf_range(-PAD,h+PAD))
		patch(im,p,Vector2(rng.randi_range(2,9)*2,2),Color("182e30") if i%3 else Color("1c3231"))
	for y in range(-PAD,h+PAD,4):
		var x := snappedf(river_x(y,w),2)
		patch(im,Vector2(x-38,y),Vector2(76,4),Color("263c3c"))
		patch(im,Vector2(x-30,y),Vector2(60,4),Color("102b36"))
		patch(im,Vector2(x-21,y),Vector2(42,4),Color("193945"))
		if y%24 == 0: patch(im,Vector2(x-18,y),Vector2(23,2),Color("315361"))
	# Sort trunks by depth, then exclude the entire canopy from playable roads.
	var trees: Array[Vector2] = []
	for i in 1250:
		var p := Vector2(rng.randf_range(-PAD,w+PAD),rng.randf_range(-PAD,h+PAD))
		if absf(p.x-river_x(p.y,w)) < 55: continue
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
	trees.sort_custom(func(a: Vector2,b: Vector2): return a.y < b.y)
	for p in trees:
		var variant := rng.randi_range(0,2)
		var shade: Color = [Color("213e3b"),Color("1b3434"),Color("27423c")][variant]
		patch(im,p+Vector2(-17,0),Vector2(38,8),Color("0b1c22"))
		patch(im,p+Vector2(-2,-15),Vector2(4,22),Color("3a3c31"))
		for tier in range(3+variant%2):
			var span := 8+tier*8+variant*2
			var y := -44-variant%2*10+tier*11
			patch(im,p+Vector2(-span/2,y),Vector2(span,7),shade)
			patch(im,p+Vector2(-span/2-4,y+7),Vector2(span+8,7),Color("152e30"))
			patch(im,p+Vector2(-span/2,y+3),Vector2(4,5),shade.lightened(0.05))
	for r in buildings:
		patch(im,r.position-Vector2(10,-r.size.y+2),Vector2(r.size.x+20,12),Color("28352f"))
		for i in 7: patch(im,Vector2(r.position.x-6+i*10,r.end.y+7+(i%2)*2),Vector2(6,2),Color("46504a"))
	var texture := ImageTexture.create_from_image(im)
	terrain_cache[data.scenario_id] = texture
	return texture

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
