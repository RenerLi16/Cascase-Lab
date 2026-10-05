"""Build a synthetic browser harness in an isolated temporary copy (no project mutation)."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile
import uuid


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--godot',default='godot')
    parser.add_argument('--output',default='build/web-test')
    parser.add_argument('--backend-url',default='',help='e.g. https://cascade.test:8443 for an online rehearsal')
    parser.add_argument('--require-access-code',action='store_true')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    output=(root/args.output).resolve();output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cascade-web-test-') as temp:
        copy=Path(temp)
        for name in ('assets','scenarios','scripts','scenes','tests'):
            shutil.copytree(root/name,copy/name)
        for name in ('project.godot','export_presets.cfg'):
            shutil.copy2(root/name,copy/name)
        project=copy/'project.godot'
        text=project.read_text().replace('res://scenes/Main.tscn','res://tests/web_integration.tscn').replace('[cascade]', '[cascade]\noutbox_key="cascade.synthetic.test.'+uuid.uuid4().hex+'"')
        if args.backend_url: text=text.replace('backend_url="http://127.0.0.1:8787"','backend_url="'+args.backend_url.rstrip('/')+'"')
        if args.require_access_code: text=text.replace('[cascade]','[cascade]\nrequire_access_code=true',1)
        project.write_text(text)
        presets=copy/'export_presets.cfg'
        presets.write_text(presets.read_text().replace('tools/*,tests/*,','tools/*,'))
        subprocess.run([args.godot,'--headless','--log-file',str(copy/'import.log'),'--path',temp,'--editor','--import','--quit'],check=True,stdout=subprocess.DEVNULL)
        subprocess.run([args.godot,'--headless','--log-file',str(copy/'export.log'),'--path',temp,'--export-debug','Web',str(output/'index.html')],check=True,stdout=subprocess.DEVNULL)
    print('Synthetic browser test exported to '+str(output))

if __name__=='__main__':main()
