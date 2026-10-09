"""Explicit public projection; reject extra fields at every model-input boundary."""
import json
import re

CONDITIONS = ('NONE', 'DIRECT_RECOMMENDATION', 'CONSTRUCTIVE_DISSENT')
# Support-context contract. cascade-context-2 retired the narrative dispatches that context v1
# carried as public_reports. The game sends this version with every intervention request.
CONTEXT_VERSION = 'cascade-context-3'
# Field names from the retired narrative-report contract. Any occurrence, at any depth, is
# rejected explicitly instead of being dropped or forwarded to a model.
# cascade-context-3 adds each road's public bridge flag (bridge-only closure).
DEPRECATED_FIELDS = frozenset({'public_reports', 'published_reports', 'public_intel', 'reports', 'report',
                               'intel', 'dispatch', 'dispatches', 'field_dispatch', 'field_dispatches'})
ACTIONS = ('VERIFY', 'MONITOR', 'SHIELD', 'ISOLATE', 'WAIT')
REASONS = ('', 'visible outbreak', 'suspected hidden exposure', 'protect important route',
           'protect supply access', 'gather more information', 'prevent cascade', 'other / uncertain')
RULES = {
    'costs': {'VERIFY': 1, 'MONITOR': 1, 'SHIELD': 1, 'ISOLATE': 2, 'WAIT': 0},
    'observations': 'known_pressure=-1 means unknown. Verification is dated evidence, not current pressure. Monitoring reveals no installation baseline, only later changes.',
    'effects': 'VERIFY reveals a snapshot. MONITOR reports later changes. SHIELD blocks incoming infection for this round only and does not cure exposure. ISOLATE (shown to players as Close bridge) closes a bridge permanently for both infection and supplies; pay one unit to each endpoint. WAIT spends nothing.',
    'access': 'Deliver from stocked depots along open roads through functioning shelters. Overrun shelters cannot receive or relay supplies. Already monitored/shielded targets cannot repeat that action. Only roads with bridge=true can be isolated; ordinary roads always stay open. Closed bridges cannot be isolated again.',
    'resolution': 'Overrun shelters transmit along open roads at resolution. Existing exposure progresses when exposure_progresses is true. Incoming infection is simultaneous; newly overrun shelters transmit next round.',
}

class Invalid(ValueError):
    def __init__(self, reason='invalid_request'):
        self.reason = reason
        super().__init__(reason)


def require(ok, reason='invalid_request'):
    if not ok:
        raise Invalid(reason)


def keys(value, expected):
    require(isinstance(value, dict) and set(value) == set(expected.split()))


def integer(value, low, high):
    require(type(value) in (int, float) and int(value) == value and low <= value <= high)


def string(value, maximum=4000):
    require(isinstance(value, str) and len(value) <= maximum)


def identifier(value):
    require(isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,80}', value))


def canonical(value):
    # Godot serializes whole-valued JSON numbers as floats. Normalize before hashing.
    def normalize(v):
        if isinstance(v, dict): return {k: normalize(x) for k, x in v.items()}
        if isinstance(v, list): return [normalize(x) for x in v]
        if isinstance(v, float) and v.is_integer(): return int(v)
        return v
    return json.dumps(normalize(value), ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


def reject_deprecated(value, depth=0):
    require(depth <= 12)
    if isinstance(value, dict):
        for key, item in value.items():
            require(key not in DEPRECATED_FIELDS, 'deprecated_report_field')
            reject_deprecated(item, depth + 1)
    elif isinstance(value, list):
        for item in value: reject_deprecated(item, depth + 1)


def validate_request(body):
    """Intervention request envelope: condition, the current context version, and the context."""
    reject_deprecated(body)
    require(isinstance(body, dict) and set(body) == {'condition', 'context_version', 'context'}, 'deprecated_or_malformed_request')
    require(body['context_version'] == CONTEXT_VERSION, 'deprecated_context_version')
    require(body['condition'] in CONDITIONS)
    validate_context(body['context'])
    return body


def validate_context(c):
    # Explicit allowlist: network, supplies, actions, dated observations, anonymous structured
    # responses, public rules and display names. Nothing else may reach a provider.
    reject_deprecated(c)
    keys(c, 'round remaining_budget shelters roads depots previous_actions responses public_rules display_names legal_actions')
    integer(c['round'], 1, 3)
    integer(c['remaining_budget'], 0, 6)
    require(isinstance(c['shelters'], dict) and len(c['shelters']) == 8)
    for sid, s in c['shelters'].items():
        require(re.fullmatch('[A-H]', sid))
        keys(s, 'overrun known_pressure verified_history monitored shielded')
        for flag in ('overrun', 'monitored', 'shielded'): require(type(s[flag]) is bool)
        integer(s['known_pressure'], -1, 2)
        require(isinstance(s['verified_history'], list) and len(s['verified_history']) <= 18)
        for h in s['verified_history']:
            keys(h, 'round pressure'); integer(h['round'], 1, c['round']); integer(h['pressure'], 0, 2)
    require(isinstance(c['roads'], dict) and len(c['roads']) <= 28)
    for rid, r in c['roads'].items():
        keys(r, 'endpoints closed bridge')
        require(type(r['closed']) is bool and type(r['bridge']) is bool and isinstance(r['endpoints'], list) and len(r['endpoints']) == 2)
        require(all(x in c['shelters'] for x in r['endpoints']) and rid == '-'.join(r['endpoints']))
    require(isinstance(c['depots'], dict) and len(c['depots']) == 2)
    for sid, amount in c['depots'].items():
        require(sid in c['shelters']); integer(amount, 0, 6)
    require(sum(c['depots'].values()) == c['remaining_budget'])
    require(isinstance(c['display_names'], dict) and set(c['display_names']) == set(c['shelters']) | set(c['roads']))
    for name in c['display_names'].values(): string(name, 100)
    keys(c['public_rules'], 'costs observations effects access resolution exposure_progresses')
    require({k:v for k,v in c['public_rules'].items() if k != 'exposure_progresses'} == RULES)
    require(type(c['public_rules']['exposure_progresses']) is bool)
    require(isinstance(c['responses'], list) and len(c['responses']) == 3)
    for r in c['responses']:
        keys(r, 'danger_location preferred_action action_target confidence reason')
        require(r['danger_location'] in c['display_names'] and r['reason'] in REASONS)
        validate_action(r['preferred_action'], r['action_target'], c)
        integer(r['confidence'], 1, 5)
    require(isinstance(c['previous_actions'], list) and len(c['previous_actions']) <= 18)
    for a in c['previous_actions']:
        keys(a, 'type target round cost depots'); validate_action(a['type'], a['target'], c)
        integer(a['round'], 1, c['round']); require(a['cost'] == RULES['costs'][a['type']])
        require(isinstance(a['depots'], list) and len(a['depots']) <= 2 and all(d in c['depots'] for d in a['depots']))
    require(isinstance(c['legal_actions'], list) and c['legal_actions'] == legal_actions(c))
    return c


def validate_action(action, target, c):
    require(action in ACTIONS)
    # Only bridges can be closed: an ISOLATE target must be a road flagged bridge=true.
    require(target == 'NONE' if action == 'WAIT' else (target in c['roads'] and c['roads'][target]['bridge']) if action == 'ISOLATE' else target in c['shelters'])


def legal_actions(c):
    def funded(target):
        available = []
        for depot, amount in c['depots'].items():
            if amount <= 0 or c['shelters'][depot]['overrun']: continue
            seen, todo = set(), [depot]
            while todo:
                node = todo.pop()
                if node in seen or c['shelters'][node]['overrun']: continue
                seen.add(node)
                for r in c['roads'].values():
                    if not r['closed'] and node in r['endpoints']: todo.extend(x for x in r['endpoints'] if x not in seen)
            if target in seen: available.append(depot)
        return available
    actions = []
    for sid in sorted(c['shelters']):
        if not funded(sid): continue
        for action, flag in (('VERIFY', None), ('MONITOR', 'monitored'), ('SHIELD', 'shielded')):
            if flag and c['shelters'][sid][flag]: continue
            actions.append({'action': action, 'target': sid})
    for rid in sorted(c['roads']):
        r = c['roads'][rid]
        if r['bridge'] and not r['closed'] and any(a != b or c['depots'][a] >= 2 for a in funded(r['endpoints'][0]) for b in funded(r['endpoints'][1])):
            actions.append({'action': 'ISOLATE', 'target': rid})
    return actions + [{'action': 'WAIT', 'target': 'NONE'}]


def validate_output(o, c, condition):
    # Reason codes name the failed rule only; they never contain model text.
    require(isinstance(o, dict), 'not_object')
    require(set(o) == {'lines', 'action', 'target', 'referenced_locations'}, 'wrong_fields')
    require(isinstance(o['lines'], list) and len(o['lines']) == 3, 'not_three_lines')
    lines, normalized = [], False
    for line in o['lines']:
        require(isinstance(line, str) and '\n' not in line.strip(), 'line_not_single_string')
        line = line.strip()
        # Compatibility: a full-width heading colon is converted to the ASCII colon the UI splits on.
        if ':' not in line and '\uff1a' in line:
            line = line.replace('\uff1a', ':', 1); normalized = True
        require(':' in line, 'line_missing_heading_colon')
        require(len(line) <= 180, 'line_too_long')
        require(re.search(r'[\u4e00-\u9fff]', line), 'line_not_chinese')
        lines.append(line)
    text = '\n'.join(lines)
    require(90 <= len(text), 'text_too_short')
    require(len(text) <= 420, 'text_too_long')
    require(isinstance(o['referenced_locations'], list) and len(o['referenced_locations']) <= 16, 'referenced_locations_invalid')
    require(all(isinstance(x, str) and x in c['display_names'] for x in o['referenced_locations']), 'unknown_referenced_location')
    # IDs in prose must also be recognized and declared. Semantic correctness still needs review.
    mentioned = set(re.findall(r'(?<![A-Za-z])([A-Z](?:-[A-Z])?)(?![A-Za-z])', text))
    require(mentioned <= set(c['display_names']), 'unknown_location_in_text')
    require(mentioned <= set(o['referenced_locations']), 'undeclared_location_in_text')
    if condition == 'DIRECT_RECOMMENDATION':
        require(o['action'] in ACTIONS, 'unknown_action')
        require({'action':o['action'], 'target':o['target']} in c['legal_actions'], 'action_not_legal')
    else:
        require(o['action'] == '' and o['target'] == '', 'dissent_selected_action')
    return dict(text=text, action=o['action'], target=o['target'], format_normalized=normalized)
