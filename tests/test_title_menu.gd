extends "res://tests/test_presentation.gd"

# Title screen, decorative network, Play setup step, password-gated Dev Mode and
# sandbox separation. Run with --offline-tests (windowed for screenshots).

const PASSWORD_ENV := "CASCADE_DEV_PASSWORD"

var title
var net: MenuNetwork

func open_menu(base: Vector2i, window: Vector2i) -> void:
	root.content_scale_size = base
	root.size = window
	if is_instance_valid(app):
		app.queue_free()
		await settle()
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	await settle(45)
	bind()

func bind() -> void:
	title = app.title_screen
	net = title.network if is_instance_valid(title) else null

# Every frame for a while: nothing drawn may touch the real control bounds.
func watch(frames: int, label: String) -> void:
	var worst := 0
	for i in frames:
		await process_frame
		worst = maxi(worst,net.content_violations()+net.violations)
	check(worst == 0,"No circles or lines over the interface: "+label)

func push(event: InputEvent) -> void:
	root.push_input(event,true)

func mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	if pressed: event.button_mask = MOUSE_BUTTON_MASK_LEFT
	push(event)

func mouse_move(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	push(event)

func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	push(event)
	await process_frame
	var release := event.duplicate()
	release.pressed = false
	push(release)
	await process_frame

func dot_index() -> int:
	for i in net.dots.size():
		if not net.dots[i].hidden: return i
	return -1

func protected_contains(point: Vector2) -> bool:
	for rect in net.protected_rects():
		if rect.has_point(point): return true
	return false

func all_text() -> String:
	var parts := PackedStringArray()
	for kind in ["Label","Button","LineEdit","RichTextLabel"]:
		for node in descendants(app,kind):
			parts.append(str(node.text))
			if node is LineEdit: parts.append(node.placeholder_text)
	return "\n".join(parts)

func run() -> void:
	capture_dir = "/tmp/cascade-title"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var sync := root.get_node("StudySync")
	check(not sync.enabled and sync.sessions.is_empty(),"Offline test outbox")
	# 1. Layout, language and network at the reference sizes and an embedded viewport.
	var sizes := [[Vector2i(1440,900),Vector2i(1440,900),"1440"],[Vector2i(1200,800),Vector2i(1200,800),"1200"],[Vector2i(1440,900),Vector2i(1200,800),"1200scaled"],[Vector2i(1440,900),Vector2i(960,600),"embed960"],[Vector2i(1440,900),Vector2i(720,450),"small720"]]
	for entry in sizes:
		for chinese in [false,true]:
			FirstPlayText.chinese = chinese
			UIkit.reduced_motion = false
			await open_menu(entry[0],entry[1])
			var tag: String = entry[2]+("-zh" if chinese else "-en")
			check(app.session == null and app.mission_session == null and app.practice == null,"Title load creates no session: "+tag)
			check(is_instance_valid(title) and title.title_label.text.replace("\n"," ") == "CASCADE LAB","Title text: "+tag)
			check(title.subtitle_label.text == "OUTBREAK","Subtitle text: "+tag)
			check(title.title_label.get_theme_font("font") == title.TITLE_FONT,"Pixel title font: "+tag)
			for line in descendants(title.column,"Label"):
				if line != title.title_label and line != title.subtitle_label:
					check(line.get_theme_font("font") != title.TITLE_FONT and line.get_theme_font("font") != title.SUBTITLE_FONT,"Body copy uses the readable face: "+tag)
			if entry[2] == "1440": check(title.title_size >= 80 and title.title_size <= 110,"Title 80–110 px at 1440×900")
			check(title.title_label.get_global_rect().end.x <= app.size.x and title.title_label.get_global_rect().position.x >= 0,"Title not clipped: "+tag)
			var play: Button = title.play_button
			var dev: Button = title.dev_button
			check(play != null and dev != null,"Play and Dev Mode present: "+tag)
			check(dev.get_global_rect().position.y >= play.get_global_rect().end.y and absf(dev.get_global_rect().get_center().x-play.get_global_rect().get_center().x) < 2,"Dev Mode directly below Play: "+tag)
			check(dev.size.y < play.size.y and dev.size.x < play.size.x,"Dev Mode smaller than Play: "+tag)
			check_layout("title-"+tag)
			check(net.drawn_dots >= (5 if entry[2] == "small720" else 8),"Network drawn: "+tag+" (%d)" % net.drawn_dots)
			check(net.drawn_dots <= 30 and net.edges.size() <= net.dots.size()*2,"Network density limited: "+tag)
			for i in net.dots.size(): check(net.dots[i].neighbors.size() <= 4,"Degree capped")
			await watch(40,"idle "+tag)
			await snapshot("title-"+tag)
	FirstPlayText.chinese = false
	# Smaller physical windows get fewer nodes before any text shrinks.
	await open_menu(Vector2i(1440,900),Vector2i(1440,900))
	var full_count := net.dots.size()
	var full_title: int = title.title_size
	await open_menu(Vector2i(1440,900),Vector2i(720,450))
	check(net.dots.size() < full_count,"Smaller window reduces density (%d < %d)" % [net.dots.size(),full_count])
	check(title.title_size >= full_title and title.text_scale > 1.0,"Text is not shrunk on the small window")

	# 2. Pointer interaction at 1440×900.
	await open_menu(Vector2i(1440,900),Vector2i(1440,900))
	var index := dot_index()
	var dot = net.dots[index]
	mouse_move(dot.pos,false)
	await settle(2)
	check(net.hovered == index,"Hover highlights a node")
	check(net.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,"Pointer cursor over node")
	var before_scale: float = dot.scale
	await settle(10)
	check(dot.scale > before_scale or dot.scale > 1.1,"Hovered node enlarges")
	mouse_button(dot.pos,true)
	await settle(2)
	check(net.dragging == index,"Press starts drag")
	# Drag straight across Play and release on it: Play must not activate.
	var play_center: Vector2 = title.play_button.get_global_rect().get_center()
	var start: Vector2 = dot.pos
	var violations_during_drag := 0
	for step in 30:
		var p := start.lerp(play_center,(step+1)/30.0)
		mouse_move(p,true)
		await process_frame
		violations_during_drag += net.content_violations()+net.violations
	check(violations_during_drag == 0,"Dragged node and its lines stay out of protected areas")
	var clear := true
	for rect in net.protected_rects():
		if rect.grow(dot.radius).has_point(dot.pos): clear = false
	check(clear,"Dragged node stops at the protected boundary")
	mouse_button(play_center,false)
	await settle(4)
	check(app.practice == null and app.session == null and title.stage == "title","Releasing a drag over Play does not activate it")
	check(net.dragging == -1,"Release ends drag")
	await watch(60,"settle after drag")
	check(dot.pos.distance_to(dot.home) < 40.0,"Released node settles toward its home (%.1f)" % dot.pos.distance_to(dot.home))
	# Click (no drag) gives a spring reaction.
	var index2 := dot_index()
	var other = net.dots[index2]
	mouse_move(other.pos,false)
	await settle(2)
	mouse_button(other.pos,true)
	await process_frame
	var popped: float = other.scale_vel
	mouse_button(other.pos,false)
	await settle(2)
	check(popped > 0.0 or other.scale > 1.2,"Click gives a spring reaction")
	# Resize while a node is being dragged.
	var drag_dot = net.dots[dot_index()]
	mouse_button(drag_dot.pos,true)
	await process_frame
	mouse_move(drag_dot.pos+Vector2(30,20),true)
	await process_frame
	root.size = Vector2i(1200,800)
	root.content_scale_size = Vector2i(1200,800)
	await settle(3)
	mouse_move(Vector2(600,400),true)
	await watch(10,"resize during drag")
	mouse_button(Vector2(600,400),false)
	await watch(40,"after resize release")
	check(net.dragging == -1 and app.practice == null,"Resize mid-drag ends cleanly without activating controls")
	# Clicking Play with a real pointer event still works.
	root.content_scale_size = Vector2i(1440,900)
	root.size = Vector2i(1440,900)
	await settle(6)
	var play_rect: Rect2 = title.play_button.get_global_rect()
	mouse_move(play_rect.get_center(),false)
	await process_frame
	mouse_button(play_rect.get_center(),true)
	await process_frame
	mouse_button(play_rect.get_center(),false)
	await settle(4)
	check(app.practice != null and app.session == null,"Network never intercepts the Play click")
	check(not is_instance_valid(net),"Menu network is freed on entering play")

	# 3. Reduced motion: static network, hover feedback only.
	UIkit.reduced_motion = true
	await open_menu(Vector2i(1440,900),Vector2i(1440,900))
	var snapshot_positions: Array = []
	for d in net.dots: snapshot_positions.append(d.pos)
	await settle(30)
	var moved := 0
	for i in net.dots.size():
		if net.dots[i].pos.distance_to(snapshot_positions[i]) > 0.01: moved += 1
	check(moved == 0,"Reduced motion: no drift")
	var still = net.dots[dot_index()]
	mouse_move(still.pos,false)
	await settle(2)
	check(net.hovered >= 0 and still.scale == 1.35,"Reduced motion keeps hover feedback without spring")
	await snapshot("title-reduced-motion")
	UIkit.reduced_motion = false
	await settle(2)
	check(title.motion_button.text == "Motion: on","Motion label follows the preference")
	# Motion toggle on the title.
	await click("Motion: on")
	check(UIkit.reduced_motion and title.motion_button.text == "Motion: reduced","Motion toggle")
	await click("Motion: reduced")
	check(not UIkit.reduced_motion,"Motion toggle restores")
	# Language toggle keeps the network protected around new bounds.
	await click("简体中文")
	check(FirstPlayText.chinese and title.play_button.text == "开始游戏","Language switch")
	await watch(20,"after language switch")
	await click("English")
	check(not FirstPlayText.chinese,"Language switch back")

	# 4. Keyboard: Tab reaches Play, Dev Mode and the corner controls.
	await open_menu(Vector2i(1440,900),Vector2i(1440,900))
	check(root.gui_get_focus_owner() == title.play_button,"Play has initial keyboard focus")
	await key(KEY_TAB)
	check(root.gui_get_focus_owner() == title.dev_button,"Tab moves Play → Dev Mode")

	# 5. Access-code setup step.
	sync.enabled = true
	sync.set_process(false)
	sync.outbox_path = "/tmp/cascade-title-outbox-"+Crypto.new().generate_random_bytes(6).hex_encode()+".json"
	ProjectSettings.set_setting("cascade/require_access_code",true)
	sync.access_code = ""
	for chinese in [false,true]:
		FirstPlayText.chinese = chinese
		app._show_main_menu()
		await settle(30)
		bind()
		check(app.find_child("AccessCodeEntry",true,false) == null,"No code field on the title")
		await click("开始游戏" if chinese else "Play")
		await settle(4)
		var entry = app.find_child("AccessCodeEntry",true,false)
		check(entry != null and entry.paste_button != null,"Setup step shows the existing code entry and Paste")
		check(title.start_button.disabled,"Start disabled until a valid code")
		check(root.gui_get_focus_owner() == entry.field,"Code field focused")
		check(entry.field.secret,"Code field stays masked")
		entry.apply_pasted_text("  Synthetic-Code_Aa-123 ")
		check(not title.start_button.disabled and app.session == null and app.practice == null and sync.access_code == "","Paste validates without starting or committing")
		await watch(20,"setup "+("zh" if chinese else "en"))
		await snapshot("setup-"+("zh" if chinese else "en"))
		check_layout("setup")
		await key(KEY_ESCAPE)
		check(title.stage == "title","Escape returns to the title")
		await click("开始游戏" if chinese else "Play")
		entry = app.find_child("AccessCodeEntry",true,false)
		check(entry.field.text == "Synthetic-Code_Aa-123","Code kept after Back")
		entry.field.text = "short"
		entry.field.text_changed.emit("short")
		check(title.start_button.disabled and entry.hint.text != "","Invalid code: Start disabled with message")
		entry.field.text = "Synthetic-Code_Aa-123"
		entry.field.text_changed.emit(entry.field.text)
		check(sync.sessions.is_empty(),"No session before explicit Start")
	await click("开始")
	FirstPlayText.chinese = false
	check(app.practice != null and sync.access_code == "Synthetic-Code_Aa-123","Start commits the code and enters the normal flow")
	check(sync.sessions.is_empty(),"Practice still creates no records")
	ProjectSettings.set_setting("cascade/require_access_code",false)
	sync.access_code = ""
	sync.enabled = false
	DirAccess.remove_absolute(sync.outbox_path)

	# 6. Password-gated Dev Mode.
	ProjectSettings.set_setting("cascade/dev_password_required",true)
	DevGate.lock()
	var password := OS.get_environment(PASSWORD_ENV)
	check(password != "","Test password supplied via environment")
	for chinese in [false,true]:
		FirstPlayText.chinese = chinese
		app._show_main_menu()
		await settle(30)
		bind()
		app._show_level_picker()
		check(app.title_screen != null and app.find_child("TitleScreen",true,false) != null,"Locked picker cannot be opened directly")
		app._start_dev("riverside_01_v3")
		check(app.session == null,"Locked sandbox cannot be started directly")
		await click("Dev Mode")
		check(is_instance_valid(title.dialog),"Dev Mode opens the password dialog")
		check(net.paused and net.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Network paused under the dialog")
		await settle(3)
		check(root.gui_get_focus_owner() == title.password_field and title.password_field.secret,"Masked field focused")
		check(title.unlock_button.disabled,"Unlock disabled while empty")
		for i in 7:
			await key(KEY_TAB)
			check(title.dialog.is_ancestor_of(root.gui_get_focus_owner()),"Tab focus stays in dialog")
		await key(KEY_TAB,true)
		check(title.dialog.is_ancestor_of(root.gui_get_focus_owner()),"Shift+Tab focus stays in dialog")
		title.password_field.grab_focus()
		title.password_field.text = "bwsiinstructors"
		title.password_field.text_changed.emit(title.password_field.text)
		await key(KEY_ENTER)
		check(not DevGate.unlocked and is_instance_valid(title.dialog),"Wrong (case-changed) password stays locked")
		check(title.password_error.text != "" and title.password_field.text == "","Concise error and cleared field")
		check(not title.password_error.text.to_lower().contains("bwsi"),"Error does not echo input")
		await watch(10,"dialog open")
		await snapshot("password-error-"+("zh" if chinese else "en"))
		await key(KEY_ESCAPE)
		check(not is_instance_valid(title.dialog) and not net.paused,"Escape cancels and resumes the network")
		await click("Dev Mode")
		await settle(3)
		await snapshot("password-dialog-"+("zh" if chinese else "en"))
		await click("取消" if chinese else "Cancel")
		check(not is_instance_valid(title.dialog),"Cancel closes the dialog")
		check(not all_text().contains(password),"Password never shown in the interface")
	FirstPlayText.chinese = false
	await click("Dev Mode")
	await settle(3)
	title.password_field.text = password
	title.password_field.text_changed.emit(password)
	await key(KEY_ENTER)
	await settle(3)
	check(DevGate.unlocked and app.title_screen == null,"Correct password + Enter unlocks")
	check(button_containing("Start · ") != null and not all_text().contains(password),"Level picker shown; password not displayed")
	var labels := all_text()
	check(labels.contains("Dev mode — not research data"),"Picker labelled not research data")
	await snapshot("level-picker")
	# Each scenario starts as a local sandbox: no surveys, no uploads, no AI.
	sync.enabled = true
	sync.set_process(false)
	sync.outbox_path = "/tmp/cascade-title-outbox-"+Crypto.new().generate_random_bytes(6).hex_encode()+".json"
	sync.sessions = [{"session_id":"pending-research","client_secret":"x","credential":"","metadata":{},"next_seq":2,"pending":[{"seq":1}],"closing":"","closed":false}]
	for scenario in ScenarioData.registry().scenarios:
		await click("Start · "+scenario.title)
		await settle(4)
		check(app.session != null and app.session.is_sandbox() and not app.session.dev_mode,"Sandbox started: "+scenario.id)
		check(sync.game == null and sync.mission == null and sync.active.is_empty(),"Sandbox not attached to saving: "+scenario.id)
		check(app.session.support_provider is MockSupportProvider,"Sandbox has no backend/model provider: "+scenario.id)
		check(app.session.state.total_supply() == 6,"Normal resources: "+scenario.id)
		check(all_text().contains("Dev mode — not research data"),"Run labelled: "+scenario.id)
		var payload: Dictionary = app._export_payload()
		check(not payload.has("upload_recovery") and not JSON.stringify(payload).contains("pending-research"),"Sandbox export excludes pending research records: "+scenario.id)
		await click("Begin actions")
		check(app.session.phase == GameManager.Phase.ACTIONS,"No survey/timer before actions: "+scenario.id)
		await click("Menu")
		check(button_containing("Reveal hidden state") != null,"Hidden-state inspector retained: "+scenario.id)
		await click("Choose another scenario")
		await click("Leave mission")
		check(button_containing("Start · ") != null,"Return to level selection keeps unlock: "+scenario.id)
	check(sync.sessions.size() == 1 and sync.sessions[0].pending.size() == 1,"Sandbox added nothing to the outbox")
	# Normal play after sandbox inherits nothing.
	await click("Back")
	await settle(10)
	bind()
	check(is_instance_valid(title),"Back returns to title")
	app._start_dev("riverside_01_v3")
	app.session.set_dev_mode(true)
	app._start_normal()
	await settle(3)
	check(not app.session.is_sandbox() and not app.session.dev_mode and not app.board.dev_mode,"Normal play does not inherit sandbox or reveal")
	check(button_containing("Begin actions") == null and not all_text().contains("not research data"),"Normal play has no sandbox controls or label")
	check(sync.game == app.session,"Normal play attaches to saving")
	check(app._export_payload().has("upload_recovery"),"Normal export keeps recovery records")
	sync.detach()
	sync.sessions = []
	sync.enabled = false
	DirAccess.remove_absolute(sync.outbox_path)
	# Unlock persists until locked; Lock relocks.
	app._show_main_menu()
	await settle(10)
	bind()
	await click("Dev Mode")
	check(button_containing("Start · ") != null,"Unlock remembered for this app session")
	await click("Lock Dev Mode")
	check(not DevGate.unlocked and is_instance_valid(app.title_screen),"Lock Dev Mode relocks")
	bind()
	await click("Dev Mode")
	check(is_instance_valid(title.dialog),"Locked again: dialog required")
	await key(KEY_ESCAPE)
	# Owner modals pause the network as well.
	app._show_message("Could not start mission","Synthetic error.")
	await settle(2)
	check(net.paused,"Error modal pauses the network")
	await watch(5,"error modal")
	app._close_modal()
	await settle(2)
	check(not net.paused,"Closing modal resumes")
	# Participant configuration hides the entry entirely.
	ProjectSettings.set_setting("cascade/development_access",false)
	app._show_main_menu()
	await settle(5)
	check(button_containing("Dev Mode") == null,"Participant configuration hides Dev Mode")
	app._show_level_picker()
	check(button_containing("Start · ") == null,"Participant configuration blocks picker")
	ProjectSettings.set_setting("cascade/development_access",true)
	# Offline native development build keeps direct access.
	ProjectSettings.set_setting("cascade/dev_password_required",false)
	DevGate.lock()
	app._show_main_menu()
	await settle(5)
	await click("Dev Mode")
	check(button_containing("Start · ") != null and button_containing("Lock Dev Mode") == null,"Offline development build opens picker directly")
	app.queue_free()
	await settle()
	print("TITLE MENU TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
