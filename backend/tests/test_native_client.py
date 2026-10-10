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
            service=Service(Config(database=str(Path(temp)/'test.sqlite3'), public_records=True, public_ai=True, public_policy_id='synthetic-test-only', public_round_interval=0))
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

    def test_full_session_forms_and_lost_acknowledgment(self):
        with tempfile.TemporaryDirectory() as temp:
            service=Service(Config(database=str(Path(temp)/'forms.sqlite3'), public_records=True,
                                   public_policy_id='synthetic-forms-only', max_body=71000))
            base_handler=handler(service)
            class LostFormAckHandler(base_handler):
                lost_ack=False
                def send_response(self, code, message=None):
                    if self.path.endswith('/events') and code == 200 and not self.lost_ack:
                        with service.store.connect() as db:
                            has_form = db.execute('SELECT count(*) FROM round_evaluations').fetchone()[0] > 0
                        if has_form:
                            LostFormAckHandler.lost_ack=True
                            raise ConnectionResetError('synthetic lost form acknowledgment')
                    return super().send_response(code,message)
            server=ThreadingHTTPServer(('127.0.0.1',0),LostFormAckHandler)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            try:
                env=os.environ | {'CASCADE_TEST_URL':f'http://127.0.0.1:{server.server_port}',
                                  'CASCADE_TEST_OUTBOX':str(Path(temp)/'outbox.json')}
                result=subprocess.run([GODOT,'--headless','--log-file',str(Path(temp)/'godot.log'),'--path',str(ROOT),
                                       '--script','tests/test_form_backend_client.gd','--','--offline-tests'],
                                      env=env,capture_output=True,text=True,timeout=45)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertTrue(LostFormAckHandler.lost_ack)
                print(result.stdout.strip())
                with service.store.connect() as db:
                    self.assertEqual(db.execute('SELECT status FROM sessions').fetchone()[0],'completed')
                    for table,count in [('round_evaluations',36),('scenario_reasoning',12),('private_events',36),('interventions',0)]:
                        self.assertEqual(db.execute(f'SELECT count(*) FROM {table}').fetchone()[0],count)
                    self.assertNotIn('HTTP_FORM_CANARY',' '.join(row[0] for row in db.execute('SELECT body FROM game_events')))
                    self.assertIn('HTTP_FORM_CANARY',db.execute('SELECT body FROM scenario_reasoning LIMIT 1').fetchone()[0])
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
