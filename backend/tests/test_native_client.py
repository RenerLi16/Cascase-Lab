"""Real Godot HTTP/outbox integration; mock provider only, never external traffic."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from backend.config import Config
from backend.server import Service, handler
from .fixtures import ROOT

GODOT=os.getenv('GODOT_BIN') or shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'

@unittest.skipUnless(Path(GODOT).exists(),'Godot binary not installed')
class NativeClientTests(unittest.TestCase):
    def test_real_http_queue_and_async_intervention(self):
        with tempfile.TemporaryDirectory() as temp:
            service=Service(Config(database=str(Path(temp)/'test.sqlite3')))
            base_handler=handler(service)
            class LostAckHandler(base_handler):
                lost_ack=False
                def send_response(self, code, message=None):
                    if self.path.endswith('/events') and code==200 and not LostAckHandler.lost_ack:
                        # Storage already committed; drop the first response to force a duplicate retry.
                        LostAckHandler.lost_ack=True
                        raise ConnectionResetError('synthetic lost acknowledgment')
                    return super().send_response(code,message)
            server=ThreadingHTTPServer(('127.0.0.1',0),LostAckHandler)
            thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
            try:
                env=os.environ | {'CASCADE_TEST_URL':f'http://127.0.0.1:{server.server_port}', 'CASCADE_TEST_OUTBOX':str(Path(temp)/'outbox.json')}
                result=subprocess.run([GODOT,'--headless','--log-file',str(Path(temp)/'godot.log'),'--path',str(ROOT),'--script','tests/test_backend_client.gd','--','--offline-tests'],env=env,capture_output=True,text=True,timeout=65)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIn('0 failures',result.stdout)
                self.assertTrue(LostAckHandler.lost_ack)
                print(result.stdout.strip())
                with service.store.connect() as db:
                    self.assertEqual(db.execute('SELECT count(*) FROM interventions').fetchone()[0],1)
                    self.assertEqual(db.execute('SELECT status FROM sessions').fetchone()[0],'interrupted')
                    self.assertEqual(db.execute('SELECT count(*) FROM private_events').fetchone()[0],3)
                    events=db.execute('SELECT body FROM game_events').fetchall()
                    self.assertTrue(any('INTERRUPTED_UPLOAD_TEST' in row[0] for row in events))
                    count,unique=db.execute('SELECT count(*),count(DISTINCT event_id) FROM receipts').fetchone()
                    self.assertEqual(count,unique)
            finally:
                server.shutdown();server.server_close();thread.join();service.close()

    def test_rejected_access_code_recovers_queued_records(self):
        with tempfile.TemporaryDirectory() as temp:
            service=Service(Config(database=str(Path(temp)/'test.sqlite3'),access_code='synthetic-code-123'))
            server=ThreadingHTTPServer(('127.0.0.1',0),handler(service))
            thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
            try:
                env=os.environ | {'CASCADE_TEST_URL':f'http://127.0.0.1:{server.server_port}', 'CASCADE_TEST_OUTBOX':str(Path(temp)/'outbox.json')}
                result=subprocess.run([GODOT,'--headless','--log-file',str(Path(temp)/'godot.log'),'--path',str(ROOT),'--script','tests/test_access_code_recovery.gd','--','--offline-tests'],env=env,capture_output=True,text=True,timeout=65)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIn('0 failures',result.stdout)
                print(result.stdout.strip().splitlines()[-1])
                with service.store.connect() as db:
                    self.assertEqual(db.execute('SELECT count(*) FROM sessions').fetchone()[0],1)
                    self.assertGreater(db.execute('SELECT count(*) FROM receipts').fetchone()[0],0)
            finally:
                server.shutdown();server.server_close();thread.join();service.close()

if __name__=='__main__': unittest.main()
