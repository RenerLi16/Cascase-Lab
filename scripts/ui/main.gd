extends Control

var session: GameManager
var board: NetworkView
var sidebar: VBoxContainer
var modal: Control
var selected_shelter := ""
var selected_edge := ""
var map_zoom := 1.0
var map_pan := Vector2.ZERO
var map_token := 0
var export_status := ""
var phase_label: Label
var zoom_label: Label
var footer: VBoxContainer
var support_card: VBoxContainer
var support_countdown: Label
var support_continue: Button

func _ready() -> void:
	theme = UIkit.make_theme()
	session = GameManager.new()
	session.changed.connect(_render)
	_render()

func _private_phase() -> bool:
	return session.phase in [GameManager.Phase.PRIVATE_GATE,GameManager.Phase.PRIVATE_FORM]

func _busy() -> bool:
	return session.phase in [GameManager.Phase.DELIVERY,GameManager.Phase.RESOLUTION]

func _process(_delta: float) -> void:
	if session == null or session.phase != GameManager.Phase.INTERVENTION: return
	if not is_instance_valid(support_countdown) or not is_instance_valid(support_continue): return
	var seconds := session.support_seconds_remaining()
	support_countdown.text = "Continue in %ds" % seconds if seconds > 0 else "Ready to continue"
	support_continue.disabled = not session.support_shown or seconds > 0

func _render() -> void:
	if map_token != session.run_token:
		map_zoom = 1.0
		map_pan = Vector2.ZERO
		selected_shelter = ""
		selected_edge = ""
		map_token = session.run_token
	elif is_instance_valid(board):
		map_zoom = board.zoom
		map_pan = board.pan
	for child in get_children():
		remove_child(child)
		child.queue_free()
	modal = null
	board = null
	var background := ColorRect.new()
	background.color = UIkit.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,UIkit.XL)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation",UIkit.LG)
	margin.add_child(page)
	_build_header(page)
	UIkit.rule(page,true)
	if session.phase == GameManager.Phase.PRIVATE_GATE:
		_build_handoff(page)
		return
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation",UIkit.XL)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	_build_map(body)
	var panel := PanelContainer.new()
	panel.name = "DecisionSheet"
	panel.custom_minimum_size.x = 380
	panel.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.PANEL,0,UIkit.LG))
	body.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",UIkit.MD)
	panel.add_child(column)
	column.add_child(UIkit.label("ROUND %02d / %02d" % [session.state.round,session.scenario.rounds],UIkit.CAPTION,UIkit.MUTED))
	phase_label = UIkit.label(PresentationText.phase_title(session.phase),UIkit.DISPLAY)
	column.add_child(phase_label)
	UIkit.rule(column,true)
	sidebar = UIkit.scroll_column(column)
	sidebar.add_theme_constant_override("separation",UIkit.LG)
	if session.phase == GameManager.Phase.RESULTS:
		_build_results(sidebar)
	elif _private_phase():
		_build_private(sidebar)
	elif session.phase == GameManager.Phase.INTERVENTION:
		_build_support(sidebar)
	elif _busy():
		_build_operation(sidebar)
	else:
		if not session.latest_observation.is_empty(): _observation_card(sidebar,session.latest_observation)
		if session.phase == GameManager.Phase.ROUND_COMPLETE:
			sidebar.add_child(UIkit.label("RESOLUTION RECORD",UIkit.CAPTION,UIkit.MUTED))
			for alert in session.last_summary.get("monitor_alerts",[]): _observation_card(sidebar,alert)
			_build_intel(sidebar)
		elif session.phase == GameManager.Phase.ACTIONS:
			_build_selection(sidebar)
			_build_intel(sidebar,true)
		else:
			_build_intel(sidebar)
			_build_selection(sidebar)
	footer = VBoxContainer.new()
	column.add_child(footer)
	_build_phase_button()
	if _busy(): _animate_phase.call_deferred(session.run_token)

func _build_header(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",UIkit.SM)
	parent.add_child(row)
	var masthead := VBoxContainer.new()
	masthead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead.add_theme_constant_override("separation",UIkit.XS)
	row.add_child(masthead)
	masthead.add_child(UIkit.label("CASCADE LAB  /  OUTBREAK",UIkit.SECTION))
	var help := UIkit.quiet("Field guide",_show_help)
	help.tooltip_text = "Rules and map controls"
	row.add_child(help)
	if session.can_configure_condition(): row.add_child(UIkit.quiet("Session setup",_show_session_setup))
	var dev := CheckButton.new()
	dev.text = "Dev mode"
	dev.add_theme_font_size_override("font_size",UIkit.CAPTION)
	dev.add_theme_color_override("font_color",UIkit.MUTED)
	dev.add_theme_stylebox_override("normal",UIkit.box(Color.TRANSPARENT,Color.TRANSPARENT,0,UIkit.SM))
	dev.add_theme_stylebox_override("disabled",UIkit.box(Color.TRANSPARENT,Color.TRANSPARENT,0,UIkit.SM))
	dev.tooltip_text = "Facilitator / debugging only"
	dev.button_pressed = session.dev_mode
	dev.disabled = _private_phase() or _busy() or session.phase == GameManager.Phase.INTERVENTION
	dev.toggled.connect(_request_dev_mode)
	row.add_child(dev)
	if session.dev_mode and not _private_phase():
		var inspect := UIkit.quiet("Inspect",_show_inspector)
		inspect.disabled = _busy() or session.phase == GameManager.Phase.INTERVENTION
		row.add_child(inspect)
	var restart := UIkit.quiet("Restart",_request_restart)
	restart.disabled = _busy()
	row.add_child(restart)

func _build_map(parent: Node) -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation",UIkit.MD)
	parent.add_child(left)
	var top := HBoxContainer.new()
	left.add_child(top)
	var title := UIkit.label(session.scenario.scenario_title.to_upper(),UIkit.CAPTION)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIkit.label("%d / 8 FUNCTIONING" % (8-session.state.overrun_ids().size()),UIkit.CAPTION,UIkit.MUTED))
	var border := PanelContainer.new()
	border.add_theme_stylebox_override("panel",UIkit.box(UIkit.MAP,UIkit.LINE,0,0))
	border.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(border)
	board = NetworkView.new()
	border.add_child(board)
	board.configure(session.scenario,session.state,session.dev_mode and not _private_phase())
	board.zoom = map_zoom
	board.pan = map_pan
	board.selected_shelter = selected_shelter
	board.selected_edge = selected_edge
	board.shelter_selected.connect(_select_shelter)
	board.edge_selected.connect(_select_edge)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",UIkit.XS)
	left.add_child(controls)
	controls.add_child(UIkit.quiet("−",func(): board.zoom_at(1.0/1.2,board.size/2)))
	controls.add_child(UIkit.quiet("+",func(): board.zoom_at(1.2,board.size/2)))
	controls.add_child(UIkit.quiet("Center",func(): board.center_map()))
	zoom_label = UIkit.label("%d%%" % roundi(board.zoom*100),UIkit.CAPTION,UIkit.MUTED)
	controls.add_child(zoom_label)
	board.view_changed.connect(func(): zoom_label.text = "%d%%" % roundi(board.zoom*100))
	var legend := UIkit.paragraph("Drag to pan · Wheel to zoom",UIkit.CAPTION,UIkit.MUTED)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_child(legend)
	if _private_phase():
		_build_intel(left,true)
	elif session.dev_mode:
		left.add_child(UIkit.label("DEV MODE · HIDDEN STATE VISIBLE · SOURCE " + session.scenario.original_source,UIkit.CAPTION,UIkit.RED))


func _build_intel(parent: Node, compact: bool = false) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",UIkit.SM)
	parent.add_child(column)
	UIkit.rule(column)
	column.add_child(UIkit.label("FIELD DISPATCH",UIkit.CAPTION,UIkit.MUTED))
	var latest: Dictionary = session.public_intel.back()
	column.add_child(UIkit.label("R%02d   ·   %s" % [latest.round,latest.time],UIkit.CAPTION,UIkit.MUTED))
	column.add_child(UIkit.paragraph(latest.text,UIkit.CAPTION if compact else UIkit.BODY,UIkit.TEXT))
	if session.public_intel.size() > 1:
		var archive := VBoxContainer.new()
		archive.visible = false
		column.add_child(UIkit.quiet("Earlier dispatches  +",func(): archive.visible = not archive.visible))
		column.add_child(archive)
		for index in session.public_intel.size()-1:
			var report: Dictionary = session.public_intel[index]
			archive.add_child(UIkit.label("R%02d   ·   %s" % [report.round,report.time],UIkit.CAPTION,UIkit.MUTED))
			archive.add_child(UIkit.paragraph(report.text,UIkit.CAPTION,UIkit.MUTED))

func _build_selection(parent: Node) -> void:
	UIkit.rule(parent)
	if selected_shelter == "" and selected_edge == "":
		parent.add_child(UIkit.paragraph("Select a shelter or road.",UIkit.SECTION,UIkit.TEXT))
		if session.phase == GameManager.Phase.ACTIONS:
			parent.add_child(UIkit.paragraph("Shelter: Verify · Monitor · Shield\nRoad: Isolate",UIkit.CAPTION))
		return
	if selected_edge != "":
		var edge: EdgeState = session.state.edges[selected_edge]
		parent.add_child(UIkit.label("ROAD %s — %s" % [edge.from,edge.to],UIkit.SECTION))
		parent.add_child(UIkit.label("CLOSED / BOTH DIRECTIONS" if edge.isolated else "Open / two-way",UIkit.CAPTION,UIkit.RED if edge.isolated else UIkit.MUTED))
		if session.phase == GameManager.Phase.ACTIONS: _action_button(parent,"ISOLATE",selected_edge)
	else:
		var shelter: ShelterState = session.state.shelters[selected_shelter]
		parent.add_child(UIkit.label(selected_shelter+" / "+shelter.display_name,UIkit.SECTION))
		parent.add_child(UIkit.label("Pressure: " + PresentationText.known_status(shelter),UIkit.BODY,UIkit.RED if shelter.is_overrun else UIkit.MUTED))
		var access: Array[String] = []
		for depot in session.action_manager.supply.eligible_depots(selected_shelter): access.append(depot)
		parent.add_child(UIkit.paragraph("Supply from depot " + ", ".join(access) if not access.is_empty() else "NO SUPPLY ROUTE",UIkit.CAPTION))
		if session.phase == GameManager.Phase.ACTIONS:
			for kind in ["VERIFY","MONITOR","SHIELD"]: _action_button(parent,kind,selected_shelter)
		else:
			if shelter.is_monitored: parent.add_child(UIkit.label("MONITOR / active",UIkit.CAPTION,UIkit.TEAL))
			if shelter.shielded_this_round: parent.add_child(UIkit.label("SHIELD / this resolution only",UIkit.CAPTION,UIkit.TEAL))
		for record in shelter.verified_history:
			parent.add_child(UIkit.label("OBS R%d / Pressure %d at verification" % [record.round,record.pressure],UIkit.CAPTION,UIkit.MUTED))
		if session.dev_mode: parent.add_child(UIkit.label("DEV · P%d" % shelter.zombie_pressure,UIkit.CAPTION,UIkit.RED))

func _action_button(parent: Node, kind: String, target: String) -> void:
	var reason := session.action_manager.unavailable_reason(kind,target)
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation",UIkit.XS)
	parent.add_child(group)
	var button := UIkit.button("%s   /   %d SUPPLY" % [kind,2 if kind == "ISOLATE" else 1],func(): _request_action(kind,target))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = reason != ""
	button.tooltip_text = reason if reason != "" else PresentationText.ACTION_DETAILS[kind]
	group.add_child(button)
	if reason != "": group.add_child(UIkit.paragraph(reason,UIkit.CAPTION,UIkit.MUTED))

func _observation_card(parent: Node, observation: Dictionary) -> void:
	var note := VBoxContainer.new()
	note.add_theme_constant_override("separation",UIkit.SM)
	parent.add_child(note)
	UIkit.rule(note)
	note.add_child(UIkit.paragraph(PresentationText.observation_text(observation),UIkit.BODY,UIkit.TEXT))

func _build_phase_button() -> void:
	match session.phase:
		GameManager.Phase.OBSERVE:
			footer.add_child(UIkit.button("Private judgment",session.start_private,true))
		GameManager.Phase.DISCUSSION:
			footer.add_child(UIkit.label("Discuss your next move.",UIkit.CAPTION,UIkit.MUTED))
			footer.add_child(UIkit.button("Finish initial discussion",session.begin_support,true))
		GameManager.Phase.INTERVENTION:
			support_countdown = UIkit.label("Continue in %ds" % session.support_seconds_remaining(),UIkit.CAPTION,UIkit.MUTED)
			footer.add_child(support_countdown)
			support_continue = UIkit.button("Proceed to actions",session.proceed_to_actions,true)
			support_continue.disabled = true
			footer.add_child(support_continue)
		GameManager.Phase.ACTIONS:
			footer.add_child(UIkit.button("End round",_request_resolution,true))
		GameManager.Phase.ROUND_COMPLETE:
			var newly: Array = session.last_summary.newly_overrun
			footer.add_child(UIkit.paragraph("Shelters lost: " + (", ".join(newly) if not newly.is_empty() else "None"),UIkit.CAPTION,UIkit.RED if not newly.is_empty() else UIkit.MUTED))
			footer.add_child(UIkit.button("Results" if session.state.round==3 else "Next round",session.next_round,true))
		GameManager.Phase.RESULTS:
			footer.add_child(UIkit.button("Export session JSON",_export_session))
			footer.add_child(UIkit.button("Play again",_request_restart,true))

func _show_session_setup() -> void:
	if not session.can_configure_condition(): return
	var column := _modal_base("Session setup")
	column.add_child(UIkit.label("FACILITATOR / EXPERIMENT CONFIGURATION",UIkit.CAPTION,UIkit.MUTED))
	column.add_child(UIkit.paragraph("Condition remains fixed for three rounds and on restart.",UIkit.BODY))
	var picker := OptionButton.new()
	picker.name = "ConditionPicker"
	for label: String in SupportLibrary.LABELS: picker.add_item(label)
	picker.select(session.intervention_type)
	column.add_child(picker)
	column.add_child(UIkit.paragraph("Every condition includes the same 15-second decision pause after initial discussion.",UIkit.CAPTION))
	column.add_child(UIkit.button("Apply condition",func(): session.configure_condition(picker.selected),true))
	column.add_child(UIkit.button("Cancel",_close_modal))

func _build_support(parent: Node) -> void:
	support_card = UIkit.card(parent,UIkit.INNER)
	support_card.name = "SupportCard"
	support_card.add_theme_constant_override("separation",UIkit.MD)
	support_card.get_parent().custom_minimum_size.y = 400
	# No condition-dependent styling, timing, wording or hierarchy.
	for line: String in str(session.support_message.text).split("\n"):
		var separator := line.find(":")
		support_card.add_child(UIkit.label(line.substr(0,separator+1),UIkit.BODY))
		support_card.add_child(UIkit.paragraph(line.substr(separator+1).strip_edges(),UIkit.BODY,UIkit.TEXT))
	_mark_support_visible.call_deferred(session.run_token,session.state.round)

func _mark_support_visible(token: int, round_number: int) -> void:
	await get_tree().process_frame
	if token != session.run_token or round_number != session.state.round: return
	if session.phase == GameManager.Phase.INTERVENTION and is_instance_valid(support_card) and support_card.is_visible_in_tree():
		session.mark_support_shown()

func _select_shelter(id: String) -> void:
	selected_shelter = id
	selected_edge = ""
	if _private_phase() or _busy():
		board.selected_shelter = id
		board.selected_edge = ""
		board.queue_redraw()
	else: _render()

func _select_edge(id: String) -> void:
	selected_shelter = ""
	selected_edge = id
	if _private_phase() or _busy():
		board.selected_shelter = ""
		board.selected_edge = id
		board.queue_redraw()
	else: _render()

func _request_action(kind: String, target: String) -> void:
	if session.phase != GameManager.Phase.ACTIONS: return
	var options := session.action_manager.supply.delivery_options(kind,target)
	if options.is_empty(): return
	var column := _modal_base("%s %s?" % [kind,target.replace("-"," — ")])
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 46
	for option in options:
		var text: String = "1 supply · " + session.scenario.shelter_names[option[0]]
		if kind == "ISOLATE":
			var edge: EdgeState = session.state.edges[target]
			text = "%s to %s  +  %s to %s" % [session.scenario.shelter_names[option[0]],edge.from,session.scenario.shelter_names[option[1]],edge.to]
		picker.add_item(text)
	column.add_child(picker)
	column.add_child(UIkit.label("Cost: %d supply" % (2 if kind=="ISOLATE" else 1),UIkit.BODY,UIkit.ACCENT))
	if kind=="ISOLATE":
		column.add_child(UIkit.paragraph("Stops zombie movement. Supply impact:",UIkit.BODY))
		var losses := session.action_manager.preview_isolation(target)
		for depot in losses:
			column.add_child(UIkit.paragraph("%s: %s" % [session.scenario.shelter_names[depot],"no route loss" if losses[depot].is_empty() else ", ".join(losses[depot])+" lose access"],UIkit.BODY,UIkit.AMBER))
		column.add_child(UIkit.paragraph("One unit to each endpoint. Road closes after both arrive.",UIkit.CAPTION))
		board.preview_edge = target
		for lost: Array in losses.values():
			for id in lost:
				if not board.preview_lost.has(id): board.preview_lost.append(id)
	var preview_paths := func():
		var assignments: Array[String] = []
		assignments.assign(options[picker.selected])
		board.supply_paths.clear()
		for delivery in session.action_manager.supply.delivery_plan(kind,target,assignments): board.supply_paths.append(delivery.path)
		board.queue_redraw()
	picker.item_selected.connect(func(_index: int): preview_paths.call())
	preview_paths.call()
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(UIkit.button("Cancel",_close_modal))
	buttons.add_child(UIkit.button("Confirm delivery",func():
		var assignments: Array[String] = []
		assignments.assign(options[picker.selected])
		_close_modal()
		var result := session.dispatch_action(kind,target,assignments)
		if not result.ok: _show_message("Unavailable",result.error),true))

func _request_resolution() -> void:
	_show_modal("End Round %d?" % session.state.round,"Unused supply carries forward. Active shields expire after resolution.","Resolve",func(): session.begin_resolution())

func _animate_phase(token: int) -> void:
	if token != session.run_token: return
	var current_board := board
	if session.phase == GameManager.Phase.DELIVERY:
		await current_board.play_deliveries(session.pending_action.deliveries)
		if token == session.run_token and session.pending_action.type == "ISOLATE":
			await current_board.play_closure(session.pending_action.target)
		if token == session.run_token: session.complete_delivery(token)
	elif session.phase == GameManager.Phase.RESOLUTION:
		if not session.resolution_applied:
			await current_board.play_outbreak(session.pending_resolution.movements)
			if token == session.run_token: session.apply_resolution(token)
		else:
			await current_board.play_reveal(session.last_summary.newly_overrun)
			if token == session.run_token: session.finish_resolution(token)

func _build_private(parent: Node) -> void:
	parent.add_theme_constant_override("separation",UIkit.SM)
	parent.add_child(UIkit.label("PRIVATE INPUT / PLAYER %d ONLY" % (session.private_player+1),UIkit.CAPTION,UIkit.AMBER))
	var locations: Array = session.state.shelters.keys()+session.state.edges.keys()
	var danger := _picker(parent,"Most immediate danger",locations)
	var action := _picker(parent,"Proposed action",PlayerBelief.ACTIONS)
	var target := _picker(parent,"Action target",[])
	target.disabled = true
	var confidence := _picker(parent,"Confidence · 1 low / 5 high",["1","2","3","4","5"])
	var reason := _picker(parent,"Main reason · optional",PlayerBelief.REASONS.slice(1))
	var submit := UIkit.button("Submit & pass screen",func():
		var belief := PlayerBelief.new(str(danger.get_selected_metadata()),str(action.get_selected_metadata()),str(target.get_selected_metadata()),int(confidence.get_selected_metadata()),"" if reason.selected==0 else str(reason.get_selected_metadata()))
		session.submit_belief(belief),true)
	submit.disabled = true
	parent.add_child(submit)
	var validate := func(_index: int): submit.disabled = danger.selected==0 or action.selected==0 or target.selected==0 or confidence.selected==0
	action.item_selected.connect(func(_index: int):
		_fill_picker(target,session.survey_targets(str(action.get_selected_metadata())))
		target.disabled = str(action.get_selected_metadata())=="WAIT"
		if target.disabled: target.select(1)
		validate.call(0))
	for picker in [danger,target,confidence]: picker.item_selected.connect(validate)

func _picker(parent: Node, title: String, values: Array) -> OptionButton:
	parent.add_child(UIkit.paragraph(title,UIkit.CAPTION,UIkit.TEXT))
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 40
	picker.add_theme_stylebox_override("normal",UIkit.box(UIkit.PANEL,UIkit.LINE,0,UIkit.SM))
	_fill_picker(picker,values)
	parent.add_child(picker)
	return picker

func _fill_picker(picker: OptionButton, values: Array) -> void:
	picker.clear()
	picker.add_item("Choose…")
	picker.set_item_disabled(0,true)
	for value in values:
		var text := str(value)
		if session.state.shelters.has(text): text += " · " + session.scenario.shelter_names[text]
		elif session.state.edges.has(text): text = "Road " + text.replace("-"," — ")
		elif text=="WAIT": text = "WAIT / SAVE SUPPLY"
		elif text=="NONE": text = "No target"
		picker.add_item(text)
		picker.set_item_metadata(picker.item_count-1,value)
	picker.select(0)

func _build_results(parent: Node) -> void:
	parent.add_child(UIkit.label("%d / 8" % (8-session.state.overrun_ids().size()),UIkit.METRIC))
	parent.add_child(UIkit.label("SHELTERS FUNCTIONING",UIkit.CAPTION))
	UIkit.rule(parent,true)
	for entry in [["Shelters lost",str(session.state.overrun_ids().size())],["Supplies spent","%d / 6" % (6-session.state.total_supply())],["Roads closed",str(session.closed_road_count())]]:
		var row := HBoxContainer.new()
		parent.add_child(row)
		var key := UIkit.label(entry[0],UIkit.BODY,UIkit.MUTED)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		row.add_child(UIkit.label(entry[1],UIkit.SECTION))
	UIkit.rule(parent)
	parent.add_child(UIkit.paragraph("LOST LOCATIONS\n" + (", ".join(session.state.overrun_ids()) if not session.state.overrun_ids().is_empty() else "None"),UIkit.CAPTION,UIkit.RED))
	if export_status != "" and session.dev_mode: parent.add_child(UIkit.paragraph(export_status,UIkit.CAPTION))

func _show_help() -> void:
	var column := _modal_base("Field guide")
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(0,minf(450,size.y-270))
	column.add_child(wrapper)
	UIkit.scroll_column(wrapper).add_child(UIkit.rich(PresentationText.RULES+PresentationText.MAP_KEY))
	column.add_child(UIkit.button("Close",_close_modal,true))

func _show_inspector() -> void:
	if not session.dev_mode or _private_phase() or _busy(): return
	var column := _modal_base("DEV MODE / INSPECTOR")
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(0,minf(450,size.y-270))
	column.add_child(wrapper)
	UIkit.scroll_column(wrapper).add_child(UIkit.paragraph(PresentationText.debug(session),UIkit.CAPTION,UIkit.TEXT))
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(UIkit.button("Export research JSON",_export_session))
	buttons.add_child(UIkit.button("Close",_close_modal,true))

func _request_dev_mode(enabled: bool) -> void:
	if not enabled: session.set_dev_mode(false); return
	_show_modal("Enable Dev mode?","Reveals hidden state and private records. Flags this session as a development run.","Enable Dev mode",func(): session.set_dev_mode(true),func(): _render())

func _request_restart() -> void:
	_show_modal("Restart scenario?","Current progress will be cleared.","Restart scenario",func(): export_status = ""; session.reset())
func _export_session() -> void:
	var filename := "cascade_session_"+Time.get_datetime_string_from_system().replace(":","-")+".json"
	var text := JSON.stringify(session.export_dictionary(),"\t")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(),filename,"application/json")
		export_status = "Session JSON download requested."
		_render()
		return
	var dialog := FileDialog.new()
	dialog.title = "Export session JSON"
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Session JSON"])
	dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	dialog.current_file = filename
	dialog.size = Vector2i(850,560)
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null:
			_show_message("Export failed","Could not write to that location. Choose a writable folder and try again.")
		else:
			file.store_string(text)
			file.close()
			export_status = "Saved session JSON: "+path
			_render())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _modal_base(title: String) -> VBoxContainer:
	_close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var shade := ColorRect.new()
	shade.color = Color(UIkit.TEXT,0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640,0)
	panel.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.TEXT,0,UIkit.XXL))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	panel.add_child(column)
	column.add_child(UIkit.paragraph(title,UIkit.DISPLAY,UIkit.TEXT))
	return column

func _show_modal(title: String, body: String, confirm_text: String, confirm: Callable, cancel: Callable = Callable()) -> void:
	var column := _modal_base(title)
	column.add_child(UIkit.paragraph(body,UIkit.BODY,UIkit.MUTED))
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(UIkit.button("Cancel",func(): _close_modal(); if cancel.is_valid(): cancel.call()))
	buttons.add_child(UIkit.caution(UIkit.button(confirm_text,func(): _close_modal(); confirm.call())))

func _show_message(title: String, body: String) -> void:
	var column := _modal_base(title)
	column.add_child(UIkit.paragraph(body,UIkit.BODY))
	column.add_child(UIkit.button("Close",_close_modal,true))

func _close_modal() -> void:
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal = null
	if is_instance_valid(board):
		board.supply_paths.clear()
		board.preview_edge = ""
		board.preview_lost.clear()
		board.queue_redraw()

func _build_handoff(parent: Node) -> void:
	var center := CenterContainer.new()
	center.name = "PrivacyScreen"
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(center)
	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(640,0)
	sheet.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.PANEL,0,UIkit.XXL))
	center.add_child(sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",UIkit.XL)
	sheet.add_child(column)
	column.add_child(UIkit.label("ROUND %02d  /  PRIVATE INPUT" % session.state.round,UIkit.CAPTION,UIkit.MUTED))
	UIkit.rule(column,true)
	column.add_child(UIkit.label("PLAYER %d ONLY" % (session.private_player+1),UIkit.DISPLAY))
	column.add_child(UIkit.paragraph("Pass the screen. Other players: look away.",UIkit.BODY,UIkit.TEXT))
	column.add_child(UIkit.button("Open my form",session.open_private_form,true))
	phase_label = null

func _build_operation(parent: Node) -> void:
	if session.phase == GameManager.Phase.DELIVERY:
		var action: GameAction = session.pending_action
		parent.add_child(UIkit.label(action.type+" / "+action.target,UIkit.SECTION))
		parent.add_child(UIkit.paragraph("Supply en route",UIkit.BODY))
	else:
		parent.add_child(UIkit.label("OUTBREAK RESOLUTION",UIkit.CAPTION,UIkit.MUTED))
		parent.add_child(UIkit.paragraph("Updating the district.",UIkit.SECTION,UIkit.TEXT))
		if session.resolution_applied:
			var newly: Array = session.last_summary.newly_overrun
			parent.add_child(UIkit.paragraph("Newly Overrun: "+(", ".join(newly) if not newly.is_empty() else "None"),UIkit.BODY,UIkit.RED))
