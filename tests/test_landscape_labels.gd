extends "res://tests/test_city_art.gd"

const CHINESE_NAMES := {
	"riverside_01_v3":["北部仓库","旧集市","市民诊所","西区学校","交通枢纽","东门","河畔会堂","南部仓库"],
	"twin_districts_02_v2":["西部仓库","长廊学校","集市广场","运河关卡","东门","山脊诊所","东区庭院","东部仓库"],
	"lifeline_03_v2":["北部仓库","西区学校","南部仓库","调度场","服务枢纽","山顶诊所","台地避难所","东部会堂"],
	"crossfire_04_v2":["西部仓库","西部接待大厅","运河学校","北部交汇处","转运广场","东部接待大厅","花园避难所","东部仓库"]}

func annotations(tag: String) -> void:
	var board: NetworkView = app.board
	board._refresh_geometry()
	for id in board.title_rects:
		var title: Rect2 = board.title_rects[id]
		var block := Rect2(title.position,Vector2(title.size.x,NetworkView.NAME_BLOCK))
		check(title.position.y >= 168,"Label below toolbar: "+tag+id)
		for edge in board.state.edges.values():
			if edge.isolated or edge.id == board.preview_edge:
				check(not block.intersects(board.bridge_notice_rect(edge.id)),"Tower label leaves bridge notice readable: "+tag+id)
		check(not board._annotation_hides_road(title),"Label leaves all roads and decks visible: "+tag+id)
		if is_instance_valid(app.source_picker):
			check(block.end.y+board.global_position.y <= app.source_picker.global_position.y-4,"Full source label above picker: "+tag+id+str(block)+str(app.source_picker.get_global_rect()))

func run() -> void:
	UIkit.reduced_motion = true
	capture_dir = ProjectSettings.globalize_path("res://build/landscape/after")
	for viewport in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport
		root.size = viewport
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		for entry in ScenarioData.registry().scenarios:
			for chinese in [false,true]:
				FirstPlayText.chinese = chinese
				app._start_dev(entry.id)
				app.session.set_dev_mode(false)
				# Rendering fixture only: production scenario text and language scope are unchanged.
				if chinese:
					for id in app.session.state.shelters:
						app.session.state.shelters[id].display_name = CHINESE_NAMES[entry.id][id.unicode_at(0)-65]
					app.board.annotation_key = ""
				await settle(4)
				var tag: String = str(viewport.x)+"-"+entry.id
				var lang := "zh-fixture" if chinese else "en"
				annotations(tag+lang)
				geometry_checks()
				await snapshot(tag+"-overview-"+lang)
				app.session.begin_sandbox_actions()
				app._request_action("ISOLATE",app.session.scenario.bridges[0])
				await settle(3)
				annotations(tag+lang+"sources")
				await snapshot(tag+"-sources-"+lang)
				await select_delivery_sources()
				await settle(3)
				annotations(tag+lang+"routes")
				await snapshot(tag+"-routes-"+lang)
				app._close_source_picker()
				for edge in app.session.scenario.bridges:
					app.session.state.edges[edge].isolated = true
					app.board._move_camera(app.board._point_on_path(app.board.visual_road(edge),app.board.closure_fraction(edge)),2.5,false)
					await settle(2)
					annotations(tag+lang+"closed-"+edge)
					app.session.state.edges[edge].isolated = false
				FirstPlayText.chinese = false
		app.queue_free()
		await settle()
	print("LANDSCAPE LABELS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
