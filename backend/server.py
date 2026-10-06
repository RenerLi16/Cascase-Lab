"""Local development HTTP API. Run with python3 -m backend.server."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re
import hmac
import threading
from .config import Config
from .providers import Failure, MockProvider, QwenProvider, PROMPT_VERSION
from .storage import SQLiteStorage, Conflict, Unauthorized
from .validation import CONDITIONS, CONTEXT_VERSION, Invalid, canonical, identifier, integer, keys, require, validate_request

# Session protocol. Schema 6 sessions use the no-dispatch context (CONTEXT_VERSION).
SESSION_VERSION = (6, 'cascade-development-6')
# Older clients' queued records may still upload as historical records, but such sessions can
# never request a model intervention: their context contract carried narrative dispatches.
LEGACY_RECORD_VERSIONS = {(5, 'cascade-development-5')}

class Service:
    def __init__(self, config, store=None, provider=None):
        self.config = config
        self.store = store or make_store(config)
        self.provider = provider or (QwenProvider(config) if config.provider == 'qwen' else MockProvider(config))
        self.pool = ThreadPoolExecutor(max_workers=config.max_jobs, thread_name_prefix='interventions')
        self.slots = threading.BoundedSemaphore(config.max_jobs)
        self.lock = threading.Lock()

    def dispatch(self, method, path, body, token):
        if method == 'POST' and path == '/v1/sessions':
            # access_code is required only when the server is configured with one (public mode).
            require(isinstance(body, dict) and set(body) - {'access_code'} == {'session_id','client_secret','metadata'})
            if self.config.access_code:
                supplied = body.get('access_code')
                if not (isinstance(supplied, str) and hmac.compare_digest(supplied.encode(), self.config.access_code.encode())):
                    raise Unauthorized()
            identifier(body['session_id'])
            require(isinstance(body['client_secret'], str) and re.fullmatch('[a-f0-9]{64}', body['client_secret']))
            m = body['metadata']
            keys(m, 'schema_version game_version scenario_order order_source condition participant_slots record_mode research_eligible')
            version = (m['schema_version'], m['game_version'])
            require(version == SESSION_VERSION or version in LEGACY_RECORD_VERSIONS)
            require(m['record_mode'] == 'synthetic-development' and m['research_eligible'] is False)
            require(m['condition'] in CONDITIONS and m['participant_slots'] == ['P1','P2','P3'])
            require(isinstance(m['scenario_order'], list) and 1 <= len(m['scenario_order']) <= 4 and len(set(m['scenario_order'])) == len(m['scenario_order']))
            for s in m['scenario_order']: identifier(s)
            require(m['order_source'] in ('configured','development_default_not_randomized'))
            return 200, self.store.start(body['session_id'],body['client_secret'],m,self.config.max_sessions,self.config.max_daily_sessions) | {'provider':self.config.provider}
        match = re.fullmatch(r'/v1/sessions/([A-Za-z0-9_-]+)/(?:(events|completion)|interventions/([A-Za-z0-9_-]+)/([1-3]))',path)
        if not match: return 404, {'error':'not_found'}
        sid, resource, scenario, round_text = match.groups()
        meta = self.store.authorize(sid,token)
        if method == 'POST' and resource == 'events':
            keys(body, 'events'); require(isinstance(body['events'], list) and 1 <= len(body['events']) <= 100)
            for e in body['events']:
                keys(e, 'event_id seq channel scenario round phase condition payload')
                identifier(e['event_id']); integer(e['seq'],1,100000)
                require(e['channel'] in ('game','private','audit') and e['scenario'] in meta['scenario_order'])
                integer(e['round'],0,3)
                require(e['condition'] == meta['condition'] and isinstance(e['phase'],str) and len(e['phase']) <= 40)
                require(isinstance(e['payload'],dict) and len(canonical(e['payload'])) <= 64000)
            return 200, self.store.ingest(sid,body['events'])
        if method == 'POST' and resource == 'completion':
            keys(body, 'status last_seq'); integer(body['last_seq'],0,100000)
            require(body['status'] in ('completed','interrupted'))
            return 200, self.store.complete(sid,body['status'],body['last_seq'])
        if scenario:
            require(scenario in meta['scenario_order'])
            round_number = int(round_text)
            if method == 'POST':
                if (meta['schema_version'], meta['game_version']) != SESSION_VERSION:
                    # Legacy sessions keep uploading records; they never reach a provider again.
                    return 400, {'error':'deprecated_session_protocol'}
                try: validate_request(body)
                except Invalid as exc:
                    if exc.reason.startswith('deprecated'): return 400, {'error':exc.reason}
                    raise
                require(body['condition'] == meta['condition'] and body['condition'] != 'NONE')
                require(body['context']['round'] == round_number)
                with self.lock:
                    existing = self.store.job(sid,scenario,round_number)
                    if existing:
                        # Compare even completed/failed jobs, rejecting changed inputs for same identity,
                        # and never reuse a result produced under another prompt or context version.
                        self.store.create_job(sid,scenario,round_number,body,{})
                        if self._stale(sid,scenario,round_number,existing): raise Conflict()
                        return 200, existing
                    if self.store.recent_count('interventions') >= self.config.max_daily_interventions:
                        return 429, {'error':'daily_intervention_limit'}
                    if not self.slots.acquire(blocking=False): return 503, {'error':'generation_capacity'}
                    try:
                        self.store.create_job(sid,scenario,round_number,body,{
                            'prompt_version':PROMPT_VERSION,'context_version':CONTEXT_VERSION,'provider':self.config.provider,
                            'settings':self.config.settings(), 'region':self.config.region() or 'unconfigured', 'record_mode':'synthetic-development'})
                        self.pool.submit(self._generate,sid,scenario,round_number,body)
                    except Exception:
                        self.slots.release(); raise
            elif method != 'GET': return 405, {'error':'method_not_allowed'}
            result = self.store.job(sid,scenario,round_number)
            if result and (meta['schema_version'], meta['game_version']) == SESSION_VERSION and self._stale(sid,scenario,round_number,result):
                raise Conflict()
            return (200,result) if result else (404,{'error':'not_found'})
        return 405, {'error':'method_not_allowed'}

    def _stale(self, sid, scenario, round_number, job):
        """A completed message produced under another prompt or context version is never reused."""
        if job['status'] != 'completed': return False
        audit = self.store.job_audit(sid,scenario,round_number)
        return audit.get('prompt_version') != PROMPT_VERSION or audit.get('context_version') != CONTEXT_VERSION

    def _generate(self, sid, scenario, round_number, body):
        try:
            result = self.provider.generate(body['context'],body['condition'])
            self.store.finish_job(sid,scenario,round_number,result=result)
        except Failure as exc:
            self.store.finish_job(sid,scenario,round_number,error=exc.code,rejected=exc.rejected)
        except Exception:
            self.store.finish_job(sid,scenario,round_number,error='internal_provider_error')
        finally: self.slots.release()

    def close(self):
        self.pool.shutdown(wait=True)
        if hasattr(self.store, 'close'): self.store.close()


def make_store(config):
    if config.database_url:
        from .storage_pg import PostgresStorage
        return PostgresStorage(config.database_url, config.db_root_cert, max_size=config.max_jobs + 8)
    return SQLiteStorage(config.database)


def handler(service):
    class Handler(BaseHTTPRequestHandler):
        # Deliberately no request path, token, body, or provider exception logging.
        def log_message(self, *args): pass

        def setup(self):
            super().setup(); self.connection.settimeout(10)

        def do_OPTIONS(self): self.handle_api(preflight=True)
        def do_GET(self): self.handle_api()
        def do_POST(self): self.handle_api()

        def handle_api(self, preflight=False):
            origin = self.headers.get('Origin')
            status, response = 500, {'error':'internal_error'}
            allowed_origin = origin in service.config.origins
            failure = ''
            try:
                # Unauthenticated liveness probe for the host platform; reveals nothing.
                if self.path == '/healthz' and self.command == 'GET' and not preflight:
                    status,response = 200,{'ok':True}
                # CORS plus request rejection, including opaque/null origins; no wildcard.
                elif origin is not None and not allowed_origin:
                    status,response = 403,{'error':'origin_denied'}
                elif self.headers.get('Host','').split(':')[0] not in service.config.allowed_hosts:
                    status,response = 403,{'error':'host_denied'}
                elif preflight:
                    status,response = 204,{}
                else:
                    body = None
                    if self.command == 'POST':
                        require(self.headers.get('Content-Type','').split(';')[0] == 'application/json')
                        require(not self.headers.get('Transfer-Encoding'))
                        length = int(self.headers.get('Content-Length','0'))
                        require(0 < length <= service.config.max_body)
                        raw = self.rfile.read(length); require(len(raw) == length)
                        body = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(Invalid()))
                    auth = self.headers.get('Authorization','')
                    token = auth[7:] if auth.startswith('Bearer ') else ''
                    status,response = service.dispatch(self.command,self.path,body,token)
            except Unauthorized: status,response = 401,{'error':'unauthorized'}
            except Conflict: status,response = 409,{'error':'conflicting_reuse'}
            except (Invalid, ValueError, KeyError, TypeError, OverflowError): status,response = 400,{'error':'invalid_request'}
            except Exception as exc:
                status,response = 500,{'error':'internal_error'}
                failure = type(exc).__name__ + (f" sqlstate={exc.sqlstate}" if getattr(exc,'sqlstate',None) else '')
            if status >= 400:
                # Diagnostics only: route shape, status, error code and exception class. No IDs, bodies,
                # tokens, access codes or origins are logged.
                route = re.sub(r'/v1/sessions/[^/]+', '/v1/sessions/:id', self.path.split('?')[0])
                route = re.sub(r'/interventions/[^/]+/[^/]+$', '/interventions/:scenario/:round', route)
                print(f"request_failed {self.command} {route[:80]} status={status} error={response.get('error','')} {failure}".rstrip(), flush=True)
            data = canonical(response).encode()
            try:
                self.send_response(status)
                self.send_header('Content-Type','application/json; charset=utf-8')
                self.send_header('Cache-Control','no-store')
                self.send_header('X-Content-Type-Options','nosniff')
                if allowed_origin:
                    self.send_header('Access-Control-Allow-Origin',origin)
                    self.send_header('Vary','Origin')
                    self.send_header('Access-Control-Allow-Methods','GET,POST,OPTIONS')
                    self.send_header('Access-Control-Allow-Headers','Authorization,Content-Type')
                self.send_header('Content-Length',str(0 if status == 204 else len(data)))
                self.end_headers()
                if status != 204: self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError): pass
    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port',type=int,default=None)
    args = parser.parse_args()
    config = Config.from_env()
    port = args.port or config.port
    service = Service(config)
    server = ThreadingHTTPServer((config.host,port),handler(service))
    server.daemon_threads = True
    def maintenance():
        while not stopped.wait(30): service.store.expire()
    stopped = threading.Event()
    threading.Thread(target=maintenance,daemon=True).start()
    # Never print credentials, database URLs or the access code.
    mode = 'public' if config.public() else 'local-only'
    print(f'Cascade synthetic-development backend on {config.host}:{port} ({mode}); provider={config.provider}; model={config.model if config.provider == "qwen" else "development-mock"}; storage={service.store.describe()}',flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        stopped.set(); server.server_close(); service.close()

if __name__ == '__main__': main()
