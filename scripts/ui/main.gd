extends Control

var practice: PracticeView
var practice_completed_version := ""
var mission_session: MissionSession
var session: GameManager
var board: NetworkView
var sidebar: VBoxContainer
var modal: Control
var selected_shelter := ""
var selected_edge := ""
var map_zoom := 1.0
var map_token := 0
var export_status := ""
var phase_label: Label
var timer_label: Label
var inspector: PanelContainer
var inspector_column: VBoxContainer
var survey_drawer: PanelContainer
var survey_content: VBoxContainer
var survey_toggle: Button
var survey_collapsed := false
var survey_tween: Tween
var road_bubble: PanelContainer
var road_pointer: Control
var workspace: Control
var map_center := Vector2(500,350)
var footer: VBoxContainer
var support_card: VBoxContainer
var support_countdown: Label
var support_continue: Button
var save_indicator: Label
var save_text := ""
# Presentation constants at the 1440 x 900 reference layout.
const SIDEBAR_WIDTH := 400
const SUPPORT_SIDEBAR_WIDTH := 460
# Every condition's note uses this identical card height.
const SUPPORT_NOTE_HEIGHT := 480
const SURVEY_HEIGHT := 470
const SURVEY_COLLAPSED := 88
const HEADER_SIDE := 340

func _ready() -> void:
	theme = UIkit.make_theme()
	_show_main_menu()

func _private_phase() -> bool:
	return session.phase in [GameManager.Phase.PRIVATE_GATE,GameManager.Phase.PRIVATE_FORM]

func _busy() -> bool:
	return session.phase in [GameManager.Phase.DELIVERY,GameManager.Phase.RESOLUTION]

func _process(_delta: float) -> void:
	if is_instance_valid(save_indicator): _refresh_save_notice()
	if session == null: return
	if session.phase == GameManager.Phase.DISCUSSION:
		_update_timer(session.discussion_seconds_remaining())
		session.tick_discussion()
	elif session.phase == GameManager.Phase.INTERVENTION:
		var seconds := session.support_seconds_remaining()
		_update_timer(seconds)
		if is_instance_valid(support_countdown) and is_instance_valid(support_continue):
			support_countdown.text = "Continue in %ds" % seconds if seconds > 0 else "Ready to continue"
			if session.support_message.is_empty(): support_countdown.text = "Waiting for AI support…"
			support_continue.disabled = not session.support_shown or seconds > 0
	if is_instance_valid(road_bubble): _position_road_bubble()

func _update_timer(seconds: int) -> void:
	if is_instance_valid(timer_label): timer_label.text = "%d:%02d" % [seconds / 60,seconds % 60]

# Saving and connection state. Routine saves stay quiet during play; problems are
# always shown. The main menu may also show routine status for the facilitator.
func _refresh_save_notice() -> void:
	var text := StudySync.status_text()
	if text == save_text and save_indicator.has_meta("ready"): return
	save_text = text
	save_indicator.set_meta("ready",true)
	# Automated test runs disable saving on purpose; participants never see that state.
	var routine := text.begins_with("Saved") or text.begins_with("Saving") or not StudySync.enabled
	save_indicator.text = text
	save_indicator.visible = not routine or save_indicator.has_meta("show_routine")
	save_indicator.add_theme_color_override("font_color",UIkit.SECONDARY if routine else UIkit.WARNING)

func _render() -> void:
	if map_token != session.run_token:
		map_zoom = 1.0
		map_center = Vector2(session.scenario.world_size[0],session.scenario.world_size[1])*0.5
		selected_shelter = ""
		selected_edge = ""
		map_token = session.run_token
	elif is_instance_valid(board):
		map_zoom = board.zoom
		map_center = board.camera_center
	if session.phase == GameManager.Phase.PRIVATE_GATE:
		selected_shelter = ""
		selected_edge = ""
		map_zoom = 1.0
		map_center = Vector2(session.scenario.world_size[0],session.scenario.world_size[1])*0.5
	for child in get_children():
		remove_child(child)
		child.queue_free()
	modal = null
	board = null
	road_bubble = null
	road_pointer = null
	survey_drawer = null
	support_card = null
	support_countdown = null
	support_continue = null
	var background := ColorRect.new()
	background.color = UIkit.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,UIkit.XL)
	margin.add_theme_constant_override("margin_top",UIkit.LG)
	margin.add_theme_constant_override("margin_bottom",UIkit.XL-4)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation",UIkit.LG)
	margin.add_child(page)
	_build_header(page)
	if session.phase == GameManager.Phase.PRIVATE_GATE:
		_build_handoff(page)
		return
	workspace = Control.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(workspace)
	var body := HBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation",UIkit.LG)
	workspace.add_child(body)
	workspace.resized.connect(_size_survey)
	_build_map(body)
	inspector = PanelContainer.new()
	inspector.name = "BuildingDetails"
	inspector.custom_minimum_size.x = SIDEBAR_WIDTH
	inspector.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.LINE,6,UIkit.XL-4))
	body.add_child(inspector)
	inspector_column = UIkit.scroll_column(inspector)
	inspector_column.get_parent().follow_focus = true
	_refresh_inspector()
	# One compact action bar under the map: map instructions on the left, the phase action on the right.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation",UIkit.XL)
	page.add_child(bar)
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	notes.add_theme_constant_override("separation",UIkit.XS)
	bar.add_child(notes)
	notes.add_child(UIkit.meta("Select a location piece or a road. Solid roads carry supplies; dotted roads have no supply route."))
	if session.dev_mode and not _private_phase(): notes.add_child(UIkit.meta("Dev mode · hidden state visible",UIkit.DANGER))
	if session.is_sandbox(): notes.add_child(UIkit.meta("Dev mode — not research data",UIkit.WARNING))
	footer = VBoxContainer.new()
	footer.custom_minimum_size.x = 360
	footer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_theme_constant_override("separation",UIkit.SM)
	bar.add_child(footer)
	_build_phase_button()
	if session.phase == GameManager.Phase.PRIVATE_FORM: _build_survey_drawer()
	if selected_edge != "": _build_road_bubble()
	if _busy(): _animate_phase.call_deferred(session.run_token)

func _refresh_inspector() -> void:
	for child in inspector_column.get_children():
		inspector_column.remove_child(child)
		child.queue_free()
	var phase_panel := session.phase in [GameManager.Phase.INTERVENTION,GameManager.Phase.RESULTS,GameManager.Phase.ROUND_COMPLETE] or _busy()
	inspector.visible = selected_shelter != "" or phase_panel
	inspector.custom_minimum_size.x = SUPPORT_SIDEBAR_WIDTH if session.phase == GameManager.Phase.INTERVENTION else SIDEBAR_WIDTH
	sidebar = inspector_column
	if session.phase == GameManager.Phase.INTERVENTION:
		# The header already names the decision pause; the note stands alone.
		_build_support(sidebar)
	elif session.phase == GameManager.Phase.RESULTS: _build_results(sidebar)
	elif _busy(): _build_operation(sidebar)
	elif session.phase == GameManager.Phase.ROUND_COMPLETE:
		sidebar.add_child(UIkit.heading("Round %d · What changed" % session.last_summary.round))
		var newly: Array = session.last_summary.newly_overrun
		sidebar.add_child(UIkit.paragraph("Newly Overrun: " + (", ".join(newly) if not newly.is_empty() else "None"),UIkit.BODY,UIkit.DANGER if not newly.is_empty() else UIkit.TEXT))
		sidebar.add_child(UIkit.strong("%d supplies remaining · %d roads closed" % [session.state.total_supply(),session.closed_road_count()]))
		for action: GameAction in session.state.actions:
			if action.round == session.last_summary.round:
				sidebar.add_child(UIkit.meta("%s · %s · delivery complete" % [action.type,action.target]))
		for observation in session.state.observations:
			if observation.round == session.last_summary.round: _observation_card(sidebar,observation)
		if not session.last_summary.shields.is_empty(): sidebar.add_child(UIkit.meta("Shields expired: " + ", ".join(session.last_summary.shields)))
	if selected_shelter != "":
		_build_selection(sidebar)
		if not session.latest_observation.is_empty() and session.latest_observation.get("target","") == selected_shelter:
			_observation_card(sidebar,session.latest_observation)

func _build_header(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 72
	row.add_theme_constant_override("separation",UIkit.XL)
	parent.add_child(row)
	var left := HBoxContainer.new()
	left.custom_minimum_size.x = HEADER_SIDE
	left.add_theme_constant_override("separation",UIkit.LG)
	row.add_child(left)
	var menu := UIkit.button("Menu",_show_menu)
	menu.tooltip_text = "Session menu and field guide"
	menu.custom_minimum_size.x = 92
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(menu)
	var context := VBoxContainer.new()
	context.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	context.add_theme_constant_override("separation",0)
	left.add_child(context)
	context.add_child(UIkit.strong("Mission %d of %d" % [mission_session.index+1,mission_session.order.size()]))
	context.add_child(UIkit.label("Round %d of %d" % [session.state.round,session.scenario.rounds]))
	# Phase title with its countdown on the same line, keeping the header compact.
	var heading := HBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation",UIkit.LG+4)
	row.add_child(heading)
	phase_label = UIkit.text_label("Discussion time" if session.phase == GameManager.Phase.DISCUSSION else PresentationText.phase_title(session.phase),UIkit.HEADING_FONT,UIkit.DISPLAY)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_child(phase_label)
	# Countdowns are plain charcoal figures: visible, without an urgency colour.
	timer_label = UIkit.figure("",UIkit.TIMER,UIkit.TEXT)
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(timer_label)
	if session.phase == GameManager.Phase.DISCUSSION: _update_timer(session.discussion_seconds_remaining())
	elif session.phase == GameManager.Phase.INTERVENTION: _update_timer(session.support_seconds_remaining())
	else: timer_label.visible = false
	var status := VBoxContainer.new()
	status.custom_minimum_size.x = HEADER_SIDE
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.add_theme_constant_override("separation",UIkit.XS)
	row.add_child(status)
	var readouts := HBoxContainer.new()
	readouts.alignment = BoxContainer.ALIGNMENT_END
	readouts.add_theme_constant_override("separation",UIkit.XL+4)
	status.add_child(readouts)
	_readout(readouts,"%d / 8" % (8-session.state.overrun_ids().size()),"Shelters functioning")
	_readout(readouts,"%d / 6" % session.state.total_supply(),"Supply remaining")
	save_indicator = UIkit.meta("")
	save_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	save_text = ""
	status.add_child(save_indicator)
	_refresh_save_notice()

func _readout(parent: Node, value: String, caption: String) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",0)
	parent.add_child(column)
	var number := UIkit.figure(value,UIkit.METRIC)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(number)
	var name_label := UIkit.text_label(caption,UIkit.MEDIUM_FONT,UIkit.SMALL,UIkit.SECONDARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(name_label)

func _show_menu() -> void:
	var column := _modal_base("Session menu")
	column.add_child(UIkit.button("Field guide",_show_help))
	column.add_child(UIkit.button("Export recovery JSON",_export_session))
	if session.can_configure_condition(): column.add_child(UIkit.button("Session setup",_show_session_setup))
	if session.is_sandbox():
		var dev := CheckButton.new()
		dev.text = "Reveal hidden state"
		dev.button_pressed = session.dev_mode
		dev.disabled = _busy()
		dev.toggled.connect(_request_dev_mode)
		column.add_child(dev)
		if session.dev_mode:
			var inspect := UIkit.button("Inspect",_show_inspector)
			inspect.disabled = _busy()
			column.add_child(inspect)
		column.add_child(UIkit.button("Restart",_request_restart))
		column.add_child(UIkit.button("Choose another scenario",func(): _request_leave(_show_level_picker)))
	column.add_child(UIkit.button("Main menu",func(): _request_leave(_show_main_menu)))
	column.add_child(_motion_toggle())
	UIkit.spacer(column,UIkit.XS)
	column.add_child(UIkit.button("Close",_close_modal,true))

func _build_map(parent: Node) -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation",UIkit.SM)
	parent.add_child(left)
	var top := HBoxContainer.new()
	left.add_child(top)
	var title := UIkit.text_label(session.scenario.scenario_title,UIkit.HEADING_FONT,26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	top.add_child(title)
	var overview := UIkit.quiet("Overview",_clear_selection)
	overview.tooltip_text = "Return to the full district (Escape)"
	top.add_child(overview)
	var border := PanelContainer.new()
	border.add_theme_stylebox_override("panel",UIkit.box(UIkit.MAP,Color.TRANSPARENT,0,0))
	border.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(border)
	board = NetworkView.new()
	border.add_child(board)
	board.configure(session.scenario,session.state,session.dev_mode and not _private_phase())
	board.zoom = map_zoom
	board.camera_center = map_center
	board.selected_shelter = selected_shelter
	board.selected_edge = selected_edge
	board.focus_id = selected_shelter
	board.shelter_selected.connect(_select_shelter)
	board.edge_selected.connect(_select_edge)
	board.background_selected.connect(_clear_selection)

func _build_survey_drawer() -> void:
	survey_collapsed = false
	survey_drawer = PanelContainer.new()
	survey_drawer.name = "SurveyDrawer"
	workspace.add_child(survey_drawer)
	survey_drawer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	survey_drawer.offset_top = -minf(SURVEY_HEIGHT,workspace.size.y)
	survey_drawer.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.LINE_STRONG,6,UIkit.XL-4))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",UIkit.LG)
	survey_drawer.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation",UIkit.LG)
	column.add_child(top)
	var private_label := UIkit.strong("Private input · Player %d only" % (session.private_player+1),UIkit.BODY,UIkit.WARNING)
	private_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	private_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(private_label)
	survey_toggle = UIkit.button("Hide survey · inspect map",_toggle_survey)
	survey_toggle.name = "SurveyToggle"
	survey_toggle.custom_minimum_size.x = 360
	top.add_child(survey_toggle)
	survey_content = VBoxContainer.new()
	survey_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(survey_content)
	_build_private(UIkit.scroll_column(survey_content))
	# Container geometry settles after the first frame.
	_size_survey.call_deferred()

func _size_survey() -> void:
	await get_tree().process_frame
	if is_instance_valid(survey_drawer):
		survey_drawer.offset_top = -float(SURVEY_COLLAPSED) if survey_collapsed else -minf(SURVEY_HEIGHT,workspace.size.y)
		survey_drawer.offset_bottom = 0

func _toggle_survey() -> void:
	survey_collapsed = not survey_collapsed
	survey_toggle.text = "Expand survey · continue your answers" if survey_collapsed else "Hide survey · inspect map"
	survey_content.visible = not survey_collapsed
	if survey_collapsed: survey_toggle.grab_focus()
	if survey_tween: survey_tween.kill()
	var goal := -float(SURVEY_COLLAPSED) if survey_collapsed else -minf(SURVEY_HEIGHT,workspace.size.y)
	if UIkit.reduced_motion():
		survey_drawer.offset_top = goal
		return
	survey_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	survey_tween.tween_property(survey_drawer,"offset_top",goal,0.25)

func _clear_selection() -> void:
	if not is_instance_valid(board): return
	selected_shelter = ""
	selected_edge = ""
	board.selected_shelter = ""
	board.selected_edge = ""
	board.center_map()
	_clear_road_bubble()
	_refresh_inspector()

func _unhandled_key_input(event: InputEvent) -> void:
	if session == null: return
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(modal): _close_modal()
		else: _clear_selection()
		get_viewport().set_input_as_handled()

func _clear_road_bubble() -> void:
	for node in [road_bubble,road_pointer]:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	road_bubble = null
	road_pointer = null

func _build_road_bubble() -> void:
	_clear_road_bubble()
	if selected_edge == "" or _busy(): return
	road_pointer = Control.new()
	road_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(road_pointer)
	road_pointer.draw.connect(func():
		var rect := Rect2(road_bubble.position,road_bubble.size)
		var end := road_pointer.position.clamp(rect.position,rect.end)-road_pointer.position
		road_pointer.draw_line(Vector2.ZERO,end,UIkit.LINE_STRONG,1.5,true)
		road_pointer.draw_circle(Vector2.ZERO,3,UIkit.ACTION))
	road_bubble = PanelContainer.new()
	road_bubble.name = "RoadBubble"
	road_bubble.custom_minimum_size.x = 300
	road_bubble.size = Vector2(300,0)
	road_bubble.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.LINE_STRONG,6,UIkit.LG))
	board.add_child(road_bubble)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",UIkit.SM)
	road_bubble.add_child(content)
	var edge: EdgeState = session.state.edges[selected_edge]
	var row := HBoxContainer.new()
	content.add_child(row)
	var title := UIkit.strong("Road "+selected_edge.replace("-"," — "),UIkit.BODY,UIkit.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var close := UIkit.quiet("×",func(): selected_edge = ""; board.selected_edge = ""; board.queue_redraw(); _clear_road_bubble())
	close.tooltip_text = "Close"
	row.add_child(close)
	content.add_child(UIkit.meta("Closed · both directions" if edge.isolated else "Open · two-way route"))
	if session.phase == GameManager.Phase.ACTIONS: _action_button(content,"ISOLATE",selected_edge)
	else: content.add_child(UIkit.paragraph("Road decisions unlock in the action phase.",UIkit.BODY,UIkit.SECONDARY))
	_position_road_bubble.call_deferred()

func _position_road_bubble() -> void:
	if not is_instance_valid(road_bubble) or selected_edge == "": return
	board._refresh_geometry()
	road_bubble.reset_size()
	var anchor := board._point_on_path(board.road_geometry[selected_edge],board.closure_fraction(selected_edge))
	anchor = anchor.clamp(Vector2(24,24),board.size-Vector2(24,24))
	var extent := road_bubble.size
	var best := Vector2(8,8)
	var best_score := INF
	for x in [8.0,maxf(8,board.size.x-extent.x-8)]:
		for y in [8.0,maxf(8,board.size.y-extent.y-8)]:
			var rect := Rect2(Vector2(x,y),extent)
			var score := rect.get_center().distance_to(anchor)*0.01
			if rect.grow(24).has_point(anchor): score += 10000
			# Prefer corners that leave building names and status stamps readable.
			for id in board.title_rects:
				var plate: Rect2 = board.title_rects[id]
				if rect.intersects(Rect2(plate.position,Vector2(plate.size.x,board.NAME_BLOCK))): score += 6
			for id in board.road_geometry:
				for step in 21:
					if rect.grow(8).has_point(board._point_on_path(board.road_geometry[id],step/20.0)):
						score += 10 if id == selected_edge else 1
			if score < best_score:
				best_score = score
				best = rect.position
	road_bubble.position = best
	road_pointer.position = anchor
	road_pointer.queue_redraw()

func _build_selection(parent: Node) -> void:
	if selected_shelter == "": return
	var shelter: ShelterState = session.state.shelters[selected_shelter]
	var top := HBoxContainer.new()
	parent.add_child(top)
	var tag := UIkit.meta(("Depot " if session.state.depots.has(selected_shelter) else "Shelter ")+selected_shelter)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tag)
	var close := UIkit.quiet("×",_clear_selection)
	close.tooltip_text = "Close"
	top.add_child(close)
	parent.add_child(UIkit.heading(shelter.display_name))
	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation",UIkit.SM)
	parent.add_child(facts)
	facts.add_child(UIkit.paragraph("Pressure: " + PresentationText.known_status(shelter),UIkit.BODY,UIkit.DANGER if shelter.is_overrun else UIkit.TEXT))
	var access: Array[String] = []
	for depot in session.action_manager.supply.eligible_depots(selected_shelter): access.append(session.scenario.shelter_names[depot])
	facts.add_child(UIkit.paragraph("Supply access: " + ", ".join(access) if not access.is_empty() else "No stocked supply route"))
	if session.state.depots.has(selected_shelter): facts.add_child(UIkit.strong("%d supply remaining" % session.state.depots[selected_shelter].supply_remaining))
	if shelter.is_monitored: facts.add_child(UIkit.paragraph("Monitor active",UIkit.BODY,UIkit.PROTECT))
	if shelter.shielded_this_round: facts.add_child(UIkit.paragraph("Shield active · this resolution only",UIkit.BODY,UIkit.PROTECT))
	for record in shelter.verified_history:
		facts.add_child(UIkit.paragraph("OBS R%d · Pressure %d at verification" % [record.round,record.pressure],UIkit.BODY,UIkit.SECONDARY))
	if session.dev_mode and not _private_phase(): facts.add_child(UIkit.strong("DEV · P%d" % shelter.zombie_pressure,UIkit.SMALL,UIkit.DANGER))
	UIkit.rule(parent)
	if session.phase == GameManager.Phase.ACTIONS:
		parent.add_child(UIkit.strong("Decisions"))
		for kind in ["VERIFY","MONITOR","SHIELD"]: _action_button(parent,kind,selected_shelter)
	else: parent.add_child(UIkit.paragraph("Decisions unlock in the action phase.",UIkit.BODY,UIkit.SECONDARY))

func _action_button(parent: Node, kind: String, target: String) -> void:
	var reason := session.action_manager.unavailable_reason(kind,target)
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation",UIkit.XS+2)
	parent.add_child(group)
	var button := UIkit.button("%s  ·  %d supply" % [kind,2 if kind == "ISOLATE" else 1],func(): _request_action(kind,target))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = reason != ""
	button.tooltip_text = PresentationText.unavailable_text(reason) if reason != "" else PresentationText.ACTION_DETAILS[kind]
	group.add_child(button)
	if reason != "": group.add_child(UIkit.meta(PresentationText.unavailable_text(reason)))

func _observation_card(parent: Node, observation: Dictionary) -> void:
	var note := VBoxContainer.new()
	note.add_theme_constant_override("separation",UIkit.MD)
	parent.add_child(note)
	UIkit.rule(note)
	note.add_child(UIkit.paragraph(PresentationText.observation_text(observation)))

func _build_phase_button() -> void:
	match session.phase:
		GameManager.Phase.OBSERVE:
			if session.is_sandbox(): footer.add_child(UIkit.button("Begin actions",session.begin_sandbox_actions,true))
			else:
				footer.add_child(UIkit.meta("Record a private proposal. This does not execute a move."))
				footer.add_child(UIkit.button("Choose your first move" if session.state.round == 1 else "Choose your next move",session.start_private,true))
		GameManager.Phase.DISCUSSION:
			footer.add_child(UIkit.paragraph("Discuss your next move. Actions unlock after the discussion timer.",UIkit.BODY,UIkit.SECONDARY))
		GameManager.Phase.INTERVENTION:
			support_countdown = UIkit.meta("Continue in %ds" % session.support_seconds_remaining())
			footer.add_child(support_countdown)
			support_continue = UIkit.button("Proceed to actions",session.proceed_to_actions,true)
			support_continue.disabled = true
			footer.add_child(support_continue)
		GameManager.Phase.ACTIONS:
			footer.add_child(UIkit.button("End round",_request_resolution,true))
		GameManager.Phase.ROUND_COMPLETE:
			var newly: Array = session.last_summary.newly_overrun
			footer.add_child(UIkit.paragraph("Shelters lost: " + (", ".join(newly) if not newly.is_empty() else "None"),UIkit.BODY,UIkit.DANGER if not newly.is_empty() else UIkit.SECONDARY))
			footer.add_child(UIkit.button("Results" if session.state.round==3 else "Next round",session.next_round,true))

func _show_session_setup() -> void:
	if not session.can_configure_condition(): return
	var column := _modal_base("Session setup")
	column.add_child(UIkit.meta("Facilitator only · experiment configuration"))
	column.add_child(UIkit.paragraph("Condition remains fixed across all four missions."))
	var picker := OptionButton.new()
	picker.name = "ConditionPicker"
	picker.custom_minimum_size.y = 48
	for label: String in SupportLibrary.LABELS: picker.add_item(label)
	picker.select(session.intervention_type)
	column.add_child(picker)
	column.add_child(UIkit.paragraph("Every condition includes the same 15-second decision pause after initial discussion.",UIkit.BODY,UIkit.SECONDARY))
	var buttons := _button_row(column)
	buttons.add_child(_sized(UIkit.button("Cancel",_close_modal)))
	buttons.add_child(_sized(UIkit.button("Apply condition",func(): session.configure_condition(picker.selected),true)))

func _build_support(parent: Node) -> void:
	support_card = UIkit.card(parent,UIkit.SUNKEN)
	support_card.name = "SupportCard"
	support_card.add_theme_constant_override("separation",UIkit.XS)
	support_card.get_parent().custom_minimum_size.y = SUPPORT_NOTE_HEIGHT
	if session.support_message.is_empty():
		support_card.add_child(UIkit.paragraph("Waiting for AI support…"))
		return
	# All completed messages use the same structure, fonts, and actual-display timing.
	var first := true
	for line: String in str(session.support_message.text).split("\n"):
		var separator := line.find(":")
		var head := UIkit.strong(line.substr(0,separator+1))
		if not first:
			head.custom_minimum_size.y = 42
			head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		support_card.add_child(head)
		support_card.add_child(UIkit.paragraph(line.substr(separator+1).strip_edges()))
		first = false
	_mark_support_visible.call_deferred(session.run_token,session.state.round)

func _mark_support_visible(token: int, round_number: int) -> void:
	await get_tree().process_frame
	if session == null or token != session.run_token or round_number != session.state.round: return
	if session.phase == GameManager.Phase.INTERVENTION and is_instance_valid(support_card) and support_card.is_visible_in_tree():
		session.mark_support_shown()

func _select_shelter(id: String) -> void:
	if _busy(): return
	selected_shelter = id
	selected_edge = ""
	board.selected_shelter = id
	board.selected_edge = ""
	_clear_road_bubble()
	_refresh_inspector()
	board.pop_piece(id)
	board.focus_building(id)

func _select_edge(id: String) -> void:
	if _busy(): return
	selected_edge = id
	board.selected_edge = id
	board.queue_redraw()
	_build_road_bubble()

func _request_action(kind: String, target: String) -> void:
	if session.phase != GameManager.Phase.ACTIONS: return
	var options := session.action_manager.supply.delivery_options(kind,target)
	if options.is_empty(): return
	var column := _modal_base("%s %s?" % [kind,target.replace("-"," — ")])
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 48
	for option in options:
		var text: String = "1 supply · " + session.scenario.shelter_names[option[0]]
		if kind == "ISOLATE":
			var edge: EdgeState = session.state.edges[target]
			text = "%s to %s  +  %s to %s" % [session.scenario.shelter_names[option[0]],edge.from,session.scenario.shelter_names[option[1]],edge.to]
		picker.add_item(text)
	column.add_child(picker)
	column.add_child(UIkit.strong("Cost: %d supply" % (2 if kind=="ISOLATE" else 1)))
	if kind=="ISOLATE":
		column.add_child(UIkit.paragraph("Stops zombie movement. Supply impact:"))
		var losses := session.action_manager.preview_isolation(target)
		for depot in losses:
			column.add_child(UIkit.paragraph("%s: %s" % [session.scenario.shelter_names[depot],"no route loss" if losses[depot].is_empty() else ", ".join(losses[depot])+" lose access"],UIkit.BODY,UIkit.WARNING))
		column.add_child(UIkit.paragraph("One unit to each endpoint. Road closes after both arrive.",UIkit.BODY,UIkit.SECONDARY))
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
	var buttons := _button_row(column)
	buttons.add_child(_sized(UIkit.button("Cancel",_close_modal)))
	buttons.add_child(_sized(UIkit.button("Confirm delivery",func():
		var assignments: Array[String] = []
		assignments.assign(options[picker.selected])
		_close_modal()
		var result := session.dispatch_action(kind,target,assignments)
		if not result.ok: _show_message("Unavailable",PresentationText.unavailable_text(str(result.error))),true)))

func _request_resolution() -> void:
	_show_modal("End round %d?" % session.state.round,"Unused supply carries forward. Active shields expire after resolution.","Resolve",func(): session.begin_resolution())

func _animate_phase(token: int) -> void:
	if session == null or token != session.run_token: return
	var current_board := board
	if session.phase == GameManager.Phase.DELIVERY:
		await current_board.play_deliveries(session.pending_action.deliveries)
		if session != null and token == session.run_token and session.pending_action.type == "ISOLATE":
			await current_board.play_closure(session.pending_action.target)
		if session != null and token == session.run_token: session.complete_delivery(token)
	elif session.phase == GameManager.Phase.RESOLUTION:
		if not session.resolution_applied:
			await current_board.play_outbreak(session.pending_resolution.movements)
			if session != null and token == session.run_token: session.apply_resolution(token)
		else:
			await current_board.play_reveal(session.last_summary.newly_overrun)
			if session != null and token == session.run_token: session.finish_resolution(token)

func _build_private(parent: Node) -> void:
	parent.add_theme_constant_override("separation",UIkit.LG)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",UIkit.XL)
	grid.add_theme_constant_override("v_separation",UIkit.LG)
	parent.add_child(grid)
	var locations: Array = session.state.shelters.keys()+session.state.edges.keys()
	var danger := _survey_picker(grid,"Most immediate danger",locations)
	var action := _survey_picker(grid,"Proposed action",PlayerBelief.ACTIONS)
	var target := _survey_picker(grid,"Action target",[])
	target.disabled = true
	var confidence := _survey_picker(grid,"Confidence · 1 low / 5 high",["1","2","3","4","5"])
	var reason := _survey_picker(grid,"Main reason · required",PlayerBelief.REASONS.slice(1))
	var submit := UIkit.button("Submit & pass screen",func():
		var belief := PlayerBelief.new(str(danger.get_selected_metadata()),str(action.get_selected_metadata()),str(target.get_selected_metadata()),int(confidence.get_selected_metadata()),"" if reason.selected==0 else str(reason.get_selected_metadata()))
		session.submit_belief(belief),true)
	submit.disabled = true
	submit.custom_minimum_size.x = 320
	submit.size_flags_horizontal = Control.SIZE_SHRINK_END
	parent.add_child(submit)
	var validate := func(_index: int): submit.disabled = danger.selected==0 or action.selected==0 or target.selected==0 or confidence.selected==0 or reason.selected==0
	action.item_selected.connect(func(_index: int):
		_fill_picker(target,session.survey_targets(str(action.get_selected_metadata())))
		target.disabled = str(action.get_selected_metadata())=="WAIT"
		if target.disabled: target.select(1)
		validate.call(0))
	for picker in [danger,target,confidence,reason]: picker.item_selected.connect(validate)

func _survey_picker(parent: Node, title: String, values: Array) -> OptionButton:
	var field := VBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation",UIkit.SM)
	parent.add_child(field)
	return _picker(field,title,values)

func _picker(parent: Node, title: String, values: Array) -> OptionButton:
	var question := UIkit.text_label(title,UIkit.MEDIUM_FONT,UIkit.BODY)
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(question)
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 48
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
	var headline := VBoxContainer.new()
	headline.add_theme_constant_override("separation",0)
	parent.add_child(headline)
	headline.add_child(UIkit.figure("%d / 8" % (8-session.state.overrun_ids().size()),UIkit.METRIC_LARGE))
	headline.add_child(UIkit.meta("Shelters functioning"))
	UIkit.rule(parent)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",UIkit.SM)
	parent.add_child(rows)
	for entry in [["Shelters lost",str(session.state.overrun_ids().size())],["Supplies spent","%d / 6" % (6-session.state.total_supply())],["Roads closed",str(session.closed_road_count())]]:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var key := UIkit.label(entry[0],UIkit.BODY,UIkit.SECONDARY)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		row.add_child(UIkit.strong(entry[1]))
	var lost := session.state.overrun_ids()
	parent.add_child(UIkit.paragraph("Lost locations: " + (", ".join(lost) if not lost.is_empty() else "None"),UIkit.BODY,UIkit.DANGER if not lost.is_empty() else UIkit.SECONDARY))
	if export_status != "" and session.is_sandbox(): parent.add_child(UIkit.meta(export_status))
	UIkit.rule(parent)
	_build_result_controls(parent)

func _build_result_controls(parent: Node) -> void:
	mission_session.capture_result()
	if session.is_sandbox():
		parent.add_child(UIkit.button("Replay",_request_restart,true))
		parent.add_child(UIkit.button("Choose another scenario",_show_level_picker))
	elif mission_session.index+1 < mission_session.order.size():
		parent.add_child(UIkit.button("Continue to next mission",_next_mission,true))
	else: parent.add_child(UIkit.strong("Session complete · %d of %d missions" % [mission_session.order.size(),mission_session.order.size()]))
	parent.add_child(UIkit.button("Export DEV JSON" if session.is_sandbox() else "Export session JSON",_export_session))
	parent.add_child(UIkit.button("Main menu",_show_main_menu))

func _show_help() -> void:
	var column := _modal_base("Field guide",820)
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(0,minf(540,size.y-250))
	column.add_child(wrapper)
	var guide := UIkit.rich(PresentationText.RULES+PresentationText.MAP_KEY)
	# Guide section titles are the only bold runs; render them as headings.
	guide.add_theme_font_override("bold_font",UIkit.HEADING_FONT)
	guide.add_theme_font_size_override("bold_font_size",24)
	UIkit.scroll_column(wrapper).add_child(guide)
	column.add_child(UIkit.button("Close",_close_modal,true))

func _show_inspector() -> void:
	if not session.dev_mode or _private_phase() or _busy(): return
	var column := _modal_base("Dev mode · inspector")
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(0,minf(450,size.y-270))
	column.add_child(wrapper)
	UIkit.scroll_column(wrapper).add_child(UIkit.paragraph(PresentationText.debug(session),UIkit.SMALL,UIkit.TEXT))
	var buttons := _button_row(column)
	buttons.add_child(_sized(UIkit.button("Export DEV JSON",_export_session)))
	buttons.add_child(_sized(UIkit.button("Close",_close_modal,true)))

func _request_dev_mode(enabled: bool) -> void:
	if not session.is_sandbox(): return
	if not enabled: session.set_dev_mode(false); return
	_show_modal("Enable Dev mode?","Reveals hidden state and private records. Flags this session as a development run.","Enable Dev mode",func(): session.set_dev_mode(true),func(): _render())

func _request_restart() -> void:
	_show_modal("Restart scenario?","Current progress will be cleared.","Restart scenario",func(): _start_dev(session.scenario.scenario_id))
func _export_session() -> void:
	var filename := ("cascade_recovery_" if session == null else "cascade_DEV_" if session.is_sandbox() else "cascade_session_")+Time.get_datetime_string_from_system().replace(":","-")+".json"
	var exported := mission_session.export_dictionary() if mission_session != null else {"record_mode":"synthetic-development","research_eligible":false}
	exported["upload_recovery"] = StudySync.recovery_export()
	var text := JSON.stringify(exported,"\t")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(),filename,"application/json")
		export_status = "Session JSON download requested."
		if session != null: _render()
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
			if session != null: _render()
			else: dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _modal_base(title: String, width: float = 640) -> VBoxContainer:
	_close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var shade := ColorRect.new()
	shade.color = Color(UIkit.TEXT,0.4)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(width,size.x-48),0)
	panel.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.LINE_STRONG,8,UIkit.XXL))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",UIkit.LG)
	panel.add_child(column)
	column.add_child(UIkit.heading(title))
	return column

func _button_row(parent: Node) -> HBoxContainer:
	UIkit.spacer(parent,UIkit.XS)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation",UIkit.MD)
	parent.add_child(buttons)
	return buttons

func _sized(button: Button) -> Button:
	button.custom_minimum_size.x = 160
	return button

func _show_modal(title: String, body: String, confirm_text: String, confirm: Callable, cancel: Callable = Callable()) -> void:
	var column := _modal_base(title)
	column.add_child(UIkit.paragraph(body))
	var buttons := _button_row(column)
	buttons.add_child(_sized(UIkit.button("Cancel",func(): _close_modal(); if cancel.is_valid(): cancel.call())))
	buttons.add_child(_sized(UIkit.caution(UIkit.button(confirm_text,func(): _close_modal(); confirm.call()))))

func _show_message(title: String, body: String) -> void:
	var column := _modal_base(title)
	column.add_child(UIkit.paragraph(body))
	var buttons := _button_row(column)
	buttons.add_child(_sized(UIkit.button("Close",_close_modal,true)))

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
	sheet.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.LINE,8,40))
	center.add_child(sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",UIkit.LG)
	sheet.add_child(column)
	column.add_child(UIkit.meta("Round %d · private input" % session.state.round))
	column.add_child(UIkit.heading("Player %d only" % (session.private_player+1),UIkit.DISPLAY+2))
	column.add_child(UIkit.paragraph("Pass the screen. Other players: look away."))
	UIkit.spacer(column,UIkit.SM)
	column.add_child(UIkit.button("Open my form",session.open_private_form,true))
	phase_label = null

func _build_operation(parent: Node) -> void:
	if session.phase == GameManager.Phase.DELIVERY:
		var action: GameAction = session.pending_action
		parent.add_child(UIkit.heading(action.type+" · "+action.target))
		var spent := action.deliveries.size()
		parent.add_child(UIkit.paragraph("Supplies: %d → %d · %d spent" % [session.state.total_supply()+spent,session.state.total_supply(),spent]))
		parent.add_child(UIkit.paragraph("Supply en route. The action takes effect on arrival."))
	else:
		parent.add_child(UIkit.heading("Updating the district"))
		if session.resolution_applied:
			var newly: Array = session.last_summary.newly_overrun
			parent.add_child(UIkit.paragraph("Newly Overrun: "+(", ".join(newly) if not newly.is_empty() else "None"),UIkit.BODY,UIkit.DANGER if not newly.is_empty() else UIkit.TEXT))

func _dev_access_enabled() -> bool:
	return not OS.has_feature("participant") and bool(ProjectSettings.get_setting("cascade/development_access",true))

func _dispose_run() -> void:
	practice = null
	StudySync.detach()
	if session != null:
		session.invalidate()
		if session.changed.is_connected(_render): session.changed.disconnect(_render)
	session = null
	mission_session = null
	map_token = 0
	selected_shelter = ""
	selected_edge = ""
	export_status = ""
	if is_instance_valid(board) and board.camera_tween: board.camera_tween.kill()
	if survey_tween: survey_tween.kill()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	board = null
	modal = null
	road_bubble = null
	support_card = null

func _menu_page() -> VBoxContainer:
	_dispose_run()
	var background := ColorRect.new()
	background.color = UIkit.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,UIkit.XXL)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 640
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation",UIkit.LG)
	center.add_child(column)
	return column

func _show_main_menu() -> void:
	var column := _menu_page()
	column.add_child(_menu_ornament())
	column.add_child(UIkit.heading("Cascade Lab: Outbreak",UIkit.DISPLAY+6))
	var premise := UIkit.paragraph(FirstPlayText.premise())
	premise.custom_minimum_size.x = 640
	column.add_child(premise)
	var language := UIkit.quiet("Introduction & practice: English / 简体中文",func(): FirstPlayText.chinese = not FirstPlayText.chinese; _show_main_menu())
	column.add_child(language)
	UIkit.spacer(column,UIkit.SM)
	var play := UIkit.button("Play",_begin_play,true)
	var replay: Button
	if _practice_enabled() and practice_completed_version != "":
		replay = UIkit.button(FirstPlayText.choose("Replay practice","重玩练习"),_start_practice)
	play.custom_minimum_size.y = 56
	if StudySync.access_required():
		# Online builds: the facilitator enters the study access code before play.
		var code := LineEdit.new()
		code.name = "AccessCode"
		code.placeholder_text = "Study access code"
		code.secret = true
		code.text = StudySync.access_code
		code.custom_minimum_size.y = 52
		code.text_changed.connect(func(value: String):
			StudySync.set_access_code(value)
			play.disabled = StudySync.access_code.length() < 12
			if replay != null: replay.disabled = play.disabled)
		play.disabled = StudySync.access_code.length() < 12
		column.add_child(code)
	column.add_child(play)
	if replay != null:
		replay.disabled = play.disabled
		column.add_child(replay)
	if _practice_enabled(): column.add_child(UIkit.meta(FirstPlayText.choose("Start with a short, unscored practice. Replay it before the measured missions.","先进行简短、不计分的练习。正式任务开始前可以重玩。")))
	if _dev_access_enabled(): column.add_child(UIkit.button("Dev Mode",_show_level_picker))
	column.add_child(_motion_toggle())
	save_indicator = UIkit.meta("")
	if not StudySync.sessions.is_empty(): save_indicator.set_meta("show_routine",true)
	save_text = ""
	column.add_child(save_indicator)
	_refresh_save_notice()
	if not StudySync.sessions.is_empty(): column.add_child(UIkit.button("Export pending recovery JSON",_export_session))
	_focus_if_present.call_deferred(play)

# Accessibility preference only: same timing and information in every condition.
func _motion_toggle() -> Button:
	var toggle := UIkit.quiet("",func(): pass)
	toggle.name = "ReduceMotion"
	toggle.toggle_mode = true
	toggle.button_pressed = UIkit.reduced_motion()
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toggle.expand_icon = false
	var refresh := func():
		toggle.text = FirstPlayText.choose("Reduce motion","减少动画")+(FirstPlayText.choose(" · on"," · 开") if toggle.button_pressed else FirstPlayText.choose(" · off"," · 关"))
		toggle.icon = UIkit.switch_icon(toggle.button_pressed)
	refresh.call()
	toggle.toggled.connect(func(enabled: bool):
		UIkit.set_reduced_motion(enabled)
		refresh.call())
	return toggle

# Decorative only: a few blank pieces on a road, echoing the board. No map data.
func _menu_ornament() -> Control:
	var art := Control.new()
	art.name = "MenuOrnament"
	art.custom_minimum_size = Vector2(640,76)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(func():
		var road := PackedVector2Array([Vector2(8,50),Vector2(150,30),Vector2(320,52),Vector2(490,28),Vector2(632,46)])
		art.draw_polyline(road,UIkit.ROAD_CASING,14,true)
		art.draw_polyline(road,UIkit.ROAD,8,true)
		for index in [1,2,3]:
			var c: Vector2 = road[index]
			var h := 20.0
			var shape := PackedVector2Array([c+Vector2(-h*0.86,-h*0.28),c+Vector2(0,-h),c+Vector2(h*0.86,-h*0.28),c+Vector2(h*0.86,h*0.86),c+Vector2(-h*0.86,h*0.86)])
			if index == 2: shape = PackedVector2Array([c+Vector2(-h*0.9,-h*0.86),c+Vector2(h*0.9,-h*0.86),c+Vector2(h*0.9,h*0.86),c+Vector2(-h*0.9,h*0.86)])
			var base := shape.duplicate()
			for i in base.size(): base[i] += Vector2(0,3)
			art.draw_colored_polygon(base,UIkit.EDGE)
			art.draw_colored_polygon(shape,UIkit.PANEL)
			shape.append(shape[0])
			art.draw_polyline(shape,UIkit.TEXT,2.0,true))
	return art

func _show_level_picker() -> void:
	if not _dev_access_enabled(): return
	var column := _menu_page()
	column.add_child(UIkit.meta("Dev mode — not research data",UIkit.WARNING))
	column.add_child(UIkit.heading("Choose a district",UIkit.DISPLAY))
	column.add_child(UIkit.paragraph("Play one mission with the same rules and supplies. Surveys, discussion timers, and decision support are skipped."))
	var first_start: Button
	for entry in ScenarioData.registry().scenarios:
		var card := UIkit.card(column,UIkit.PANEL)
		card.add_theme_constant_override("separation",UIkit.SM)
		card.add_child(UIkit.heading(entry.title,24))
		card.add_child(UIkit.paragraph(entry.blurb,UIkit.BODY,UIkit.SECONDARY))
		var start := UIkit.button("Start · " + entry.title,func(): _start_dev(entry.id))
		start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		start.custom_minimum_size.x = 240
		card.add_child(start)
		if first_start == null: first_start = start
	var back := UIkit.button("Back",_show_main_menu)
	column.add_child(back)
	_focus_if_present.call_deferred(first_start)

func _practice_enabled() -> bool:
	# Proposed protocol addition: existing participant builds retain the prior entry
	# until a supervisor explicitly approves and configures this practice version.
	return _dev_access_enabled() or bool(ProjectSettings.get_setting("cascade/practice_approved",false))

func _begin_play() -> void:
	if StudySync.access_required() and StudySync.access_code.length() < 12: return
	if _practice_enabled(): _start_practice()
	else: _start_normal()

func _start_practice() -> void:
	if not _practice_enabled(): return
	if StudySync.access_required() and StudySync.access_code.length() < 12: return
	_dispose_run()
	practice = PracticeView.new()
	add_child(practice)
	practice.exited.connect(_show_main_menu)
	practice.finished.connect(func(version: String):
		practice_completed_version = version
		_start_normal())

func _start_normal() -> void:
	if StudySync.access_required() and StudySync.access_code.length() < 12: return
	_dispose_run()
	var configured: Array = ProjectSettings.get_setting("cascade/scenario_order",[])
	mission_session = MissionSession.new(GameManager.RunPurpose.NORMAL,GameManager.InterventionType.NONE,configured)
	_connect_mission()

func _start_dev(id: String) -> void:
	if not _dev_access_enabled(): return
	_dispose_run()
	mission_session = MissionSession.new(GameManager.RunPurpose.DEV_SANDBOX,GameManager.InterventionType.NONE,[id])
	_connect_mission()

func _connect_mission() -> void:
	if mission_session.current == null:
		var message := mission_session.error
		_show_main_menu()
		_show_message("Could not start mission",message)
		return
	session = mission_session.current
	StudySync.attach(mission_session)
	session.changed.connect(_render)
	_render()

func _next_mission() -> void:
	if session.phase != GameManager.Phase.RESULTS: return
	if session.changed.is_connected(_render): session.changed.disconnect(_render)
	if mission_session.advance(): _connect_mission()

func _request_leave(destination: Callable) -> void:
	if session == null or session.phase == GameManager.Phase.RESULTS:
		destination.call()
		return
	_show_modal("Leave this mission?","This unfinished mission will be discarded. Export any records you need before leaving.","Leave mission",destination)

func _focus_if_present(button: Button) -> void:
	if is_instance_valid(button) and button.is_inside_tree(): button.grab_focus()
