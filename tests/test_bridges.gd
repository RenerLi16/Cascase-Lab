extends "res://tests/test_ui.gd"

# Bridge-only closure (rule bridge-only-1, scenario pack 1.1.0).
# Domain, survey, support-context, geometry, map UI and practice checks.
const EXPECTED := {
	"practice_demo_v2":["C-E","D-F"],
	"riverside_01_v3":["E-F"],
	"twin_districts_02_v2":["C-D","D-E"],
	"lifeline_03_v2":["D-E","E-F","E-G"],
	"crossfire_04_v2":["B-D","B-E","D-F","E-F"],
}
const FILES := ["res://scenarios/practice_demo.json","res://scenarios/scenario_01.json","res://scenarios/scenario_02.json","res://scenarios/scenario_03.json","res://scenarios/scenario_04.json"]

func run() -> void:
	data_checks()
	loader_checks()
	for path in FILES: action_checks(ScenarioData.load_path(path))
	closure_effect_checks()
	survey_checks()
	condition_checks()
	support_checks()
	for path in FILES: geometry_checks(ScenarioData.load_path(path))
	await ui_checks()
	await practice_checks()
	print("BRIDGE TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func sandbox(data: ScenarioData) -> GameManager:
	var game := GameManager.new(data,GameManager.InterventionType.NONE,Callable(),GameManager.RunPurpose.DEV_SANDBOX)
	game.logger.capture_timing = false
	game.begin_sandbox_actions()
	return game

func pair(values: Array) -> Array[String]:
	var output: Array[String] = []
	output.assign(values)
	return output

func spent_events(game: GameManager) -> int:
	var count := 0
	for event in game.logger.to_array():
		if event.type in ["ACTION_SELECTED","SUPPLY_SPENT","SUPPLY_DELIVERY_STARTED"]: count += 1
	return count

func data_checks() -> void:
	var registry := ScenarioData.registry()
	check(registry.pack_version == "1.1.0" and str(registry.closure_rule).begins_with("bridge-only-1"),"Pack version records the bridge-only rule")
	for path in FILES:
		var data := ScenarioData.load_path(path)
		check(data != null,"Scenario loads: "+path+" "+ScenarioData.last_error)
		check(EXPECTED.has(data.scenario_id),"Scenario ID is versioned: "+data.scenario_id)
		check(data.bridges == EXPECTED[data.scenario_id],"Finalized bridge list: "+data.scenario_id)
		var state := GameState.new(data)
		for id in state.edges:
			check(state.edges[id].bridge == data.bridges.has(id),"Edge flag follows scenario data: %s %s" % [data.scenario_id,id])
			check(state.copy().edges[id].bridge == state.edges[id].bridge,"State copy keeps bridge flag")
			check(state.edges[id].to_dictionary().bridge == state.edges[id].bridge,"Export carries bridge flag")
	for entry in registry.scenarios:
		check(ScenarioData.load_by_id(entry.id) != null,"Registry resolves "+entry.id)

func loader_checks() -> void:
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenarios/scenario_02.json"))
	var missing := base.duplicate(true)
	missing.erase("bridges")
	check(ScenarioData.from_dictionary(missing) == null and ScenarioData.last_error.contains("bridges"),"Bridges field is required")
	for bad in [["E-D"],["X-Y"],["C-D","C-D"],[3],"C-D"]:
		var copy := base.duplicate(true)
		copy.bridges = bad
		check(ScenarioData.from_dictionary(copy) == null,"Invalid bridge list rejected: "+str(bad))
	var none := base.duplicate(true)
	none.bridges = []
	var loaded := ScenarioData.from_dictionary(none)
	check(loaded != null and GameState.new(loaded).edges.values().all(func(e: EdgeState): return not e.bridge),"An empty list means no edge can close")

func action_checks(data: ScenarioData) -> void:
	var game := sandbox(data)
	var depot: String = data.supply_depots[0]
	for id in game.state.edges:
		if data.bridges.has(id):
			check(game.action_manager.unavailable_reason("ISOLATE",id) == "","Bridge is closable at start: %s %s" % [data.scenario_id,id])
			continue
		check(game.action_manager.unavailable_reason("ISOLATE",id) == "NOT A BRIDGE","Ordinary road rejected: %s %s" % [data.scenario_id,id])
		check(game.action_manager.supply.delivery_options("ISOLATE",id).is_empty(),"Ordinary road has no delivery options")
		for funding in [[depot,depot],[data.supply_depots[0],data.supply_depots[1]]]:
			var result := game.dispatch_action("ISOLATE",id,pair(funding))
			check(not result.ok and result.error == "NOT A BRIDGE","Direct ordinary-road request refused: "+id)
		check(game.state.total_supply() == 6 and spent_events(game) == 0 and game.phase == GameManager.Phase.ACTIONS,"Refused request consumes nothing: "+id)
		check(not game.state.edges[id].isolated,"Ordinary road remains open: "+id)
	var request := GameAction.new("ISOLATE",game.state.edges.keys()[0],"",game.state.round)
	request.endpoint_depots.assign([depot,depot])
	if not data.bridges.has(request.target):
		check(not game.action_manager.reserve(request).ok and game.state.total_supply() == 6,"ActionManager.reserve enforces the rule directly")

func closure_effect_checks() -> void:
	# Valid closure: two deliveries, closure only on arrival, then blocks supply transit.
	var life := sandbox(ScenarioData.load_by_id("lifeline_03_v2"))
	var result := life.dispatch_action("ISOLATE","D-E",pair(["A","C"]))
	check(result.ok and result.action.deliveries.size() == 2,"Bridge closure sends one delivery to each end")
	check(life.state.total_supply() == 4 and not life.state.edges["D-E"].isolated,"Two supplies reserved; bridge open while in transit")
	check(life.action_manager.unavailable_reason("ISOLATE","E-F") == "DELIVERY IN PROGRESS","No second request while delivering")
	check(life.complete_delivery(life.run_token) and life.state.edges["D-E"].isolated,"Bridge closes after both deliveries arrive")
	check(not life.complete_delivery(life.run_token),"Arrival cannot be applied twice")
	check(life.action_manager.unavailable_reason("ISOLATE","D-E") == "ROAD CLOSED","Closed bridge cannot be closed again")
	# Unreachable endpoints: the eastern bridges are now cut off from both western depots.
	for id in ["E-F","E-G"]:
		check(life.action_manager.unavailable_reason("ISOLATE",id) == "NO SUPPLY ROUTE","Unreachable bridge ends refused: "+id)
		check(not life.dispatch_action("ISOLATE",id,pair(["A","C"])).ok and life.state.total_supply() == 4,"Unreachable request consumes nothing: "+id)
	# Insufficient supplies.
	var twin := sandbox(ScenarioData.load_by_id("twin_districts_02_v2"))
	twin.state.depots.A.supply_remaining = 1
	twin.state.depots.H.supply_remaining = 0
	check(twin.action_manager.unavailable_reason("ISOLATE","C-D") == "NO SUPPLY","One remaining unit cannot close a bridge")
	check(not twin.dispatch_action("ISOLATE","C-D",pair(["A","A"])).ok and twin.state.total_supply() == 1 and spent_events(twin) == 0,"Insufficient stock consumes nothing")
	twin.state.depots.H.supply_remaining = 1
	check(not twin.dispatch_action("ISOLATE","C-D",pair(["A","A"])).ok and twin.state.total_supply() == 2,"Unfunded assignment refused without spending")
	check(twin.dispatch_action("ISOLATE","C-D",pair(["A","H"])).ok and twin.state.total_supply() == 0,"Split funding remains valid")
	# Closure blocks outbreak spread across the bridge.
	for closed in [false,true]:
		var cross := sandbox(ScenarioData.load_by_id("crossfire_04_v2"))
		if closed:
			check(cross.dispatch_action("ISOLATE","B-D",pair(["A","H"])).ok and cross.complete_delivery(cross.run_token),"Crossfire bridge closes")
		for round_number in 2:
			cross.begin_resolution()
			cross.apply_resolution(cross.run_token)
			cross.finish_resolution(cross.run_token)
			cross.next_round()
			cross.begin_sandbox_actions()
			cross.phase = GameManager.Phase.ACTIONS
		check(cross.state.shelters.D.zombie_pressure == (1 if closed else 2),"Closed bridge blocks spread from B into D" if closed else "Open bridge carries spread from B and F into D")

func survey_checks() -> void:
	var data := ScenarioData.load_by_id("crossfire_04_v2")
	var game := GameManager.new(data,GameManager.InterventionType.NONE,func(): return 0)
	check(game.survey_targets("ISOLATE") == data.bridges,"Survey offers only bridges as closure targets")
	check(game.survey_targets("SHIELD").size() == 8,"Shelter targets unchanged")
	game.start_private()
	game.open_private_form()
	check(not game.submit_belief(PlayerBelief.new("D-E","ISOLATE","D-E",3,"prevent cascade")),"Survey refuses closing an ordinary road")
	check(game.submit_belief(PlayerBelief.new("D-E","ISOLATE","B-D",3,"prevent cascade")),"Ordinary road can still be named as a danger; bridge closure accepted")

func condition_checks() -> void:
	for condition in [GameManager.InterventionType.NONE,GameManager.InterventionType.DIRECT_RECOMMENDATION,GameManager.InterventionType.CONSTRUCTIVE_DISSENT]:
		for purpose in [GameManager.RunPurpose.NORMAL,GameManager.RunPurpose.DEV_SANDBOX]:
			var game := GameManager.new(ScenarioData.load_by_id("crossfire_04_v2"),condition,func(): return 0,purpose)
			game.phase = GameManager.Phase.ACTIONS
			check(game.dispatch_action("ISOLATE","D-E",pair(["A","H"])).error == "NOT A BRIDGE","Same rule in condition %d purpose %d" % [condition,purpose])
			check(game.dispatch_action("ISOLATE","B-D",pair(["A","H"])).ok,"Bridge closable in condition %d purpose %d" % [condition,purpose])

func responses(kind: String, target: String) -> Array:
	var output: Array = []
	for index in 3: output.append({"danger_location":"D","preferred_action":kind,"action_target":target,"confidence":3,"reason":"prevent cascade"})
	return output

func support_checks() -> void:
	check(SupportContext.VERSION == "cascade-context-3" and SupportLibrary.VERSION == "support-1.2.0","Support contract versions advanced")
	var game := sandbox(ScenarioData.load_by_id("crossfire_04_v2"))
	var input := SupportContext.build(game.state,responses("ISOLATE","D-E"))
	for id in game.state.edges:
		check(input.roads[id].bridge == game.state.edges[id].bridge,"Context exposes public bridge flag: "+id)
		check(input.display_names[id] == ("Bridge " if game.state.edges[id].bridge else "Road ")+id,"Display names distinguish bridges")
	check(input.responses.is_empty(),"Ordinary-road closure proposals never reach support")
	check(str(input.public_rules.access).contains("bridge=true") and str(input.public_rules.effects).contains("Close bridge"),"Public rules state the bridge-only rule")
	for action in input.legal_actions:
		if action.action == "ISOLATE": check(game.state.edges[action.target].bridge,"Legal closure list holds bridges only")
	var legal_bridges: Array = input.legal_actions.filter(func(a: Dictionary): return a.action == "ISOLATE").map(func(a: Dictionary): return a.target)
	check(legal_bridges == ["B-D","B-E","D-F","E-F"],"Every reachable bridge is a legal closure")
	var advice := SupportLibrary.generate(input,"DIRECT_RECOMMENDATION")
	check(not (advice.action == "ISOLATE" and advice.target == "D-E"),"Direct support never recommends an ordinary-road closure")
	input = SupportContext.build(game.state,responses("ISOLATE","B-D"))
	advice = SupportLibrary.generate(input,"DIRECT_RECOMMENDATION")
	check(advice.action == "ISOLATE" and advice.target == "B-D" and advice.text.begins_with("Recommendation: Close Bridge B-D"),"Supported bridge proposal is recommended as Close bridge")
	check(SupportLibrary.word_count(advice.text) >= 35 and SupportLibrary.word_count(advice.text) <= 60,"Revised template within word limits")
	# A hand-edited context cannot smuggle an ordinary road into the legal list.
	input.roads["D-E"].bridge = false
	check(not SupportLibrary.legal_actions(input).has({"action":"ISOLATE","target":"D-E"}),"Library ignores unflagged roads")

func geometry_checks(data: ScenarioData) -> void:
	var state := GameState.new(data)
	var view := NetworkView.new()
	view.configure(data,state)
	view.size = Vector2(1440,900)
	var tag := data.scenario_id
	for id in data.node_positions:
		var rect := view.tower_world_rect(id)
		check(WoodlandArt.bank_distance(data,view.network_anchor(id)) > 25,"Forecourt on solid ground: %s %s" % [tag,id])
		for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
			check(WoodlandArt.bank_distance(data,corner) > 0,"Tower sprite on solid ground: %s %s" % [tag,id])
	check(view.bridge_edges.keys() == data.bridges,"Decks only on designated bridges: "+tag)
	for id in state.edges:
		var road := view.visual_road(id)
		var spans: Array = view.bridge_edges.get(id,[])
		var wet := 0
		for i in road.size()-1:
			var steps := ceili(road[i].distance_to(road[i+1])/2.0)
			for step in steps+1:
				var at := road[i].lerp(road[i+1],float(step)/steps)
				var d := WoodlandArt.bank_distance(data,at)
				if not state.edges[id].bridge:
					if d <= 6:
						wet += 1
					continue
				if d <= 0:
					var covered := false
					for span: PackedVector2Array in spans:
						if Geometry2D.get_closest_point_to_segment(at,span[0],span[1]).distance_to(at) < 0.01: covered = true
					if not covered: wet += 1
		if not state.edges[id].bridge:
			check(wet == 0,"Ordinary road never enters water, ravine or bank: %s %s" % [tag,id])
			continue
		check(spans.size() == 1,"Bridge crosses exactly one obstacle: %s %s" % [tag,id])
		check(wet == 0,"Bridge deck spans the full obstacle: %s %s" % [tag,id])
		for span: PackedVector2Array in spans:
			check(WoodlandArt.bank_distance(data,span[0]) > 8 and WoodlandArt.bank_distance(data,span[1]) > 8,"Deck meets solid ground at both ends: %s %s" % [tag,id])
			check(span[0].distance_to(span[1]) < 130,"Deck crosses rather than runs along the obstacle: %s %s" % [tag,id])
			var gate := view._point_on_path(road,view.closure_fraction(id))
			check(Geometry2D.get_closest_point_to_segment(gate,span[0],span[1]).distance_to(gate) < 1.0 and WoodlandArt.bank_distance(data,gate) < 0,"Barricade sits on the deck over the obstacle: %s %s" % [tag,id])
	# Water ripples never animate inside a dry ravine.
	for ripple: Array in WoodlandArt.ripples(data,1):
		var centre: Vector2 = ripple[0]+ripple[1]*0.5
		check(WoodlandArt.obstacle_kind(data,centre) == "water","Ripples stay on water: "+tag)
		break
	# Decks stay registered to their roads after zoom, pan and resize.
	for setting in [[Vector2(1440,900),1.0,Vector2.ZERO],[Vector2(1200,800),1.6,Vector2(40,-25)],[Vector2(1600,1000),2.2,Vector2(-60,30)]]:
		view.size = setting[0]
		view.zoom = setting[1]
		view.camera_center = Vector2(data.world_size[0],data.world_size[1])*0.5+setting[2]
		view._update_camera()
		view._refresh_geometry()
		for id in view.bridge_edges:
			for span: PackedVector2Array in view.bridge_edges[id]:
				var screen_mid := view.to_screen((span[0]+span[1])*0.5)
				var points: PackedVector2Array = view.road_geometry[id]
				var nearest := INF
				for i in points.size()-1: nearest = minf(nearest,Geometry2D.get_closest_point_to_segment(screen_mid,points[i],points[i+1]).distance_to(screen_mid))
				check(nearest < 0.5,"Deck stays on its road after zoom/pan/resize: %s %s" % [tag,id])
	view.free()

func bubble_text() -> String:
	var text := ""
	if not is_instance_valid(app.road_bubble): return text
	for node in descendants(app.road_bubble,"Label")+descendants(app.road_bubble,"Button"): text += str(node.text)+"\n"
	return text

func ui_checks() -> void:
	root.content_scale_size = Vector2i(1440,900)
	root.size = Vector2i(1440,900)
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app._start_dev("crossfire_04_v2")
	await settle(4)
	check(app.session.begin_sandbox_actions(),"Sandbox actions")
	await settle(4)
	# Ordinary road: inspectable, explained, no closure action.
	await map_click("D-E",true)
	check(app.selected_edge == "D-E" and is_instance_valid(app.road_bubble),"Ordinary road still opens its bubble")
	check(bubble_text().contains("Road D — E") and bubble_text().contains(PresentationText.BRIDGE_ONLY),"Ordinary road explains the rule")
	check(button_containing("CLOSE BRIDGE") == null,"Ordinary road offers no closure button")
	# A direct (non-button) request is still refused by authoritative validation.
	app._request_action("ISOLATE","D-E")
	await settle(3)
	check(is_instance_valid(app.source_picker) and app.source_picker.feasible_options().is_empty(),"Picker for an ordinary road has no eligible depot")
	check(button_containing("Confirm delivery") == null and app.session.state.total_supply() == 6,"No confirmation or spending for an ordinary road")
	var refused: Dictionary = app.session.dispatch_action("ISOLATE","D-E",pair(["A","A"]))
	check(not refused.ok and refused.error == "NOT A BRIDGE" and app.session.state.total_supply() == 6,"Direct dispatch of an ordinary road refused without cost")
	await click("Cancel")
	check(not is_instance_valid(app.source_picker) and app.session.state.actions.is_empty(),"Cancel leaves no action")
	# Bridge: explained with the neutral consequence and the Close bridge action.
	await map_click("B-D",true)
	check(bubble_text().contains("Bridge B — D") and bubble_text().contains(PresentationText.CLOSURE_EFFECT),"Bridge bubble states the consequence neutrally")
	var close_button := button_containing("CLOSE BRIDGE")
	check(close_button != null and not close_button.disabled and close_button.text.contains("2 supply"),"Bridge offers Close bridge at two supplies")
	await click("CLOSE BRIDGE")
	check(is_instance_valid(app.source_picker) and app.board.preview_edge == "B-D","Close bridge opens source selection with preview")
	await select_delivery_sources(["A","H"])
	check(app.session.state.total_supply() == 6,"Source selection never reserves supplies")
	await click("Cancel")
	check(not is_instance_valid(app.source_picker) and app.session.state.total_supply() == 6 and app.session.state.actions.is_empty(),"Cancellation spends nothing")
	# Duplicate confirmation produces exactly one closure.
	await map_click("B-D",true)
	await click("CLOSE BRIDGE")
	await select_delivery_sources(["A","H"])
	var picker = app.source_picker
	check(button_containing("Confirm delivery") != null,"Confirmation available after both sources")
	picker.confirm_selection()
	picker.confirm_selection()
	await settle()
	check(app.session.state.total_supply() == 4 and app.session.phase == GameManager.Phase.DELIVERY,"Duplicate confirmation reserves two supplies once")
	check(not app.session.state.edges["B-D"].isolated,"Bridge open while deliveries travel")
	await wait_delivery()
	check(app.session.state.edges["B-D"].isolated and app.session.state.actions.size() == 1,"One closure after both deliveries arrive")
	var logged: Array = app.session.logger.to_array().filter(func(e: Dictionary): return e.type == "EDGE_ISOLATED")
	check(logged.size() == 1 and logged[0].target == "B-D","Existing EDGE_ISOLATED log entry recorded once")
	await map_click("B-D",true)
	check(bubble_text().contains("Closed") and button_containing("CLOSE BRIDGE") == null,"Closed bridge offers no further action")
	app.queue_free()
	await settle()

func practice_checks() -> void:
	for chinese in [false,true]:
		FirstPlayText.chinese = chinese
		var practice := PracticeView.new()
		root.add_child(practice)
		await settle(3)
		check(practice.scenario.bridges == ["C-E","D-F"],"Practice uses the same bridge rule")
		practice.step = 1
		practice.select_road("A-C")
		await settle(2)
		var text := ""
		for node in descendants(practice,"Label")+descendants(practice,"Button"): text += str(node.text)+"\n"
		check(text.contains("只有桥梁可以关闭" if chinese else "Only bridges can be closed"),"Practice explains the rule on an ordinary road")
		check(not text.contains("关闭桥梁 · 2" if chinese else "Close bridge · 2"),"Practice offers no closure on an ordinary road")
		practice.select_road("C-E")
		await settle(2)
		text = ""
		for node in descendants(practice,"Label")+descendants(practice,"Button"): text += str(node.text)+"\n"
		check(text.contains("关闭桥梁 · 2" if chinese else "Close bridge · 2"),"Practice teaches Close bridge on a bridge")
		check(text.contains("将阻止疫情传播和物资运送经过此连接" if chinese else "blocks outbreak spread and supply deliveries across this connection"),"Practice states the consequence")
		var before := practice.state.total_supply()
		practice.perform_delivery("ISOLATE","A-C",pair(["A","A"]))
		check(practice.state.total_supply() == before and not practice.busy,"Practice refuses ordinary-road closure without cost")
		practice.queue_free()
		await settle()
	FirstPlayText.chinese = false
