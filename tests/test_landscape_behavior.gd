extends SceneTree

const FIXTURE := "res://tests/landscape_behavior_baseline.json"
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func legacy_duration(view: NetworkView, nodes: Array) -> float:
	var path := view.world_path_for_nodes(nodes)
	var length := 0.0
	for i in path.size()-1: length += path[i].distance_to(path[i+1])
	return clampf(0.7+length/900.0,0.7,1.5)

func _initialize() -> void:
	var record := OS.get_environment("LANDSCAPE_BASELINE") == "record"
	var result := {}
	for entry in ScenarioData.registry().scenarios:
		var data := ScenarioData.load_by_id(entry.id)
		var state := GameState.new(data)
		var view := NetworkView.new()
		view.scenario = data
		view.state = state
		var scenario := {"edges":[],"routes":[]}
		for e in state.edges.values(): scenario.edges.append(e.to_dictionary())
		# All combinations of designated closures, plus every single overrun location.
		for mask in 1 << data.bridges.size():
			for i in data.bridges.size(): state.edges[data.bridges[i]].isolated = bool(mask & (1 << i))
			for overrun in [""]+data.node_positions.keys():
				for id in state.shelters: state.shelters[id].is_overrun = id == overrun
				for depot in data.supply_depots:
					for target in data.node_positions:
						var path := NetworkManager.new(state).get_supply_path(depot,target)
						var cost := 0.0
						for i in path.size()-1: cost += state.edges[NetworkManager.new(state).road_between(path[i],path[i+1])].length
						var duration := legacy_duration(view,path) if record else float(view.call("delivery_duration",[{"path":path}]))
						scenario.routes.append([mask,overrun,depot,target,path,snappedf(cost,0.000001),snappedf(duration,0.000001)])
		result[entry.id] = scenario
		view.free()
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenario_validation_cases.json")).cases
	cases.append({"name":"Riverside / verify, monitor, close crossing and protect", "file":"scenario_01.json", "round_actions":[[["VERIFY","E",["A"]],["MONITOR","E",["H"]],["ISOLATE","E-F",["A","H"]]],[["SHIELD","B",["A"]]],[]]})
	cases.append({"name":"Riverside / no actions", "file":"scenario_01.json", "round_actions":[[],[],[]]})
	result.replays = []
	for spec in cases:
		var game := GameManager.new(ScenarioData.load_path("res://scenarios/"+spec.file),GameManager.InterventionType.NONE,func(): return 0,GameManager.RunPurpose.DEV_SANDBOX)
		game.logger.capture_timing = false
		var replay := {"name":spec.name,"rounds":[]}
		for round_index in 3:
			game.begin_sandbox_actions()
			for action in spec.round_actions[round_index]:
				var depots: Array[String] = []
				depots.assign(action[2])
				check(game.dispatch_action(action[0],action[1],depots).ok,"Replay action accepted")
				game.complete_delivery(game.run_token)
			game.begin_resolution()
			game.apply_resolution(game.run_token)
			game.finish_resolution(game.run_token)
			replay.rounds.append(game.last_summary.duplicate(true))
			game.next_round()
		replay.events = game.logger.to_array()
		for event in replay.events:
			event.erase("timestamp_utc")
			event.erase("elapsed_ms")
		result.replays.append(replay)
	# JSON normalizes Vector/int/float representations consistently for the comparison.
	result = JSON.parse_string(JSON.stringify(result))
	if record:
		FileAccess.open(FIXTURE,FileAccess.WRITE).store_string(JSON.stringify(result))
		print("Saved pre-change route, timing and replay baseline")
	else:
		FileAccess.open("/tmp/landscape-behavior-actual.json",FileAccess.WRITE).store_string(JSON.stringify(result))
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
		for id in result:
			if id == "replays":
				check(result[id] == expected[id],"All deterministic action/resolution/log replays unchanged")
			else:
				check(result[id].edges == expected[id].edges,"Connections, weights and eligibility unchanged: "+id)
				for i in result[id].routes.size(): check(result[id].routes[i] == expected[id].routes[i],"Route/cost/delivery timing unchanged: %s %d" % [id,i])
		print("LANDSCAPE BEHAVIOR: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
