extends "res://tests/test_city_art.gd"

const CodeEntry = preload("res://scripts/ui/access_code_entry.gd")

func start_fixture(id: String = "riverside_01_v3") -> void:
	app._start_dev(id)
	app.session.set_dev_mode(false)
	app.session.begin_sandbox_actions()
	await settle(4)

func run() -> void:
	capture_dir = ProjectSettings.globalize_path("res://build/three-improvements")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	UIkit.reduced_motion = true
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	await terrain_checks()
	await source_checks()
	await clipboard_checks()
	print("UI IMPROVEMENTS: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await settle()
	quit(0 if failures == 0 else 1)

func terrain_checks() -> void:
	for viewport in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport
		root.size = viewport
		for entry in ScenarioData.registry().scenarios:
			await start_fixture(entry.id)
			var tag := "%d-%s" % [viewport.x,entry.id]
			geometry_checks()
			var board: NetworkView = app.board
			var data: ScenarioData = app.session.scenario
			for id in data.node_positions:
				var rect := board.tower_world_rect(id)
				check(WoodlandArt.bank_distance(data,board.network_anchor(id)) > 25,"Tower base and forecourt stand on dry land: "+id)
				for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
					check(WoodlandArt.bank_distance(data,corner) > 0,"Full sprite is on solid land: "+id)
			for edge in app.session.state.edges:
				var road := board.visual_road(edge)
				check(road == CityMapProfiles.road(data,edge),"Scenery never changes authoritative road")
				for i in 201:
					var at := board._point_on_path(road,i/200.0)
					if WoodlandArt.bank_distance(data,at) <= 0:
						var on_bridge := false
						for span: PackedVector2Array in board.bridges:
							if Geometry2D.get_closest_point_to_segment(at,span[0],span[1]).distance_to(at) < 0.01: on_bridge = true
						check(on_bridge,"Every water/bank crossing is fully bridged")
			for span: PackedVector2Array in board.bridges:
				check(WoodlandArt.bank_distance(data,span[0]) > 8 and WoodlandArt.bank_distance(data,span[1]) > 8,"Bridge meets solid banks at both ends")
				check(span[0].distance_to(span[1]) < 200,"No road travels lengthwise through the river")
			# One deck per designated bridge edge, none elsewhere (bridge-only-1).
			check(board.bridge_edges.keys() == data.bridges,"Decks drawn exactly on scenario bridge edges")
			for edge in data.bridges: check(board.bridge_edges[edge].size() == 1,"Each bridge edge has one complete deck: "+edge)
			check(board.bridges.size() == data.bridges.size(),"Intentional crossing count")
			await snapshot(tag+"-overview")
			if DisplayServer.get_name() != "headless":
				var before := await public_pixels()
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
				check(before == await public_pixels(),"Terrain and all lamps ignore hidden P0/P1")
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
			for id in data.node_positions:
				app._select_shelter(id)
				await settle(2)
				geometry_checks()
				var rect := board.tower_screen_rect(id)
				check(rect.end.x < app.inspector.global_position.x and rect.position.y > 152 and rect.end.y < viewport.y-100,"Inspection leaves selected tower visible")
				if id in ["A","E","H"]: await snapshot(tag+"-inspection-"+id)
			app._clear_selection()
			board.change_zoom(0.3)
			board.camera_center += Vector2(35,20)
			board._update_camera()
			geometry_checks()
			for span: PackedVector2Array in board.bridges:
				check(board.to_world(board.to_screen(span[0])).distance_to(span[0]) < 0.001,"Bridge stays in the road coordinate transform after pan/zoom")

func source_checks() -> void:
	root.content_scale_size = Vector2i(1440,900)
	root.size = Vector2i(1440,900)
	for kind in ["VERIFY","MONITOR","SHIELD"]:
		await start_fixture()
		app._select_shelter("C")
		app._request_action(kind,"C")
		await settle()
		var picker = app.source_picker
		check(app.modal == null and picker != null,"Source selection leaves the map interactive")
		check(picker.assignments.is_empty() and picker.eligible.size() == 2,"Multiple depots are equally eligible, none preselected")
		check(app.session.state.total_supply() == 6,"Selection spends nothing")
		app._select_shelter("B")
		check(picker.assignments.is_empty(),"A non-depot cannot become a source")
		await snapshot("source-choose-"+kind)
		app._select_shelter("A")
		check(picker.assignments == ["A"] and app.selected_shelter == "C","Depot click chooses source while retaining destination")
		check(app.board.supply_paths[0] == app.session.action_manager.supply.delivery_plan(kind,"C",["A"] as Array[String])[0].path,"Preview uses existing shortest route")
		app._select_shelter("H")
		check(picker.assignments == ["H"],"Source can be changed before confirmation")
		picker.go_back()
		check(picker.assignments.is_empty() and app.board.supply_paths.is_empty(),"Back clears the unconfirmed route")
		app._select_shelter("H")
		await snapshot("source-confirm-"+kind)
		check_layout("source confirmation")
		picker.confirm_selection()
		picker.confirm_selection()
		check(app.session.state.total_supply() == 5 and app.session.phase == GameManager.Phase.DELIVERY,"Double confirmation reserves exactly one supply")
		check(app.session.pending_action.endpoint_depots == ["H"],"Confirmed origin matches player's chosen depot")
		await wait_delivery()
		check(app.session.state.actions.size() == 1,"Exactly one action completes")
		var events: Array = app.session.logger.to_array()
		var origins: Array = []
		for event in events:
			if event.type == "SUPPLY_DELIVERY_STARTED": origins.append(event.metadata.depot)
		check(origins == ["H"],"Existing action log records the chosen origin")
	# One eligible source still requires an explicit click; stale stock revalidates.
	await start_fixture()
	app.session.state.depots.H.supply_remaining = 0
	app._request_action("VERIFY","C")
	check(app.source_picker.eligible == ["A"] and app.source_picker.assignments.is_empty(),"One depot is not silently selected")
	app.source_picker.confirm_selection()
	check(app.session.state.total_supply() == 3,"Cannot confirm without choosing")
	app._select_shelter("A")
	app.session.state.depots.A.supply_remaining = 0
	app.source_picker.confirm_selection()
	check(app.session.phase == GameManager.Phase.ACTIONS and app.session.state.actions.is_empty(),"Stale stock cannot dispatch")
	await snapshot("source-none")
	check(app.source_picker.eligible.is_empty(),"Zero eligible depots is explained without spending")
	app._close_source_picker()
	# Same-source feasibility is filtered for endpoint two.
	await start_fixture()
	app.session.state.depots.A.supply_remaining = 1
	app._request_action("ISOLATE","E-F")
	app._select_shelter("A")
	check(app.source_picker.eligible == ["H"],"One remaining unit cannot fund both endpoints")
	await create_timer(0.23).timeout
	app._select_shelter("A")
	check(app.source_picker.assignments == ["A"],"Infeasible second click is ignored")
	app.source_picker.go_back()
	check(app.source_picker.assignments.is_empty(),"Back permits changing endpoint one")
	app._close_source_picker()
	check(app.session.state.total_supply() == 4,"Cancel never partially reserves isolation")
	for same_source in [true,false]:
		await start_fixture()
		app._request_action("ISOLATE","E-F")
		app._select_shelter("A")
		await snapshot("isolate-endpoint-two")
		await create_timer(0.23).timeout
		app._select_shelter("A" if same_source else "H")
		var picker = app.source_picker
		check(app.board.supply_paths.size() == 2,"Both isolation routes are previewed")
		check(app.board.preview_edge == "E-F" and not app.board.preview_lost.is_empty(),"Closure consequences are retained")
		await snapshot("isolate-"+("same" if same_source else "different"))
		check_layout("isolation confirmation")
		picker.confirm_selection()
		picker.confirm_selection()
		check(app.session.state.total_supply() == 4 and not app.session.state.edges["E-F"].isolated,"Both units reserved together, road stays open in transit")
		check(app.session.pending_action.endpoint_depots == (["A","A"] if same_source else ["A","H"]),"Isolation logs exact endpoint assignments")
		await wait_delivery()
		check(app.session.state.edges["E-F"].isolated and app.session.state.actions.size() == 1,"Both arrivals close the road exactly once")
	# New session disposes any unfinished selection.
	await start_fixture()
	app._request_action("VERIFY","C")
	app._select_shelter("A")
	var stale = app.source_picker
	app._start_dev("lifeline_03_v2")
	stale.confirm_selection()
	check(app.source_picker == null and app.session.state.total_supply() == 6,"Session change clears stale source selection")
	# All experimental conditions expose the same component.
	for condition in 3:
		app._start_normal()
		app.session.configure_condition(condition)
		app.session.phase = GameManager.Phase.ACTIONS
		app._render()
		app._request_action("VERIFY","C")
		check(app.source_picker.assignments.is_empty() and app.source_picker.eligible == ["A","H"],"Same source-selection UI across all conditions")
		app._close_source_picker()
	# Compact bilingual source flow in practice at the smaller size.
	root.content_scale_size = Vector2i(1200,800)
	root.size = Vector2i(1200,800)
	for chinese in [false,true]:
		FirstPlayText.chinese = chinese
		app._begin_play()
		var practice: PracticeView = app.practice
		practice.select_shelter("E")
		practice.deliver("VERIFY","E")
		check(practice.state.total_supply() == 6 and practice.source_picker.assignments.is_empty(),"Practice uses explicit selection too")
		practice.select_shelter("A")
		await snapshot("1200-practice-source-"+("zh" if chinese else "en"))
		check_layout("practice source")
		practice.source_picker.confirm_selection()
		while practice.busy: await create_timer(0.05).timeout
		check(practice.step == 1 and practice.state.actions[0].endpoint_depots == ["A"],"Practice shares confirmed origins and effects")
		practice.select_road("C-E")
		practice.deliver("ISOLATE","C-E")
		practice.select_shelter("A")
		await create_timer(0.23).timeout
		practice.select_shelter("A")
		await snapshot("1200-practice-isolate-"+("zh" if chinese else "en"))
		practice.source_picker.confirm_selection()
		while practice.busy: await create_timer(0.05).timeout
		check(practice.step == 2 and practice.state.edges["C-E"].isolated,"Practice isolation retains arrival semantics")
	FirstPlayText.chinese = false

func clipboard_checks() -> void:
	app._show_main_menu()
	var sync := root.get_node("StudySync")
	sync.enabled = true
	sync.set_process(false)
	ProjectSettings.set_setting("cascade/require_access_code",true)
	for chinese in [false,true]:
		FirstPlayText.chinese = chinese
		sync.access_code = ""
		app._show_main_menu()
		# The title stays uncluttered; Play opens the focused access-code step.
		check(app.find_child("AccessCodeEntry",true,false) == null,"Title screen has no code field")
		await click("开始游戏" if chinese else "Play")
		var entry = app.find_child("AccessCodeEntry",true,false)
		var play := button_containing("开始" if chinese else "Start")
		check(play.disabled,"Empty code disables Start")
		entry.apply_pasted_text("  Synthetic-Code_Aa-123 \n")
		check(entry.field.text == "Synthetic-Code_Aa-123" and sync.access_code == "","Paste trims surrounding whitespace, preserves case and does not submit credentials")
		check(not play.disabled and app.session == null,"Paste updates manual validation without starting play")
		entry.field.text = "short"
		entry.field.text_changed.emit("short")
		check(play.disabled,"Manual and paste validation agree")
		entry.apply_pasted_text("tiny")
		check(play.disabled,"Invalid short paste cannot enable Play")
		entry.apply_pasted_text("Synthetic-Code_Aa-123")
		for bad in ["  ","bad\ncode","x".repeat(6000)]:
			entry.apply_pasted_text(bad)
			check(entry.field.text == "Synthetic-Code_Aa-123","Empty, multiline and huge paste preserve editable field safely")
		entry._clipboard_result(["blocked",""])
		check(entry.field.editable and entry.paste_button.disabled,"Denial leaves field editable and prevents repeated permission requests")
		await snapshot("1200-paste-fallback-"+("zh" if chinese else "en"))
		check_layout("paste field")
		sync.access_code = ""
		CodeEntry.browser_denied = false
		app._show_main_menu()
		app.title_screen.show_setup()
		await snapshot("1200-paste-"+("zh" if chinese else "en"))
	sync.enabled = false
	sync.access_code = ""
	ProjectSettings.set_setting("cascade/require_access_code",false)
	FirstPlayText.chinese = false
