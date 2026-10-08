"""Export an isolated, offline visual review. Never reads the research outbox."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GODOT = '/Applications/Godot.app/Contents/MacOS/Godot'
OUTPUT = ROOT / 'build' / 'medieval-web'
OUTPUT.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='cascade-medieval-preview-') as temporary:
    project = Path(temporary)
    for name in ('assets', 'scenarios', 'scripts', 'scenes'):
        shutil.copytree(ROOT / name, project / name)
    for name in ('project.godot', 'export_presets.cfg'):
        shutil.copy2(ROOT / name, project / name)
    sync = project / 'scripts/study_sync.gd'
    sync.write_text(sync.read_text().replace('if OS.get_cmdline_user_args().has("--offline-tests"):', 'if true: # Offline review copy only.'))
    harness = project / 'scenes/MedievalReview.gd'
    harness.write_text('''extends Node
var elapsed := 0.0
var app: Control
func _ready() -> void:
    app = load("res://scenes/Main.tscn").instantiate()
    add_child(app)
    var query = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('scenario') || 'riverside_01_v2'"))
    if query == "practice":
        FirstPlayText.chinese = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('lang') === 'zh'"))
        app._begin_play()
    elif ScenarioData.registry().development_default_order.has(query):
        app._start_dev(query)
        app.session.set_dev_mode(false)
        app.session.begin_sandbox_actions()
func _process(delta: float) -> void:
    elapsed += delta
    if elapsed < 1: return
    elapsed = 0
    var data := {"fps":Engine.get_frames_per_second(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0}
    if app != null and is_instance_valid(app.board):
        data["zoom"] = app.board.zoom
        data["selected"] = app.selected_shelter
        data["phase"] = app.session.phase
        data["supplies"] = app.session.state.total_supply()
        data["actions"] = app.session.state.actions.size()
    JavaScriptBridge.eval("document.getElementById('canvas').setAttribute('data-review',"+JSON.stringify(JSON.stringify(data))+");")
''')
    (project / 'scenes/MedievalReview.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://scenes/MedievalReview.gd" id="1"]\n[node name="MedievalReview" type="Node"]\nscript = ExtResource("1")\n')
    settings = project / 'project.godot'
    settings.write_text(settings.read_text().replace('res://scenes/Main.tscn', 'res://scenes/MedievalReview.tscn'))
    for arguments in (['--editor', '--import', '--quit'], ['--export-debug', 'Web', str(OUTPUT / 'index.html')]):
        result = subprocess.run([GODOT, '--headless', '--path', str(project), '--log-file', str(project / 'godot.log'), *arguments], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if result.returncode or 'SCRIPT ERROR' in result.stdout:
            raise RuntimeError(result.stdout)
print(OUTPUT / 'index.html')
