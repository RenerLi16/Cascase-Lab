extends VBoxContainer

signal code_changed(value: String, valid: bool)
const MAX_LENGTH := 512
static var browser_denied := false
var field: LineEdit
var paste_button: Button
var hint: Label
var callback_ref: JavaScriptObject
var request_ticket: JavaScriptObject
var pending := false
var clipboard_status := "idle"

func t(en: String, zh: String) -> String:
	return FirstPlayText.choose(en,zh)

func _ready() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	field = LineEdit.new()
	field.name = "AccessCode"
	field.placeholder_text = t("Study access code","研究访问码")
	field.secret = true
	field.max_length = MAX_LENGTH
	field.custom_minimum_size.y = 52
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	paste_button = UIkit.button(t("Paste","粘贴"),paste_clicked)
	paste_button.custom_minimum_size.x = 92
	row.add_child(paste_button)
	hint = UIkit.meta("")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	field.text_changed.connect(_manual_change)
	if OS.has_feature("web"):
		callback_ref = JavaScriptBridge.create_callback(_clipboard_result)
		# Defines a helper only. No clipboard reads or permission requests on load.
		JavaScriptBridge.eval("""
		window.CascadeClipboard = window.CascadeClipboard || {
		 read: function(done, limit) {
		  let alive = true;
		  let timer;
		  const finish = (status, text) => {
		   if (!alive) return;
		   alive = false; clearTimeout(timer); done(status, text);
		  };
		  const ticket = {cancel: () => {alive = false; clearTimeout(timer);}};
		  const policy = document.permissionsPolicy || document.featurePolicy;
		  if (!window.isSecureContext || !navigator.clipboard || !navigator.clipboard.readText ||
		      (policy && !policy.allowsFeature('clipboard-read'))) {
		   queueMicrotask(() => finish('blocked', '')); return ticket;
		  }
		  timer = setTimeout(() => finish('blocked', ''), 10000);
		  try {
		   navigator.clipboard.readText().then(text => {
		    if (text.length > 4096) {finish('large', ''); return;}
		    text = text.trim();
		    finish(text.length > limit ? 'large' : 'ok', text.length > limit ? '' : text);
		   }, () => finish('blocked', ''));
		  } catch (_) {finish('blocked', '');}
		  return ticket;
		 }
		};
		""",true)
		if browser_denied: _fallback()

static func valid_code(value: String) -> bool:
	var text := value.strip_edges()
	if text.length() < 12 or text.length() > MAX_LENGTH: return false
	for character in text:
		if character.unicode_at(0) < 32 or character.unicode_at(0) == 127: return false
	return true

func _manual_change(value: String) -> void:
	var normalized := value.strip_edges()
	code_changed.emit(normalized,valid_code(normalized))
	if normalized == "": hint.text = ""
	elif not valid_code(normalized): hint.text = t("Enter a valid access code (at least 12 characters).","请输入有效访问码（至少 12 个字符）。")
	else: hint.text = ""

func paste_clicked() -> void:
	if pending or (OS.has_feature("web") and browser_denied): return
	pending = true
	paste_button.disabled = true
	clipboard_status = "pending"
	if OS.has_feature("web"):
		request_ticket = JavaScriptBridge.get_interface("CascadeClipboard").read(callback_ref,MAX_LENGTH)
	else:
		# Native clipboard access also occurs only after the explicit click.
		_clipboard_result(["ok",DisplayServer.clipboard_get()])

func _clipboard_result(args: Array) -> void:
	if not is_inside_tree(): return
	pending = false
	paste_button.disabled = false
	clipboard_status = str(args[0])
	if clipboard_status == "blocked":
		browser_denied = true
		_fallback()
	elif clipboard_status == "large":
		hint.text = t("Clipboard text is too long. Paste only the access code.","剪贴板内容过长，请仅粘贴访问码。")
	else:
		apply_pasted_text(str(args[1]))

func apply_pasted_text(value: String) -> void:
	if value.length() > 4096:
		hint.text = t("Clipboard text is too long. Paste only the access code.","剪贴板内容过长，请仅粘贴访问码。")
		return
	var normalized := value.strip_edges()
	if normalized == "":
		hint.text = t("Clipboard is empty.","剪贴板为空。")
		return
	if normalized.length() > MAX_LENGTH or normalized.contains("\n") or normalized.contains("\r") or normalized.contains("\t"):
		hint.text = t("Paste only one access code.","请仅粘贴一个访问码。")
		return
	field.text = normalized
	field.caret_column = normalized.length()
	field.text_changed.emit(normalized) # Identical path to manual typing; never submits.
	field.grab_focus()

func _fallback() -> void:
	clipboard_status = "blocked"
	paste_button.disabled = true
	hint.text = t("Click the code field and press Ctrl+V / ⌘V.","点击访问码输入框，然后按 Ctrl+V / ⌘V。")

func _exit_tree() -> void:
	if request_ticket != null: request_ticket.cancel()
