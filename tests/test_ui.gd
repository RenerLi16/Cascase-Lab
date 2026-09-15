extends SceneTree

var app: Control
var checks := 0
var failures := 0
var support_time := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("UI FAIL: " + description)

func descendants(node: Node, type: String) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child.is_class(type): result.append(child)
		result.append_array(descendants(child,type))
	return result

func button_containing(fragment: String) -> Button:
	for button: Button in descendants(app,"Button"):
		if fragment in button.text and button.is_visible_in_tree(): return button
	return null

func click(fragment: String) -> void:
	var button := button_containing(fragment)
	check(button != null,"Button exists: "+fragment)
	if button == null: return
	check(not button.disabled,"Button enabled: "+fragment)
	if button.disabled: return
	button.pressed.emit()
	await settle()

func settle(frames: int = 3) -> void:
	for _frame in frames: await process_frame

func map_click(target: String, road: bool = false) -> void:
	await settle()
	var point: Vector2
	if road:
		var edge: EdgeState = app.session.state.edges[target]
		point = (app.board.positions[edge.from]+app.board.positions[edge.to])/2.0
	else: point = app.board.positions[target]
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.pressed = true
	input.position = point
	app.board._gui_input(input)
	input.pressed = false
	app.board._gui_input(input)
	await settle()
	check(app.selected_edge == target if road else app.selected_shelter == target,"Map selects "+target)

func choose(picker: OptionButton, value: String) -> bool:
	for index in picker.item_count:
		if picker.get_item_metadata(index) == value or picker.get_item_text(index) == value:
			picker.select(index)
			picker.item_selected.emit(index)
			return true
	return false

func submit_private(round_number: int, index: int) -> void:
	check(app.session.phase == GameManager.Phase.PRIVATE_GATE,"Private handoff is visible")
	check(descendants(app,"OptionButton").is_empty(),"Private handoff clears previous form controls")
	await click("Open my form")
	var pickers := descendants(app,"OptionButton")
	check(pickers.size()==5,"Private survey has five structured fields")
	for picker: OptionButton in pickers: check(picker.selected==0,"Private fields begin blank")
	var danger: OptionButton = pickers[0]
	var action: OptionButton = pickers[1]
	var target: OptionButton = pickers[2]
	var confidence: OptionButton = pickers[3]
	var reason: OptionButton = pickers[4]
	check(choose(danger,"E-F" if index==0 else "E"),"Choose danger location")
	check(choose(action,"WAIT" if index==1 else "VERIFY"),"Choose structured action")
	if action.get_selected_metadata() == "WAIT":
		check(target.disabled,"WAIT has no target")
	else:
		check(choose(target,"E"),"Choose action target")
	check(choose(confidence,str(index+2)),"Choose confidence")
	check(choose(reason,"prevent cascade"),"Choose structured reason")
	await click("Submit & pass screen")
	check(app.session.private_surveys[round_number].size()==index+1,"Private response stored internally only")

func dispatch(kind: String, target: String, assignments: Array[String]) -> void:
	var result: Dictionary = app.session.dispatch_action(kind,target,assignments)
	check(result.ok,"Dispatch "+kind+" "+target)
	if not result.ok: return
	check(app.session.phase == GameManager.Phase.DELIVERY,"Delivery phase shown")
	check(app.session.pending_action.deliveries.size()==assignments.size(),"Delivery count matches action")
	await create_timer(2.2).timeout
	await settle()
	check(app.session.phase == GameManager.Phase.ACTIONS,"Delivery returns to action phase")

func run() -> void:
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.session._support_clock = func(): return support_time
	await settle()
	check(app.session.phase == GameManager.Phase.OBSERVE,"Scenario starts in Observe")
	check(app.session.state.overrun_ids().is_empty(),"Normal opening has no visible Overrun")
	check(app.session.state.shelters.E.zombie_pressure==1,"Exactly one hidden exposure at start")
	check(app.session.public_intel.size()==1,"Round 1 public intel is visible")
	check(not app.session.dev_mode,"Dev mode starts off")
	check(app.board != null,"Map is the primary interface")
	check(app.board.zoom==1.0 and app.board.pan==Vector2.ZERO,"Map starts centered at 100 percent")
	check(app.board.hit_test(app.board.positions["E"])=="E","Map node hit testing works")
	var old_zoom: float = app.board.zoom
	app.board.zoom_at(1.3,app.board.size/2)
	check(app.board.zoom>old_zoom,"Map zoom in works")
	app.board.center_map()
	check(app.board.zoom==1.0 and app.board.pan==Vector2.ZERO,"Center resets map")
	var drag := InputEventMouseButton.new()
	drag.button_index=MOUSE_BUTTON_LEFT; drag.pressed=true; drag.position=Vector2(200,200)
	app.board._gui_input(drag)
	var move := InputEventMouseMotion.new(); move.position=Vector2(250,240)
	app.board._gui_input(move)
	var release := InputEventMouseButton.new(); release.button_index=MOUSE_BUTTON_LEFT; release.pressed=false; release.position=Vector2(250,240)
	app.board._gui_input(release)
	check(app.board.pan != Vector2.ZERO,"Map drag pans")
	app.board.center_map()
	await click("Private judgment")
	for index in 3: await submit_private(1,index)
	check(app.session.phase == GameManager.Phase.DISCUSSION,"Private submissions lead directly to discussion")
	check(button_containing("Beliefs")==null,"Normal UI has no Beliefs tab")
	check(button_containing("Reports")==null,"Normal UI has no Reports tab")
	check(button_containing("Log")==null,"Normal UI has no Log tab")
	await click("Finish initial discussion")
	check(app.session.phase == GameManager.Phase.INTERVENTION,"Discussion leads to decision pause")
	check(app.session.support_shown,"Visible support card records display")
	check(button_containing("Proceed to actions").disabled,"Continue is locked for the equivalent pause")
	check(not app.session.proceed_to_actions(),"Manager rejects early continuation")
	check(app.session.support_message.template_id=="none.pause","No AI gets a neutral message")
	support_time += SupportLibrary.PAUSE_SECONDS * 1000
	await settle()
	await click("Proceed to actions")
	check(app.session.phase == GameManager.Phase.ACTIONS,"Actions phase is explicit")
	await map_click("E")
	check(button_containing("VERIFY")!=null,"Verify action is visible")
	check(button_containing("MONITOR")!=null,"Monitor action is visible")
	check(button_containing("SHIELD")!=null,"Shield action is visible")
	await dispatch("VERIFY","E",["H"])
	check(app.session.latest_observation.get("pressure",-1)==1,"Verify resolves on delivery")
	check(app.session.state.shelters.E.verified_history.size()==1,"Verify marker persists")
	await dispatch("MONITOR","E",["A"])
	await dispatch("SHIELD","E",["A"])
	await map_click("E-F",true)
	await click("ISOLATE")
	check(app.modal != null,"Isolation opens concise confirmation modal")
	check(button_containing("Confirm delivery")!=null,"Isolation has explicit confirmation")
	check(app.board.preview_edge=="E-F" and not app.board.preview_lost.is_empty(),"Isolation previews supply losses on map")
	await click("Confirm delivery")
	check(app.session.phase==GameManager.Phase.DELIVERY,"Isolation begins two-endpoint delivery")
	check(app.session.pending_action.deliveries.size()==2,"Isolation sends one unit to each endpoint")
	await create_timer(2.2).timeout
	check(app.session.state.edges["E-F"].isolated,"Road closes only after both deliveries arrive")
	check(app.session.state.total_supply()==1,"Fixed supply is deducted, never regenerated")
	await click("End round")
	await click("Resolve")
	await create_timer(3.0).timeout
	check(app.session.phase == GameManager.Phase.ROUND_COMPLETE,"Resolution returns to round complete")
	check(app.session.state.overrun_ids()==["E"],"Hidden initial exposure becomes Overrun during play")
	check(app.session.state.monitor_alerts.size()==1,"Monitor alert appears after pressure change")
	check(app.session.public_intel.size()==1,"Only round-one intel before next round")
	await click("Next round")
	check(app.session.phase==GameManager.Phase.OBSERVE and app.session.state.round==2,"Next round returns to Observe")
	check(app.session.public_intel.size()==2 and app.session.public_intel[1].round==2,"Round 2 intel publishes at boundary")
	var dev_toggle: CheckButton = descendants(app,"CheckButton")[0]
	dev_toggle.toggled.emit(true)
	await settle()
	check(app.modal != null,"Dev mode asks before revealing state")
	await click("Enable Dev mode")
	check(app.session.dev_mode and app.board.dev_mode,"Dev mode reveals hidden pressure on map")
	await click("Inspect")
	check(app.modal != null,"Dev inspector opens")
	check(button_containing("Export research JSON")!=null,"Dev inspector offers research export")
	await click("Close")
	app._export_session()
	await settle()
	var export_dialogs := descendants(app,"FileDialog")
	check(export_dialogs.size()==1,"Session export opens a save dialog")
	if export_dialogs.size()==1:
		var export_path := "/tmp/cascade-lab-ui-export.json"
		export_dialogs[0].file_selected.emit(export_path)
		await settle()
		var exported_text := FileAccess.get_file_as_string(export_path)
		var exported_json = JSON.parse_string(exported_text)
		check(exported_json is Dictionary and exported_json.get("schema_version",0)==3,"Session export writes schema v3 JSON")
	await click("Restart")
	check(app.modal != null,"Restart asks before clearing")
	await click("Restart scenario")
	check(app.session.phase==GameManager.Phase.OBSERVE and app.session.state.total_supply()==6,"Restart resets state and fixed stock")
	check(app.session.private_surveys.is_empty() and app.session.state.actions.is_empty(),"Restart clears private and action history")
	print("UI TESTS: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
