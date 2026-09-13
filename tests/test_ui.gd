extends SceneTree

# Drives the real scene's buttons, forms, map input, dialogs and screen transitions.
# Run without --headless to also capture screenshots under /tmp/cascade-lab-qa.
var app: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("UI FAIL: "+description)

func descendants(node: Node, type: String) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child.is_class(type): found.append(child)
		found.append_array(descendants(child,type))
	return found

func button_containing(fragment: String) -> Button:
	for button: Button in descendants(app,"Button"):
		if fragment in button.text and button.is_visible_in_tree(): return button
	return null

func click(fragment: String) -> void:
	var button := button_containing(fragment)
	check(button!=null,"Button exists: "+fragment)
	if button==null: return
	check(not button.disabled,"Button enabled: "+fragment)
	if button.disabled: return
	button.pressed.emit()
	await settle()

func settle() -> void:
	for frame in 3: await process_frame

func capture(name: String) -> void:
	await settle()
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("/tmp/cascade-lab-qa")
	picture.save_png("/tmp/cascade-lab-qa/"+name+".png")

func pick_form(source: String, predicted: String, confidence: String) -> void:
	var options := descendants(app,"OptionButton")
	check(options.size()==(3 if app.session.collecting_update else 4),"Private form contains only fresh current fields")
	for option: OptionButton in options: check(option.selected==0,"No private answer preselected or leaked")
	var submit := button_containing("Submit privately")
	check(submit!=null and submit.disabled,"Cannot submit unanswered form")
	var values: Array[String] = [source,predicted]
	if not app.session.collecting_update: values.append("SHIELD")
	values.append(confidence)
	for index in options.size():
		var option: OptionButton = options[index]
		for item in option.item_count:
			if option.get_item_text(item)==values[index]:
				option.select(item)
				option.item_selected.emit(item)
	await click("Submit privately")

func private_cycle(update: bool) -> void:
	for index in 3:
		check(app.session.phase==GameManager.Phase.PRIVATE_GATE,"Private handoff shown")
		check(descendants(app,"OptionButton").is_empty(),"Handoff clears all form controls")
		check(app.board==null,"No underlying shared board during privacy gate")
		await click("I am Player %d" % (index+1))
		if index==0: await capture("private-update" if update else "private-initial")
		await pick_form("D" if update else ["B","D","B"][index],"F",str(index+2))
	check(app.session.phase==GameManager.Phase.BELIEFS,"Anonymous comparison follows all three submissions")
	await capture("belief-changes" if update else "initial-beliefs")
	await click("Begin team discussion")

func map_select(target: String, road: bool = false) -> void:
	var map: NetworkView = app.board
	await settle()
	var point: Vector2
	if road:
		var edge: EdgeState = app.session.state.edges[target]
		point=(map.positions[edge.from]+map.positions[edge.to])/2.0
	else: point=map.positions[target]
	check(map.hit_test(point)==target,"Map geometry picks "+target)
	var input := InputEventMouseButton.new()
	input.button_index=MOUSE_BUTTON_LEFT
	input.pressed=true
	input.position=point
	map._gui_input(input)
	await settle()
	check(app.selected_edge==target if road else app.selected_shelter==target,"Map click selects target "+target)

func queue(kind: String, target: String, depot: String) -> void:
	await map_select(target,kind=="ISOLATE")
	await click(kind+"  ·")
	var pickers := descendants(app.modal,"OptionButton")
	check(pickers.size()==1,"Action asks for paying depot")
	if pickers.is_empty(): return
	var picker: OptionButton=pickers[0]
	for index in picker.item_count:
		if picker.get_item_text(index).begins_with("Depot "+depot):
			picker.select(index)
			picker.item_selected.emit(index)
	if kind=="ISOLATE":
		await capture("isolation-preview")
		await click("Review isolation warning")
		check(button_containing("I understand")!=null,"Isolation requires second confirmation")
		await click("I understand")
	else: await click("Add to plan")

func confirm() -> void:
	await click("Review & confirm")
	await capture("plan-confirmation")
	await click("Confirm & spend supply")
	check(app.session.draft.is_empty(),"Confirmed draft clears")

func resolve_round() -> void:
	await click("Resolve Round")
	await click("Resolve spread")
	check(app.session.phase==GameManager.Phase.SUMMARY,"Spread moves to summary screen")

func run() -> void:
	app=load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	await settle()
	await capture("menu-1440")
	await click("Begin briefing")
	await capture("briefing")
	# Exercise every report/rules tab as real TabContainer controls.
	for tab: TabContainer in descendants(app,"TabContainer"):
		for index in tab.get_tab_count():
			tab.current_tab=index
			await settle()
	await click("Start private judgments")
	await capture("privacy-gate")
	await private_cycle(false)
	await click("Proceed to Actions")
	await capture("actions")
	# Disabled actions explain why an Overrun shelter cannot receive supplies.
	await map_select("D")
	check(button_containing("VERIFY  ·").disabled,"Overrun shelter action is disabled")
	check("Overrun" in button_containing("VERIFY  ·").tooltip_text,"Disabled action has explanatory tooltip")
	# Canceling an action doesn't queue or spend anything.
	await map_select("A")
	await click("VERIFY  ·")
	await click("Cancel")
	check(app.session.draft.is_empty() and app.session.state.total_supply()==6,"Cancel is side-effect free")
	await queue("VERIFY","B","H")
	await confirm()
	check(app.session.state.shelters.B.verified_history[0].pressure==1,"Confirmed Verify reveals exact current pressure")
	await queue("MONITOR","E","A")
	await queue("SHIELD","E","A")
	await queue("ISOLATE","D-G","H")
	check(button_containing("Resolve Round").disabled,"Spread button disabled with pending plan")
	await confirm()
	check(app.session.state.depots.A.supply_remaining==1 and app.session.state.depots.H.supply_remaining==0,"Multi-action plan spends the selected depot balances")
	await capture("round-one-plan-applied")
	await click("Return to discussion")
	await click("Proceed to Actions")
	await resolve_round()
	check(app.session.state.overrun_ids()==["D"],"Shield and isolation prevent first-round infections")
	await click("Examine new evidence")
	check(app.session.phase==GameManager.Phase.DIAGNOSTIC,"Mandatory diagnostic evidence screen exists")
	await capture("diagnostic-evidence")
	await click("Record private belief updates")
	await private_cycle(true)
	check(app.session.state.round==2,"Round 2 follows private updates")
	await click("Proceed to Actions")
	# Exercise clear-plan and confirmation cancellation.
	await queue("SHIELD","E","A")
	await click("Clear plan")
	check(app.session.state.total_supply()==1 and app.session.draft.is_empty(),"Clear plan preserves supply")
	await queue("SHIELD","E","A")
	await click("Review & confirm")
	await click("Keep planning")
	check(app.session.draft.size()==1,"Cancel confirmation preserves draft")
	await confirm()
	await resolve_round()
	await click("Discuss Round 3")
	await click("Proceed to Actions")
	# No fixed action allowance: zero remaining supply still permits resolving the game.
	await resolve_round()
	check(app.session.state.monitor_alerts.size()==1,"Monitor alerts appear when E changes in Round 3")
	await capture("round-three-summary")
	await click("View mission results")
	check(app.session.phase==GameManager.Phase.RESULTS,"Full UI playthrough reaches results")
	check(app.session.state.overrun_ids()==["D","E"],"Final score is six survivors")
	check(app.session.belief_change_count()==2,"Results calculate belief changes")
	await capture("results-1440")
	for tab: TabContainer in descendants(app,"TabContainer"):
		for index in tab.get_tab_count():
			tab.current_tab=index
			await settle()
			tab.current_tab=0
	# File dialog callback uses the same export path the player invokes.
	await click("Export session JSON")
	var dialogs := descendants(app,"FileDialog")
	check(dialogs.size()==1,"Native export opens a save dialog")
	if not dialogs.is_empty():
		dialogs[0].file_selected.emit("/tmp/cascade-ui-session.json")
		await settle()
	check(FileAccess.file_exists("/tmp/cascade-ui-session.json"),"Session JSON saved to a selected local file")
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("/tmp/cascade-ui-session.json"))
	check(saved.events.size()>20 and saved.final_state.shelters.E.zombie_pressure==2,"Export contains final state and structured events")
	# Test at a smaller laptop viewport, then restore.
	root.size=Vector2i(1100,720)
	await capture("results-1100")
	check(app.footer.get_global_rect().end.y<=app.size.y+2,"Footer fits at laptop size")
	root.size=Vector2i(1440,900)
	await settle()
	await click("Play again")
	await click("Cancel")
	check(app.session.phase==GameManager.Phase.RESULTS,"Cancel restart preserves results")
	await click("Play again")
	await click("Restart mission")
	check(app.session.phase==GameManager.Phase.MENU and app.session.state.total_supply()==6,"Restart returns to clean menu")
	var dev: CheckButton=descendants(app,"CheckButton")[0]
	dev.toggled.emit(true)
	await click("Enable DEV MODE")
	check(app.session.dev_mode and app.board.dev_mode,"Dev toggle reveals labeled board state")
	await capture("dev-mode")
	dev=descendants(app,"CheckButton")[0]
	dev.toggled.emit(false)
	await settle()
	check(not app.session.dev_mode and app.session.dev_used,"Turning dev off preserves exposure flag")
	print("UI TESTS: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
