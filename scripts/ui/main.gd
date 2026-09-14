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

func _ready() -> void:
	theme = UIkit.make_theme()
	session = GameManager.new()
	session.changed.connect(_render)
	_render()

func _private_phase() -> bool:
	return session.phase in [GameManager.Phase.PRIVATE_GATE,GameManager.Phase.PRIVATE_FORM]

func _busy() -> bool:
	return session.phase in [GameManager.Phase.DELIVERY,GameManager.Phase.RESOLUTION]

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
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,18)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation",14)
	margin.add_child(page)
	_build_header(page)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation",16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	_build_map(body)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 350
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	body.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	column.add_child(UIkit.label("ROUND %d / %d" % [session.state.round,session.scenario.rounds],13,UIkit.MUTED))
	phase_label = UIkit.label(session.phase_label(),22,UIkit.RED if _busy() else UIkit.ACCENT)
	column.add_child(phase_label)
	var divider := HSeparator.new()
	column.add_child(divider)
	sidebar = UIkit.scroll_column(column)
	sidebar.add_theme_constant_override("separation",14)
	_build_supply(sidebar)
	if session.phase == GameManager.Phase.RESULTS:
		_build_results(sidebar)
	elif _private_phase():
		_build_private(sidebar)
	else:
		if not session.latest_observation.is_empty(): _observation_card(sidebar,session.latest_observation)
		if session.phase in [GameManager.Phase.ROUND_COMPLETE,GameManager.Phase.RESOLUTION] and session.resolution_applied:
			for alert in session.last_summary.get("monitor_alerts",[]): _observation_card(sidebar,alert)
		_build_intel(sidebar)
		_build_selection(sidebar)
	footer = VBoxContainer.new()
	column.add_child(footer)
	_build_phase_button()
	if _busy(): _animate_phase.call_deferred(session.run_token)

func _build_header(parent: Node) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var title := UIkit.label("CASCADE LAB  /  OUTBREAK",23)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(UIkit.label("COOPERATIVE CONTAINMENT",11,UIkit.MUTED))
	var help := UIkit.button("?",_show_help)
	help.tooltip_text = "Rules and map controls"
	row.add_child(help)
	var dev := CheckButton.new()
	dev.text = "Dev mode"
	dev.button_pressed = session.dev_mode
	dev.disabled = _private_phase() or _busy()
	dev.toggled.connect(_request_dev_mode)
	row.add_child(dev)
	if session.dev_mode and not _private_phase():
		var inspect := UIkit.button("Inspect",_show_inspector)
		inspect.disabled = _busy()
		row.add_child(inspect)
	var restart := UIkit.button("Restart",_request_restart)
	restart.disabled = _busy()
	row.add_child(restart)

func _build_map(parent: Node) -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.35
	parent.add_child(left)
	var top := HBoxContainer.new()
	left.add_child(top)
	var title := UIkit.label(session.scenario.scenario_title.to_upper(),15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIkit.label("%d / 8 functioning" % (8-session.state.overrun_ids().size()),14,UIkit.ACCENT))
	var border := PanelContainer.new()
	border.add_theme_stylebox_override("panel",UIkit.box(UIkit.INNER,UIkit.LINE,4,0))
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
	left.add_child(controls)
	controls.add_child(UIkit.button("−",func(): board.zoom_at(1.0/1.2,board.size/2)))
	controls.add_child(UIkit.button("+",func(): board.zoom_at(1.2,board.size/2)))
	controls.add_child(UIkit.button("Center",func(): board.center_map()))
	zoom_label = UIkit.label("%d%%" % roundi(board.zoom*100),13,UIkit.MUTED)
	controls.add_child(zoom_label)
	board.view_changed.connect(func(): zoom_label.text = "%d%%" % roundi(board.zoom*100))
	var legend := UIkit.paragraph("Drag to pan · Wheel to zoom\nM monitor   V verified   S shield   /   Green ring: supply access",12,UIkit.MUTED)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_child(legend)
	if session.dev_mode and not _private_phase():
		left.add_child(UIkit.label("DEV MODE · HIDDEN STATE VISIBLE · SOURCE " + session.scenario.original_source,13,UIkit.RED))

func _build_supply(parent: Node) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	for id in session.state.depots:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",3)
		row.add_child(column)
		column.add_child(UIkit.label(session.scenario.shelter_names[id].to_upper(),11,UIkit.MUTED))
		column.add_child(UIkit.label("%d / 3 supply" % session.state.depots[id].supply_remaining,19,UIkit.ACCENT))

func _build_intel(parent: Node) -> void:
	var card := UIkit.card(parent,UIkit.INNER)
	card.add_child(UIkit.label("PUBLIC INTEL",13))
	card.add_child(UIkit.paragraph("City surveillance · scheduled each round",11,UIkit.MUTED))
	for index in session.public_intel.size():
		var report: Dictionary = session.public_intel[index]
		var latest := index == session.public_intel.size()-1
		card.add_child(UIkit.label("R%d · %s" % [report.round,report.time],12,UIkit.ACCENT))
		card.add_child(UIkit.paragraph(report.text,15 if latest else 12,UIkit.TEXT if latest else UIkit.MUTED))

func _build_selection(parent: Node) -> void:
	parent.add_child(UIkit.label("SELECTED",12,UIkit.MUTED))
	if selected_shelter == "" and selected_edge == "":
		parent.add_child(UIkit.paragraph("Select a shelter or road.",17))
		return
	if selected_edge != "":
		var edge: EdgeState = session.state.edges[selected_edge]
		parent.add_child(UIkit.label("ROAD %s — %s" % [edge.from,edge.to],23))
		parent.add_child(UIkit.label("ROAD CLOSED" if edge.isolated else "Two-way road",14,UIkit.RED if edge.isolated else UIkit.MUTED))
		if session.phase == GameManager.Phase.ACTIONS: _action_button(parent,"ISOLATE",selected_edge)
	else:
		var shelter: ShelterState = session.state.shelters[selected_shelter]
		parent.add_child(UIkit.label("SHELTER " + selected_shelter,23))
		parent.add_child(UIkit.label(shelter.display_name,15))
		parent.add_child(UIkit.label("Known: " + PresentationText.known_status(shelter),16,UIkit.RED if shelter.is_overrun else UIkit.MUTED))
		var access: Array[String] = []
		for depot in session.action_manager.supply.eligible_depots(selected_shelter): access.append(session.scenario.shelter_names[depot])
		parent.add_child(UIkit.paragraph("Supply: " + (", ".join(access) if not access.is_empty() else "NO SUPPLY ROUTE"),13,UIkit.ACCENT))
		if shelter.is_monitored: parent.add_child(UIkit.label("MONITORED",12,UIkit.TEAL))
		if shelter.shielded_this_round: parent.add_child(UIkit.label("SHIELDED · this resolution",12,UIkit.TEAL))
		for record in shelter.verified_history:
			parent.add_child(UIkit.label("Verified R%d: Pressure %d" % [record.round,record.pressure],13,UIkit.TEAL))
		if session.phase == GameManager.Phase.ACTIONS:
			for kind in ["VERIFY","MONITOR","SHIELD"]: _action_button(parent,kind,selected_shelter)
		if session.dev_mode: parent.add_child(UIkit.label("DEV · P%d" % shelter.zombie_pressure,14,UIkit.RED))

func _action_button(parent: Node, kind: String, target: String) -> void:
	var reason := session.action_manager.unavailable_reason(kind,target)
	var button := UIkit.button("%s · %d" % [kind,2 if kind == "ISOLATE" else 1],func(): _request_action(kind,target))
	button.disabled = reason != ""
	button.tooltip_text = reason if reason != "" else {"VERIFY":"Exact pressure snapshot","MONITOR":"Reports later changes","SHIELD":"Blocks incoming infection this resolution","ISOLATE":"One delivery to each endpoint"}[kind]
	parent.add_child(button)
	if reason != "": parent.add_child(UIkit.label(reason,11,UIkit.RED))

func _observation_card(parent: Node, observation: Dictionary) -> void:
	var card := UIkit.card(parent,Color("e1e9da"))
	card.add_child(UIkit.paragraph(PresentationText.observation_text(observation),17,UIkit.ACCENT))

func _build_phase_button() -> void:
	match session.phase:
		GameManager.Phase.OBSERVE:
			footer.add_child(UIkit.button("Private judgment",session.start_private,true))
		GameManager.Phase.DISCUSSION:
			footer.add_child(UIkit.label("Discuss your next move.",14,UIkit.MUTED))
			footer.add_child(UIkit.button("Proceed to actions",session.proceed_to_actions,true))
		GameManager.Phase.ACTIONS:
			footer.add_child(UIkit.button("End round",_request_resolution,true))
		GameManager.Phase.DELIVERY:
			footer.add_child(UIkit.label("Supply en route…",15,UIkit.ACCENT))
		GameManager.Phase.RESOLUTION:
			footer.add_child(UIkit.label("Resolution…",15,UIkit.RED))
		GameManager.Phase.ROUND_COMPLETE:
			var newly: Array = session.last_summary.newly_overrun
			footer.add_child(UIkit.paragraph("Shelters lost: " + (", ".join(newly) if not newly.is_empty() else "None"),14,UIkit.RED if not newly.is_empty() else UIkit.MUTED))
			footer.add_child(UIkit.button("Results" if session.state.round==3 else "Next round",session.next_round,true))
		GameManager.Phase.RESULTS:
			footer.add_child(UIkit.button("Export session JSON",_export_session))
			footer.add_child(UIkit.button("Play again",_request_restart,true))

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
			text = "%s → %s  +  %s → %s" % [session.scenario.shelter_names[option[0]],edge.from,session.scenario.shelter_names[option[1]],edge.to]
		picker.add_item(text)
	column.add_child(picker)
	column.add_child(UIkit.label("Cost: %d supply" % (2 if kind=="ISOLATE" else 1),18,UIkit.ACCENT))
	if kind=="ISOLATE":
		column.add_child(UIkit.paragraph("Stops zombie movement. Supply impact:",15))
		var losses := session.action_manager.preview_isolation(target)
		for depot in losses:
			column.add_child(UIkit.paragraph("%s: %s" % [session.scenario.shelter_names[depot],"no route loss" if losses[depot].is_empty() else ", ".join(losses[depot])+" lose access"],15,UIkit.AMBER))
		column.add_child(UIkit.paragraph("One unit to each endpoint. Road closes after both arrive.",13))
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
		if token == session.run_token: session.complete_delivery(token)
	elif session.phase == GameManager.Phase.RESOLUTION:
		if not session.resolution_applied:
			await current_board.play_outbreak(session.pending_resolution.movements)
			if token == session.run_token: session.apply_resolution(token)
		else:
			await current_board.play_reveal(session.last_summary.newly_overrun)
			if token == session.run_token: session.finish_resolution(token)

func _build_private(parent: Node) -> void:
	parent.add_child(UIkit.label("PLAYER %d ONLY" % (session.private_player+1),20,UIkit.AMBER))
	if session.phase == GameManager.Phase.PRIVATE_GATE:
		parent.add_child(UIkit.paragraph("Other players: look away.",17))
		parent.add_child(UIkit.button("Open my form",session.open_private_form,true))
		_build_intel(parent)
		return
	var locations: Array = session.state.shelters.keys()+session.state.edges.keys()
	var danger := _picker(parent,"Most immediate danger",locations)
	var action := _picker(parent,"What should the team do next?",PlayerBelief.ACTIONS)
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
	_build_intel(parent)

func _picker(parent: Node, title: String, values: Array) -> OptionButton:
	parent.add_child(UIkit.paragraph(title,14,UIkit.TEXT))
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 40
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
	parent.add_child(UIkit.label("SURVIVORS",13,UIkit.MUTED))
	parent.add_child(UIkit.label("%d / 8" % (8-session.state.overrun_ids().size()),48,UIkit.ACCENT))
	parent.add_child(UIkit.label("SUPPLY USED   %d / 6" % (6-session.state.total_supply()),17))
	parent.add_child(UIkit.label("ROADS CLOSED   %d" % session.closed_road_count(),17))
	parent.add_child(UIkit.paragraph("SHELTERS LOST\n" + (", ".join(session.state.overrun_ids()) if not session.state.overrun_ids().is_empty() else "None"),17,UIkit.RED))
	if export_status != "" and session.dev_mode: parent.add_child(UIkit.paragraph(export_status,12))

func _show_help() -> void:
	var column := _modal_base("Field guide")
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(0,490)
	column.add_child(wrapper)
	UIkit.scroll_column(wrapper).add_child(UIkit.rich(PresentationText.RULES))
	column.add_child(UIkit.button("Close",_close_modal,true))

func _show_inspector() -> void:
	if not session.dev_mode or _private_phase() or _busy(): return
	var column := _modal_base("DEV MODE / INSPECTOR")
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(0,470)
	column.add_child(wrapper)
	UIkit.scroll_column(wrapper).add_child(UIkit.paragraph(PresentationText.debug(session),13,UIkit.TEXT))
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
	shade.color = Color(0.17,0.18,0.15,0.50)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620,0)
	panel.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.TEAL,14,26))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	panel.add_child(column)
	column.add_child(UIkit.paragraph(title,25,UIkit.TEXT))
	return column

func _show_modal(title: String, body: String, confirm_text: String, confirm: Callable, cancel: Callable = Callable()) -> void:
	var column := _modal_base(title)
	column.add_child(UIkit.paragraph(body,17,UIkit.MUTED))
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(UIkit.button("Cancel",func(): _close_modal(); if cancel.is_valid(): cancel.call()))
	buttons.add_child(UIkit.button(confirm_text,func(): _close_modal(); confirm.call(),true))

func _show_message(title: String, body: String) -> void:
	var column := _modal_base(title)
	column.add_child(UIkit.paragraph(body,17))
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
