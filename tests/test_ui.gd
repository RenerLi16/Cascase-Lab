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

# Retired narrative dispatches must not appear anywhere in the participant interface.
func dispatch_ui_visible() -> bool:
	for kind in ["Label","Button","RichTextLabel"]:
		for node: Control in descendants(app,kind):
			var text := str(node.text).to_lower()
			# "Dispatch yard" is a shelter name in Lifeline; only the retired report UI is matched.
			if node.is_visible_in_tree() and (text.contains("field dispatch") or text.contains("dispatches")): return true
	return false

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
		point = app.board._point_on_path(app.board.road_geometry[target],0.5)
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
	await click("Hide survey")
	await create_timer(0.35).timeout
	check(not app.survey_content.visible,"Retracted survey hides private answers")
	await map_click("E")
	await create_timer(0.65).timeout
	check(app.inspector.visible,"Retracted survey permits building inspection")
	await click("Expand survey")
	await create_timer(0.35).timeout
	check(app.survey_content.visible and pickers[0] == descendants(app,"OptionButton")[0],"Survey controls survive map inspection")
	check(confidence.get_selected_metadata()==str(index+2),"Survey answer survives collapse and expand")
	await click("Submit & pass screen")
	check(app.session.private_surveys[round_number].size()==index+1,"Private response stored internally only")

# Await the public phase instead of assuming a fixed vehicle/arrival duration.
func wait_delivery() -> void:
	var deadline := Time.get_ticks_msec()+4000
	while app.session.phase == GameManager.Phase.DELIVERY and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(app.session.phase == GameManager.Phase.ACTIONS,"Delivery completes within four seconds")

func dispatch(kind: String, target: String, assignments: Array[String]) -> void:
	var result: Dictionary = app.session.dispatch_action(kind,target,assignments)
	check(result.ok,"Dispatch "+kind+" "+target)
	if not result.ok: return
	check(app.session.phase == GameManager.Phase.DELIVERY,"Delivery phase shown")
	check(app.session.pending_action.deliveries.size()==assignments.size(),"Delivery count matches action")
	await wait_delivery()
	await settle()
	check(app.session.phase == GameManager.Phase.ACTIONS,"Delivery returns to action phase")

func run() -> void:
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app._start_normal()
	app.session._support_clock = func(): return support_time
	await settle()
	check(app.session.phase == GameManager.Phase.OBSERVE,"Scenario starts in Observe")
	check(app.session.state.overrun_ids().is_empty(),"Normal opening has no visible Overrun")
	check(app.session.state.shelters.E.zombie_pressure==1,"Exactly one hidden exposure at start")
	check(app.session.get("public_intel")==null and not dispatch_ui_visible(),"No field dispatch panel or history control")
	check(not app.session.dev_mode,"Dev mode starts off")
	check(app.board != null,"Map is the primary interface")
	check(app.board.zoom==1.0 and app.board.pan==Vector2.ZERO,"Map starts centered at 100 percent")
	check(app.board.hit_test(app.board.positions["E"])=="E","Map node hit testing works")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = app.board.size/2
	app.board._gui_input(wheel)
	check(is_equal_approx(app.board.zoom,1.1),"Wheel provides bounded overview zoom")
	await map_click("E")
	await create_timer(0.65).timeout
	check(is_equal_approx(app.board.zoom,2.0),"Building selection animates into a close-up")
	check(app.inspector.visible,"Building opens right information panel")
	check(app.board.to_screen(app.board.world_building("E").get_center()).x < app.inspector.position.x+app.workspace.position.x,"Camera leaves selected tower clear of floating inspector")
	var old_zoom: float = app.board.zoom
	await map_click("E-F",true)
	check(app.board.zoom==old_zoom,"Road selection does not zoom")
	check(is_instance_valid(app.road_bubble),"Road selection opens anchored bubble")
	await click("Overview")
	await create_timer(0.65).timeout
	check(app.board.zoom==1.0 and app.board.pan==Vector2.ZERO,"Overview restores district")
	check(not app.inspector.visible,"Overview closes building panel")
	await click("Choose your")
	for index in 3: await submit_private(1,index)
	check(app.session.phase == GameManager.Phase.DISCUSSION,"Private submissions lead directly to discussion")
	check(button_containing("Beliefs")==null,"Normal UI has no Beliefs tab")
	check(button_containing("Reports")==null,"Normal UI has no Reports tab")
	check(button_containing("Log")==null,"Normal UI has no Log tab")
	support_time += GameManager.DISCUSSION_SECONDS * 1000
	await settle(8)
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
	await wait_delivery()
	check(app.session.state.edges["E-F"].isolated,"Road closes only after both deliveries arrive")
	check(app.session.state.total_supply()==1,"Fixed supply is deducted, never regenerated")
	await click("End round")
	await click("Resolve")
	await create_timer(3.0).timeout
	check(app.session.phase == GameManager.Phase.ROUND_COMPLETE,"Resolution returns to round complete")
	check(app.session.state.overrun_ids()==["E"],"Hidden initial exposure becomes Overrun during play")
	check(app.session.state.monitor_alerts.size()==1,"Monitor alert appears after pressure change")
	check(not dispatch_ui_visible(),"Round summary shows no dispatch")
	await click("Next round")
	check(app.session.phase==GameManager.Phase.OBSERVE and app.session.state.round==2,"Next round returns to Observe")
	check(app.session.state.round==2 and not dispatch_ui_visible() and button_containing("Earlier")==null,"Round 2 begins without a narrative report or dispatch history")
	app._show_help()
	await settle()
	var guide := ""
	for node: RichTextLabel in descendants(app,"RichTextLabel"): guide += node.get_parsed_text().to_lower()
	check(guide.contains("verify") and not guide.contains("surveillance") and not guide.contains("report arrives") and not guide.contains("dispatch"),"Field guide has no instruction to use narrative reports")
	app._close_modal()
	await click("Menu")
	check(descendants(app,"CheckButton").is_empty(),"Normal sessions cannot reveal hidden state")
	await click("Main menu")
	await click("Leave mission")
	await click("Dev Mode")
	await click("Start · Riverside")
	check(app.session.is_sandbox(),"Dev selection creates a distinct sandbox")
	await click("Menu")
	var dev_toggle: CheckButton = descendants(app,"CheckButton")[0]
	dev_toggle.toggled.emit(true)
	await settle()
	await click("Enable Dev mode")
	check(app.session.dev_mode and app.board.dev_mode,"Sandbox reveals hidden pressure on request")
	await click("Menu")
	await click("Inspect")
	check(button_containing("Export DEV JSON")!=null,"Dev inspector offers labelled debug export")
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
		check(exported_json is Dictionary and exported_json.get("schema_version",0)==GameManager.EXPORT_SCHEMA and exported_json.get("context_version","")==SupportContext.VERSION and not exported_text.contains("public_intel") and exported_json.run_purpose=="dev" and not exported_json.research_eligible,"Session export writes marked dev JSON")
	await click("Menu")
	await click("Restart")
	check(app.modal != null,"Restart asks before clearing")
	await click("Restart scenario")
	check(app.session.phase==GameManager.Phase.OBSERVE and app.session.state.total_supply()==6,"Restart resets state and fixed stock")
	check(app.session.private_surveys.is_empty() and app.session.state.actions.is_empty(),"Restart clears private and action history")
	print("UI TESTS: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
