extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func fresh() -> GameManager:
	return GameManager.new()

func _run() -> void:
	test_scenario_and_routes()
	test_actions()
	test_spread()
	test_plan_transactions()
	test_flow_and_replay()
	test_strategy()
	print("RULE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_scenario_and_routes() -> void:
	var game := fresh()
	var state := game.state
	var network := NetworkManager.new(state)
	check(state.shelters.size()==8 and state.depots.size()==2,"Eight shelters and two depots")
	check(state.total_supply()==6,"Exactly six supply initially")
	check(state.overrun_ids()==["D"],"Only D initially Overrun")
	check(network.can_supply_reach("H","A"),"Supply can traverse arrows backwards")
	check(network.get_supply_path("H","A")==["H","G","E","B","A"],"Deterministic shortest supply path")
	check(not network.can_supply_reach("A","D"),"Overrun target cannot receive supply")
	check(network.get_supply_path("A","F").has("D")==false,"Overrun node never relays supply")
	check(network.get_reachable_shelters("A").size()==7,"All living nodes reachable initially")
	var preview := network.preview_isolation("G-H")
	check(preview.A==["H"],"G-H cut removes H from Depot A")
	check(preview.H==["A","B","C","E","F","G"],"G-H cut removes west from Depot H")
	check(not state.edges["G-H"].isolated,"Preview does not mutate actual edge")
	check(game.action_manager.isolate("G-H","H").ok,"Can close road from reachable endpoint")
	check(not network.can_supply_reach("H","G"),"Isolated road blocks supply both ways")
	check(state.depots.H.supply_remaining==1,"Isolation costs two from chosen depot")
	check(not game.action_manager.isolate("G-H","A").ok,"Cannot isolate twice")
	check(not game.action_manager.shield("G","H").ok,"Cannot spend disconnected depot supply")
	state.shelters.A.zombie_pressure=2
	check(network.get_reachable_shelters("A").is_empty(),"Overrun depot cannot originate supply")

func test_actions() -> void:
	var game := fresh()
	var manager := game.action_manager
	check(manager.verify("B","H").ok,"Verify can use chosen remote depot")
	check(game.state.shelters.B.zombie_pressure==1,"Verify does not heal")
	check(game.state.shelters.B.verified_history==[{"round":1,"pressure":1}],"Verify exact current pressure with date")
	check(game.state.depots.H.supply_remaining==2 and game.state.depots.A.supply_remaining==3,"Correct depot deduction")
	check(manager.monitor("F","A").ok,"Monitor reachable shelter")
	check(game.state.shelters.F.monitor_known_pressure==-1,"Monitor installation does not reveal baseline")
	check(not manager.monitor("F","A").ok,"No duplicate monitor charges")
	check(manager.shield("E","A").ok,"Shield reachable shelter")
	check(game.state.shelters.E.zombie_pressure==1,"Shield does not heal exposed shelter")
	check(NetworkManager.new(game.state).can_supply_reach("H","A"),"Shield leaves supply routes active")
	check(not manager.shield("E","H").ok,"Cannot waste supply on duplicate shield")
	check(not manager.verify("D","A").ok,"Overrun actions unavailable")
	var before := game.state.total_supply()
	check(not manager.execute(GameAction.new("CHEAT","A","A",1)).ok,"Reject unknown action")
	check(not manager.execute(GameAction.new("VERIFY","A","A",2)).ok,"Reject stale round")
	check(not manager.execute(GameAction.new("VERIFY","A","",1)).ok,"Require a named depot")
	check(before==game.state.total_supply(),"Rejected requests never spend")
	game.resolve_zombie_spread()
	check(game.state.shelters.E.zombie_pressure==1,"Shield blocks entire incoming pressure")
	check(not game.state.shelters.E.shielded_this_round,"Shield expires after one spread")
	game.state.round=2
	game.resolve_zombie_spread()
	check(game.state.shelters.E.is_overrun,"Expired shield does not block later phase")
	game.state.round=3
	game.resolve_zombie_spread()
	check(game.state.shelters.B.verified_history[0].pressure==1,"Historical verification never updates")
	check(game.state.shelters.B.zombie_pressure==2,"Verified node can change later")
	check(game.state.monitor_alerts.size()==1 and "0 → 1" in game.state.monitor_alerts[0],"Monitor reports later exact change")
	check(game.state.shelters.F.is_monitored,"Monitor persists across rounds")

func test_spread() -> void:
	var game := fresh()
	var result := game.resolve_zombie_spread()
	check(result.newly_overrun==["E","G"],"Initial spread follows directed outgoing edges")
	check(game.state.shelters.B.zombie_pressure==1,"No reverse zombie spread through B-D")
	check(game.state.shelters.F.zombie_pressure==0 and game.state.shelters.H.zombie_pressure==0,"No same-phase cascades")
	check(game.state.shelters.D.zombie_pressure==2,"Overrun stays capped at two")
	game.state.shelters.C.zombie_pressure=2
	game.state.shelters.F.shielded_this_round=true
	game.resolve_zombie_spread()
	check(game.state.shelters.F.zombie_pressure==0,"Shield blocks stacked incoming pressure")
	game.resolve_zombie_spread()
	check(game.state.shelters.F.zombie_pressure==2,"Two incoming sources stack when shield expires")
	check(game.state.shelters.D.is_overrun,"Overrun remains permanent across phases")
	game=fresh()
	game.action_manager.isolate("D-E","A")
	check(game.resolve_zombie_spread().newly_overrun==["G"],"Isolation prevents zombie transmission")
	# Outgoing infection ignores a source's shield, including defensive state loaded by a future server.
	game=fresh()
	game.state.shelters.D.shielded_this_round=true
	check(game.resolve_zombie_spread().newly_overrun==["E","G"],"Shield never blocks outgoing zombies")
	# Verify is a dated snapshot of CURRENT pressure, even after prior spread.
	game=fresh()
	game.resolve_zombie_spread()
	game.state.round=2
	check(game.action_manager.verify("F","A").ok,"Verify remains possible after route changes")
	check(game.state.shelters.F.verified_history.back()=={"round":2,"pressure":0},"Verification records current round and pressure")

func test_plan_transactions() -> void:
	var game := fresh()
	var plan: Array[GameAction] = [GameAction.new("VERIFY","A","A",1),GameAction.new("ISOLATE","D-E","A",1),GameAction.new("SHIELD","G","A",1)]
	check(not game.action_manager.commit_plan(plan).ok,"Overspending plan rejected atomically")
	check(game.state.total_supply()==6 and game.state.actions.is_empty(),"Rejected batch leaves supplies and actions untouched")
	check(game.state.shelters.A.verified_history.is_empty(),"Rejected plan reveals no information")
	plan = [GameAction.new("ISOLATE","G-H","H",1),GameAction.new("SHIELD","E","H",1)]
	check(not game.action_manager.commit_plan(plan).ok,"Later road-dependent action invalidated by earlier closure")
	check(not game.state.edges["G-H"].isolated,"Failed route-dependent plan rolls back whole batch")
	plan = [GameAction.new("ISOLATE","G-H","H",1),GameAction.new("VERIFY","E","H",1)]
	check(game.action_manager.commit_plan(plan).ok,"Information phase applies before containment phase")
	check(game.state.actions[0].type=="VERIFY" and game.state.actions[1].type=="ISOLATE","Information-first execution is stable")
	check(game.state.total_supply()==3,"Whole plan commits exact resource cost")
	game=fresh()
	var forged := GameAction.new("ISOLATE","D-E","A",1)
	forged.cost=0
	check(game.action_manager.execute(forged).ok and game.state.depots.A.supply_remaining==1,"Costs recomputed from rules, never trusted from request")
	game=fresh()
	game.state.depots.A.supply_remaining=1
	game.state.depots.H.supply_remaining=1
	check(not game.action_manager.can_isolate("D-E"),"Isolation cannot combine one unit from each depot")

func submit_all(game: GameManager, source: String) -> void:
	for index in 3:
		check(game.phase==GameManager.Phase.PRIVATE_GATE,"Separate privacy handoff for every player")
		game.open_private_form()
		check(game.submit_belief(PlayerBelief.new(source,"F","SHIELD",index+2)),"Private belief accepted")

func prepare_actions(game: GameManager) -> void:
	game.start_briefing()
	game.start_private()
	submit_all(game,"B")
	game.begin_discussion()
	game.proceed_to_actions()

func finish_round(game: GameManager) -> void:
	check(game.resolve_round(),"Round resolves from action phase")
	check(game.phase==GameManager.Phase.SUMMARY,"Round summary shown")
	game.continue_after_summary()
	if game.phase==GameManager.Phase.DIAGNOSTIC:
		check(game.state.round==1,"Diagnostic evidence occurs immediately after Round 1 summary")
		game.start_private(true)
		submit_all(game,"D")
		check(game.phase==GameManager.Phase.BELIEFS,"Belief comparison shown after three updates")
		game.begin_discussion()
	if game.phase==GameManager.Phase.DISCUSSION: game.proceed_to_actions()

func test_flow_and_replay() -> void:
	var game := fresh()
	check(not game.resolve_round(),"Cannot skip phases from menu")
	check(not game.queue_action("SHIELD","E","A").ok,"Cannot queue actions outside action phase")
	game.start_briefing()
	game.start_private()
	game.open_private_form()
	check(not game.submit_belief(PlayerBelief.new("Z","F","SHIELD",3)),"Invalid shelter belief rejected")
	check(not game.submit_belief(PlayerBelief.new("B","D","SHIELD",3)),"Already Overrun prediction rejected")
	check(not game.submit_belief(PlayerBelief.new("B","F","SHIELD",6)),"Confidence limited to 1–5")
	check(game.initial_beliefs.is_empty(),"Invalid beliefs never appended")
	game=fresh()
	prepare_actions(game)
	check(game.initial_beliefs.size()==3,"Three initial beliefs collected")
	check(game.queue_action("SHIELD","E","A").ok,"Queue action")
	check(game.state.total_supply()==6,"Queue does not spend actual supply")
	check(not game.resolve_round(),"Cannot silently discard an unconfirmed plan")
	check(game.confirm_actions().ok,"Confirm queued action")
	finish_round(game)
	check(game.state.round==2 and game.updated_beliefs.size()==3,"Round 2 starts only after mandatory private updates")
	check(game.belief_change_count()==3,"Source belief changes counted")
	finish_round(game)
	check(game.state.round==3,"Exactly next round reached")
	finish_round(game)
	check(game.phase==GameManager.Phase.RESULTS,"Results appear after third round")
	check(not game.resolve_round(),"Cannot resolve a fourth round")
	var payload := game.export_dictionary()
	var encoded := JSON.stringify(payload)
	check(JSON.parse_string(encoded).events.size()==game.logger.events.size(),"Structured event JSON roundtrips")
	check(payload.ground_truth.original_source=="D","Export includes ground truth at results")
	check(payload.initial_beliefs.size()==3 and payload.post_evidence_beliefs.size()==3,"Export includes both belief collections")
	var diagnostic_count := 0
	var complete_count := 0
	for index in game.logger.events.size():
		var event: GameEvent = game.logger.events[index]
		check(event.order==index+1,"Event order is contiguous and deterministic")
		if event.type=="DIAGNOSTIC_EVIDENCE_SHOWN": diagnostic_count+=1
		if event.type=="SESSION_COMPLETED": complete_count+=1
	check(diagnostic_count==1 and complete_count==1,"Mandatory diagnostic and completion each occur once")
	game.set_dev_mode(true)
	game.set_dev_mode(false)
	check(game.dev_used,"Development exposure is permanently flagged for session")
	game.reset()
	check(game.phase==GameManager.Phase.MENU and game.state.total_supply()==6,"Restart restores mission")
	check(game.initial_beliefs.is_empty() and game.updated_beliefs.is_empty() and game.logger.events.size()==1,"Restart clears beliefs and logs")
	check(not game.dev_used and not game.dev_mode,"Restart clears dev exposure")
	var first := fresh()
	var second := fresh()
	prepare_actions(first)
	prepare_actions(second)
	for index in 3:
		finish_round(first)
		finish_round(second)
	check(JSON.stringify(first.export_dictionary())==JSON.stringify(second.export_dictionary()),"Identical decisions yield identical state and event payloads")

func test_strategy() -> void:
	var bad := fresh()
	for index in 3: bad.resolve_zombie_spread()
	check(8-bad.state.overrun_ids().size()==1,"No containment leaves one surviving shelter")
	var good := fresh()
	check(good.action_manager.isolate("D-E","A").ok,"Strong strategy closes first source edge")
	check(good.action_manager.isolate("D-G","H").ok,"Strong strategy closes second source edge")
	for index in 3: good.resolve_zombie_spread()
	check(8-good.state.overrun_ids().size()==7,"Strong strategy saves all seven initially living shelters")
	check(good.state.total_supply()==2,"Strong strategy retains two supply")
	var shields := fresh()
	for index in 3:
		check(shields.action_manager.shield("E","A").ok,"Alternative strategy can shield E each round")
		check(shields.action_manager.shield("G","H").ok,"Alternative strategy can shield G each round")
		shields.resolve_zombie_spread()
		shields.state.round+=1
	check(8-shields.state.overrun_ids().size()==7 and shields.state.total_supply()==0,"All-shield strategy is also viable")
	# Deterministic test-only baseline: uniformly sample legal actions (not part of gameplay).
	var rng := RandomNumberGenerator.new()
	rng.seed=73019
	var saved := 0
	for trial in 200:
		var random_game := fresh()
		for round_number in range(1,4):
			random_game.state.round=round_number
			for choice in 2:
				var legal: Array[GameAction] = []
				for kind in GameAction.TYPES:
					var targets: Array = random_game.state.edges.keys() if kind=="ISOLATE" else random_game.state.shelters.keys()
					for target in targets:
						for depot in random_game.action_manager.supply.eligible_depots(target,2 if kind=="ISOLATE" else 1,kind=="ISOLATE"):
							if random_game.action_manager.unavailable_reason(kind,target,depot).is_empty(): legal.append(GameAction.new(kind,target,depot,round_number))
				if not legal.is_empty(): random_game.action_manager.execute(legal[rng.randi_range(0,legal.size()-1)])
			random_game.resolve_zombie_spread()
		saved += 8-random_game.state.overrun_ids().size()
	var average := float(saved)/200.0
	print("STRATEGY: containment 7/8, no containment 1/8, seeded random legal-action baseline %.2f/8 (200 trials)" % average)
	check(average<5.0,"Deliberate containment substantially outperforms random clicking")
