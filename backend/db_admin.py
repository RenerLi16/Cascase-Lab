"""One-time RDS setup and record checks, run from your own computer.

  pip install -r backend/requirements.txt
  python3 -m backend.fetch_rds_ca
  python3 -m backend.db_admin setup   --host YOUR-DB.xxxx.rds.amazonaws.com
  python3 -m backend.db_admin summary --host YOUR-DB.xxxx.rds.amazonaws.com

Passwords are typed at hidden prompts (never arguments, files or logs). `setup` creates a
limited `cascade_app` login that can only use the app's database; the backend creates its
own tables on first start. `summary` prints record counts only, never record contents.
"""
import argparse
import getpass
import json
from pathlib import Path

from .storage_pg import DEFAULT_ROOT_CERT


def connect(args, user, password):
    import psycopg
    return psycopg.connect(host=args.host, port=args.port, dbname=args.database, user=user, password=password,
                           sslmode='verify-full', sslrootcert=args.ca, connect_timeout=15)


def setup(args):
    from psycopg import sql
    admin_password = getpass.getpass(f'RDS master password for {args.admin_user}: ')
    if admin_password != admin_password.strip():
        print('Note: removed spaces at the start/end of the master password you entered.')
        admin_password = admin_password.strip()
    print(f'(master password entered: {len(admin_password)} characters)')
    app_password = getpass.getpass('New password for cascade_app (16+ characters; letters, digits, - and _): ')
    if len(app_password) < 16:
        raise SystemExit(f'That password has {len(app_password)} characters; it needs at least 16. Nothing was changed.')
    if not all(c.isascii() and (c.isalnum() or c in '-_') for c in app_password):
        raise SystemExit('Use only letters, digits, - and _ (other symbols break the connection URL). Nothing was changed.')
    if app_password != getpass.getpass('Repeat cascade_app password: '):
        raise SystemExit('The two passwords did not match. Nothing was changed.')
    import psycopg
    try:
        admin = connect(args, args.admin_user, admin_password)
    except psycopg.OperationalError as exc:
        if 'password authentication failed' in str(exc):
            raise SystemExit('The database rejected the MASTER password (first prompt). Check it, or reset it in '
                             'AWS: Modify -> new master password -> Apply immediately, then wait for "Available". '
                             'Nothing was changed.')
        if 'timeout' in str(exc).lower():
            raise SystemExit('Could not reach the database: check the security group allows your current IP (My IP).')
        raise
    with admin as db:
        exists = db.execute("SELECT 1 FROM pg_roles WHERE rolname='cascade_app'").fetchone()
        verb = 'ALTER' if exists else 'CREATE'
        db.execute(sql.SQL(verb + ' ROLE cascade_app WITH LOGIN PASSWORD {}').format(sql.Literal(app_password)))
        db.execute(sql.SQL('GRANT CONNECT ON DATABASE {} TO cascade_app').format(sql.Identifier(args.database)))
        db.execute('GRANT USAGE, CREATE ON SCHEMA public TO cascade_app')
        db.execute(sql.SQL('REVOKE ALL ON DATABASE {} FROM PUBLIC').format(sql.Identifier(args.database)))
    print(f"cascade_app is ready ({'password updated' if exists else 'created'}). Build CASCADE_DATABASE_URL as described in docs/DEPLOYMENT.md.")


def summary(args):
    password = getpass.getpass('cascade_app password: ')
    with connect(args, 'cascade_app', password) as db:
        if not db.execute("SELECT to_regclass('public.sessions')").fetchone()[0]:
            raise SystemExit('No tables yet: start the backend once so it can create them.')
        for label, query in (
                ('sessions by status', 'SELECT status, count(*) FROM sessions GROUP BY status ORDER BY status'),
                ('saved events (game / private / audit)', 'SELECT (SELECT count(*) FROM game_events), (SELECT count(*) FROM private_events), (SELECT count(*) FROM audit_events)'),
                ('AI interventions by status', 'SELECT status, coalesce(error, \'-\'), count(*) FROM interventions GROUP BY 1, 2 ORDER BY 1')):
            print(label + ':', [tuple(row) for row in db.execute(query).fetchall()])


def _iso(ts):
    import datetime
    return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S') if ts else ''


def _events(db, table):
    rows = db.execute(f'SELECT e.session_id, r.seq, e.body FROM {table} e JOIN receipts r '
                      'ON r.session_id = e.session_id AND r.event_id = e.event_id ORDER BY e.session_id, r.seq').fetchall()
    for sid, seq, body in rows:
        yield sid, seq, json.loads(body)


def export(args):
    """Write every saved record to readable CSV files (and an Excel workbook when openpyxl is available)."""
    import csv
    import datetime
    password = getpass.getpass('cascade_app password: ')
    sheets = {}
    with connect(args, 'cascade_app', password) as db:
        if not db.execute("SELECT to_regclass('public.sessions')").fetchone()[0]:
            raise SystemExit('No tables yet: start the backend once so it can create them.')
        rows = []
        for sid, metadata, status, updated in db.execute('SELECT id, metadata, status, updated FROM sessions ORDER BY updated'):
            m = json.loads(metadata)  # login hashes are never exported
            rows.append([sid, status, m.get('condition'), ' > '.join(m.get('scenario_order', [])), m.get('order_source'),
                         m.get('record_mode'), m.get('research_eligible'), m.get('game_version'), _iso(updated)])
        sheets['sessions'] = (['session_id', 'status', 'condition', 'scenario_order', 'order_source', 'record_mode',
                               'research_eligible', 'game_version', 'last_activity_utc'], rows)
        rows = []
        for sid, seq, e in _events(db, 'game_events'):
            p = e['payload']
            rows.append([sid, seq, e['scenario'], e['round'], e['phase'], e['condition'], p.get('type'), p.get('target'),
                         json.dumps(p.get('old_value'), ensure_ascii=False), json.dumps(p.get('new_value'), ensure_ascii=False),
                         p.get('elapsed_ms'), p.get('timestamp_utc'), json.dumps(p.get('metadata', {}), ensure_ascii=False)])
        sheets['game_events'] = (['session_id', 'seq', 'scenario', 'round', 'phase', 'condition', 'event_type', 'target',
                                  'old_value', 'new_value', 'elapsed_ms', 'timestamp_utc', 'details'], rows)
        rows = []
        for sid, seq, e in _events(db, 'private_events'):
            p = e['payload']; r = p.get('response', {})
            rows.append([sid, seq, e['scenario'], e['round'], e['condition'], p.get('slot'), r.get('danger_location'),
                         r.get('preferred_action'), r.get('action_target'), r.get('confidence'), r.get('reason')])
        sheets['private_responses'] = (['session_id', 'seq', 'scenario', 'round', 'condition', 'player_slot', 'danger_location',
                                        'preferred_action', 'action_target', 'confidence', 'reason'], rows)
        rows = []
        for sid, seq, e in _events(db, 'audit_events'):
            p = dict(e['payload']); kind = p.pop('type', '')
            if kind == 'CLIENT_HEARTBEAT' and not args.heartbeats: continue
            rows.append([sid, seq, e['scenario'], e['round'], e['phase'], e['condition'], kind,
                         p.get('displayed_text', ''), p.get('displayed_utc', p.get('requested_utc', p.get('received_utc', ''))),
                         json.dumps(p, ensure_ascii=False)])
        sheets['audit_events'] = (['session_id', 'seq', 'scenario', 'round', 'phase', 'condition', 'event_type',
                                   'displayed_text', 'time_utc', 'details'], rows)
        rows = []
        for sid, scen, rnd, request, audit, status, result, error, requested, finished in db.execute(
                'SELECT session_id, scenario, round, request, audit, status, result, error, requested, finished '
                'FROM interventions ORDER BY requested'):
            req = json.loads(request); aud = json.loads(audit); res = json.loads(result) if result else {}
            usage = res.get('usage', {})
            rows.append([sid, scen, rnd, req.get('condition'), status, error or '', res.get('provider', aud.get('provider')),
                         res.get('model', (aud.get('settings') or {}).get('model')), aud.get('prompt_version'), aud.get('region'),
                         res.get('text', ''), res.get('action', ''), res.get('target', ''), usage.get('prompt_tokens'),
                         usage.get('completion_tokens'), _iso(requested), _iso(finished), aud.get('rejected_output', '')])
        sheets['ai_interventions'] = (['session_id', 'scenario', 'round', 'condition', 'status', 'error', 'provider', 'model',
                                       'prompt_version', 'region', 'message_text', 'action', 'target', 'prompt_tokens',
                                       'completion_tokens', 'requested_utc', 'finished_utc', 'rejected_model_output'], rows)
        rows = [[sid, st, _iso(t)] for sid, st, t in db.execute('SELECT session_id, status, recorded FROM lifecycle ORDER BY recorded')]
        sheets['lifecycle'] = (['session_id', 'status', 'time_utc'], rows)
    folder = Path(args.out) / datetime.datetime.now().strftime('%Y-%m-%d_%H%M%S')
    folder.mkdir(parents=True, exist_ok=True)
    for name, (header, rows) in sheets.items():
        with open(folder / f'{name}.csv', 'w', newline='', encoding='utf-8-sig') as f:  # BOM so Excel shows Chinese text
            w = csv.writer(f); w.writerow(header); w.writerows(rows)
    try:
        from openpyxl import Workbook
        wb = Workbook(); wb.remove(wb.active)
        for name, (header, rows) in sheets.items():
            ws = wb.create_sheet(name[:31]); ws.append(header)
            for row in rows: ws.append([str(v)[:32000] if isinstance(v, str) else v for v in row])
            ws.freeze_panes = 'A2'
        wb.save(folder / 'cascade_export.xlsx')
        workbook = ' and cascade_export.xlsx'
    except ImportError:
        workbook = ''
    for name, (_, rows) in sheets.items(): print(f'{name}: {len(rows)} rows')
    print(f'Saved CSV files{workbook} in {folder}. These contain private study responses: keep them private.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['setup', 'summary', 'export'])
    parser.add_argument('--host', required=True)
    parser.add_argument('--port', type=int, default=5432)
    parser.add_argument('--database', default='cascade_lab')
    parser.add_argument('--admin-user', default='postgres')
    parser.add_argument('--ca', default=DEFAULT_ROOT_CERT)
    parser.add_argument('--out', default='exports', help='export: folder for the files (git-ignored)')
    parser.add_argument('--heartbeats', action='store_true', help='export: include 30-second client heartbeats')
    args = parser.parse_args()
    {'setup': setup, 'summary': summary, 'export': export}[args.command](args)


if __name__ == '__main__':
    main()
