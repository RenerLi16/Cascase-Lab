"""Public demos use a closed, structured game vocabulary, never a free-text AI proxy."""
import json
from pathlib import Path
from .validation import keys, require

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = json.loads((ROOT / 'scenarios/registry.json').read_text())
SCENARIOS = {entry['id']: json.loads((ROOT / entry['path'].removeprefix('res://')).read_text())
             for entry in REGISTRY['scenarios']}
PUBLIC_VERSION = (9, 'cascade-public-9')
LEGACY_PUBLIC_VERSIONS = {(8, 'cascade-public-8')}


def validate_context(scenario, context):
    source = SCENARIOS[scenario]
    roads = {'-'.join(edge): edge for edge in source['edges']}
    require(set(context['roads']) == set(roads))
    for rid, edge in roads.items():
        road = context['roads'][rid]
        require(road['endpoints'] == edge and road['bridge'] == (rid in source['bridges']))
    require(set(context['depots']) == set(source['supply_amounts']))
    require(all(amount <= source['supply_amounts'][key] for key, amount in context['depots'].items()))
    names = source['shelter_names'] | {rid: ('Bridge ' if rid in source['bridges'] else 'Road ') + rid for rid in roads}
    require(context['display_names'] == names)


def reject_research_claims(value, depth=0):
    require(depth <= 12)
    # Event bodies are untrusted, too. Research status only comes from server metadata.
    if isinstance(value, dict):
        for key, item in value.items():
            if key in ('research_eligible', 'consented', 'enrolled', 'research_authorized'):
                require(item is False)
            if key == 'record_mode': require(item == 'public-demo')
            reject_research_claims(item, depth+1)
    elif isinstance(value, list):
        for item in value: reject_research_claims(item, depth+1)
