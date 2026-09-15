extends SceneTree

var checks := 0
var failures := 0
var now_ms := 1000

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fresh(condition: int = 0) -> GameManager:
	return GameManager.new(null,condition as GameManager.InterventionType,func(): return now_ms)

func responses(action: String = "VERIFY", target: String = "E", reason: String = "gather more information", confidence: int = 4) -> Array:
	var output: Array = []
	for index in 3: output.append(PlayerBelief.new(target if target != "NONE" else "E",action,target,confidence,reason).to_dictionary())
	return output

func context(game: GameManager, answers: Array = []) -> Dictionary:
	return SupportContext.build(game.state,game.public_intel,answers if not answers.is_empty() else responses())

func submit_round(game: GameManager) -> void:
	game.start_private()
	for index in 3:
		game.open_private_form()
		game.submit_belief(PlayerBelief.new("E","VERIFY","E",4,"gather more information"))

func support_events(game: GameManager) -> Array:
	return game.logger.to_array().filter(func(e: Dictionary): return e.type=="SUPPORT_SHOWN")

func run() -> void:
	test_projection()
	test_templates()
	test_recommendations()
	test_dissent()
	test_lifecycle()
	await test_ui_conditions()
	print("SUPPORT TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func test_projection() -> void:
	var game := fresh()
	var clean := context(game)
	check(clean.shelters.E.known_pressure==-1 and clean.shelters.A.known_pressure==-1,"P0/P1 both remain unknown")
	var dirty := responses()
	dirty[0].player_name="PRIVATE_NAME_CANARY"
	dirty[0].explanation="PRIVATE_TEXT_CANARY"
	dirty[0].participant_id="PRIVATE_ID_CANARY"
	dirty[0].hidden_state={"source":"E"}
	check(context(game,dirty)==clean,"Private metadata is removed by whitelist")
	dirty[0].reason="INJECTED_REASON_CANARY"
	check(not JSON.stringify(context(game,dirty)).contains("CANARY"),"Non-enum reasoning text cannot enter support")
	var before := JSON.stringify(clean)
	for id in game.state.shelters:
		game.state.shelters[id].zombie_pressure=1 if game.state.shelters[id].zombie_pressure==0 else 0
	game.scenario.original_source="HIDDEN_SOURCE_CANARY"
	game.scenario.ground_truth_timeline=[{"text":"FUTURE_CANARY"}]
	game.scenario.public_intel[2].text="UNPUBLISHED_CANARY"
	game.dev_mode=true
	check(JSON.stringify(context(game))==before,"Hidden pressure/source/future intel and Dev Mode never affect the projection")
	for condition in SupportLibrary.CONDITIONS:
		check(SupportLibrary.generate(context(game),condition)==SupportLibrary.generate(clean,condition),"Hidden state cannot alter output: "+condition)
	var supplied_reports: Array = game.public_intel.duplicate(true)
	supplied_reports.append({"round":3,"time":"future","text":"FUTURE_CANARY"})
	check(not JSON.stringify(SupportContext.build(game.state,supplied_reports,responses())).contains("CANARY"),"Future reports filtered even if mistakenly supplied")
	game.state.shelters.E.verified_history.append({"round":1,"pressure":1})
	game.state.shelters.E.verified_history.append({"round":3,"pressure":2})
	game.state.round=2
	var historical := context(game)
	check(historical.shelters.E.known_pressure==-1 and historical.shelters.E.verified_history[0].pressure==1,"Old Verify remains dated, not current hidden pressure")
	check(historical.shelters.E.verified_history.size()==1,"Future dated evidence cannot enter support")
	game.state.shelters.B.is_monitored=true
	check(context(game).shelters.B.known_pressure==-1,"Monitor without an alert has no baseline")
	game.state.shelters.B.monitor_known_pressure=1
	game.state.shelters.C.zombie_pressure=2
	check(context(game).shelters.B.known_pressure==1 and context(game).shelters.C.known_pressure==2,"Public monitor and Overrun information permitted")
	clean.shelters.A.known_pressure=99
	check(game.state.shelters.A.zombie_pressure!=99,"Projection does not alias simulation objects")
	var mixed := responses()
	mixed[0]=PlayerBelief.new("F","SHIELD","F",1,"protect supply access").to_dictionary()
	var original := context(game,mixed)
	mixed.reverse()
	check(original==context(game,mixed),"Anonymous input is invariant to player order")
	for condition in SupportLibrary.CONDITIONS:
		check(SupportLibrary.generate(original,condition)==SupportLibrary.generate(context(game,mixed),condition),"Output is invariant to player order: "+condition)

func test_templates() -> void:
	for id in SupportLibrary.TEMPLATES:
		var text: String = "\n".join(SupportLibrary.TEMPLATES[id]).replace("%s","E-F")
		check(SupportLibrary.word_count(text)>=35 and SupportLibrary.word_count(text)<=60,"35–60 words for "+id)
		check(text.split("\n").size()==3,"Three equal sections for "+id)
		for banned in ["minority","majority","player 1","player 2","player 3"]:
			check(not text.to_lower().contains(banned),"No attribution in "+id)
		if id.begins_with("dissent"):
			check(text.begins_with("Decision check:") and text.contains("\nDiscuss:") and text.contains("\nEvidence to seek:"),"Dissent format")
			check(not text.contains("Recommendation:") and not text.to_lower().contains("choose "),"Dissent does not prescribe a final action")
			check(text.count("?")==1,"One focused discussion question")
		elif id.begins_with("direct"):
			check(text.begins_with("Recommendation:") and text.contains("\nWhy:") and text.contains("\nCheck:"),"Direct format")

func test_recommendations() -> void:
	var game := fresh()
	var input := context(game)
	var advice := SupportLibrary.generate(input,"DIRECT_RECOMMENDATION")
	check(advice.action=="VERIFY" and advice.target=="E","Direct recommends specific valid investigation")
	check(advice==SupportLibrary.generate(JSON.parse_string(JSON.stringify(input)),"DIRECT_RECOMMENDATION"),"JSON roundtrip exactly regenerates text and version")
	for kind in ["MONITOR","ISOLATE"]:
		input=context(game,responses(kind,"E-F" if kind=="ISOLATE" else "E"))
		check(SupportLibrary.generate(input,"DIRECT_RECOMMENDATION").action==kind,"Supported legal proposal: "+kind)
	game.state.shelters.E.zombie_pressure=2
	input=context(game)
	advice=SupportLibrary.generate(input,"DIRECT_RECOMMENDATION")
	check(advice.action=="SHIELD" and advice.target!="E","Visible Overrun risk supports protection of a functioning neighbor")
	game.state.shelters.B.monitor_known_pressure=1
	game.state.shelters.C.verified_history.append({"round":1,"pressure":1})
	advice=SupportLibrary.generate(context(game),"DIRECT_RECOMMENDATION")
	check(not advice.target in ["B","C"],"Does not offer shielding as a cure for known exposure")
	input=context(game,responses("WAIT","NONE"))
	check(SupportLibrary.generate(input,"DIRECT_RECOMMENDATION").template_id=="direct.wait_agreement","Unanimous wait has explicit recommendation")
	game.state.depots.A.supply_remaining=0
	game.state.depots.H.supply_remaining=0
	for condition in SupportLibrary.CONDITIONS:
		advice=SupportLibrary.generate(context(game),condition)
		check(SupportLibrary.word_count(advice.text)>=35,"Zero-budget message remains within format")
	check(SupportLibrary.generate(context(game),"DIRECT_RECOMMENDATION").action=="WAIT","Zero budget never recommends impossible spending")
	# Compare independent public-only eligibility against authoritative action validation.
	for sample in 48:
		game=fresh()
		game.state.depots.A.supply_remaining=sample % 4
		game.state.depots.H.supply_remaining=(sample / 4) as int % 4
		for index in game.state.shelters.size():
			var id: String = game.state.shelters.keys()[index]
			game.state.shelters[id].zombie_pressure=2 if (sample+index) % 7==0 else index % 2
			game.state.shelters[id].is_monitored=(sample+index) % 5==0
			game.state.shelters[id].shielded_this_round=(sample+index) % 6==0
		for index in game.state.edges.size(): game.state.edges.values()[index].isolated=(sample+index) % 5==0
		input=context(game)
		var legal := SupportLibrary.legal_actions(input)
		for kind in GameAction.TYPES:
			for target in (game.state.edges.keys() if kind=="ISOLATE" else game.state.shelters.keys()):
				check(legal.has({"action":kind,"target":target})==game.action_manager.unavailable_reason(kind,target).is_empty(),"Public eligibility matches live rules")
		advice=SupportLibrary.generate(input,"DIRECT_RECOMMENDATION")
		check(advice.action=="WAIT" or game.action_manager.unavailable_reason(advice.action,advice.target).is_empty(),"Generated recommendation is executable")

func test_dissent() -> void:
	var game := fresh()
	check(SupportLibrary.generate(context(game),"CONSTRUCTIVE_DISSENT").template_id=="dissent.agreement","Agreement challenges shared assumption")
	var answers := responses()
	answers[0].reason=""
	check(SupportLibrary.generate(context(game,answers),"CONSTRUCTIVE_DISSENT").template_id=="dissent.agreement","Missing optional reason is not invented disagreement")
	answers=responses()
	answers[0].preferred_action="SHIELD"
	check(SupportLibrary.generate(context(game,answers),"CONSTRUCTIVE_DISSENT").template_id=="dissent.different","Different actions trigger decision check")
	answers=responses()
	answers[0].reason="protect supply access"
	check(SupportLibrary.generate(context(game,answers),"CONSTRUCTIVE_DISSENT").template_id=="dissent.assumptions","Different reasoning is distinguished from different decisions")
	answers=responses()
	answers[0].confidence=1
	check(SupportLibrary.generate(context(game,answers),"CONSTRUCTIVE_DISSENT").template_id=="dissent.confidence","Confidence uncertainty does not invent action disagreement")
	for values in [responses(),answers]:
		var output := SupportLibrary.generate(context(game,values),"CONSTRUCTIVE_DISSENT")
		check(output.action=="" and output.target=="","Dissent has no machine-readable action prescription")

func test_lifecycle() -> void:
	for condition in 3:
		var game := fresh(condition)
		check(game.intervention_type==condition,"Condition selected on construction")
		check(not game.begin_support() and not game.proceed_to_actions(),"No early intervention or actions")
		for round_number in range(1,4):
			submit_round(game)
			check(game.phase==GameManager.Phase.DISCUSSION and support_events(game).size()==round_number-1,"No support before initial discussion")
			check(not game.configure_condition((condition+1)%3),"Condition cannot change mid-session")
			check(not game.proceed_to_actions(),"Discussion cannot bypass support")
			check(game.begin_support() and not game.begin_support(),"Exactly one support per round")
			check(support_events(game).size()==round_number-1,"Generated but unseen text is not logged as shown")
			now_ms+=30000
			check(not game.proceed_to_actions(),"Generation time does not count as exposure")
			check(game.mark_support_shown() and not game.mark_support_shown(),"Display receipt is idempotent")
			var event: Dictionary = support_events(game).back()
			check(event.metadata.condition==game.condition_name() and event.metadata.round==round_number,"Condition and round logged")
			check(event.metadata.scenario_id==game.scenario.scenario_id and event.metadata.template_version==SupportLibrary.VERSION,"Scenario and immutable template version logged")
			check(event.metadata.allowed_inputs==SupportContext.CATEGORIES and event.metadata.displayed_text==game.support_message.text,"Log categories and actual displayed text")
			check(event.timestamp_utc.ends_with("Z") and event.elapsed_ms>=0,"Time shown is recorded")
			check(event.metadata.size()==7 and not event.metadata.has("responses"),"Support audit stores no input values or individual responses")
			check(not game.dispatch_action("VERIFY","E",["H"]).ok and not game.begin_resolution(),"Actions and resolution blocked during pause")
			var text: String = game.support_message.text
			game.set_dev_mode(true)
			check(not game.dev_mode,"Dev controls cannot interrupt exposure")
			now_ms+=14999
			check(game.support_seconds_remaining()==1 and not game.proceed_to_actions(),"Cannot continue before 15 seconds")
			now_ms+=1
			check(game.proceed_to_actions() and not game.proceed_to_actions(),"One guarded transition after the same interval")
			check(game.support_message.text==text and support_events(game).size()==round_number,"No regeneration after pause")
			game.begin_resolution()
			game.apply_resolution(game.run_token)
			game.finish_resolution(game.run_token)
			game.next_round()
		check(game.phase==GameManager.Phase.RESULTS,"All three conditions finish all three rounds")
		var exported := game.export_dictionary()
		check(exported.intervention==game.condition_name() and exported.schema_version==3,"Export uses actual condition and schema")
		check(exported.private_surveys.size()==9 and not JSON.stringify(exported).contains("participant_"),"Research answers retained without respondent identifiers")
		for event in game.logger.events:
			if event.type=="PRIVATE_SURVEY_SUBMITTED": check(event.metadata.is_empty() and event.target=="","Survey receipt cannot link an answer to handoff timing")
		game.reset()
		check(game.intervention_type==condition and game.support_message.is_empty() and not game.support_shown,"Restart preserves condition and clears prior exposure")
		check(game.configure_condition((condition+1)%3),"Facilitator can configure fresh run")

func test_ui_conditions() -> void:
	var app: Control = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.session._support_clock=func(): return now_ms
	for condition in 3:
		app.session.reset()
		app._show_session_setup()
		var picker: OptionButton = app.modal.find_child("ConditionPicker",true,false)
		check(picker!=null and picker.item_count==3,"Facilitator setup offers exactly three conditions")
		picker.select(condition)
		app.session.configure_condition(picker.selected)
		submit_round(app.session)
		app.session.begin_support()
		for frame in 5: await process_frame
		check(app.support_card.is_visible_in_tree() and app.support_card.get_child_count()==6,"Same sidebar note and three heading/body pairs for every condition")
		check(app.support_continue.disabled and app.session.support_shown,"Visible card starts timed gate")
		var shown: String = app.session.support_message.text
		var texts := PackedStringArray()
		for child in app.support_card.get_children(): texts.append(child.text)
		check(" ".join(texts).contains(shown.split("\n")[0].split(":",true,1)[1].strip_edges()),"Actual generated text is rendered")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/cascade-support-%d.png" % condition)
		app._select_shelter("A")
		for frame in 5: await process_frame
		check(support_events(app.session).size()==1 and app.session.support_message.text==shown,"Map selection rerender does not regenerate or relog")
		now_ms+=15000
		for frame in 3: await process_frame
		check(not app.support_continue.disabled,"Identical countdown unlocks every condition")
		app.support_continue.pressed.emit()
		check(app.session.phase==GameManager.Phase.ACTIONS,"Support does not execute the recommendation; team enters actions")
	app.queue_free()
	await process_frame
