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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['setup', 'summary'])
    parser.add_argument('--host', required=True)
    parser.add_argument('--port', type=int, default=5432)
    parser.add_argument('--database', default='cascade_lab')
    parser.add_argument('--admin-user', default='postgres')
    parser.add_argument('--ca', default=DEFAULT_ROOT_CERT)
    args = parser.parse_args()
    {'setup': setup, 'summary': summary}[args.command](args)


if __name__ == '__main__':
    main()
