"""Build the itch.io web upload pointed at the online backend, without editing the project.

Example:
  python3 tools/build_web_release.py --godot /Applications/Godot.app/Contents/MacOS/Godot \
      --backend-url https://cascade-lab-backend.onrender.com

Produces build/itch/ and build/cascade-lab-itch.zip (upload the zip to itch.io as an HTML game).
The build contains no secrets. Play creates an anonymous public session on the matching backend.

Instructor/demo build (password-gated Dev Mode sandbox below Play):
  python3 tools/build_web_release.py --godot ... --backend-url ... --preset "Web Instructor"
Produces build/itch-instructor/ and build/cascade-lab-itch-instructor.zip. The participant
preset never offers Dev Mode. The Dev Mode password is a convenience gate, not authentication.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--backend-url', required=True)
    parser.add_argument('--preset', default='Web Participant')
    parser.add_argument('--output', default=None, help='default: build/itch, or build/itch-instructor for the instructor preset')
    args = parser.parse_args()
    url = args.backend_url.rstrip('/')
    if not re.fullmatch(r'https://[A-Za-z0-9.-]+(:\d+)?', url):
        parser.error('--backend-url must be an https:// origin such as https://name.onrender.com (browsers block http from itch.io)')
    if args.preset not in ('Web Participant', 'Web Instructor'):
        parser.error('--preset must be "Web Participant" or "Web Instructor"')
    instructor = args.preset == 'Web Instructor'
    if args.output is None:
        args.output = 'build/itch-instructor' if instructor else 'build/itch'
    root = Path(__file__).resolve().parents[1]
    output = (root / args.output).resolve()
    if output.exists(): shutil.rmtree(output)
    output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix='cascade-itch-') as temp:
        copy = Path(temp)
        for name in ('assets', 'scenarios', 'scripts', 'scenes'):
            shutil.copytree(root / name, copy / name)
        for name in ('project.godot', 'export_presets.cfg'):
            shutil.copy2(root / name, copy / name)
        project = copy / 'project.godot'
        text = project.read_text()
        text = re.sub(r'^backend_url=.*$', f'backend_url="{url}"', text, flags=re.M)
        text = re.sub(r'^support_provider=.*$', 'support_provider="backend"', text, flags=re.M)
        # Dev Mode comes only from the "instructor" feature tag of that preset (password-gated);
        # the participant preset carries the "participant" tag, which always hides it.
        text = re.sub(r'^development_access=.*$', 'development_access=false', text, flags=re.M)
        project.write_text(text)
        subprocess.run([args.godot, '--headless', '--log-file', str(copy / 'import.log'), '--path', temp, '--editor', '--import', '--quit'], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([args.godot, '--headless', '--log-file', str(copy / 'export.log'), '--path', temp, '--export-release', args.preset, str(output / 'index.html')], check=True, stdout=subprocess.DEVNULL)
    # Keep the intended audience next to the upload files so an older participant
    # zip cannot be mistaken for the password-gated instructor/demo export.
    manifest = {
        'preset': args.preset,
        'audience': 'instructor-demo' if instructor else 'research-participant',
        'developer_sandbox': instructor,
        'developer_gate': 'session-only convenience password' if instructor else 'unavailable',
        'backend_origin': url,
        'files_sha256': {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in sorted(output.iterdir()) if path.is_file()},
    }
    (output / 'build-info.json').write_text(json.dumps(manifest, indent=2) + '\n')
    archive = shutil.make_archive(str(output.parent / ('cascade-lab-itch-instructor' if instructor else 'cascade-lab-itch')), 'zip', output)
    print(f'Export preset: {args.preset}\nDeveloper sandbox: {"password-gated" if instructor else "unavailable"}\nitch.io build: {output}\nUpload this zip to itch.io (Kind of project: HTML): {archive}')


if __name__ == '__main__':
    main()
