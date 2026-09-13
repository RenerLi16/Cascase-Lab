extends Control

var session: GameManager
var page: VBoxContainer
var content: HBoxContainer
var sidebar: VBoxContainer
var footer: HBoxContainer
var board: NetworkView
var modal: Control
var active_tab := 0
var selected_shelter := "E"
var selected_edge := ""
var export_status := ""

func _ready() -> void:
	theme = UIkit.make_theme()
	session = GameManager.new()
	session.changed.connect(_render)
	_render()

func _render() -> void:
	# Remove old forms immediately, including their selected answers and keyboard focus.
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
	for side in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_"+side, 22)
	add_child(margin)
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)
	_build_header()
	content = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 20)
	page.add_child(content)
	footer = HBoxContainer.new()
	footer.custom_minimum_size.y = 48
	page.add_child(footer)
	match session.phase:
		GameManager.Phase.PRIVATE_GATE: _build_private_gate()
		GameManager.Phase.PRIVATE_FORM: _build_private_form()
		GameManager.Phase.RESULTS: _build_results()
		_:
			_build_map()
			sidebar = VBoxContainer.new()
			sidebar.custom_minimum_size.x = 430
			sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sidebar.size_flags_stretch_ratio = 1.0
			content.add_child(sidebar)
			_build_shared_phase()
	var private_screen := session.phase in [GameManager.Phase.PRIVATE_GATE,GameManager.Phase.PRIVATE_FORM]
	if not private_screen and session.phase != GameManager.Phase.RESULTS:
		var footnote := UIkit.label("3 PARTICIPANTS   /   ONE DEVICE   /   DETERMINISTIC SCENARIO", 11, UIkit.MUTED)
		footnote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(footnote)
		footer.move_child(footnote,0)

func _build_header() -> void:
	var row := HBoxContainer.new()
	page.add_child(row)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 1)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(brand)
	brand.add_child(UIkit.label("CASCADE LAB", 26, UIkit.TEXT))
	brand.add_child(UIkit.label("O U T B R E A K   /   COOPERATIVE CONTAINMENT", 11, UIkit.TEAL))
	var private_screen := session.phase in [GameManager.Phase.PRIVATE_GATE,GameManager.Phase.PRIVATE_FORM]
	if private_screen:
		row.add_child(UIkit.label("PRIVATE JUDGMENT  ·  %d / 3" % (session.private_player+1),15,UIkit.AMBER))
	else:
		row.add_child(UIkit.label("SCENARIO 01  /  " + session.scenario.scenario_title.to_upper(),12,UIkit.MUTED))
		var dev := CheckButton.new()
		dev.text = "DEV MODE"
		dev.button_pressed = session.dev_mode
		dev.tooltip_text = "Reveals hidden pressure and the source. This session will be marked as a development run."
		dev.toggled.connect(_request_dev_mode)
		row.add_child(dev)
	if session.phase != GameManager.Phase.MENU:
		row.add_child(UIkit.button("Restart", _request_restart))

func _request_dev_mode(enabled: bool) -> void:
	if not enabled:
		session.set_dev_mode(false)
		return
	_show_modal("Reveal hidden ground truth?", "DEV MODE exposes every pressure value and the original source. This permanently flags the session as a development run, even if you turn it off later.", "Enable DEV MODE", func(): session.set_dev_mode(true), func(): _render())

func _request_restart() -> void:
	_show_modal("Restart this mission?", "This clears the current mission, private judgments and session log. Export a completed session before restarting if you want to keep it.", "Restart mission", func():
		active_tab = 0
		selected_shelter = "E"
		selected_edge = ""
		export_status = ""
		session.reset())

func _phase_title() -> String:
	match session.phase:
		GameManager.Phase.MENU: return "Eight shelters. One team."
		GameManager.Phase.BRIEFING: return "Read the same evidence."
		GameManager.Phase.BELIEFS: return "Notice where you disagree."
		GameManager.Phase.DISCUSSION: return "Build your shared plan."
		GameManager.Phase.ACTIONS: return "Every supply unit counts."
		GameManager.Phase.SUMMARY: return "The outbreak has moved."
		GameManager.Phase.DIAGNOSTIC: return "A new piece of the story."
	return "Contain the cascade."

func _build_map() -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.65
	content.add_child(left)
	var eyebrow := "FIELD OPERATIONS  /  MISSION BRIEF"
	if session.phase not in [GameManager.Phase.MENU,GameManager.Phase.BRIEFING]:
		eyebrow = "FIELD OPERATIONS  /  ROUND %02d OF 03" % session.state.round
	left.add_child(UIkit.label(eyebrow,12,UIkit.ACCENT))
	left.add_child(UIkit.label(_phase_title(),30,UIkit.TEXT))
	if session.dev_mode:
		left.add_child(UIkit.label("DEV MODE — HIDDEN PRESSURE & SOURCE REVEALED",14,UIkit.AMBER))
	_build_supply_bar(left)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	var top := HBoxContainer.new()
	stack.add_child(top)
	var map_title := UIkit.label("SHELTER NETWORK",12,UIkit.MUTED)
	map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(map_title)
	top.add_child(UIkit.label("● %d SURVIVING   /   %d OVERRUN" % [8-session.state.overrun_ids().size(),session.state.overrun_ids().size()],12,UIkit.RED if session.state.overrun_ids().size()>1 else UIkit.ACCENT))
	board = NetworkView.new()
	stack.add_child(board)
	board.configure(session.scenario,session.state,session.dev_mode)
	board.selected_shelter = selected_shelter
	board.selected_edge = selected_edge
	board.shelter_selected.connect(_select_shelter)
	board.edge_selected.connect(_select_edge)
	stack.add_child(UIkit.paragraph("→  Zombies follow arrows     ↔  Supply travels both ways\nGreen ring: stocked supply route   ·   M monitor   V verified   S shield\nRed X: closed road   ·   Pressure 0 and 1 remain hidden",12,UIkit.MUTED))
	left.add_child(UIkit.paragraph("Click a shelter or road to inspect it. A quiet shelter is not necessarily safe.",13,UIkit.MUTED))

func _build_supply_bar(parent: Node) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	for id in session.state.depots:
		var card := UIkit.card(row,UIkit.INNER)
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(UIkit.label("DEPOT "+id,11,UIkit.MUTED))
		var depot: SupplyDepot = session.state.depots[id]
		card.add_child(UIkit.label("%d / %d supply" % [depot.supply_remaining,depot.capacity],20,UIkit.ACCENT))
	var total := UIkit.card(row)
	total.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total.add_child(UIkit.label("TOTAL REMAINING",11,UIkit.MUTED))
	total.add_child(UIkit.label("%d / 6" % session.state.total_supply(),20))

func _tabs(parent: Node, names: Array[String]) -> Array[VBoxContainer]:
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(tabs)
	var columns: Array[VBoxContainer] = []
	for title in names:
		var wrapper := VBoxContainer.new()
		wrapper.name = title
		tabs.add_child(wrapper)
		columns.append(UIkit.scroll_column(wrapper))
	tabs.current_tab = mini(active_tab,names.size()-1)
	tabs.tab_changed.connect(func(index: int): active_tab = index)
	return columns

func _build_shared_phase() -> void:
	match session.phase:
		GameManager.Phase.MENU:
			var welcome := UIkit.card(sidebar)
			welcome.add_child(UIkit.label("A STRATEGY & RESEARCH GAME",12,UIkit.TEAL))
			welcome.add_child(UIkit.label("Contain the outbreak.\nQuestion your theory.",29))
			welcome.add_child(UIkit.paragraph("Three people share the same evidence. You may see three different stories. Discuss, investigate and contain a fictional zombie outbreak before it cascades through the network.",17))
			welcome.add_child(UIkit.label("8 shelters  ·  6 supplies  ·  3 rounds",18,UIkit.ACCENT))
			welcome.add_child(UIkit.paragraph("Play together on one computer. Pass the screen only for private judgments. Allow about 15–25 minutes. There is no timer.",15))
			welcome.add_child(UIkit.button("Begin briefing  →", func(): active_tab = 0; session.start_briefing(),true))
			var note := UIkit.card(sidebar)
			note.add_child(UIkit.paragraph("ACTIVE SCENARIO / " + session.scenario.scenario_title.to_upper(),12,UIkit.TEAL))
			note.add_child(UIkit.paragraph("An emergency arrives late. One camera points toward B. Another story may be hiding in the timestamps.",16))
			note.add_child(UIkit.paragraph("The map shows all roads and the publicly Overrun shelter. Green rings indicate access to a stocked depot, not safety.",14))
		GameManager.Phase.BRIEFING:
			sidebar.add_child(UIkit.label("SHARED BRIEFING",20,UIkit.ACCENT))
			var columns := _tabs(sidebar,["Reports","Rules"])
			columns[0].add_child(UIkit.rich(PresentationText.evidence(session.scenario)))
			columns[0].add_child(UIkit.paragraph("Read the Rules tab together before continuing. Then each player records a private interpretation of this same evidence.",15,UIkit.AMBER))
			columns[1].add_child(UIkit.rich(PresentationText.RULES))
			footer.add_child(UIkit.button("Start private judgments  →",func(): active_tab = 0; session.start_private(),true))
		GameManager.Phase.BELIEFS:
			sidebar.add_child(UIkit.label("BELIEF CHANGES" if session.collecting_update else "INITIAL TEAM BELIEFS",20,UIkit.ACCENT))
			var column := UIkit.scroll_column(sidebar)
			column.add_child(UIkit.paragraph("Anonymous labels stay consistent across both judgments. Compare interpretations, then discuss the next decision.",15))
			column.add_child(UIkit.rich(PresentationText.beliefs(session,session.collecting_update)))
			footer.add_child(UIkit.button("Begin team discussion  →",func(): active_tab = 0; session.begin_discussion(),true))
		GameManager.Phase.DISCUSSION,GameManager.Phase.ACTIONS:
			_build_operations()
		GameManager.Phase.SUMMARY:
			_build_summary()
		GameManager.Phase.DIAGNOSTIC:
			sidebar.add_child(UIkit.label("NEW EVIDENCE / AFTER ROUND 1",19,UIkit.AMBER))
			var column := UIkit.scroll_column(sidebar)
			var card := UIkit.card(column,UIkit.INNER)
			card.add_child(UIkit.paragraph(session.scenario.diagnostic_evidence.title,26,UIkit.TEXT))
			card.add_child(UIkit.paragraph(session.scenario.diagnostic_evidence.text,19,UIkit.TEXT))
			column.add_child(UIkit.paragraph("Does this change your account of where the outbreak began? Each player now records a private update before the team compares beliefs.",17,UIkit.AMBER))
			column.add_child(UIkit.rich(PresentationText.evidence(session.scenario)))
			footer.add_child(UIkit.button("Record private belief updates  →",func(): session.start_private(true),true))

func _build_operations() -> void:
	var actions_phase := session.phase == GameManager.Phase.ACTIONS
	sidebar.add_child(UIkit.label("SELECT & CONFIRM ACTIONS" if actions_phase else "TEAM DISCUSSION",20,UIkit.ACCENT))
	var names: Array[String] = ["Plan","Reports","Log","Beliefs","Rules"]
	if session.dev_mode: names.append("Dev")
	var columns := _tabs(sidebar,names)
	if not actions_phase:
		columns[0].add_child(UIkit.paragraph("Discuss aloud: what do the reports establish, which arrows threaten the next shelters, and which depot should pay? Nothing happens until your team confirms an action or resolves spread.",17,UIkit.TEXT))
	if actions_phase:
		if not session.notices.is_empty():
			var notice := UIkit.card(columns[0],UIkit.INNER)
			notice.add_child(UIkit.label("CONFIRMED / ACTION RESULTS",12,UIkit.TEAL))
			notice.add_child(UIkit.paragraph("\n\n".join(session.notices),16,UIkit.TEXT))
	_build_selection(columns[0],actions_phase)
	if actions_phase: _build_draft(columns[0])
	columns[1].add_child(UIkit.rich(PresentationText.evidence(session.scenario,not session.updated_beliefs.is_empty())))
	columns[2].add_child(UIkit.label("INVESTIGATION LOG",16,UIkit.TEAL))
	columns[2].add_child(UIkit.rich(PresentationText.investigation(session.state)))
	columns[2].add_child(UIkit.label("CONFIRMED ACTIONS",16,UIkit.TEAL))
	columns[2].add_child(UIkit.rich(PresentationText.action_history(session.state)))
	columns[3].add_child(UIkit.rich(PresentationText.beliefs(session,not session.updated_beliefs.is_empty())))
	columns[4].add_child(UIkit.rich(PresentationText.RULES))
	if session.dev_mode: columns[5].add_child(UIkit.rich(PresentationText.debug(session)))
	if actions_phase:
		footer.add_child(UIkit.button("Return to discussion",session.return_to_discussion))
		var resolve := UIkit.button("Resolve Round %d spread  →" % session.state.round,_request_spread,true)
		resolve.disabled = not session.draft.is_empty()
		resolve.tooltip_text = "Confirm or clear the queued plan before resolving spread." if resolve.disabled else "Ends this round; all current Overrun shelters transmit simultaneously."
		footer.add_child(resolve)
	else:
		footer.add_child(UIkit.button("Proceed to Actions  →",session.proceed_to_actions,true))

func _select_shelter(id: String) -> void:
	selected_shelter = id
	selected_edge = ""
	if session.phase in [GameManager.Phase.ACTIONS,GameManager.Phase.DISCUSSION]:
		active_tab = 0
		_render()
	elif board != null:
		board.selected_shelter = id
		board.selected_edge = ""
		board.queue_redraw()

func _select_edge(id: String) -> void:
	selected_edge = id
	selected_shelter = ""
	if session.phase in [GameManager.Phase.ACTIONS,GameManager.Phase.DISCUSSION]:
		active_tab = 0
		_render()
	elif board != null:
		board.selected_edge = id
		board.selected_shelter = ""
		board.queue_redraw()

func _build_selection(parent: Node, actions_phase: bool) -> void:
	var projected := session.projected_state()
	var manager := ActionManager.new(projected,EventLogger.new())
	var card := UIkit.card(parent)
	if selected_edge != "":
		var edge: EdgeState = session.state.edges[selected_edge]
		card.add_child(UIkit.label("ROAD %s → %s" % [edge.from,edge.to],24))
		card.add_child(UIkit.paragraph("Permanently closed" if edge.isolated else "Active road · zombies move %s → %s; supply moves both ways." % [edge.from,edge.to],15,UIkit.RED if edge.isolated else UIkit.MUTED))
		card.add_child(UIkit.paragraph("Isolation crews must reach at least one non-Overrun endpoint. Both units must come from the same depot.",14))
		if actions_phase: _action_choice(card,manager,"ISOLATE",selected_edge,"Close this road permanently.")
	else:
		if selected_shelter == "": selected_shelter = "E"
		var shelter: ShelterState = session.state.shelters[selected_shelter]
		card.add_child(UIkit.label("SHELTER " + selected_shelter,24))
		card.add_child(UIkit.label(shelter.display_name,15,UIkit.MUTED))
		var status := "Unknown · pressure 0 or 1"
		if shelter.is_overrun: status = "OVERRUN · pressure 2 · permanent"
		elif shelter.monitor_known_pressure >= 0: status = "Monitor's latest reading: pressure %d" % shelter.monitor_known_pressure
		if session.dev_mode: status += "\nDEV actual pressure: %d" % shelter.zombie_pressure
		card.add_child(UIkit.paragraph("Known status: " + status,16,UIkit.RED if shelter.is_overrun else UIkit.TEXT))
		var reachable: Array[String] = []
		for depot in session.state.depots:
			if NetworkManager.new(session.state).can_supply_reach(depot,selected_shelter): reachable.append("Depot "+depot)
		card.add_child(UIkit.paragraph("Supply routes: " + (", ".join(reachable) if not reachable.is_empty() else "None"),14,UIkit.TEAL))
		if shelter.shielded_this_round: card.add_child(UIkit.label("SHIELDED · expires after this spread",14,UIkit.TEAL))
		if shelter.is_monitored: card.add_child(UIkit.label("MONITOR ACTIVE · reports future changes",14,UIkit.TEAL))
		if not shelter.verified_history.is_empty():
			var record: Dictionary = shelter.verified_history.back()
			card.add_child(UIkit.paragraph("Historical verification: Round %d, Pressure %d. This snapshot does not update." % [record.round,record.pressure],14,UIkit.AMBER))
		if actions_phase:
			_action_choice(card,manager,"VERIFY",selected_shelter,"Reveal current pressure once.")
			_action_choice(card,manager,"MONITOR",selected_shelter,"Report future pressure changes.")
			_action_choice(card,manager,"SHIELD",selected_shelter,"Block all incoming pressure this round.")

func _action_choice(parent: Node, manager: ActionManager, kind: String, target: String, description: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	parent.add_child(row)
	var reason := manager.unavailable_reason(kind,target)
	var button := UIkit.button("%s  ·  %d supply" % [kind,2 if kind=="ISOLATE" else 1],func(): _request_action(kind,target))
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason if button.disabled else description
	row.add_child(button)
	row.add_child(UIkit.paragraph((kind+" unavailable: "+reason) if button.disabled else description,13,UIkit.AMBER if button.disabled else UIkit.MUTED))

func _request_action(kind: String, target: String) -> void:
	var projected := session.projected_state()
	var manager := ActionManager.new(projected,EventLogger.new())
	var cost := 2 if kind == "ISOLATE" else 1
	var eligible := manager.supply.eligible_depots(target,cost,kind=="ISOLATE")
	if eligible.is_empty(): return
	var column := _modal_base("%s %s" % [kind,target])
	column.add_child(UIkit.paragraph("Choose the depot that pays. This queues the action; you will review the whole plan before supplies are spent.",16))
	var depot_picker := OptionButton.new()
	depot_picker.custom_minimum_size.y = 46
	for depot in eligible:
		depot_picker.add_item("Depot %s · %d supply available" % [depot,projected.depots[depot].supply_remaining])
	column.add_child(depot_picker)
	var cost_label := UIkit.label("",18,UIkit.ACCENT)
	column.add_child(cost_label)
	var path_label := UIkit.paragraph("",14,UIkit.TEAL)
	column.add_child(path_label)
	var show_cost := func():
		var depot: String = eligible[depot_picker.selected]
		cost_label.text = "Cost: %d supply from Depot %s" % [cost,depot]
		var destination := target
		if kind == "ISOLATE":
			var edge: EdgeState = projected.edges[target]
			destination = edge.from if manager.supply.network.can_supply_reach(depot,edge.from) else edge.to
		var path := manager.supply.network.get_supply_path(depot,destination)
		path_label.text = "Active supply path: " + " ↔ ".join(path)
		if board != null:
			board.supply_path = path
			board.queue_redraw()
	depot_picker.item_selected.connect(func(_index: int): show_cost.call())
	show_cost.call()
	if kind == "ISOLATE":
		column.add_child(UIkit.paragraph(_isolation_warning(projected,target),16,UIkit.AMBER))
		if board != null:
			board.preview_edge = target
			for losses: Array in manager.preview_isolation(target).values():
				for id in losses:
					if not board.preview_lost.has(id): board.preview_lost.append(id)
			board.queue_redraw()
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(UIkit.button("Cancel",_close_modal))
	buttons.add_child(UIkit.button("Review isolation warning  →" if kind=="ISOLATE" else "Add to plan",func():
		var depot: String = eligible[depot_picker.selected]
		if kind == "ISOLATE":
			_show_modal("Confirm permanent road closure",_isolation_warning(projected,target)+"\n\nCost: 2 supply from Depot "+depot+". This cannot be reopened during the mission.","I understand · add isolation",func(): _queue_action(kind,target,depot))
		else: _queue_action(kind,target,depot),true))

func _isolation_warning(state: GameState, edge_id: String) -> String:
	var losses := NetworkManager.new(state).preview_isolation(edge_id)
	var message := "WARNING · ISOLATION BLOCKS ZOMBIES AND SUPPLIES\n"
	for depot in losses:
		message += "\nFrom Depot %s: %s" % [depot,"no shelters lose a route." if losses[depot].is_empty() else "disconnects " + ", ".join(losses[depot]) + "."]
	return message

func _queue_action(kind: String, target: String, depot: String) -> void:
	_close_modal()
	var result := session.queue_action(kind,target,depot)
	if not result.ok: _show_message("Action unavailable",result.error)

func _build_draft(parent: Node) -> void:
	var card := UIkit.card(parent,UIkit.INNER)
	card.add_child(UIkit.label("QUEUED PLAN · NOT YET SPENT",13,UIkit.TEAL))
	if session.draft.is_empty():
		card.add_child(UIkit.paragraph("No queued actions. You can spend any amount this round, including none.",14))
		return
	card.add_child(UIkit.rich(_plan_text()))
	var row := HBoxContainer.new()
	card.add_child(row)
	row.add_child(UIkit.button("Clear plan",session.clear_draft))
	row.add_child(UIkit.button("Review & confirm",_review_plan,true))

func _plan_text() -> String:
	var output := ""
	var total := 0
	for action in ActionManager.ordered_plan(session.draft):
		output += "[b]%s %s[/b] · %d from Depot %s\n" % [action.type,action.target,action.cost,action.depot_used]
		total += action.cost
	var projected := session.projected_state()
	output += "\n[b]Cost: %d supply[/b]\nAfter confirmation: " % total
	var balances: Array[String] = []
	for id in projected.depots: balances.append("Depot %s: %d/3" % [id,projected.depots[id].supply_remaining])
	output += " · ".join(balances)
	return output

func _review_plan() -> void:
	var column := _modal_base("Confirm this action plan?")
	column.add_child(UIkit.rich(_plan_text()))
	column.add_child(UIkit.paragraph("Information actions apply first, then shields and isolation in queue order. Confirmed actions spend supply immediately. You can inspect the results and choose more actions before ending the round.",15))
	var preview := session.state.copy()
	var preview_manager := ActionManager.new(preview,EventLogger.new())
	for action in ActionManager.ordered_plan(session.draft):
		if action.type == "ISOLATE": column.add_child(UIkit.paragraph(_isolation_warning(preview,action.target),14,UIkit.AMBER))
		preview_manager.execute(action)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(UIkit.button("Keep planning",_close_modal))
	buttons.add_child(UIkit.button("Confirm & spend supply",func():
		_close_modal()
		var result := session.confirm_actions()
		if not result.ok: _show_message("Plan could not be applied",result.error),true))

func _request_spread() -> void:
	_show_modal("Resolve Round %d?" % session.state.round,"Every currently Overrun shelter will send pressure along its active outgoing arrows. Shields block incoming pressure, then expire. You cannot take more actions in this round after resolving it.","Resolve spread",func(): session.resolve_round())

func _build_summary() -> void:
	sidebar.add_child(UIkit.label("ROUND %d / FIELD REPORT" % session.state.round,20,UIkit.ACCENT))
	var column := UIkit.scroll_column(sidebar)
	var summary := session.last_summary
	var newly: Array = summary.newly_overrun
	var card := UIkit.card(column)
	card.add_child(UIkit.label("%d / 8 shelters surviving" % summary.survivors,26))
	card.add_child(UIkit.paragraph("Newly Overrun: " + (", ".join(newly) if not newly.is_empty() else "None"),19,UIkit.RED if not newly.is_empty() else UIkit.ACCENT))
	card.add_child(UIkit.paragraph("Shields expired: " + (", ".join(summary.shielded) if not summary.shielded.is_empty() else "None"),15))
	card.add_child(UIkit.paragraph("%d supply remains for the mission. No supplies regenerate." % summary.supply_remaining,15))
	column.add_child(UIkit.label("MONITOR ALERTS",14,UIkit.TEAL))
	column.add_child(UIkit.paragraph("\n\n".join(summary.monitor_alerts) if not summary.monitor_alerts.is_empty() else "No monitor reported a pressure change.",16,UIkit.TEXT))
	column.add_child(UIkit.paragraph("Quiet, unmonitored shelters may have changed without a public alert. Newly Overrun shelters begin transmitting next round.",15,UIkit.AMBER))
	column.add_child(UIkit.rich(PresentationText.action_history(session.state)))
	if session.dev_mode: column.add_child(UIkit.rich(PresentationText.debug(session)))
	var text := "View mission results  →" if session.state.round==3 else ("Examine new evidence  →" if session.state.round==1 else "Discuss Round 3  →")
	footer.add_child(UIkit.button(text,func(): active_tab = 0; session.continue_after_summary(),true))

func _build_private_gate() -> void:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var card := UIkit.card(center)
	card.get_parent().custom_minimum_size.x = 630
	card.add_child(UIkit.label("PASS THE SCREEN",13,UIkit.TEAL))
	card.add_child(UIkit.label("PLAYER %d ONLY" % (session.private_player+1),44))
	card.add_child(UIkit.paragraph("Other players: please look away.",24,UIkit.AMBER))
	card.add_child(UIkit.paragraph("Your answers stay hidden until all three players submit. The next screen contains only your form and the team's shared factual evidence.",17))
	card.add_child(UIkit.label("POST-EVIDENCE UPDATE" if session.collecting_update else "INITIAL JUDGMENT",14,UIkit.TEAL))
	card.add_child(UIkit.button("I am Player %d · open my form" % (session.private_player+1),session.open_private_form,true))
	footer.add_child(UIkit.label("PRIVACY HANDOFF  /  PREVIOUS ANSWERS CLEARED FROM THE SCREEN",12,UIkit.MUTED))

func _build_private_form() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 420
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(left)
	var form := UIkit.scroll_column(left)
	form.add_child(UIkit.label("PLAYER %d / PRIVATE" % (session.private_player+1),28,UIkit.AMBER))
	form.add_child(UIkit.paragraph("Use your own interpretation. No answer is selected for you.",16))
	var source := _belief_picker(form,"1  ·  Suspected outbreak source",session.state.shelters.keys())
	var candidates: Array = []
	for id in session.state.shelters:
		if not session.state.shelters[id].is_overrun: candidates.append(id)
	candidates.append("None")
	var predicted := _belief_picker(form,"2  ·  Most likely to become Overrun next",candidates)
	var preference: OptionButton
	if not session.collecting_update:
		preference = _belief_picker(form,"3  ·  Your preferred action",GameAction.TYPES)
	var confidence := _belief_picker(form,"%d  ·  Confidence (1 = low, 5 = high)" % (3 if session.collecting_update else 4),["1","2","3","4","5"])
	var submit := UIkit.button("Submit privately & clear screen  →",func():
		var belief := PlayerBelief.new(source.get_item_text(source.selected),predicted.get_item_text(predicted.selected),"" if session.collecting_update else preference.get_item_text(preference.selected),int(confidence.get_item_text(confidence.selected)))
		session.submit_belief(belief),true)
	submit.disabled = true
	form.add_child(submit)
	var validate := func(_index: int):
		submit.disabled = source.selected==0 or predicted.selected==0 or confidence.selected==0 or (not session.collecting_update and preference.selected==0)
	for picker in [source,predicted,confidence]: picker.item_selected.connect(validate)
	if preference != null: preference.item_selected.connect(validate)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.5
	content.add_child(right)
	right.add_child(UIkit.label("SAME SHARED FACTS / NO PRIVATE EVIDENCE",14,UIkit.TEAL))
	var columns := _tabs(right,["Reports","Rules","Network"])
	columns[0].add_child(UIkit.rich(PresentationText.evidence(session.scenario,session.collecting_update)))
	columns[1].add_child(UIkit.rich(PresentationText.RULES))
	var private_map := NetworkView.new()
	private_map.custom_minimum_size.y = 360
	columns[2].add_child(private_map)
	private_map.configure(session.scenario,session.state,false)
	columns[2].add_child(UIkit.paragraph("Arrows show zombie direction. Supply may travel both ways. Red means Overrun. Green rings indicate a route to a stocked depot.",14))
	_build_supply_bar(columns[2])
	if session.collecting_update:
		columns[0].add_child(UIkit.rich("[b]SHARED INVESTIGATION LOG[/b]\n\n"+PresentationText.investigation(session.state)))
	footer.add_child(UIkit.label("Only this player's form is visible. Shared discussion resumes after all three submissions.",13,UIkit.MUTED))

func _belief_picker(parent: Node, title: String, values: Array) -> OptionButton:
	parent.add_child(UIkit.paragraph(title,17,UIkit.TEXT))
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 48
	picker.add_item("Choose an answer…")
	picker.set_item_disabled(0,true)
	for value in values: picker.add_item(str(value))
	# Godot auto-selects the first enabled item as items are added; restore the prompt.
	picker.select(0)
	parent.add_child(picker)
	return picker

func _build_results() -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	content.add_child(left)
	left.add_child(UIkit.label("MISSION COMPLETE",14,UIkit.ACCENT))
	left.add_child(UIkit.label("%d / 8 shelters survived" % (8-session.state.overrun_ids().size()),36))
	left.add_child(UIkit.paragraph("Overrun: " + ", ".join(session.state.overrun_ids()),18,UIkit.RED))
	_build_supply_bar(left)
	board = NetworkView.new()
	left.add_child(board)
	board.configure(session.scenario,session.state,false)
	board.reveal_truth = true
	left.add_child(UIkit.paragraph("Final pressure is now revealed: P0 Safe · P1 Exposed · P2 Overrun. Exposed shelters count as surviving.",14))
	if session.dev_used: left.add_child(UIkit.label("DEVELOPMENT RUN · hidden state was revealed",14,UIkit.AMBER))
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 470
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(right)
	var columns := _tabs(right,["Truth","Actions","Log","Beliefs","Events"])
	columns[0].add_child(UIkit.label("GROUND TRUTH REVEALED",21,UIkit.ACCENT))
	columns[0].add_child(UIkit.label("Original outbreak source: " + session.scenario.original_source,22))
	var states := "[b]SHELTER     INITIAL → FINAL PRESSURE[/b]\n"
	for id in session.state.shelters:
		states += "%s / %s     %d → %d\n" % [id,session.state.shelters[id].display_name,int(session.scenario.initial_pressures[id]),session.state.shelters[id].zombie_pressure]
	columns[0].add_child(UIkit.rich(states))
	columns[0].add_child(UIkit.label("BEFORE THE MISSION",16,UIkit.TEAL))
	for event in session.scenario.ground_truth_timeline:
		columns[0].add_child(UIkit.rich("[color=#63d8ca]%s[/color]\n%s" % [event.time,event.text]))
	columns[1].add_child(UIkit.rich(PresentationText.action_history(session.state)))
	for summary in session.state.round_summaries:
		columns[1].add_child(UIkit.rich("[b]Round %d outcome[/b]\n%d surviving · %d supply remaining\nNewly Overrun: %s" % [summary.round,summary.survivors,summary.supply_remaining,", ".join(summary.newly_overrun) if not summary.newly_overrun.is_empty() else "None"]))
	columns[2].add_child(UIkit.rich(PresentationText.investigation(session.state)))
	columns[3].add_child(UIkit.rich(PresentationText.beliefs(session,true)))
	var timeline := "[b]SESSION EVENT TIMELINE[/b]\n\n"
	for event: GameEvent in session.logger.events:
		timeline += "#%03d · R%d · %s %s\n" % [event.order,event.round,event.type,event.target]
		if event.old_value != null or event.new_value != null:
			timeline += "%s → %s\n" % [str(event.old_value),str(event.new_value)]
		timeline += "\n"
	columns[4].add_child(UIkit.rich(timeline))
	var status := UIkit.paragraph(export_status if export_status!="" else "Export a structured session record for later analysis.",13,UIkit.MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status)
	footer.add_child(UIkit.button("Export session JSON",_export_session))
	footer.add_child(UIkit.button("Play again  →",_request_restart,true))

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
	shade.color = Color(0.015,0.025,0.04,0.9)
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
		board.supply_path.clear()
		board.preview_edge = ""
		board.preview_lost.clear()
		board.queue_redraw()
