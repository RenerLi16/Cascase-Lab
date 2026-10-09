"""PostgreSQL storage (e.g. AWS RDS). Same transactional semantics as SQLiteStorage.

Requires `psycopg[binary,pool]` (see backend/requirements.txt). Local development keeps
using SQLite, which needs no extra packages.
"""
from contextlib import contextmanager
import time
from urllib.parse import parse_qs, urlsplit

from .storage import SQLStorage, PUBLIC_SCHEMA

LOCAL_HOSTS = {'localhost', '127.0.0.1', '::1', ''}
INSECURE_SSLMODES = {'disable', 'allow', 'prefer'}
DEFAULT_ROOT_CERT = 'backend/certs/rds-global-bundle.pem'

SCHEMA = '''
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL, token_hash TEXT NOT NULL,
  metadata TEXT NOT NULL, status TEXT NOT NULL, updated DOUBLE PRECISION NOT NULL);
CREATE TABLE IF NOT EXISTS receipts (
  session_id TEXT NOT NULL, event_id TEXT NOT NULL, seq INTEGER NOT NULL,
  digest TEXT NOT NULL, channel TEXT NOT NULL,
  PRIMARY KEY(session_id,event_id), UNIQUE(session_id,seq));
CREATE TABLE IF NOT EXISTS game_events (session_id TEXT, event_id TEXT, body TEXT NOT NULL, PRIMARY KEY(session_id,event_id));
CREATE TABLE IF NOT EXISTS private_events (session_id TEXT, event_id TEXT, body TEXT NOT NULL, PRIMARY KEY(session_id,event_id));
CREATE TABLE IF NOT EXISTS audit_events (session_id TEXT, event_id TEXT, body TEXT NOT NULL, PRIMARY KEY(session_id,event_id));
CREATE TABLE IF NOT EXISTS interventions (
  session_id TEXT, scenario TEXT, round INTEGER, request TEXT NOT NULL,
  audit TEXT NOT NULL, status TEXT NOT NULL, result TEXT, error TEXT,
  requested DOUBLE PRECISION NOT NULL, finished DOUBLE PRECISION,
  PRIMARY KEY(session_id,scenario,round));
CREATE TABLE IF NOT EXISTS lifecycle (session_id TEXT, status TEXT, recorded DOUBLE PRECISION);
CREATE INDEX IF NOT EXISTS lifecycle_recorded ON lifecycle(recorded);
CREATE INDEX IF NOT EXISTS interventions_requested ON interventions(requested);
'''


class Row(tuple):
    """Supports row[0] and row['column'], like sqlite3.Row."""
    def __new__(cls, names, values):
        row = super().__new__(cls, values)
        row._names = names
        return row

    def __getitem__(self, key):
        if isinstance(key, str): return tuple.__getitem__(self, self._names.index(key))
        return tuple.__getitem__(self, key)

    def keys(self): return list(self._names)


def row_factory(cursor):
    names = [c.name for c in cursor.description] if cursor.description else []
    return lambda values: Row(names, values)


class Connection:
    """Thin adapter so shared SQL can use '?' placeholders on both databases."""
    def __init__(self, conn): self.conn = conn

    def execute(self, sql, params=()):
        return self.conn.execute(sql.replace('?', '%s'), params)


def connection_options(url, root_cert=DEFAULT_ROOT_CERT):
    """Refuse unencrypted or unverified connections to any non-local database host."""
    parts = urlsplit(url)
    if parts.scheme not in ('postgres', 'postgresql'):
        raise ValueError('CASCADE_DATABASE_URL must be a postgresql:// URL')
    query = {k: v[-1] for k, v in parse_qs(parts.query).items()}
    if (parts.hostname or '') in LOCAL_HOSTS:
        return {}
    mode = query.get('sslmode', 'verify-full')
    if mode in INSECURE_SSLMODES:
        raise ValueError('Remote databases require sslmode=verify-full (or require)')
    options = {'sslmode': mode}
    if mode in ('verify-ca', 'verify-full') and 'sslrootcert' not in query:
        options['sslrootcert'] = root_cert
    return options


class PostgresStorage(SQLStorage):
    def __init__(self, url, root_cert=DEFAULT_ROOT_CERT, max_size=12):
        from psycopg_pool import ConnectionPool
        options = connection_options(url, root_cert)
        if options.get('sslrootcert'):
            import os
            if not os.path.exists(options['sslrootcert']):
                raise ValueError('Database CA bundle not found; see docs/DEPLOYMENT.md')
        self.pool = ConnectionPool(url, min_size=1, max_size=max_size, open=True, timeout=15,
                                   kwargs=options | {'row_factory': row_factory, 'connect_timeout': 10},
                                   check=ConnectionPool.check_connection)
        with self.connect() as db:
            for statement in filter(str.strip, (SCHEMA + PUBLIC_SCHEMA).split(';')):
                db.execute(statement)
            # A crash or redeploy may have happened after the provider accepted a request. Never regenerate.
            db.execute("UPDATE interventions SET status='failed', error='backend_interrupted', finished=? WHERE status='pending' AND requested<?", (time.time(),time.time()-180))

    @contextmanager
    def connect(self):
        with self.pool.connection() as conn:
            with conn.transaction():
                yield Connection(conn)

    @staticmethod
    def begin_write(db, key):
        # Serializes writers per session, matching SQLite's single-writer guarantees for one session.
        db.execute('SELECT pg_advisory_xact_lock(hashtext(?))', (key,))

    def close(self): self.pool.close()
