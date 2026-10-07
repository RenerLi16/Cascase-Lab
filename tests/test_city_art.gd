extends "res://tests/test_presentation.gd"

func geometry_checks() -> void:
	var board: NetworkView = app.board
	var scenario: ScenarioData = app.session.scenario
	var data := CityMapProfiles.layout(scenario)
	check(data.nodes.size() == 8,"Eight separate landmark records")
	check(data.edges.size() == app.session.state.edges.size(),"Exact visual edge coverage")
	check(CityMapProfiles.vector(data.image_size) == CityMapProfiles.TEXTURES[scenario.scenario_id].get_size(),"Actual raster dimensions registered")
	for id in data.nodes:
		var n: Dictionary = data.nodes[id]
		check(not board.world_building(id).grow(8).has_point(board.network_anchor(id)),"Junction outside roof "+id)
		check(board.hit_test(board.positions[id]) == id,"Landmark selects correct shelter "+id)
		check(board.to_world(board.to_screen(board.network_anchor(id))).is_equal_approx(board.network_anchor(id)),"Camera transform round trip")
	for id in data.edges:
		var edge: EdgeState = app.session.state.edges[id]
		var points := board.visual_road(id)
		check(points[0] == board.network_anchor(edge.from),"Source network anchor "+id)
		check(points[-1] == board.network_anchor(edge.to),"Destination network anchor "+id)
		var reversed := points.duplicate()
		reversed.reverse()
		check(board.world_path_for_nodes([edge.to,edge.from]) == reversed,"Reversible centerline "+id)
		for i in points.size()-1:
			check(points[i].distance_to(points[i+1]) > 0.01,"No zero-length segments")
		# Pieces sit on the junctions and take clicks there; everywhere else along
		# the visible road selects the road itself.
		for step in range(21):
			var fraction := step/20.0
			var screen := board.to_screen(board._point_on_path(points,fraction))
			var under := ""
			for nid in [edge.from,edge.to]:
				if board.token_rect(nid).grow(4).has_point(screen): under = nid
			if under != "": check(board.hit_test(screen) == under,"Junction piece takes clicks over its road end "+id)
			elif board.label_rects.values().all(func(r: Rect2): return not r.has_point(screen)):
				check(board.hit_test(screen) == id,"Select correct branch "+id+" at "+str(fraction))
		check(board.hit_test(board.to_screen(board._point_on_path(points,board.closure_fraction(id)))) == id,"Closure lies on own selectable segment")
		for step in range(101):
			var point: Vector2 = board._point_on_path(points,step/100.0)
			for nid in data.nodes:
				check(not board.world_building(nid).grow(8).has_point(point),"Road corridor avoids roof "+id+"/"+nid)
		for other in data.edges:
			var e: EdgeState = app.session.state.edges[other]
			if edge.from in [e.from,e.to] or edge.to in [e.from,e.to]: continue
			var path := board.visual_road(other)
			for i in points.size()-1:
				for j in path.size()-1:
					check(Geometry2D.segment_intersects_segment(points[i],points[i+1],path[j],path[j+1]) == null,"No invented non-node intersection")
	# Every possible two-edge transit must visit the intermediate anchor once.
	for middle in data.nodes:
		var neighbors: Array = []
		for edge: EdgeState in app.session.state.edges.values():
			if edge.from == middle: neighbors.append(edge.to)
			if edge.to == middle: neighbors.append(edge.from)
		for a in neighbors:
			for b in neighbors:
				if a == b: continue
				var path := board.world_path_for_nodes([a,middle,b])
				check(path.count(board.network_anchor(middle)) == 1,"Through-route visits junction once")
				check(not path.has(board.world_building(middle).get_center()),"No intermediate driveway detour")
				for i in path.size()-1: check(path[i] != path[i+1],"No duplicated route join")

func run() -> void:
	# CAPTURE_DIR redirects captures so verification runs do not rewrite archived report images.
	capture_dir = OS.get_environment("CAPTURE_DIR") if OS.get_environment("CAPTURE_DIR") != "" else ProjectSettings.globalize_path("res://docs/screenshots/map-alignment/after")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		for entry in ScenarioData.registry().scenarios:
			app._start_dev(entry.id)
			app.session.set_dev_mode(false)
			await settle(8)
			app.board.dev_mode = false
			var tag := str(viewport_size.x)+"-"+str(entry.id)
			geometry_checks()
			check_layout(tag)
			for rect: Rect2 in app.board.title_rects.values():
				check(not app.board._annotation_hides_road(rect),"Names leave road branches visible")
			await snapshot(tag+"-overview")
			app.board.show_annotations = false
			app.board.queue_redraw()
			await snapshot(tag+"-background")
			app.board.show_annotations = true
			app.board._move_camera(Vector2(500,350),2.6,false)
			await snapshot(tag+"-close")
			geometry_checks()
			app.board.center_map(false)
			if DisplayServer.get_name() != "headless":
				var before := await public_pixels()
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1 - shelter.zombie_pressure
				check(before == await public_pixels(),"Visual layout does not disclose hidden pressure")
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1 - shelter.zombie_pressure
			app.session.begin_sandbox_actions()
			await settle()
			app.board.dev_mode = false
			var target := "H" if entry.id == "riverside_01_v2" else "G"
			var depots: Array[String] = ["A"]
			var result: Dictionary = app.session.dispatch_action("VERIFY",target,depots)
			check(result.ok,"Real delivery accepted")
			check(app.session.pending_action.deliveries[0].path.size() >= 3,"Real delivery passes intermediate shelters")
			await create_timer(0.45).timeout
			check(app.board.animation_kind == "delivery","Actual vehicle animation running")
			check(app.board.animation_paths[0] == app.board.world_path_for_nodes(app.session.pending_action.deliveries[0].path),"Vehicle uses shared geometry")
			await snapshot(tag+"-delivery")
			var transit: String = app.session.pending_action.deliveries[0].path[1]
			app.board._move_camera(app.board.network_anchor(transit),2.6,false)
			await snapshot(tag+"-delivery-close")
			await wait_delivery()
			check(app.session.phase == GameManager.Phase.ACTIONS,"Delivery completes")
			app.board.center_map(false)
			var edge := "E-F" if entry.id == "riverside_01_v2" else "D-E"
			await map_click(edge,true)
			await snapshot(tag+"-selected")
			await click("ISOLATE")
			check(app.board.preview_edge == edge,"Preview references authoritative edge")
			await snapshot(tag+"-preview")
			await click("Confirm delivery")
			await wait_delivery()
			check(app.session.state.edges[edge].isolated,"Real closure completes after deliveries")
			app._clear_selection()
			app.board.center_map(false)
			await snapshot(tag+"-closed")
			app.board._move_camera(app.board._point_on_path(app.board.visual_road(edge),app.board.closure_fraction(edge)),2.6,false)
			await snapshot(tag+"-closed-close")
		app.queue_free()
		await settle()
	print("CITY ALIGNMENT TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
