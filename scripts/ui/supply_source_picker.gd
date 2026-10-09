extends PanelContainer

# Shared presentation for measured, development and practice controllers.
# Selection never reserves stock. The owner performs authoritative dispatch.
signal confirmed(kind: String, target: String, assignments: Array[String])
signal cancelled
var actions: ActionManager
var board: NetworkView
var kind := ""
var target := ""
var assignments: Array[String] = []
var destinations: Array[String] = []
var eligible: Array[String] = []
var locked := false
var message := ""
var column: VBoxContainer
var last_click := ""
var last_click_at := -1000

func t(en: String, zh: String) -> String:
	return FirstPlayText.choose(en,zh)

func setup(manager: ActionManager, map: NetworkView, action_kind: String, action_target: String) -> void:
	actions = manager
	board = map
	kind = action_kind
	target = action_target
	destinations = [target]
	if kind == "ISOLATE": destinations = [actions.state.edges[target].from,actions.state.edges[target].to]
	name = "SupplySourcePicker"
	add_theme_stylebox_override("panel",UIkit.box(UIkit.PANEL,UIkit.AMBER,3,12))
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 24
	offset_right = -24
	offset_top = -310
	offset_bottom = -104
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	add_child(column)
	board.source_mode = true
	board.inspection_inset = 0
	board.focus_sources()
	refresh()

func unavailable_text() -> String:
	var reason := actions.unavailable_reason(kind,target)
	var zh: String = {"NO SUPPLY":"可用物资不足。","NO SUPPLY ROUTE":"没有库存充足且路线可达的仓库。","OVERRUN":"目的地已失守。","ENDPOINT OVERRUN":"桥梁一端已失守。","ROAD CLOSED":"桥梁已关闭。","NOT A BRIDGE":"只有桥梁可以关闭。","DELIVERY IN PROGRESS":"已有物资正在运送。"}.get(reason,"当前无法执行此操作。")
	return t(PresentationText.unavailable_text(reason),zh)

func current_index() -> int:
	return mini(assignments.size(),destinations.size()-1)

func feasible_options() -> Array:
	if actions.unavailable_reason(kind,target) != "": return []
	return actions.supply.delivery_options(kind,target)

func refresh() -> void:
	var options := feasible_options()
	if not assignments.is_empty():
		var valid := false
		for option: Array in options:
			if option.slice(0,assignments.size()) == assignments: valid = true
		if not valid:
			assignments.clear()
			message = t("Supply availability changed. Choose again.","补给情况已变化，请重新选择。")
	eligible.clear()
	var index := current_index()
	for option: Array in options:
		if option.slice(0,index) == Array(assignments).slice(0,index) and not eligible.has(option[index]): eligible.append(option[index])
	board.source_destinations.assign(destinations)
	board.eligible_sources.assign(eligible)
	board.chosen_sources.assign(assignments)
	board.supply_paths.clear()
	for delivery in actions.supply.delivery_plan(kind,target,assignments): board.supply_paths.append(delivery.path)
	board.preview_edge = target if kind == "ISOLATE" else ""
	board.preview_lost.clear()
	var consequences: Array[String] = []
	if kind == "ISOLATE":
		var losses := actions.preview_isolation(target)
		for depot in losses:
			for id in losses[depot]:
				if not board.preview_lost.has(id): board.preview_lost.append(id)
			consequences.append(t("%s loses routes to %s","%s 将无法到达 %s") % [depot,", ".join(losses[depot]) if not losses[depot].is_empty() else t("none","无")])
	board.queue_redraw()
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := UIkit.heading(t("Choose supply source","选择补给仓库"),24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var back := UIkit.button(t("Back","上一步"),go_back)
	back.disabled = assignments.is_empty()
	row.add_child(back)
	row.add_child(UIkit.button(t("Cancel","取消"),func(): if not locked: cancelled.emit()))
	if options.is_empty():
		column.add_child(UIkit.paragraph(t("No eligible depot. ","没有符合条件的仓库。")+unavailable_text()))
	elif assignments.size() < destinations.size():
		var prefix := t("Bridge end %d of 2 · ","桥梁端点 %d / 2 · ") % (index+1) if kind == "ISOLATE" else ""
		column.add_child(UIkit.paragraph(prefix+t("Send 1 supply to Tower %s. Click a highlighted depot.","向塔楼 %s 运送 1 份物资。请点击高亮的仓库。") % destinations[index]))
	else:
		column.add_child(UIkit.paragraph(t("Review the routes. Click another highlighted depot to change the source.","请检查路线。点击其他高亮仓库可以更换来源。")))
	var stock: Array[String] = []
	for id in eligible: stock.append(t("%s: %d remaining","%s：剩余 %d 份") % [id,actions.state.depots[id].supply_remaining])
	if not stock.is_empty(): column.add_child(UIkit.meta(" · ".join(stock)))
	if not assignments.is_empty():
		var summary: Array[String] = []
		for i in assignments.size(): summary.append("%s → %s" % [assignments[i],destinations[i]])
		var confirmation := HBoxContainer.new()
		column.add_child(confirmation)
		var receipt := UIkit.strong("%s · %s · " % [t(PresentationText.action_name(kind),{"VERIFY":"核实","MONITOR":"监测","SHIELD":"防护","ISOLATE":"关闭桥梁"}.get(kind,kind)),"  +  ".join(summary)]+t("Cost: %d supply","消耗：%d 份物资") % destinations.size())
		receipt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirmation.add_child(receipt)
		if assignments.size() == destinations.size(): confirmation.add_child(UIkit.button(t("Confirm delivery","确认运送"),confirm_selection,true))
	if kind == "ISOLATE": column.add_child(UIkit.meta(t("The bridge closes after both deliveries arrive. "+PresentationText.CLOSURE_EFFECT+" ","两端物资均送达后桥梁关闭。将阻止疫情传播和物资运送经过此连接。")+" · ".join(consequences)))
	if message != "": column.add_child(UIkit.meta(message,UIkit.AMBER))
	_fit_card.call_deferred()

func _fit_card() -> void:
	if not is_inside_tree(): return
	offset_top = -104-get_combined_minimum_size().y


func choose(id: String) -> void:
	if locked: return
	if id == last_click and Time.get_ticks_msec()-last_click_at < 160: return
	refresh() # Recheck stock/routes before accepting the click.
	if not eligible.has(id): return
	last_click = id
	last_click_at = Time.get_ticks_msec()
	var index := current_index()
	assignments.resize(index)
	assignments.append(id)
	message = ""
	refresh()

func go_back() -> void:
	if locked or assignments.is_empty(): return
	assignments.pop_back()
	last_click = ""
	message = ""
	refresh()

func confirm_selection() -> void:
	if locked: return
	if assignments.size() != destinations.size() or not feasible_options().has(assignments):
		message = t("Supply availability changed. Choose again.","补给情况已变化，请重新选择。")
		refresh()
		return
	locked = true # Synchronous guard precedes signal / owner dispatch.
	confirmed.emit(kind,target,assignments.duplicate())

func clear_map() -> void:
	locked = true
	if not is_instance_valid(board): return
	board.source_mode = false
	board.source_destinations.clear()
	board.eligible_sources.clear()
	board.chosen_sources.clear()
	board.supply_paths.clear()
	board.preview_edge = ""
	board.preview_lost.clear()
	board.center_map(false)
