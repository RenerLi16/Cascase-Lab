"""Full four-scenario post-outcome storage contract, synthetic only; no provider calls."""
from copy import deepcopy
from dataclasses import replace
import json
from pathlib import Path
import tempfile
import unittest
from backend.config import Config
from backend.server import Service
from backend.storage import Conflict
from backend.validation import Invalid, validate_request
from backend.evaluations import INSTRUMENTS, CHANNELS
from backend.public_play import SCENARIOS
from backend.db_admin import form_export_sheets, classify_export, csv_cell
from .test_public_play import public_start
from .fixtures import request


def records(sid='forms', condition='NONE', ai=False):
    events = []
    for index, scenario in enumerate(SCENARIOS):
        for rnd in range(1,4):
            kinds = ['round_evaluation'] + (['scenario_reasoning'] if rnd == 3 else [])
            for kind in kinds:
                instrument = INSTRUMENTS[kind]
                for slot in ('P1','P2','P3'):
                    answers = {q['id']: q['options'][0] if 'options' in q else 'Not sure'
                               for q in instrument['questions'] if ai or not q.get('ai_only')}
                    payload = dict(type=kind.upper(), session_id=sid, scenario_id=scenario, scenario_index=index,
                                   slot=slot, condition=condition, instrument_version=instrument['version'],
                                   timing=instrument['timing'], submitted_utc='2026-10-10T02:00:00Z', answers=answers)
                    if kind == 'round_evaluation':
                        status = 'provider_displayed' if ai else 'no_ai_condition'
                        payload.update(round=rnd, ai_display=dict(status=status, provider='qwen' if ai else 'none',
                            not_applicable_reason='' if ai else status, message_id='fixture', message_version='fixture-1',
                            template_id='fixture', displayed_utc='2026-10-10T01:59:00Z'))
                    seq = len(events)+1
                    events.append(dict(event_id=f'form-{seq}', seq=seq, channel=kind, scenario=scenario, round=rnd,
                                       phase=kind.upper()+'_FORM', condition=condition, payload=payload))
    return events


class EvaluationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.config = Config(database=str(Path(self.temp.name)/'forms.sqlite3'), public_records=True,
                             public_policy_id='synthetic-only')
        self.service = Service(self.config)
        self.token = self.start()

    def tearDown(self):
        self.service.close()
        self.temp.cleanup()

    def start(self, sid='forms', condition='NONE'):
        body = public_start(sid,condition)
        body['metadata'].update(schema_version=9,game_version='cascade-public-9',scenario_order=list(SCENARIOS))
        return self.service.dispatch('POST','/v1/public-sessions',body,'')[1]['credential']

    def post(self, resource, body, sid='forms', token=None):
        return self.service.dispatch('POST',f'/v1/sessions/{sid}/{resource}',body,token or self.token)

    def test_complete_four_scenario_counts_exports_and_idempotent_retry(self):
        events = records()
        with self.assertRaises(Invalid): self.post('completion',dict(status='completed',last_seq=0))
        self.post('events',dict(events=events[:-1]))
        with self.assertRaises(Invalid): self.post('completion',dict(status='completed',last_seq=47))
        result = self.post('events',dict(events=events[-1:]))
        self.assertEqual(result,self.post('events',dict(events=events[-1:])))
        self.assertEqual(self.post('completion',dict(status='completed',last_seq=48))[1]['status'],'completed')
        self.assertEqual(self.post('completion',dict(status='completed',last_seq=48))[1]['status'],'completed')
        with self.service.store.connect() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM receipts').fetchone()[0],48)
            self.assertEqual(db.execute('SELECT count(*) FROM game_events').fetchone()[0],0)
            self.assertEqual(db.execute('SELECT count(*) FROM private_events').fetchone()[0],0)
            sheets = form_export_sheets(db)
            self.assertEqual(len(sheets['round_evaluations'][1]),36)
            self.assertEqual(len(sheets['scenario_reasoning'][1]),12)
            classify_export(sheets,{'forms':{'record_mode':'public-demo','research_eligible':False}})
            for header, rows in sheets.values():
                self.assertIn('instrument_version',header)
                self.assertIn('timing',header)
                self.assertEqual(rows[0][-2:],['public-demo',False])
                self.assertIn('Not sure',rows[0])

    def test_duplicate_identity_and_atomic_retry(self):
        first = records()[0]
        self.post('events',dict(events=[first]))
        second = deepcopy(first); second.update(event_id='other',seq=2)
        with self.assertRaises(Conflict): self.post('events',dict(events=[second]))
        changed = deepcopy(first); changed['payload']['answers']['explanation']='changed'
        with self.assertRaises(Conflict): self.post('events',dict(events=[changed]))
        with self.service.store.connect() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM receipts').fetchone()[0],1)
        self.service.close(); self.service = Service(self.config)
        self.assertEqual(self.post('events',dict(events=[first]))[0],200)

    def test_validation_limits_and_wrong_channel(self):
        base = records()[0]
        for patch in [dict(explanation=''),dict(explanation='  \n'),dict(explanation='x'*601),dict(influence='AI message'),dict(ai_reliance='Not at all')]:
            bad=deepcopy(base); bad['payload']['answers'].update(patch)
            with self.assertRaises(Invalid): self.post('events',dict(events=[bad]))
        for key,value in [('timing','pre_outcome'),('instrument_version','unknown'),('session_id','other'),('scenario_index',2),('slot','P4')]:
            bad=deepcopy(base); bad['payload'][key]=value
            with self.assertRaises(Invalid): self.post('events',dict(events=[bad]))
        bad=deepcopy(base); bad['channel']='game'
        with self.assertRaises(Invalid): self.post('events',dict(events=[bad]))
        base['payload']['answers']['explanation']='好'*600
        self.assertEqual(self.post('events',dict(events=[base]))[0],200)
        reasoning=next(e for e in records() if e['channel']=='scenario_reasoning')
        reasoning['seq']=2
        reasoning['payload']['answers']['strategy']='x'*1001
        with self.assertRaises(Invalid): self.post('events',dict(events=[reasoning]))
        reasoning['payload']['answers']['strategy']='x'*1000
        self.assertEqual(self.post('events',dict(events=[reasoning]))[0],200)

    def test_ai_eligibility_and_model_input_exclusion(self):
        token=self.start('ai','DIRECT_RECOMMENDATION')
        e=records('ai','DIRECT_RECOMMENDATION',True)[0]
        e['payload']['answers']['ai_usefulness']='Unable to judge'
        self.assertEqual(self.post('events',dict(events=[e]),'ai',token)[0],200)
        for provider in ['mock','unavailable','none']:
            bad=deepcopy(e);bad['payload']['ai_display']['provider']=provider
            with self.assertRaises(Invalid): self.post('events',dict(events=[bad]),'ai',token)
        for field in ('round_evaluations','scenario_reasoning','post_form_draft'):
            body=request();body['context'][field]=e['payload']['answers']
            with self.assertRaises(Invalid):validate_request(body)

    def test_local_only_and_legacy_contracts_preserved(self):
        self.service.close();self.service=Service(replace(self.config,public_records=False))
        token=self.start('local')
        self.assertEqual(self.post('events',dict(events=records('local')),'local',token)[0],403)
        self.assertEqual(self.post('completion',dict(status='completed',last_seq=0),'local',token)[0],200)
        old=public_start('legacy','NONE')
        token=self.service.dispatch('POST','/v1/public-sessions',old,'')[1]['credential']
        self.assertEqual(self.post('completion',dict(status='completed',last_seq=0),'legacy',token)[0],200)

    def test_export_older_database_without_form_tables(self):
        sheets = form_export_sheets(None, set())
        self.assertEqual(set(sheets),set(CHANNELS.values()))
        self.assertTrue(all(not rows for _,rows in sheets.values()))

    def test_free_text_csv_is_not_executed_as_a_formula(self):
        for text in ('=1+1','+1','-1','@SUM(A1)', '  =1'):
            self.assertEqual(csv_cell(text), "'" + text)
        self.assertEqual(csv_cell('Nothing'), 'Nothing')
        self.assertEqual(csv_cell(-1), -1)
