from copy import deepcopy
import json
from pathlib import Path
from backend.validation import RULES, legal_actions

ROOT = Path(__file__).resolve().parents[2]
SCENARIO = 'riverside_01_v2'


def context():
    s = json.loads((ROOT/'scenarios/scenario_01.json').read_text())
    c = dict(round=1, remaining_budget=6,
             shelters={sid:dict(overrun=False,known_pressure=-1,verified_history=[],monitored=False,shielded=False) for sid in s['shelter_names']},
             roads={'-'.join(edge):dict(endpoints=edge,closed=False) for edge in s['edges']},
             depots=s['supply_amounts'],previous_actions=[],public_reports=[s['public_intel'][0]],
             responses=[dict(danger_location='E',preferred_action='VERIFY',action_target='E',confidence=4,reason='gather more information') for _ in range(3)],
             public_rules=deepcopy(RULES)|{'exposure_progresses':True},
             display_names=s['shelter_names']|{'-'.join(e):'Road '+'-'.join(e) for e in s['edges']})
    c['legal_actions'] = legal_actions(c)
    return c


def start(sid='synthetic-test', condition='DIRECT_RECOMMENDATION'):
    return {'session_id':sid,'client_secret':'1'*64,'metadata':{
        'schema_version':5,'game_version':'cascade-development-5','scenario_order':[SCENARIO],
        'order_source':'configured','condition':condition,'participant_slots':['P1','P2','P3'],
        'record_mode':'synthetic-development','research_eligible':False}}


def event(seq=1, channel='game'):
    return dict(event_id=f'event-{seq}',seq=seq,channel=channel,scenario=SCENARIO,round=1,
                phase='DISCUSSION',condition='DIRECT_RECOMMENDATION',payload={'type':'SYNTHETIC_EVENT'})


def output(condition='DIRECT_RECOMMENDATION'):
    first = '建议: 可考虑核实 E 地点的状态。这项行动目前有可用的物资通路，能够帮助检验现有判断，但结果仍然只是本轮的一个观测。'
    if condition == 'CONSTRUCTIVE_DISSENT': first = '讨论: 初始意见一致时，可以检查大家是否都把较早的观察当作现在的事实。共同判断可能依赖相同假设，不必据此人为制造分歧。'
    return {'lines':[first,'依据: 已核实记录只说明当时的情况，未知状态仍然未知。当前公开信息不足以确定所有地点的真实状态。',
                     '核对: 请比较信息的时间与适用范围，并检查道路是否开放、物资是否充足。这个判断没有观察讨论过程，也没有访问隐藏状态。'],
            'action':'VERIFY' if condition == 'DIRECT_RECOMMENDATION' else '',
            'target':'E' if condition == 'DIRECT_RECOMMENDATION' else '',
            'referenced_locations':['E'] if condition == 'DIRECT_RECOMMENDATION' else []}
