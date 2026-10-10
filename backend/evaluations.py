"""Proposed post-outcome instruments; never part of the provider context contract."""
import json
from datetime import datetime
from pathlib import Path
from .validation import keys, require, string, integer

INSTRUMENTS = json.loads((Path(__file__).resolve().parents[1] / 'scripts/evaluation_instruments.json').read_text())
CHANNELS = {'round_evaluation': 'round_evaluations', 'scenario_reasoning': 'scenario_reasoning'}
FORM_SCHEMA = '''
CREATE TABLE IF NOT EXISTS round_evaluations (
 session_id TEXT, event_id TEXT, scenario TEXT, round INTEGER, slot TEXT, body TEXT NOT NULL,
 PRIMARY KEY(session_id,scenario,round,slot), UNIQUE(session_id,event_id));
CREATE TABLE IF NOT EXISTS scenario_reasoning (
 session_id TEXT, event_id TEXT, scenario TEXT, round INTEGER, slot TEXT, body TEXT NOT NULL,
 PRIMARY KEY(session_id,scenario,round,slot), UNIQUE(session_id,event_id));
'''


def validate_form(sid, event, metadata):
    kind = event['channel']
    p = event['payload']
    # A recognized form must use its dedicated confidential channel.
    if kind not in CHANNELS:
        require(p.get('type') not in ('ROUND_EVALUATION', 'SCENARIO_REASONING'))
        return
    require(metadata['schema_version'] >= 9)
    instrument = INSTRUMENTS[kind]
    fields = 'type session_id scenario_id scenario_index slot condition instrument_version timing submitted_utc answers'
    keys(p, fields + (' round ai_display' if kind == 'round_evaluation' else ''))
    require(p['type'] == kind.upper() and p['session_id'] == sid and p['scenario_id'] == event['scenario'])
    integer(p['scenario_index'], 0, len(metadata['scenario_order'])-1)
    require(metadata['scenario_order'][int(p['scenario_index'])] == p['scenario_id'])
    require(p['slot'] in ('P1','P2','P3') and p['condition'] == event['condition'])
    require(p['instrument_version'] == instrument['version'] and p['timing'] == instrument['timing'])
    string(p['submitted_utc'], 40)
    try:
        require(p['submitted_utc'].endswith('Z'))
        datetime.fromisoformat(p['submitted_utc'].replace('Z', '+00:00'))
    except ValueError:
        require(False)
    require(event['phase'] == kind.upper() + '_FORM')
    ai = False
    if kind == 'round_evaluation':
        integer(p['round'],1,3)
        require(p['round'] == event['round'])
        d = p['ai_display']
        keys(d, 'status provider not_applicable_reason message_id message_version template_id displayed_utc')
        for value in d.values(): string(value, 300)
        require(d['status'] in ('provider_displayed','no_ai_condition','development_mock','ai_unavailable','not_displayed'))
        ai = d['status'] == 'provider_displayed'
        require(d['not_applicable_reason'] == ('' if ai else d['status']))
        if p['condition'] == 'NONE': require(d['status'] in ('no_ai_condition','not_displayed'))
        if ai: require(p['condition'] != 'NONE' and d['provider'] == 'qwen' and bool(d['displayed_utc']))
        if d['status'] == 'development_mock': require(d['provider'] == 'mock')
        if d['status'] == 'no_ai_condition': require(p['condition'] == 'NONE')
        if d['status'] == 'ai_unavailable': require(d['provider'] == 'unavailable')
    else:
        require(event['round'] == 3)
    questions = [q for q in instrument['questions'] if ai or not q.get('ai_only')]
    require(isinstance(p['answers'], dict) and set(p['answers']) == {q['id'] for q in questions})
    for q in questions:
        value = p['answers'][q['id']]
        if 'options' in q:
            require(isinstance(value, str) and value in q['options'])
            if q['id'] == 'influence' and not ai: require(value != 'AI message')
        else:
            string(value, q['max_length'])
            require(bool(value.strip()))


def require_complete_forms(db, sid, metadata):
    # Old contracts never required these forms. Local-only public sessions upload no
    # sensitive records; their completion barrier is enforced by the game client.
    if metadata['schema_version'] < 9 or not metadata.get('remote_records', False): return
    for kind, table in CHANNELS.items():
        expected = {(s, r, slot) for s in metadata['scenario_order']
                    for r in (range(1, 4) if kind == 'round_evaluation' else [3])
                    for slot in ('P1','P2','P3')}
        actual = {tuple(row) for row in db.execute(f'SELECT scenario,round,slot FROM {table} WHERE session_id=?', (sid,)).fetchall()}
        require(actual == expected, 'required_forms_incomplete')
