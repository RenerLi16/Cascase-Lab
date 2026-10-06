extends "res://tests/test_presentation.gd"

# Visual QA capture of representative participant screens (not a pass/fail suite).
# Run with a window, for example:
#   CAPTURE_DIR=/tmp/cascade-ui godot --path . --script res://tests/capture_ui_screens.gd -- --offline-tests
# Optional: CAPTURE_SIZES=1440x900,1200x800
# Optional: CAPTURE_SCALED=1 keeps the 1440 x 900 layout and scales it into each
# window size, as the shipped stretch settings do (tests otherwise lay out natively).
# Sample AI messages below exist only to inspect layout; they are never shown in play.

const SAMPLE_QWEN := "建议: 优先核实 E 的当前压力，再决定是否关闭 E-F。E 连接两个补给站的主要路线，若在没有证据的情况下关闭 E-F，F 和 G 可能失去补给通路。\n依据: E 是四条道路的交汇点，目前地图上没有失守的避难所，也还没有任何核实或监测记录，因此无法判断 E 是否已经暴露。两个补给站各剩三份物资。\n不确定性: 核实结果只代表送达时的状态；如果 E 已经暴露，下一次结算前仍可能恶化。请比较剩余物资与延迟保护的代价。"
const SAMPLE_QWEN_LONG := "建议: 考虑使用剩余物资核实 E，并在核实结果出来之前暂缓关闭 E-F。E 位于四条道路交汇处，同时连接北部和南部补给站；一旦 E 失守，向东的补给通路会被切断，因此这里的信息最有价值。若核实显示压力为 1，再讨论是否用护盾保护 F 或关闭 E-F。\n依据: 第一轮核实记录显示 E 当时的压力为 1，但这只是送达时的快照；B 已安装监测，至今没有变化提醒。三位玩家的初始判断都把 E 视为最直接的危险，但理由不同：有人担心通路，有人担心连锁扩散。\n不确定性: 核实结果只是送达时的快照，不会自动更新；监测安装后也不会显示初始压力。如果判断错误，提前关闭道路可能让 F、G 和 H 之间的补给路线变长或中断。请在行动前确认哪个仓库仍可送达，并比较等待与立即保护的代价。"

var sizes: Array[Vector2i] = [Vector2i(1440,900),Vector2i(1200,800)]

func shot(tag: String, label: String) -> void:
	await settle(6)
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir+"/"+tag+"-"+label+".png")

func fresh(condition: int) -> void:
	if is_instance_valid(app):
		app.queue_free()
		await settle()
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	await settle()
	app._start_normal()
	app.session._support_clock = func(): return support_time
	app.session.configure_condition(condition)
	await settle()

func submit_all() -> void:
	for index in 3:
		app.session.open_private_form()
		app.session.submit_belief(PlayerBelief.new("E","VERIFY","E",3+index%2,"prevent cascade"))

func show_message(text: String, template_id: String) -> void:
	app.session.phase = GameManager.Phase.INTERVENTION
	app.session.support_shown = false
	app.session.support_message = {"text":text,"template_id":template_id,"version":"capture"}
	app._render()
	await settle(8)

func run() -> void:
	capture_dir = OS.get_environment("CAPTURE_DIR") if OS.get_environment("CAPTURE_DIR") != "" else "/tmp/cascade-ui"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	if OS.get_environment("CAPTURE_SIZES") != "":
		sizes.clear()
		for part in OS.get_environment("CAPTURE_SIZES").split(","):
			var xy := part.split("x")
			sizes.append(Vector2i(int(xy[0]),int(xy[1])))
	var scaled := OS.get_environment("CAPTURE_SCALED") == "1"
	for viewport_size in sizes:
		root.content_scale_size = Vector2i(1440,900) if scaled else viewport_size
		root.size = viewport_size
		var tag := str(viewport_size.x)+("-scaled" if scaled else "")
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		await shot(tag,"01-menu")
		await click("Dev Mode")
		await shot(tag,"02-level-picker")
		await fresh(0)
		await shot(tag,"03-observe")
		app._select_shelter("A")
		await create_timer(0.7).timeout
		await shot(tag,"04-building-observe")
		app._clear_selection()
		await create_timer(0.7).timeout
		app._show_help()
		await shot(tag,"05-field-guide")
		app._close_modal()
		app._show_menu()
		await shot(tag,"06-session-menu")
		app._show_session_setup()
		await shot(tag,"07-session-setup")
		app._close_modal()
		await click("Choose your")
		await shot(tag,"08-handoff")
		await click("Open my form")
		await shot(tag,"09-form-blank")
		var fields := descendants(app,"OptionButton")
		choose(fields[0],"E-F")
		choose(fields[1],"VERIFY")
		choose(fields[2],"E")
		choose(fields[3],"4")
		choose(fields[4],"prevent cascade")
		await shot(tag,"10-form-filled")
		fields[4].show_popup()
		await shot(tag,"11-form-options")
		fields[4].get_popup().hide()
		await click("Hide survey")
		await create_timer(0.4).timeout
		app._select_shelter("E")
		await create_timer(0.7).timeout
		await shot(tag,"12-form-hidden")
		await click("Expand survey")
		await create_timer(0.4).timeout
		await click("Submit & pass screen")
		for index in 2:
			app.session.open_private_form()
			app.session.submit_belief(PlayerBelief.new("E","VERIFY","E",4,"prevent cascade"))
		app._clear_selection()
		support_time += 34000
		await create_timer(0.7).timeout
		await shot(tag,"13-discussion")
		support_time += 86000
		await settle(8)
		await shot(tag,"14-intervention-none")
		for condition in [1,2]:
			await fresh(condition)
			app.session.start_private()
			submit_all()
			support_time += 120000
			await settle(8)
			await shot(tag,"15-intervention-%s" % ["","direct-mock","dissent-mock"][condition])
		await show_message(SAMPLE_QWEN,"capture.qwen")
		await shot(tag,"16-intervention-qwen")
		await show_message(SAMPLE_QWEN_LONG,"capture.qwen-long")
		await shot(tag,"17-intervention-qwen-long")
		await show_message("\n".join(SupportLibrary.TEMPLATES["direct.monitor"]).replace("%s","E"),"direct.monitor")
		await shot(tag,"18-intervention-english-long")
		app.session._receive_support({"error":"capture"},app.session.run_token,app.session.state.round)
		app._render()
		await settle(8)
		await shot(tag,"19-intervention-failure")
		await fresh(0)
		app.session.start_private()
		submit_all()
		support_time += 120000
		await settle(8)
		support_time += 15000
		await settle()
		await click("Proceed to actions")
		await map_click("E")
		await create_timer(0.7).timeout
		await shot(tag,"20-actions-building")
		app.session.dispatch_action("MONITOR","E",["A"] as Array[String])
		await create_timer(0.3).timeout
		await shot(tag,"21-delivery")
		await wait_delivery()
		app._select_shelter("E")
		await create_timer(0.7).timeout
		await shot(tag,"22-actions-disabled-reason")
		app._clear_selection()
		await create_timer(0.7).timeout
		await map_click("E-F",true)
		await shot(tag,"23-road-bubble")
		await click("ISOLATE")
		await shot(tag,"24-isolate-confirm")
		app._close_modal()
		await click("End round")
		await shot(tag,"25-end-round-confirm")
		await click("Resolve")
		await create_timer(2.4).timeout
		await shot(tag,"26-round-complete")
		await click("Next round")
		app._clear_selection()
		await create_timer(0.7).timeout
		await shot(tag,"27-round-two")
		for round_number in 2:
			app.session.phase = GameManager.Phase.ACTIONS
			app.session.begin_resolution()
			app.session.apply_resolution(app.session.run_token)
			app.session.finish_resolution(app.session.run_token)
			app.session.next_round()
		await settle(8)
		app._clear_selection()
		await create_timer(0.7).timeout
		await shot(tag,"28-results")
		app.queue_free()
		await settle()
	print("CAPTURED UI SCREENS in "+capture_dir)
	quit(0)
