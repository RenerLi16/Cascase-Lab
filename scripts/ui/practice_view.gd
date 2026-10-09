class_name PracticeView
extends Control

signal finished(version: String)
signal exited
# practice-2: closure step teaches the bridge-only rule used in every mission.
const VERSION := "practice-2"
# A separate controller has no MissionSession, provider, survey, or StudySync binding.
# Only the shared action, routing, state, and presentation mechanics are reused.
const SupplySourcePicker = preload("res://scripts/ui/supply_source_picker.gd")
var source_picker: PanelContainer
var scenario := ScenarioData.load_path("res://scenarios/practice_demo.json")
var state: GameState
var logger: EventLogger
var actions: ActionManager
var board: NetworkView
var detail: VBoxContainer
var counter: Label
var instruction: Label
var status: Label
var step := 0
var busy := false
var target := ""
var receipt := ""
var route_changes := ""
var generation := 0

func t(en: String, zh: String) -> String:
	return FirstPlayText.choose(en,zh)

func _ready() -> void:
	theme = UIkit.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reset()

func reset() -> void:
	close_sources()
	generation += 1
	state = GameState.new(scenario)
	logger = EventLogger.new()
	actions = ActionManager.new(state,logger)
	step = 0
	busy = false
	target = ""
	receipt = ""
	route_changes = ""
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var background := ColorRect.new()
	background.color = UIkit.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var page := VBoxContainer.new()
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var title := UIkit.heading(t("Practice · try the controls","练习 · 试用操作"),UIkit.DISPLAY)
	header.add_child(title)
	counter = UIkit.figure("6 / 6",UIkit.METRIC)
	header.add_child(counter)
	header.add_child(UIkit.label(t("supplies","份物资")))
	page.add_child(UIkit.meta(t("Separate demonstration map · unscored · take your time","独立演示地图 · 不计分 · 无时间限制")))
	instruction = UIkit.paragraph("")
	page.add_child(instruction)
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	board = NetworkView.new()
	add_child(board)
	move_child(board,1)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.inspection_inset = 390
	board.configure(scenario,state)
	board.shelter_selected.connect(select_shelter)
	board.edge_selected.connect(select_road)
	board.background_selected.connect(overview)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 350
	body.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -350
	detail = UIkit.scroll_column(panel)
	status = UIkit.paragraph("",UIkit.BODY,UIkit.SECONDARY)
	page.add_child(status)
	var row := HBoxContainer.new()
	page.add_child(row)
	row.add_child(UIkit.button(t("Overview","全图"),overview))
	row.add_child(UIkit.button(t("Reset practice","重新练习"),reset))
	row.add_child(UIkit.quiet(t("Main menu","主菜单"),func(): exited.emit()))
	row.add_child(UIkit.quiet("−",func(): board.change_zoom(-0.1)))
	row.add_child(UIkit.quiet("+",func(): board.change_zoom(0.1)))
	var motion := UIkit.quiet(t("Reduce motion","减少动态效果"),func(): UIkit.reduced_motion = not UIkit.reduced_motion)
	motion.toggle_mode = true
	motion.button_pressed = UIkit.reduced_motion
	row.add_child(motion)
	_pass_map_input(margin)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()

func _pass_map_input(node: Node) -> void:
	if node is BoxContainer or node is MarginContainer: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _pass_map_input(child)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		overview()
		get_viewport().set_input_as_handled()

func overview() -> void:
	close_sources()
	board.center_map()
	board.selected_shelter = ""
	board.selected_edge = ""
	target = ""
	refresh()

func select_shelter(id: String) -> void:
	if is_instance_valid(source_picker):
		source_picker.choose(id)
		return
	if busy: return
	board.selected_shelter = id
	board.selected_edge = ""
	target = id
	board.focus_building(id)
	refresh()

func select_road(id: String) -> void:
	if is_instance_valid(source_picker): return
	if busy: return
	board.selected_edge = id
	board.selected_shelter = ""
	target = id
	board.queue_redraw()
	refresh()

func refresh() -> void:
	var panel: Control = detail.get_parent().get_parent()
	panel.visible = target != "" or busy or step == 2
	board.inspection_inset = 390 if panel.visible else 0
	counter.text = "%d / 6" % state.total_supply()
	instruction.text = [t("1 / 3 · Select a tower, choose Verify, then click a highlighted source depot.","1 / 3 · 选择塔楼并点击核实，再点击高亮仓库选择补给来源。"),t("2 / 3 · Select a bridge (a timber deck over the river). Only bridges can be closed. Choose a source depot for each end, then confirm.","2 / 3 · 选择一座桥梁（河上的木桥）。只有桥梁可以关闭。分别为两端选择补给仓库，再确认运送。"),t("3 / 3 · Bridge closed. Inspect the map to see which supply routes remain.","3 / 3 · 桥梁已关闭。查看地图上剩余的补给路线。")][step]
	status.visible = true
	status.text = receipt
	board.configure(scenario,state)
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	if busy:
		detail.add_child(UIkit.heading(t("Supply en route","物资运送中")))
		detail.add_child(UIkit.paragraph(t("Watch the deliveries reach their destinations. Supplies are spent when you confirm.","观察物资送达目的地。确认运送时即扣除物资。")))
		return
	if state.shelters.has(target):
		detail.add_child(UIkit.heading(t("Shelter ","避难所 ")+target))
		detail.add_child(UIkit.paragraph(t("? means unobserved, not safe. Verify gives a dated reading when the delivery arrives.","？表示尚未观测，不代表安全。核实物资送达时会获得带时间标记的读数。")))
		var depots := actions.supply.eligible_depots(target)
		detail.add_child(UIkit.paragraph(t("Supply from: ","可补给的仓库：")+(", ".join(depots) if not depots.is_empty() else t("none","无"))))
		if step == 0: detail.add_child(UIkit.button(t("Deliver · VERIFY · 1 supply","运送 · 核实 · 1 份物资"),func(): deliver("VERIFY",target),true))
	elif state.edges.has(target):
		var bridge: bool = state.edges[target].bridge
		detail.add_child(UIkit.heading((t("Bridge ","桥梁 ") if bridge else t("Road ","道路 "))+target))
		if not bridge: detail.add_child(UIkit.paragraph(t("Ordinary road. Only bridges can be closed.","普通道路。只有桥梁可以关闭。")))
		elif state.edges[target].isolated: detail.add_child(UIkit.paragraph(t("Closed in both directions.","双向关闭。")))
		elif step == 1:
			detail.add_child(UIkit.paragraph(t("Close bridge spends two supplies, one at each end. The bridge closes after both arrive. It blocks outbreak spread and supply deliveries across this connection.","关闭桥梁消耗两份物资，每端一份。全部送达后桥梁关闭，将阻止疫情传播和物资运送经过此连接。")))
			for depot in actions.preview_isolation(target):
				var lost: Array = actions.preview_isolation(target)[depot]
				detail.add_child(UIkit.meta(t("Depot %s loses routes to: %s","仓库 %s 将无法到达：%s") % [depot,", ".join(lost) if not lost.is_empty() else t("none","无")]))
			detail.add_child(UIkit.button(t("Close bridge · 2 supplies","关闭桥梁 · 2 份物资"),func(): deliver("ISOLATE",target),true))
	else:
		detail.add_child(UIkit.heading(t("Try a move","试着行动")))
		detail.add_child(UIkit.paragraph(t("Click a named shelter to inspect it. Click a road or bridge to select that connection. Overview returns to the whole map.","点击标有名称的避难所查看详情。点击道路或桥梁选择连接。点击全图返回整个地图。")))
	if step == 2:
		UIkit.rule(detail)
		detail.add_child(UIkit.paragraph(route_changes))
		detail.add_child(UIkit.paragraph(t("Practice complete. Your measured session starts with fresh supplies and no practice answers or actions.","练习完成。正式任务将使用全新物资，不保留练习中的回答或行动。")))
		detail.add_child(UIkit.button(t("Start measured session","开始正式任务"),func(): finished.emit(VERSION),true))

func deliver(kind: String, id: String) -> void:
	if busy or not ((step == 0 and kind == "VERIFY") or (step == 1 and kind == "ISOLATE")): return
	if is_instance_valid(source_picker): return
	detail.get_parent().get_parent().hide()
	status.hide()
	source_picker = SupplySourcePicker.new()
	add_child(source_picker)
	source_picker.setup(actions,board,kind,id)
	var token := generation
	source_picker.cancelled.connect(func(): close_sources(); refresh())
	source_picker.confirmed.connect(func(action_kind: String, action_target: String, assignments: Array[String]):
		if token != generation or busy: return
		close_sources()
		perform_delivery(action_kind,action_target,assignments))

func close_sources() -> void:
	if not is_instance_valid(source_picker): return
	source_picker.clear_map()
	remove_child(source_picker)
	source_picker.queue_free()
	source_picker = null

func perform_delivery(kind: String, id: String, assignments: Array[String]) -> void:
	if busy or not ((step == 0 and kind == "VERIFY") or (step == 1 and kind == "ISOLATE")): return
	var request := GameAction.new(kind,id,"",state.round)
	request.endpoint_depots.assign(assignments)
	var before := state.total_supply()
	var losses := actions.preview_isolation(id) if kind == "ISOLATE" else {}
	var result := actions.reserve(request)
	if not result.ok: return
	busy = true
	receipt = t("Supplies: %d → %d · %d spent","物资：%d → %d · 已消耗 %d 份") % [before,state.total_supply(),before-state.total_supply()]
	refresh()
	# Overview keeps both depot and destination visible during the delivery.
	board.center_map(false)
	var token := generation
	await board.play_deliveries(result.action.deliveries)
	if token != generation: return
	if kind == "ISOLATE":
		await board.play_closure(id)
		if token != generation: return
	var completed := actions.complete_delivery(result.action)
	if not completed.ok: return
	if kind == "VERIFY":
		receipt += t(" · Delivered to %s. Verify: Pressure %d at round 1 (dated reading)."," · 已送达 %s。核实：第 1 轮压力 %d（历史读数）。") % [id,completed.observation.pressure]
	else:
		receipt += t(" · Both deliveries arrived. Bridge %s closed."," · 两端物资均已送达。桥梁 %s 已关闭。") % id
		var changes: Array[String] = []
		for depot in losses:
			changes.append(t("Depot %s lost routes to: %s","仓库 %s 已无法到达：%s") % [depot,", ".join(losses[depot]) if not losses[depot].is_empty() else t("none","无")])
		route_changes = "\n".join(changes)
	busy = false
	step += 1
	target = ""
	refresh()
