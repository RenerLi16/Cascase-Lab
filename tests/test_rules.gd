extends SceneTree

var checks := 0
var failures := 0
var support_time := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func fresh() -> GameManager:
	var game := GameManager.new(null,GameManager.InterventionType.NONE,func(): return support_time)
	game.logger.capture_timing = false
	return game

func _run() -> void:
	test_scenario_and_routes()
	test_delivery_and_actions()
	test_resolution()
	test_private_flow_and_logging()
	test_strategy()
	print("RULE TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func survey_round(game: GameManager) -> void:
	check(game.phase==GameManager.Phase.OBSERVE,"Each round begins in Observe")
	game.start_private()
	for index in 3:
		check(game.phase==GameManager.Phase.PRIVATE_GATE,"Handoff before each private form")
		game.open_private_form()
		check(game.submit_belief(PlayerBelief.new("E-F","WAIT","NONE",index+2,"protect supply access")),"Decision survey accepts road danger and wait")
	check(game.phase==GameManager.Phase.DISCUSSION,"No comparison; directly to discussion")
	check(game.begin_support(),"Initial discussion leads to controlled pause")
	game.mark_support_shown()
	support_time += SupportLibrary.PAUSE_SECONDS * 1000
	game.proceed_to_actions()

func act(game: GameManager, kind: String, target: String, assignments: Array[String]) -> bool:
	var result := game.dispatch_action(kind,target,assignments)
	if not result.ok: return false
	return game.complete_delivery(game.run_token)

func resolve(game: GameManager) -> void:
	check(game.begin_resolution(),"Begin resolution only from Actions")
	check(game.apply_resolution(game.run_token),"Apply simultaneous resolution")
	check(game.finish_resolution(game.run_token),"Finish visual resolution phase")

func test_scenario_and_routes() -> void:
	var game := fresh()
	var state := game.state
	check(state.shelters.size()==8,"Eight shelters retained")
	var exposed := 0
	for shelter: ShelterState in state.shelters.values():
		if shelter.zombie_pressure==1: exposed+=1
	check(exposed==1 and state.overrun_ids().is_empty(),"One initial exposure, no Overrun")
	check(state.total_supply()==6 and state.depots.A.supply_remaining==3 and state.depots.H.supply_remaining==3,"Fixed three supply per depot")
	var degree := {}
	for id in state.shelters: degree[id]=0
	for edge: EdgeState in state.edges.values():
		degree[edge.from]+=1
		degree[edge.to]+=1
	check(degree.E==4 and degree.H==1 and degree.B==3,"Hub, leaf and uneven degrees")
	var network := NetworkManager.new(state)
	check(network.get_supply_path("A","E")==["A","D","E"],"Shortest route uses physical road length, not discovery order")
	check(network.get_supply_path("H","A")==["H","G","F","E","D","A"],"Reverse travel is valid on every road")
	var loss := network.preview_isolation("E-F")
	check(loss.A==["F","G","H"] and loss.H==["A","B","C","D","E"],"Chokepoint splits major regions from opposite depots")
	check(not state.edges["E-F"].isolated,"Preview never closes road")
	state.edges["E-D"].isolated=true
	check(network.get_supply_path("A","E")==["A","B","E"],"Loop offers alternate supply route")
	state.edges["E-F"].isolated=true
	check(not network.can_supply_reach("A","F") and not network.can_supply_reach("H","E"),"Closed road blocks supply in both directions")
	state=fresh().state
	network=NetworkManager.new(state)
	state.shelters.E.zombie_pressure=2
	check(not network.can_supply_reach("A","F"),"Overrun hub cannot relay supply")
	check(network.can_supply_reach("A","C") and network.can_supply_reach("H","F"),"Both local clusters remain supplied around lost hub")
	state.shelters.H.zombie_pressure=2
	check(network.get_reachable_shelters("H").is_empty(),"Overrun depot cannot originate supply")

func test_delivery_and_actions() -> void:
	var game := fresh()
	survey_round(game)
	check(game.dispatch_action("VERIFY","E",["H"]).ok,"Dispatch Verify")
	check(game.phase==GameManager.Phase.DELIVERY,"Delivery is an explicit locked phase")
	check(game.state.depots.H.supply_remaining==2 and game.state.shelters.E.verified_history.is_empty(),"Spend at dispatch, reveal only on arrival")
	check(game.pending_action.deliveries[0].path==["H","G","F","E"],"Log actual shortest route for courier")
	check(not game.dispatch_action("SHIELD","E",["A"]).ok and not game.begin_resolution(),"Cannot act or resolve during delivery")
	var old_action := game.pending_action
	check(game.complete_delivery(game.run_token),"Arrival completes information action immediately")
	check(game.latest_observation.pressure==1 and game.latest_observation.round==1,"Verify current exact pressure")
	check(not game.action_manager.complete_delivery(old_action).ok,"Duplicate arrival cannot reapply action")
	check(game.state.shelters.E.zombie_pressure==1,"Supply never heals")
	check(act(game,"MONITOR","E",["H"]),"Permanent monitor installation")
	check(game.state.shelters.E.monitor_known_pressure==-1,"Monitor installation keeps baseline hidden")
	check(not act(game,"MONITOR","E",["A"]),"Duplicate monitor rejected")
	check(game.dispatch_action("ISOLATE","E-F",["A","H"]).ok,"Isolation can split funding between depots")
	check(game.pending_action.deliveries.size()==2,"Isolation dispatches two endpoint deliveries")
	check(game.pending_action.deliveries[0].target=="E" and game.pending_action.deliveries[1].target=="F","Each endpoint receives one unit")
	check(not game.state.edges["E-F"].isolated,"Road stays open until both couriers arrive")
	game.complete_delivery(game.run_token)
	check(game.state.edges["E-F"].isolated and game.state.total_supply()==2,"Road closes after deliveries and two units are spent")
	check(not act(game,"ISOLATE","E-F",["A","A"]),"Cannot pay for closed road again")
	check(not act(game,"SHIELD","F",["A"]),"Unreachable action rejected")
	resolve(game)
	check(game.state.monitor_alerts.size()==1 and "1 → 2" in game.state.monitor_alerts[0],"Monitor reports later exposure progression")
	check(game.state.shelters.E.verified_history[0].pressure==1,"Verification snapshot remains historical")
	check(game.state.shelters.E.is_monitored,"Monitor survives overrun")
	var test_game := fresh()
	survey_round(test_game)
	test_game.state.depots.A.supply_remaining=1
	test_game.state.depots.H.supply_remaining=1
	var before := test_game.state.total_supply()
	check(not test_game.dispatch_action("ISOLATE","E-F",["A","A"]).ok,"Cannot promise two deliveries from one unit")
	check(test_game.state.total_supply()==before and test_game.phase==GameManager.Phase.ACTIONS,"Failed reservation is atomic")
	check(act(test_game,"ISOLATE","E-F",["A","H"]),"Two half-funded depots can jointly isolate")
	check(test_game.state.total_supply()==0,"Split spend consumes exact stock")
	test_game=fresh()
	survey_round(test_game)
	check(act(test_game,"ISOLATE","E-F",["H","H"]),"One depot may fund both endpoints")
	test_game=fresh()
	survey_round(test_game)
	test_game.state.shelters.E.zombie_pressure=2
	check(test_game.action_manager.unavailable_reason("ISOLATE","E-F")=="ENDPOINT OVERRUN","Cannot deliver isolation team inside Overrun endpoint")
	check(not act(test_game,"VERIFY","E",["A"]),"Overrun cannot receive Verify")
	var token := test_game.run_token
	test_game.reset()
	check(not test_game.complete_delivery(token),"Stale animation cannot mutate restarted session")

func test_resolution() -> void:
	var game := fresh()
	survey_round(game)
	var before := JSON.stringify(game.state.to_dictionary())
	var plan := game.preview_resolution()
	check(JSON.stringify(game.state.to_dictionary())==before,"Preview is pure")
	check(plan.movements.is_empty(),"Hidden exposure never emits a visible zombie path")
	check(act(game,"SHIELD","E",["H"]),"Can shield initially exposed location")
	resolve(game)
	check(game.state.overrun_ids()==["E"],"Initial exposure matures during first resolution")
	check(not game.state.shelters.E.shielded_this_round,"Shield expires and cannot cure existing exposure")
	check(game.state.shelters.B.zombie_pressure==0,"Newly Overrun shelter does not spread same phase")
	game.next_round()
	survey_round(game)
	check(act(game,"SHIELD","B",["A"]),"Shield unexposed neighbor before spread")
	resolve(game)
	check(game.state.shelters.B.zombie_pressure==0,"Shield blocks incoming infection")
	check(game.state.shelters.C.zombie_pressure==1 and game.state.shelters.D.zombie_pressure==1 and game.state.shelters.F.zombie_pressure==1,"Overrun hub spreads across both endpoint orientations")
	check(game.state.overrun_ids()==["E"],"New exposure remains hidden until later resolution")
	game.next_round()
	survey_round(game)
	resolve(game)
	check(game.state.shelters.B.zombie_pressure==1,"Expired shield permits later exposure")
	check(game.state.shelters.C.is_overrun and game.state.shelters.D.is_overrun,"Exposed neighbors mature next phase")
	check(game.state.shelters.E.zombie_pressure==2,"Overrun is permanent and capped")
	game=fresh()
	survey_round(game)
	for shelter: ShelterState in game.state.shelters.values(): shelter.zombie_pressure=0
	game.state.shelters.B.zombie_pressure=2
	game.state.shelters.D.zombie_pressure=2
	resolve(game)
	check(game.state.shelters.A.zombie_pressure==2 and game.state.shelters.E.zombie_pressure==2,"Multiple incoming sources stack")
	check(game.state.shelters.C.zombie_pressure==1,"Bidirectional road B-C transmits")
	game=fresh()
	survey_round(game)
	for shelter: ShelterState in game.state.shelters.values(): shelter.zombie_pressure=0
	game.state.shelters.B.zombie_pressure=2
	game.state.shelters.D.zombie_pressure=2
	game.state.shelters.A.shielded_this_round=true
	game.state.shelters.E.shielded_this_round=true
	resolve(game)
	check(game.state.shelters.A.zombie_pressure==0 and game.state.shelters.E.zombie_pressure==0,"Shield blocks all stacked infection")
	game=fresh()
	survey_round(game)
	check(act(game,"ISOLATE","E-F",["A","H"]),"Isolate before origin becomes inaccessible")
	for round_number in 3:
		resolve(game)
		if round_number<2: game.next_round(); survey_round(game)
	check(game.state.shelters.F.zombie_pressure==0,"Isolation blocks all later zombie movement on road")

func canonical(payload: Dictionary) -> Dictionary:
	var copy := payload.duplicate(true)
	for event in copy.events:
		event.erase("timestamp_utc")
		event.erase("elapsed_ms")
	return copy

func test_private_flow_and_logging() -> void:
	var game := fresh()
	check(game.public_intel.size()==1 and game.public_intel[0].round==1,"Round 1 intel shown on Observe")
	check(not game.begin_resolution() and not game.dispatch_action("VERIFY","E",["H"]).ok,"Phase guards prevent premature actions")
	game.start_private()
	game.open_private_form()
	check(not game.submit_belief(PlayerBelief.new("Z","VERIFY","E",3)),"Reject unknown danger location")
	check(not game.submit_belief(PlayerBelief.new("E","ISOLATE","A",3)),"Isolation survey target must be road")
	check(not game.submit_belief(PlayerBelief.new("E","WAIT","E",3)),"Wait requires no target")
	check(not game.submit_belief(PlayerBelief.new("E","SHIELD","A",6)),"Confidence limited to 1–5")
	check(not game.submit_belief(PlayerBelief.new("E","SHIELD","A",3,"free text")),"Reason remains structured")
	game=fresh()
	for round_number in 3:
		survey_round(game)
		check(game.private_surveys[round_number+1].size()==3,"Exactly three private measurements each round")
		resolve(game)
		game.next_round()
		check(game.state.total_supply()==6,"No supply regeneration or involuntary spending")
	check(game.phase==GameManager.Phase.RESULTS and game.state.round==3,"Ends exactly after Round 3")
	check(not game.begin_resolution(),"No fourth resolution")
	check(game.public_intel.size()==3,"One predefined report at each round boundary")
	var exported := game.export_dictionary()
	check(exported.private_surveys.size()==9,"All nine surveys retained in research export")
	check(not exported.private_surveys[0].response.has("suspected_source"),"Retired source question absent from new schema")
	check(JSON.parse_string(JSON.stringify(exported)).events.size()==game.logger.events.size(),"Research JSON roundtrips")
	var intel_events := 0
	var survey_events := 0
	for index in game.logger.events.size():
		var event := game.logger.events[index]
		check(event.order==index+1,"Contiguous event order")
		if event.type=="PUBLIC_INTEL_SHOWN": intel_events+=1
		if event.type=="PRIVATE_SURVEY_SUBMITTED": survey_events+=1
	check(intel_events==3 and survey_events==9,"Exact standardized intel and survey counts")
	var timed := EventLogger.new()
	timed.record(1,"TEST")
	check(timed.events[0].elapsed_ms>=0 and timed.events[0].timestamp_utc.ends_with("Z"),"Research events include elapsed and UTC timing")
	game.set_dev_mode(true)
	game.set_dev_mode(false)
	check(game.dev_used,"Dev exposure remains flagged")
	game.reset()
	check(game.state.total_supply()==6 and game.private_surveys.is_empty() and game.state.actions.is_empty(),"Restart clears supplies, surveys and actions")
	check(game.public_intel.size()==1 and not game.dev_used and game.state.overrun_ids().is_empty(),"Restart resets intel, dev flag and initial hidden state")
	var first := fresh()
	var second := fresh()
	for round_number in 3:
		for run: GameManager in [first,second]:
			survey_round(run)
			resolve(run)
			run.next_round()
	check(canonical(first.export_dictionary())==canonical(second.export_dictionary()),"Identical decisions reproduce all state and events except real timing")

func test_strategy() -> void:
	var good := fresh()
	survey_round(good)
	check(act(good,"VERIFY","E",["H"]),"Use eastern depot for initial investigation")
	resolve(good)
	good.next_round()
	survey_round(good)
	for id in ["B","C","D"]: check(act(good,"SHIELD",id,["A"]),"Western stock protects local neighbor "+id)
	check(act(good,"SHIELD","F",["H"]),"Eastern stock protects local neighbor F")
	resolve(good)
	good.next_round()
	survey_round(good)
	resolve(good)
	check(8-good.state.overrun_ids().size()==7 and good.state.total_supply()==1,"Strong informed strategy saves seven with one supply remaining")
	# Test-only randomness: game code itself has no random outbreak or decisions.
	var rng := RandomNumberGenerator.new()
	rng.seed=73019
	var saved := 0
	for trial in 200:
		var random_game := fresh()
		for round_number in 3:
			random_game.phase=GameManager.Phase.ACTIONS
			for choice in 2:
				var legal: Array = []
				for kind in GameAction.TYPES:
					var targets: Array = random_game.state.edges.keys() if kind=="ISOLATE" else random_game.state.shelters.keys()
					for target in targets:
						if random_game.action_manager.unavailable_reason(kind,target)!="": continue
						for option in random_game.action_manager.supply.delivery_options(kind,target): legal.append({"kind":kind,"target":target,"depots":option})
				if not legal.is_empty():
					var action: Dictionary=legal[rng.randi_range(0,legal.size()-1)]
					var assignments: Array[String]=[]
					assignments.assign(action.depots)
					act(random_game,action.kind,action.target,assignments)
			random_game.begin_resolution()
			random_game.apply_resolution(random_game.run_token)
			random_game.finish_resolution(random_game.run_token)
			random_game.next_round()
		saved += 8-random_game.state.overrun_ids().size()
	var average := float(saved)/200.0
	print("STRATEGY: informed 7/8; no containment 3/8; seeded random %.2f/8 (200 trials)" % average)
	check(average<5.5,"Informed strategy substantially outperforms random legal actions")
