"""Bridge-only closure (cascade-context-3): only roads flagged bridge=true can be isolated."""
from copy import deepcopy
import unittest
from backend.providers import COMMON, PROMPT_VERSION
from backend.validation import CONTEXT_VERSION, RULES, Invalid, legal_actions, validate_context
from .fixtures import context

ORDINARY = 'B-E'   # Riverside ordinary road
BRIDGE = 'E-F'     # Riverside designated bridge


class BridgeRuleTests(unittest.TestCase):
    def test_versions_and_rules_name_the_bridge_rule(self):
        self.assertEqual((CONTEXT_VERSION, PROMPT_VERSION), ('cascade-context-3', 'cascade-zh-4'))
        self.assertIn('bridge=true', RULES['access'])
        self.assertIn('Close bridge', RULES['effects'])
        self.assertIn('bridge flags', COMMON)

    def test_fixture_marks_only_the_designated_bridge(self):
        c = context()
        self.assertEqual([r for r, v in c['roads'].items() if v['bridge']], [BRIDGE])
        validate_context(deepcopy(c))

    def test_legal_actions_list_bridges_only(self):
        isolations = [a['target'] for a in legal_actions(context()) if a['action'] == 'ISOLATE']
        self.assertEqual(isolations, [BRIDGE])

    def test_road_bridge_flag_is_required_and_boolean(self):
        for bad in ('missing', 'yes', 1, None):
            c = context()
            if bad == 'missing': del c['roads'][ORDINARY]['bridge']
            else: c['roads'][ORDINARY]['bridge'] = bad
            with self.assertRaises(Invalid): validate_context(c)

    def test_ordinary_road_isolation_rejected_in_responses_and_history(self):
        c = context()
        c['responses'][0] |= {'preferred_action': 'ISOLATE', 'action_target': ORDINARY}
        with self.assertRaises(Invalid): validate_context(c)
        c = context()
        c['responses'][0] |= {'preferred_action': 'ISOLATE', 'action_target': BRIDGE}
        validate_context(c)
        c = context() | {'round': 2}
        c['previous_actions'] = [{'type': 'ISOLATE', 'target': ORDINARY, 'round': 1, 'cost': 2, 'depots': ['A', 'A']}]
        with self.assertRaises(Invalid): validate_context(c)

    def test_tampered_legal_list_rejected(self):
        c = context()
        c['legal_actions'].insert(-1, {'action': 'ISOLATE', 'target': ORDINARY})
        with self.assertRaises(Invalid): validate_context(c)
        c = context()
        c['roads'][ORDINARY]['bridge'] = True  # flag edited without recomputing legal actions
        with self.assertRaises(Invalid): validate_context(c)


if __name__ == '__main__':
    unittest.main()
