"""Storage boundary: transactional operations, replaceable by a cloud implementation."""
from contextlib import contextmanager
import hashlib
import hmac
import json
import os
import secrets
from pathlib import Path
import sqlite3
import time
from typing import Protocol
from .validation import Invalid, canonical

SCHEMA_VERSION = 1

class Conflict(Exception): pass
class Unauthorized(Exception): pass
class Limited(Invalid):
    def __init__(self, code):
        super().__init__(code)
        self.code = code

PUBLIC_SCHEMA = """
CREATE TABLE IF NOT EXISTS service_keys (name TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS public_sessions (session_id TEXT PRIMARY KEY, created DOUBLE PRECISION NOT NULL, expires DOUBLE PRECISION NOT NULL);
CREATE TABLE IF NOT EXISTS ai_reservations (session_id TEXT, scenario TEXT, round INTEGER, attempts INTEGER NOT NULL, recorded DOUBLE PRECISION NOT NULL, PRIMARY KEY(session_id,scenario,round));
"""


class Storage(Protocol):
    def start(self, sid, secret, metadata, maximum): ...
    def authorize(self, sid, token): ...
    def ingest(self, sid, events): ...
    def create_job(self, sid, scenario, round_number, request, audit): ...
    def job(self, sid, scenario, round_number): ...
    def job_audit(self, sid, scenario, round_number): ...
    def finish_job(self, sid, scenario, round_number, result, error, rejected): ...
    def complete(self, sid, status, last_seq): ...

class SQLStorage:
    """Shared transactional logic. Subclasses supply connect(), begin_write() and the schema."""

    @staticmethod
    def digest(text): return hashlib.sha256(text.encode()).hexdigest()

    def start(self, sid, secret, metadata, maximum=1000, daily_max=None, public_config=None):
        token = hmac.new(secret.encode(), ('cascade-session:'+sid).encode(), hashlib.sha256).hexdigest()
        with self.connect() as db:
            self.begin_write(db, 'cascade-global-admission')
            if public_config:
                db.execute("INSERT INTO service_keys VALUES ('public-session-signing',?) ON CONFLICT(name) DO NOTHING", (secrets.token_hex(32),))
                key = db.execute("SELECT value FROM service_keys WHERE name='public-session-signing'").fetchone()[0]
                token = hmac.new(key.encode(), ('public:'+sid+':'+self.digest(secret)).encode(), hashlib.sha256).hexdigest()
            row = db.execute('SELECT * FROM sessions WHERE id=?', (sid,)).fetchone()
            if row:
                if not hmac.compare_digest(row['secret_hash'], self.digest(secret)): raise Unauthorized()
                existing_metadata = json.loads(row['metadata'])
                if public_config:
                    # Configuration changes must not change an already-issued identity or policy.
                    for key in ('remote_records', 'public_ai', 'policy_id'):
                        metadata[key] = existing_metadata.get(key)
                if row['metadata'] != canonical(metadata): raise Conflict()
            else:
                if db.execute('SELECT count(*) FROM sessions').fetchone()[0] >= maximum: raise Limited('session_limit')
                if daily_max is not None and db.execute("SELECT count(*) FROM lifecycle WHERE status='started' AND recorded>?", (time.time()-86400,)).fetchone()[0] >= daily_max:
                    raise Limited('daily_session_limit')
                if public_config and db.execute("SELECT count(*) FROM lifecycle WHERE status='started' AND recorded>?", (time.time()-60,)).fetchone()[0] >= public_config.max_minute_sessions:
                    raise Limited('session_rate_limit')
                if public_config:
                    db.execute('INSERT INTO public_sessions VALUES (?,?,?)', (sid,time.time(),time.time()+public_config.public_session_seconds))
                db.execute('INSERT INTO sessions VALUES (?,?,?,?,?,?)',
                           (sid,self.digest(secret),self.digest(token),canonical(metadata),'active',time.time()))
                db.execute('INSERT INTO lifecycle VALUES (?,?,?)', (sid,'started',time.time()))
        return {'session_id':sid, 'credential':token, 'research_eligible':False}

    def authorize(self, sid, token):
        with self.connect() as db:
            row = db.execute('SELECT * FROM sessions WHERE id=?', (sid,)).fetchone()
            if not row or not hmac.compare_digest(row['token_hash'], self.digest(token)): raise Unauthorized()
            return json.loads(row['metadata'])

    def ingest(self, sid, events):
        with self.connect() as db:
            self.begin_write(db, sid)
            for e in events:
                body = canonical(e)
                digest = self.digest(body)
                old = db.execute('SELECT * FROM receipts WHERE session_id=? AND (event_id=? OR seq=?)', (sid,e['event_id'],e['seq'])).fetchall()
                if old:
                    if len(old) != 1 or old[0]['digest'] != digest: raise Conflict()
                    continue
                db.execute('INSERT INTO receipts VALUES (?,?,?,?,?)', (sid,e['event_id'],e['seq'],digest,e['channel']))
                table = {'game':'game_events', 'private':'private_events', 'audit':'audit_events'}[e['channel']]
                db.execute(f'INSERT INTO {table} VALUES (?,?,?)', (sid,e['event_id'],body))
            db.execute('UPDATE sessions SET updated=? WHERE id=?', (time.time(),sid))
        return {'acknowledged':[e['event_id'] for e in events]}

    def create_job(self, sid, scenario, round_number, request, audit, limits=None, public=False):
        with self.connect() as db:
            self.begin_write(db, 'cascade-global-admission')
            existing = db.execute('SELECT request FROM interventions WHERE session_id=? AND scenario=? AND round=?', (sid,scenario,round_number)).fetchone()
            if existing:
                if existing['request'] != canonical(request): raise Conflict()
                return False
            if limits:
                now = time.time()
                if db.execute('SELECT count(*) FROM interventions WHERE requested>?', (now-86400,)).fetchone()[0] >= limits.max_daily_interventions:
                    raise Limited('daily_intervention_limit')
                reserved = db.execute('SELECT coalesce(sum(attempts),0) FROM ai_reservations WHERE recorded>?', (now-86400,)).fetchone()[0]
                if reserved + limits.attempts > limits.max_daily_ai_attempts:
                    raise Limited('ai_request_cap')
                if db.execute("SELECT count(*) FROM interventions WHERE status='pending'").fetchone()[0] >= limits.max_jobs:
                    raise Limited('generation_capacity')
                if public:
                    row = db.execute('SELECT status FROM sessions WHERE id=?', (sid,)).fetchone()
                    scope = db.execute('SELECT expires FROM public_sessions WHERE session_id=?', (sid,)).fetchone()
                    if not scope or scope[0] <= now or row[0] != 'active': raise Limited('session_inactive')
                    if round_number > 1:
                        previous = db.execute('SELECT requested FROM interventions WHERE session_id=? AND scenario=? AND round=?', (sid,scenario,round_number-1)).fetchone()
                        if not previous or previous[0] + limits.public_round_interval > now: raise Limited('round_not_eligible')
                    latest = db.execute('SELECT max(requested) FROM interventions WHERE session_id=?', (sid,)).fetchone()[0]
                    if latest is not None and latest + limits.public_round_interval > now: raise Limited('round_not_eligible')
                db.execute('INSERT INTO ai_reservations VALUES (?,?,?,?,?)', (sid,scenario,round_number,limits.attempts,now))
            db.execute('INSERT INTO interventions VALUES (?,?,?,?,?,?,?,?,?,?)',
                       (sid,scenario,round_number,canonical(request),canonical(audit),'pending',None,None,time.time(),None))
        return True

    def job(self, sid, scenario, round_number):
        with self.connect() as db:
            row = db.execute('SELECT status,result,error FROM interventions WHERE session_id=? AND scenario=? AND round=?', (sid,scenario,round_number)).fetchone()
        if not row: return None
        # No input snapshot, credentials, private responses, or research logs returned.
        return {'intervention_id':f'{sid}:{scenario}:{round_number}', 'status':row['status'],
                'message':json.loads(row['result']) if row['result'] else None, 'error':row['error']}

    def job_audit(self, sid, scenario, round_number):
        """Server-side job metadata (versions, provider settings); never returned to clients."""
        with self.connect() as db:
            row = db.execute('SELECT audit FROM interventions WHERE session_id=? AND scenario=? AND round=?', (sid,scenario,round_number)).fetchone()
        return json.loads(row['audit']) if row else {}

    def finish_job(self, sid, scenario, round_number, result=None, error=None, rejected=None):
        with self.connect() as db:
            self.begin_write(db, sid)
            if rejected is not None:
                row = db.execute('SELECT audit FROM interventions WHERE session_id=? AND scenario=? AND round=?', (sid,scenario,round_number)).fetchone()
                if row:
                    audit = json.loads(row['audit']) | {'rejected_output': rejected}
                    db.execute("UPDATE interventions SET audit=? WHERE session_id=? AND scenario=? AND round=? AND status='pending'",
                               (canonical(audit),sid,scenario,round_number))
            db.execute("UPDATE interventions SET status=?, result=?, error=?, finished=? WHERE session_id=? AND scenario=? AND round=? AND status='pending'",
                       ('failed' if error else 'completed', canonical(result) if result else None,error,time.time(),sid,scenario,round_number))

    def complete(self, sid, status, last_seq):
        with self.connect() as db:
            self.begin_write(db, sid)
            count, maximum = db.execute('SELECT count(*),coalesce(max(seq),0) FROM receipts WHERE session_id=?', (sid,)).fetchone()
            if count != last_seq or maximum != last_seq: raise Conflict()
            old = db.execute('SELECT status FROM sessions WHERE id=?', (sid,)).fetchone()[0]
            if old == 'completed' and status != old: raise Conflict()
            if old != status: db.execute('INSERT INTO lifecycle VALUES (?,?,?)', (sid,status,time.time()))
            db.execute('UPDATE sessions SET status=?,updated=? WHERE id=?', (status,time.time(),sid))
        return {'status':status, 'last_seq':last_seq}

    def expire(self, seconds=300):
        with self.connect() as db:
            db.execute("UPDATE interventions SET status='failed', error='backend_interrupted', finished=? WHERE status='pending' AND requested<?", (time.time(),time.time()-180))
            rows = db.execute("SELECT id FROM sessions WHERE status='active' AND updated<? AND id NOT IN (SELECT session_id FROM public_sessions)", (time.time()-seconds,)).fetchall()
            for row in rows:
                db.execute("UPDATE sessions SET status='interrupted' WHERE id=?", (row['id'],))
                db.execute('INSERT INTO lifecycle VALUES (?,?,?)', (row['id'],'interrupted',time.time()))

    def recent_count(self, kind, seconds=86400):
        """Abuse/spend limits: sessions started or interventions requested in the window."""
        since = time.time() - seconds
        with self.connect() as db:
            if kind == 'sessions':
                return db.execute("SELECT count(*) FROM lifecycle WHERE status='started' AND recorded>?", (since,)).fetchone()[0]
            return db.execute('SELECT count(*) FROM interventions WHERE requested>?', (since,)).fetchone()[0]

    def describe(self): return type(self).__name__


class SQLiteStorage(SQLStorage):
    def __init__(self, path):
        self.path = path
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.executescript('''
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS sessions (
              id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL, token_hash TEXT NOT NULL,
              metadata TEXT NOT NULL, status TEXT NOT NULL, updated REAL NOT NULL);
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
              requested REAL NOT NULL, finished REAL,
              PRIMARY KEY(session_id,scenario,round));
            CREATE TABLE IF NOT EXISTS lifecycle (session_id TEXT, status TEXT, recorded REAL);
            ''')
            db.executescript(PUBLIC_SCHEMA)
            # A crash may have happened after the provider accepted a request. Never regenerate.
            db.execute("UPDATE interventions SET status='failed', error='backend_interrupted', finished=? WHERE status='pending' AND requested<?", (time.time(),time.time()-180))
        os.chmod(path, 0o600)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA synchronous=FULL')
        try:
            with db: yield db
        finally: db.close()

    @staticmethod
    def begin_write(db, key):
        # SQLite: one writer at a time for the whole database.
        db.execute('BEGIN IMMEDIATE')
