"""Retired narrative dispatches never reach a model: contract, boundaries, versions, and the
final serialized Qwen request (captured by a fake HTTP transport; no Alibaba traffic)."""
from copy import deepcopy
from dataclasses import replace
from io import BytesIO
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from backend.config import Config
from backend.providers import COMMON, ROLES, PROMPT_VERSION, Failure, MockProvider, QwenProvider
from backend.server import Service, handler
from backend.storage import Conflict
from backend.validation import CONTEXT_VERSION, RULES, Invalid, canonical, legal_actions, validate_context, validate_request
from .fixtures import ROOT, SCENARIO, context, event, legacy_dispatches, output, request, start

GODOT = os.getenv('GODOT_BIN') or shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
ENDPOINT = 'https://test-workspace.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions'
PERMITTED = {'round', 'remaining_budget', 'shelters', 'roads', 'depots', 'previous_actions', 'responses',
             'public_rules', 'display_names', 'legal_actions'}
# Distinctive vocabulary of the retired dispatches (English and Chinese).
NARRATIVE_TERMS = ('distress', 'radio', 'recording', 'patrol', 'photo', 'surveillance', 'dispatcher', 'alarm',
                   'archived', 'caller', 'footage', 'shouting', 'equipment test', 'health check', 'inventory',
                   '求救', '无线电', '中继', '录音', '录像', '巡逻', '照片', '报告', '警报', '调度', '呼叫')
# Researcher-only and hidden-state field names (the system prompt itself may say "hidden pressure").
HIDDEN = ('zombie_pressure', 'ground_truth', 'original_source', 'initial_pressures', 'timeline', 'initial_exposure', 'hidden_state')


def legacy_texts():
    return [r['text'] for r in legacy_dispatches()]


def with_observations(c=None):
    """A later-round context with real, permitted evidence: dated Verify and a Monitor alert."""
    c = deepcopy(c or context())
    c['round'] = 2; c['remaining_budget'] = 4; c['depots'] = {'A': 1, 'H': 3}
    c['shelters']['E'].update(overrun=True, known_pressure=2, verified_history=[{'round': 1, 'pressure': 1}], monitored=True)
    c['shelters']['F'].update(known_pressure=1, monitored=True)
    c['previous_actions'] = [{'type': 'VERIFY', 'target': 'E', 'round': 1, 'cost': 1, 'depots': ['A']},
                             {'type': 'MONITOR', 'target': 'E', 'round': 1, 'cost': 1, 'depots': ['A']}]
    c['legal_actions'] = legal_actions(c)
    return c


def reply_for(payload):
    """A structurally valid Qwen reply chosen from the request itself (role and legal actions)."""
    system = payload['messages'][0]['content']
    snapshot = json.loads(payload['messages'][1]['content'])['public_snapshot']
    if system.endswith(ROLES['DIRECT_RECOMMENDATION']):
        choice = next(a for a in snapshot['legal_actions'] if a['action'] != 'WAIT')
        target = choice['target']
        lines = [f'建议: 可考虑对 {target} 采取这项行动。这项行动目前有可用的物资通路，能够帮助检验现有判断，但结果仍然只是本轮的一个观测。',
                 '依据: 已核实记录只说明当时的情况，未知状态仍然未知。当前公开信息不足以确定所有地点的真实状态。',
                 '核对: 请比较信息的时间与适用范围，并检查道路是否开放、物资是否充足。这个判断没有观察讨论过程，也没有访问隐藏状态。']
        body = {'lines': lines, 'action': choice['action'], 'target': target, 'referenced_locations': [target]}
    else:
        body = output('CONSTRUCTIVE_DISSENT')
    return {'choices': [{'finish_reason': 'stop', 'message': {'content': json.dumps(body, ensure_ascii=False)}}],
            'usage': {'prompt_tokens': 1, 'completion_tokens': 1, 'total_tokens': 2}}


class RecordingTransport:
    """Fake HTTP transport: records the exact serialized request that would go to Qwen."""
    def __init__(self):
        self.requests, self.lock = [], threading.Lock()

    def open(self, request, timeout):
        with self.lock: self.requests.append(request)
        return BytesIO(json.dumps(reply_for(json.loads(request.data)), ensure_ascii=False).encode())


def qwen_config(**changes):
    return Config(provider='qwen', allow_live=True, api_key='SECRET-CANARY', endpoint=ENDPOINT, **changes)


def assert_clean_payload(case, raw, extra_forbidden=()):
    for text in legacy_texts(): case.assertNotIn(text, raw)
    for term in ('public_reports', 'public_intel', 'published_reports', 'PUBLIC_INTEL', 'dispatch') + HIDDEN + tuple(extra_forbidden):
        case.assertNotIn(term, raw)


class ContractTests(unittest.TestCase):
    def test_current_context_has_only_permitted_fields(self):
        c = context()
        self.assertEqual(set(c), PERMITTED)
        self.assertEqual(validate_context(c), c)
        self.assertEqual(validate_request(request()), request())

    def test_deprecated_report_fields_rejected_at_any_depth(self):
        mutations = (lambda c: c.update(public_reports=[legacy_dispatches()[0]]),
                     lambda c: c.update(public_intel=[]),
                     lambda c: c.update(published_reports=[]),
                     lambda c: c['shelters']['E'].update(reports=['x']),
                     lambda c: c['responses'][0].update(dispatch='x'),
                     lambda c: c['public_rules'].update(intel='x'))
        for mutate in mutations:
            c = context(); mutate(c)
            with self.assertRaises(Invalid) as raised: validate_context(c)
            self.assertEqual(raised.exception.reason, 'deprecated_report_field')

    def test_request_envelope_requires_current_context_version(self):
        old_envelope = {'condition': 'DIRECT_RECOMMENDATION', 'context': context()}
        with self.assertRaisesRegex(Invalid, 'deprecated_or_malformed_request'): validate_request(old_envelope)
        with self.assertRaisesRegex(Invalid, 'deprecated_context_version'):
            validate_request(request() | {'context_version': 'cascade-context-1'})
        legacy = {'condition': 'DIRECT_RECOMMENDATION', 'context': context() | {'public_reports': legacy_dispatches()[:1]}}
        with self.assertRaisesRegex(Invalid, 'deprecated_report_field'): validate_request(legacy)
        self.assertEqual(CONTEXT_VERSION, 'cascade-context-3')

    def test_prompts_examples_mocks_and_templates_contain_no_narrative_clues(self):
        sources = {'system prompt': COMMON, **{f'role {k}': v for k, v in ROLES.items()},
                   'mock provider': canonical(MockProvider(Config()).generate(context(), 'DIRECT_RECOMMENDATION'))
                                    + canonical(MockProvider(Config()).generate(context(), 'CONSTRUCTIVE_DISSENT')),
                   'fixture replies': canonical(output()) + canonical(output('CONSTRUCTIVE_DISSENT')),
                   'public rules': canonical(RULES) + (ROOT/'scripts/public_support_rules.json').read_text()}
        for path in ('scripts/support_library.gd', 'scripts/mock_support_provider.gd', 'scripts/support_context.gd',
                     'scripts/game_manager.gd', 'scripts/ui/presentation_text.gd', 'tests/capture_ui_screens.gd'):
            sources[path] = (ROOT/path).read_text()
        for name, text in sources.items():
            for sentence in legacy_texts(): self.assertNotIn(sentence, text, name)
            prose = ' '.join(re.findall(r'"[^"\n]*"|\'[^\'\n]*\'', text)) if name.endswith('.gd') else text
            for term in NARRATIVE_TERMS:
                self.assertNotIn(term, prose.lower(), f'{name}: {term}')
        self.assertNotIn('report', COMMON.lower())
        for scenario in sorted((ROOT/'scenarios').glob('scenario_0*.json')):
            self.assertNotIn('public_intel', json.loads(scenario.read_text()), scenario.name)


class ProviderBoundaryTests(unittest.TestCase):
    def test_direct_provider_calls_cannot_bypass_the_allowlist(self):
        for c in (context() | {'public_reports': legacy_dispatches()},
                  context() | {'public_intel': [{'round': 1, 'time': 'SENTINEL', 'text': 'SENTINEL'}]}):
            transport = RecordingTransport()
            for condition in ROLES:
                with self.assertRaisesRegex(Failure, 'invalid_context:deprecated_report_field'):
                    QwenProvider(qwen_config(), transport).generate(c, condition)
                with self.assertRaisesRegex(Failure, 'invalid_context:deprecated_report_field'):
                    MockProvider(Config()).generate(c, condition)
            self.assertEqual(transport.requests, [])
        with self.assertRaisesRegex(Failure, 'invalid_condition'): QwenProvider(qwen_config(), RecordingTransport()).generate(context(), 'NONE')

    def test_final_serialized_request_for_both_conditions(self):
        transport = RecordingTransport()
        c = with_observations()
        for condition in ('DIRECT_RECOMMENDATION', 'CONSTRUCTIVE_DISSENT'):
            result = QwenProvider(qwen_config(), transport).generate(c, condition)
            self.assertEqual((result['version'], result['context_version']), (PROMPT_VERSION, CONTEXT_VERSION))
        direct, dissent = [json.loads(r.data) for r in transport.requests]
        for payload, condition in ((direct, 'DIRECT_RECOMMENDATION'), (dissent, 'CONSTRUCTIVE_DISSENT')):
            raw = canonical(payload)
            assert_clean_payload(self, raw)
            self.assertEqual([m['role'] for m in payload['messages']], ['system', 'user'])
            self.assertEqual(payload['messages'][0]['content'], COMMON + ROLES[condition])
            snapshot = json.loads(payload['messages'][1]['content'])['public_snapshot']
            self.assertEqual(set(snapshot), PERMITTED)
            self.assertEqual(snapshot['shelters']['E']['verified_history'], [{'round': 1, 'pressure': 1}])
            self.assertTrue(snapshot['shelters']['E']['monitored'] and snapshot['shelters']['F']['known_pressure'] == 1)
            self.assertEqual([a['type'] for a in snapshot['previous_actions']], ['VERIFY', 'MONITOR'])
        # Identical permitted information; only the role instruction differs.
        self.assertEqual(direct['messages'][1], dissent['messages'][1])
        self.assertNotEqual(direct['messages'][0], dissent['messages'][0])
        self.assertNotIn('SECRET-CANARY', canonical(direct))


class VersionAndServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.cfg = Config(database=str(Path(self.temp.name)/'t.sqlite3'))
        self.calls = []
        provider = MockProvider(self.cfg)
        class Counting:
            def generate(inner, c, condition):
                self.calls.append(condition); return provider.generate(c, condition)
        self.service = Service(self.cfg, provider=Counting())

    def tearDown(self): self.service.close(); self.temp.cleanup()

    def session(self, sid, schema=7, condition='DIRECT_RECOMMENDATION'):
        return self.service.dispatch('POST', '/v1/sessions', start(sid, condition, schema), '')[1]['credential']

    def post(self, sid, token, body, rnd=1):
        return self.service.dispatch('POST', f'/v1/sessions/{sid}/interventions/{SCENARIO}/{rnd}', body, token)

    def jobs(self):
        with self.service.store.connect() as db: return db.execute('SELECT count(*) FROM interventions').fetchone()[0]

    def test_deprecated_requests_rejected_before_any_provider_call(self):
        token = self.session('current')
        cases = {'deprecated_report_field': {'condition': 'DIRECT_RECOMMENDATION', 'context_version': CONTEXT_VERSION,
                                             'context': context() | {'public_reports': legacy_dispatches()}},
                 'deprecated_or_malformed_request': {'condition': 'DIRECT_RECOMMENDATION', 'context': context()},
                 'deprecated_context_version': request() | {'context_version': 'cascade-context-1'}}
        for code, body in cases.items():
            self.assertEqual(self.post('current', token, body), (400, {'error': code}))
        legacy_envelope = {'condition': 'DIRECT_RECOMMENDATION', 'context': context() | {'public_reports': legacy_dispatches()}}
        self.assertEqual(self.post('current', token, legacy_envelope), (400, {'error': 'deprecated_report_field'}))
        self.service.pool.shutdown(wait=True)
        self.assertEqual((self.calls, self.jobs()), ([], 0))

    def test_legacy_sessions_upload_records_but_never_reach_a_provider(self):
        # Schema 5 (narrative dispatches) and schema 6 (any road closable, no bridge flag).
        for schema in (5, 6):
            sid = f'legacy-{schema}'
            token = self.session(sid, schema=schema)
            prefix = '/v1/sessions/' + sid
            self.assertEqual(self.service.dispatch('POST', prefix+'/events', {'events': [event()]}, token)[0], 200)
            for body in (request(), {'condition': 'DIRECT_RECOMMENDATION', 'context': context() | {'public_reports': legacy_dispatches()}}):
                self.assertEqual(self.post(sid, token, body), (400, {'error': 'deprecated_session_protocol'}))
            self.assertEqual(self.service.dispatch('POST', prefix+'/completion', {'status': 'completed', 'last_seq': 1}, token)[0], 200)
        for schema in (4, 8):
            with self.assertRaises(Invalid): self.session(f'unknown-{schema}', schema=schema)
        self.service.pool.shutdown(wait=True)
        self.assertEqual((self.calls, self.jobs()), ([], 0))

    def test_cached_old_version_results_never_reused(self):
        token = self.session('current')
        old_body = {'condition': 'DIRECT_RECOMMENDATION', 'context': context() | {'public_reports': legacy_dispatches()[:1]}}
        store = self.service.store
        store.create_job('current', SCENARIO, 1, old_body, {'prompt_version': 'cascade-zh-2'})
        store.finish_job('current', SCENARIO, 1, result={'text': 'OLD-CACHED-DISPATCH-MESSAGE', 'version': 'cascade-zh-2'})
        with self.assertRaises(Conflict): self.post('current', token, request())
        with self.assertRaises(Conflict): self.service.dispatch('GET', f'/v1/sessions/current/interventions/{SCENARIO}/1', None, token)
        # Identical current-format request whose stored result came from another prompt version.
        store.create_job('current', SCENARIO, 2, request(c=context() | {'round': 2}), {'prompt_version': 'cascade-zh-2', 'context_version': CONTEXT_VERSION})
        store.finish_job('current', SCENARIO, 2, result={'text': 'OLD-PROMPT-MESSAGE'})
        with self.assertRaises(Conflict): self.post('current', token, request(c=context() | {'round': 2}), rnd=2)
        # A fresh request is generated under the current versions and can be retried.
        self.assertEqual(self.post('current', token, request(c=context() | {'round': 3}), rnd=3)[0], 200)
        self.service.pool.shutdown(wait=True)
        status, job = self.post('current', token, request(c=context() | {'round': 3}), rnd=3)
        self.assertEqual((status, job['message']['context_version'], job['message']['version']), (200, CONTEXT_VERSION, PROMPT_VERSION))
        self.assertEqual(store.job_audit('current', SCENARIO, 3)['context_version'], CONTEXT_VERSION)
        self.assertEqual(self.calls, ['DIRECT_RECOMMENDATION'])

    def test_no_ai_makes_zero_provider_calls(self):
        token = self.session('none', condition='NONE')
        with self.assertRaises(Invalid): self.post('none', token, request('NONE'))
        self.service.pool.shutdown(wait=True)
        self.assertEqual((self.calls, self.jobs()), ([], 0))


@unittest.skipUnless(Path(GODOT).exists(), 'Godot binary not installed')
class EndToEndOutboundTests(unittest.TestCase):
    """Real Godot game and HTTP client -> real backend -> QwenProvider -> recording transport."""

    def test_new_sessions_send_no_dispatch_data_to_qwen(self):
        with tempfile.TemporaryDirectory() as temp:
            transport = RecordingTransport()
            cfg = qwen_config(database=str(Path(temp)/'test.sqlite3'))
            service = Service(Config(database=cfg.database, public_records=True, public_ai=True, public_policy_id='synthetic-test-only', public_round_interval=0), provider=QwenProvider(cfg, transport))
            server = ThreadingHTTPServer(('127.0.0.1', 0), handler(service))
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            report_path = Path(temp)/'report.json'
            try:
                env = os.environ | {'CASCADE_TEST_URL': f'http://127.0.0.1:{server.server_port}',
                                    'CASCADE_TEST_OUTBOX': str(Path(temp)/'outbox.json'), 'CASCADE_TEST_REPORT': str(report_path)}
                result = subprocess.run([GODOT, '--headless', '--log-file', str(Path(temp)/'godot.log'), '--path', str(ROOT),
                                         '--script', 'tests/test_outbound_context.gd', '--', '--offline-tests'],
                                        env=env, capture_output=True, text=True, timeout=180)
                self.assertEqual(result.returncode, 0, result.stdout[-3000:] + result.stderr[-3000:])
                self.assertIn(' 0 failures', result.stdout)
                print(next(l for l in result.stdout.splitlines() if 'OUTBOUND CONTEXT CLIENT TESTS' in l))
                report = json.loads(report_path.read_text())
                sentinels = (report['sentinel'], report['sentinel_time'])
                timeline = [e['text'] for e in json.loads((ROOT/'scenarios/scenario_01.json').read_text())['ground_truth_timeline']]
                # Two AI conditions x two rounds reach the provider; No-AI adds nothing.
                self.assertEqual(len(transport.requests), 4)
                payloads = {}
                for r in transport.requests:
                    raw = r.data.decode()
                    assert_clean_payload(self, raw, sentinels + tuple(timeline))
                    self.assertEqual(r.get_header('Authorization'), 'Bearer SECRET-CANARY')
                    payload = json.loads(raw)
                    condition = 'DIRECT_RECOMMENDATION' if payload['messages'][0]['content'].endswith(ROLES['DIRECT_RECOMMENDATION']) else 'CONSTRUCTIVE_DISSENT'
                    self.assertEqual(payload['messages'][0]['content'], COMMON + ROLES[condition])
                    snapshot = json.loads(payload['messages'][1]['content'])['public_snapshot']
                    self.assertEqual(set(snapshot), PERMITTED)
                    payloads[(condition, snapshot['round'])] = payload
                self.assertEqual(sorted(payloads), [('CONSTRUCTIVE_DISSENT', 1), ('CONSTRUCTIVE_DISSENT', 2), ('DIRECT_RECOMMENDATION', 1), ('DIRECT_RECOMMENDATION', 2)])
                for rnd in (1, 2):
                    self.assertEqual(payloads[('DIRECT_RECOMMENDATION', rnd)]['messages'][1], payloads[('CONSTRUCTIVE_DISSENT', rnd)]['messages'][1])
                later = json.loads(payloads[('DIRECT_RECOMMENDATION', 2)]['messages'][1]['content'])['public_snapshot']
                self.assertEqual(later['shelters']['E']['verified_history'], [{'round': 1, 'pressure': 1}])
                self.assertTrue(later['shelters']['E']['monitored'] and later['shelters']['E']['overrun'])
                self.assertEqual([(a['type'], a['target']) for a in later['previous_actions']], [('VERIFY', 'E'), ('MONITOR', 'E')])
                # The game's frozen context is exactly what was sent.
                for session in report['sessions']:
                    if session['condition'] == 'NONE': continue
                    for rnd, ctx in enumerate(session['contexts'], start=1):
                        sent = json.loads(payloads[(session['condition'], rnd)]['messages'][1]['content'])['public_snapshot']
                        self.assertEqual(canonical(ctx), canonical(sent))
                if os.getenv('CASCADE_PAYLOAD_SAMPLE'):
                    sample = deepcopy(payloads[('DIRECT_RECOMMENDATION', 2)])
                    sample['messages'][1]['content'] = json.loads(sample['messages'][1]['content'])
                    Path(os.environ['CASCADE_PAYLOAD_SAMPLE']).write_text(json.dumps(
                        {'note': 'Synthetic request body captured by the fake transport (no Alibaba call). The user message content is a JSON string in the real request and is shown parsed here. The Authorization header is not part of the body and is omitted.',
                         'endpoint': ENDPOINT, 'body': sample}, ensure_ascii=False, indent=2))
                with service.store.connect() as db:
                    sessions = [json.loads(row[0]) for row in db.execute('SELECT metadata FROM sessions')]
                    self.assertEqual(len(sessions), 3)
                    self.assertTrue(all(m['game_version'] == 'cascade-public-9' and m['schema_version'] == 9 for m in sessions))
                    self.assertEqual(db.execute("SELECT count(*) FROM sessions WHERE status='interrupted' OR status='completed'").fetchone()[0], 3)
                    stored = ' '.join(row[0] for table in ('game_events', 'audit_events', 'private_events') for row in db.execute(f'SELECT body FROM {table}'))
                    self.assertIn('cascade-context-3', stored)
                    for term in sentinels + tuple(legacy_texts()) + ('PUBLIC_INTEL_SHOWN', 'public_intel', 'public_reports'):
                        self.assertNotIn(term, stored)
                    audits = [json.loads(row[0]) for row in db.execute('SELECT audit FROM interventions')]
                    self.assertEqual(len(audits), 4)
                    self.assertTrue(all(a['context_version'] == CONTEXT_VERSION and a['prompt_version'] == PROMPT_VERSION for a in audits))
                    count, unique = db.execute('SELECT count(*),count(DISTINCT event_id) FROM receipts').fetchone()
                    self.assertEqual(count, unique)
            finally:
                server.shutdown(); server.server_close(); thread.join(); service.close()


if __name__ == '__main__': unittest.main()
