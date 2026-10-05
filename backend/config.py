from dataclasses import dataclass, field
import os
import re


@dataclass(frozen=True)
class Config:
    database: str = 'backend/data/development.sqlite3'
    provider: str = 'mock'
    endpoint: str = ''
    model: str = 'qwen-plus'
    api_key: str = field(default='', repr=False)
    allow_live: bool = False
    temperature: float = 0.3
    max_tokens: int = 700
    timeout: float = 30
    attempts: int = 2
    max_body: int = 262144
    max_jobs: int = 4
    max_sessions: int = 1000
    origins: tuple = ('http://localhost:8000', 'http://127.0.0.1:8000')
    # Online deployment (Render + RDS). Defaults keep the server local-only.
    database_url: str = field(default='', repr=False)
    db_root_cert: str = 'backend/certs/rds-global-bundle.pem'
    host: str = '127.0.0.1'
    port: int = 8787
    allowed_hosts: tuple = ('localhost', '127.0.0.1')
    access_code: str = field(default='', repr=False)
    max_daily_sessions: int = 50
    max_daily_interventions: int = 300

    @classmethod
    def from_env(cls):
        return cls(database=os.getenv('CASCADE_DB', cls.database),
                   provider=os.getenv('CASCADE_PROVIDER', 'mock'),
                   endpoint=os.getenv('QWEN_ENDPOINT', ''), model=os.getenv('QWEN_MODEL', 'qwen-plus'),
                   api_key=os.getenv('DASHSCOPE_API_KEY', ''), allow_live=os.getenv('CASCADE_ALLOW_LIVE') == '1',
                   temperature=float(os.getenv('QWEN_TEMPERATURE', '0.3')),
                   max_tokens=int(os.getenv('QWEN_MAX_TOKENS', '700')),
                   timeout=float(os.getenv('QWEN_TIMEOUT_SECONDS', '30')),
                   attempts=int(os.getenv('QWEN_MAX_ATTEMPTS', '2')),
                   max_body=int(os.getenv('CASCADE_MAX_BODY_BYTES', '262144')),
                   max_jobs=int(os.getenv('CASCADE_MAX_JOBS', '4')),
                   max_sessions=int(os.getenv('CASCADE_MAX_SESSIONS', '1000')),
                   origins=_split(os.getenv('CASCADE_ORIGINS', ','.join(cls.origins))),
                   database_url=os.getenv('CASCADE_DATABASE_URL', ''),
                   db_root_cert=os.getenv('CASCADE_DB_SSLROOTCERT', cls.db_root_cert),
                   host=os.getenv('CASCADE_HOST', cls.host),
                   port=int(os.getenv('PORT') or os.getenv('CASCADE_PORT') or cls.port),
                   allowed_hosts=_split(os.getenv('CASCADE_ALLOWED_HOSTS', ','.join(cls.allowed_hosts))),
                   access_code=os.getenv('CASCADE_ACCESS_CODE', '').strip(),
                   max_daily_sessions=int(os.getenv('CASCADE_MAX_DAILY_SESSIONS', cls.max_daily_sessions)),
                   max_daily_interventions=int(os.getenv('CASCADE_MAX_DAILY_INTERVENTIONS', cls.max_daily_interventions)))

    def __post_init__(self):
        if self.provider not in ('mock', 'qwen'):
            raise ValueError('CASCADE_PROVIDER must be mock or qwen')
        if not (0 <= self.temperature < 2 and 128 <= self.max_tokens <= 2048 and
                1 <= self.timeout <= 45 and 1 <= self.attempts <= 3 and
                1 <= self.max_jobs <= 16 and 1024 <= self.max_body <= 1048576):
            raise ValueError('Invalid request/generation limits')
        if not (1 <= self.max_daily_sessions <= 10000 and 1 <= self.max_daily_interventions <= 100000):
            raise ValueError('Invalid daily limits')
        if self.public():
            # Fail fast instead of exposing an unprotected or non-durable server to the internet.
            problems = []
            if len(self.access_code) < 12: problems.append('CASCADE_ACCESS_CODE (12+ characters)')
            if not self.database_url: problems.append('CASCADE_DATABASE_URL (durable database)')
            if set(self.allowed_hosts) <= {'localhost', '127.0.0.1'}: problems.append('CASCADE_ALLOWED_HOSTS (public host name)')
            if not self.origins or not all(o.startswith('https://') for o in self.origins): problems.append('CASCADE_ORIGINS (https:// origins only)')
            if problems: raise ValueError('Public mode requires: ' + ', '.join(problems))

    def public(self):
        return self.host not in ('127.0.0.1', 'localhost', '::1')

    # Workspace-specific OpenAI-compatible endpoints documented by Alibaba (checked 2026-10-04).
    # API keys are region-bound: the key must come from the same region as the endpoint.
    REGIONS = {'ap-southeast-1': 'Singapore', 'cn-beijing': 'China (Beijing)',
               'cn-hongkong': 'China (Hong Kong)', 'ap-northeast-1': 'Japan (Tokyo)'}

    def region(self):
        match = re.fullmatch(r'https://[a-zA-Z0-9-]+\.([a-z0-9-]+)\.maas\.aliyuncs\.com/compatible-mode/v1/chat/completions', self.endpoint)
        return self.REGIONS.get(match.group(1)) if match else None

    def qwen_ready(self):
        # Exact documented HTTP endpoint for a supported region; no redirects.
        return self.allow_live and bool(self.api_key) and bool(self.model) and self.region() is not None

    def settings(self):
        return dict(model=self.model, temperature=self.temperature, max_tokens=self.max_tokens,
                    enable_thinking=False, response_format={'type': 'json_object'}, stream=False)


def _split(value):
    return tuple(x.strip() for x in value.split(',') if x.strip())
