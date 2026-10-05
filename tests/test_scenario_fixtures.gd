extends SceneTree

var failures := 0
var checks := 0
var pack_path := ""

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func load_fixture_scenario(filename: String) -> ScenarioData:
	var scenario := ScenarioData.load_path("res://scenarios/" + filename)
	check(scenario != null, "Production loader accepts " + filename + ": " + ScenarioData.last_error)
	return scenario

func run_case(spec: Dictionary) -> void:
	var scenario := load_fixture_scenario(spec.file)
	var game := GameManager.new(scenario,GameManager.InterventionType.NONE,Callable(),GameManager.RunPurpose.DEV_SANDBOX)
	for round_index in 3:
		check(game.begin_sandbox_actions(),"Sandbox enters actions without fabricated responses")
		for action in spec.round_actions[round_index]:
			var depots: Array[String] = []
			depots.assign(action[2])
			var result := game.dispatch_action(action[0], action[1], depots)
			check(result.ok, "%s R%d legal action: %s" % [spec.name, round_index + 1, str(action)])
			if not result.ok: return
			check(game.complete_delivery(game.run_token), "Delivery completed through actual action manager")
		check(game.begin_resolution(), "Resolution begins")
		check(game.apply_resolution(game.run_token), "Resolution applies")
		check(game.finish_resolution(game.run_token), "Resolution finishes")
		check(game.last_summary.survivors == int(spec.survivors[round_index]), "%s R%d survivor count" % [spec.name, round_index + 1])
		check(game.state.total_supply() == int(spec.supplies[round_index]), "%s R%d remaining stock" % [spec.name, round_index + 1])
		game.next_round()
	for id in spec.final_pressures:
		check(game.state.shelters[id].zombie_pressure == int(spec.final_pressures[id]), "%s final pressure %s" % [spec.name, id])
	check(game.phase == GameManager.Phase.RESULTS, "Three rounds reach results")
	print("CASE: ", spec.name, " | functioning=", spec.survivors, " | supplies=", spec.supplies)

func check_bridge_mechanisms() -> void:
	var twin := GameState.new(load_fixture_scenario("scenario_02.json"))
	var twin_loss := NetworkManager.new(twin).preview_isolation("D-E")
	check(twin_loss.A == ["E", "F", "G", "H"], "Twin bridge separates the eastern district from west depot")
	check(twin_loss.H == ["A", "B", "C", "D"], "Twin bridge separates the western district from east depot")
	var life := GameManager.new(load_fixture_scenario("scenario_03.json"))
	var life_loss := NetworkManager.new(life.state).preview_isolation("D-E")
	check(life_loss.A == ["E", "F", "G", "H"] and life_loss.C == ["E", "F", "G", "H"], "Lifeline closure cuts eastern nodes off from BOTH depots")
	life.phase = GameManager.Phase.ACTIONS
	var funding: Array[String] = ["A", "A"]
	check(life.dispatch_action("ISOLATE", "D-E", funding).ok, "Lifeline closure can be funded before cutting its own route")
	check(life.complete_delivery(life.run_token), "Lifeline closure completes")
	check(SupplyManager.new(life.state).eligible_depots("G").is_empty(), "Remaining western stock cannot reach G after closure")
	check(life.state.total_supply() == 4, "Four supplies remain despite inaccessible eastern shelters")

func _initialize() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenario_validation_cases.json"))
	for spec in fixtures.cases: run_case(spec)
	check_bridge_mechanisms()
	print("RESULT: ", checks, " checks; ", failures, " failures. Production loader and scenario fixtures tested. Research balance is not tested.")
	quit(1 if failures else 0)
