"""Build an offline review-only Web preview; never writes the source project or saves study records."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--output', default='/tmp/cascade-first-play/web')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cascade-first-play-review-') as directory:
        copied = Path(directory)
        for name in ('assets', 'scenarios', 'scripts', 'scenes'):
            shutil.copytree(root / name, copied / name)
        for name in ('project.godot', 'export_presets.cfg'):
            shutil.copy2(root / name, copied / name)
        sync = copied / 'scripts/study_sync.gd'
        sync.write_text(sync.read_text().replace('var enabled := true', 'var enabled := false').replace('func _ready() -> void:', 'func _ready() -> void:\n\tset_process(false)\n\treturn\n\nfunc _unused_review_init() -> void:', 1))
        # A clean import has no font cache yet. Delay the startup theme until
        # assets have been imported; the exported project retains the real font.
        project = copied / 'project.godot'
        original_project = project.read_text()
        project.write_text(original_project.replace('theme/custom_font="res://assets/fonts/UiBody.tres"', ''))
        subprocess.run([args.godot, '--headless', '--log-file', str(copied / 'import.log'), '--path', directory, '--editor', '--import', '--quit'], check=True, stdout=subprocess.DEVNULL)
        project.write_text(original_project)
        subprocess.run([args.godot, '--headless', '--log-file', str(copied / 'export.log'), '--path', directory, '--export-debug', 'Web', str(output / 'index.html')], check=True, stdout=subprocess.DEVNULL)
    print('Offline review-only preview: ' + str(output))


if __name__ == '__main__':
    main()
