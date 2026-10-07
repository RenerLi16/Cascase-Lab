class_name PracticeView
extends Control

signal finished(version: String)
signal exited
const VERSION := "practice-1"
# A separate controller has no MissionSession, provider, survey, or StudySync binding.
# Only the shared action, routing, state, and presentation mechanics are reused.
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
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	board = NetworkView.new()
	body.add_child(board)
	board.configure(scenario,state)
	board.shelter_selected.connect(select_shelter)
	board.edge_selected.connect(select_road)
	board.background_selected.connect(overview)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 350
	panel.add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.LINE,6,UIkit.XL-4))
	body.add_child(panel)
	detail = UIkit.scroll_column(panel)
	status = UIkit.paragraph("",UIkit.BODY,UIkit.SECONDARY)
	page.add_child(status)
	var row := HBoxContainer.new()
	page.add_child(row)
	row.add_child(UIkit.button(t("Overview","全图"),overview))
	row.add_child(UIkit.button(t("Reset practice","重新练习"),reset))
	row.add_child(UIkit.quiet(t("Main menu","主菜单"),func(): exited.emit()))
	refresh()

func overview() -> void:
	board.center_map()
	board.selected_shelter = ""
	board.selected_edge = ""
	target = ""
	refresh()

func select_shelter(id: String) -> void:
	if busy: return
	board.selected_shelter = id
	board.selected_edge = ""
	target = id
	board.pop_piece(id)
	board.focus_building(id)
	refresh()

func select_road(id: String) -> void:
	if busy: return
	board.selected_edge = id
	board.selected_shelter = ""
	target = id
	board.queue_redraw()
	refresh()

func refresh() -> void:
	counter.text = "%d / 6" % state.total_supply()
	instruction.text = [t("1 / 3 · Select a shelter, then send one supply to Verify it.","1 / 3 · 选择一个避难所，再运送一份物资进行核实。"),t("2 / 3 · Return to Overview. Select a road, then close it with two deliveries.","2 / 3 · 返回全图。选择一条道路，向两端运送物资后关闭它。"),t("3 / 3 · Road closed. Inspect the map to see which supply routes remain.","3 / 3 · 道路已关闭。查看地图上剩余的补给路线。")][step]
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
		detail.add_child(UIkit.heading(t("Road ","道路 ")+target))
		if state.edges[target].isolated: detail.add_child(UIkit.paragraph(t("Closed in both directions.","双向关闭。")))
		elif step == 1:
			detail.add_child(UIkit.paragraph(t("ISOLATE spends two supplies, one at each end. The road closes after both arrive. Infection and supplies can no longer pass along it.","隔离消耗两份物资，每端一份。全部送达后道路关闭，感染和物资都无法沿此路通过。")))
			for depot in actions.preview_isolation(target):
				var lost: Array = actions.preview_isolation(target)[depot]
				detail.add_child(UIkit.meta(t("Depot %s loses routes to: %s","仓库 %s 将无法到达：%s") % [depot,", ".join(lost) if not lost.is_empty() else t("none","无")]))
			detail.add_child(UIkit.button(t("Close road · 2 supplies","关闭道路 · 2 份物资"),func(): deliver("ISOLATE",target),true))
	else:
		detail.add_child(UIkit.heading(t("Try a move","试着行动")))
		detail.add_child(UIkit.paragraph(t("Click a location piece to inspect it. Click a road to select that connection. Overview returns to the whole map.","点击地点棋子查看详情。点击道路选择连接。点击全图返回整个地图。")))
	if step == 2:
		UIkit.rule(detail)
		detail.add_child(UIkit.paragraph(route_changes))
		detail.add_child(UIkit.paragraph(t("Practice complete. Your measured session starts with fresh supplies and no practice answers or actions.","练习完成。正式任务将使用全新物资，不保留练习中的回答或行动。")))
		detail.add_child(UIkit.button(t("Start measured session","开始正式任务"),func(): finished.emit(VERSION),true))

func deliver(kind: String, id: String) -> void:
	if busy or not ((step == 0 and kind == "VERIFY") or (step == 1 and kind == "ISOLATE")): return
	var options := actions.supply.delivery_options(kind,id)
	if options.is_empty(): return
	var request := GameAction.new(kind,id,"",state.round)
	request.endpoint_depots.assign(options[0])
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
		receipt += t(" · Both deliveries arrived. Road %s closed."," · 两端物资均已送达。道路 %s 已关闭。") % id
		var changes: Array[String] = []
		for depot in losses:
			changes.append(t("Depot %s lost routes to: %s","仓库 %s 已无法到达：%s") % [depot,", ".join(losses[depot]) if not losses[depot].is_empty() else t("none","无")])
		route_changes = "\n".join(changes)
	busy = false
	step += 1
	target = ""
	refresh()
