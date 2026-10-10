# Public Play session flow — 2026-10-09

Regular **Play** enters the existing introduction/practice/normal flow immediately. There is no code field, Paste button, intermediate setup screen, replacement password, or embedded backend secret. Replay practice is available on the title after practice. The title design, language/motion controls, Dev Mode password digest and sandbox behaviour are unchanged. The Participant preset still disables Dev Mode and still requires explicit `practice_approved` configuration before enabling practice.

## Release dependency

**The new web build requires this matching backend release.** Release the backend first, then re-export the game with `tools/build_web_release.py`. Public bootstrap uses schema 9 / `cascade-public-9` (with historical schema-8 record recovery retained); a prior backend cannot create it. No deployment, commit, push, cloud configuration change or paid model call was made for this change.

Startup creates three additive tables (`service_keys`, `public_sessions`, `ai_reservations`) on SQLite or PostgreSQL. Keep the database and its server signing key across restarts. No existing records are deleted or migrated into public sessions. Back up the database using the existing operator process before a release. PostgreSQL uses the same transactional implementation with a global admission advisory lock; the current local verification used SQLite, not a live PostgreSQL/RDS instance.

## Authorization and recovery

- `POST /v1/public-sessions` accepts a random session ID, a per-session random bootstrap secret and a strict game metadata envelope. Both random values are saved locally before network activity. Retrying the same bootstrap returns the same credential; changed metadata conflicts and a different secret cannot claim the identity.
- The credential is issued using a database-held random server signing key. It is not derivable from client code or a shared secret shipped in the game. Only its hash is stored in the session table. Credentials grant writes/completion and access to that session's intervention results; there is no public record-list, database, export, administrative or research-management API.
- Server metadata always labels public sessions `record_mode=public-demo`, `research_eligible=false`. Client enrollment/consent/research flags are not accepted. Public event bodies cannot override that classification. Operator CSV/workbook exports carry server-owned classification on every data sheet, including private responses and AI results. Game exports also identify public demos. The research-submission boundary continues to refuse unapproved submissions.
- Existing schema 5–7 outbox entries retain their original metadata, IDs, credentials and protected bootstrap route. They are never given a new public identity. Legacy access-code recovery remains an internal recovery API and is tested; no code entry is offered in regular Play. Pending recovery JSON excludes credentials. Preserve the original local outbox when recovering an unstarted protected session; an authorized operator can use the former client/recovery integration with its original code. Never import its events into a new public session.
- Refresh keeps pending records, marks the old run interrupted, and does not resume gameplay or create a replacement automatically. A subsequent deliberate Play is a fresh run. Closed local-only records remain available for recovery export. Offline gameplay and local persistence continue working.

## Personal testing and unresolved policy

The owner confirmed this is an unpublicized link for personal testing and that there is **no approved public/demo data policy**. This does not enroll anyone in research. Existing study/practice approval restrictions remain intact; no consent or enrollment flow has been invented or bypassed.

Defaults are `CASCADE_PUBLIC_RECORDS=0` and `CASCADE_PUBLIC_AI=0`. Public bootstrap stores only the operational session envelope (random identity, credential hashes, game version/order/condition, status/timestamps and public classification), needed for session authorization and quotas. Gameplay, existing structured forms and audit events remain on the device by default. No new analytics, names, IP identifiers or fingerprints are collected. The UI reports local saving, and an AI condition gives a clear unavailable message while keeping normal gameplay and its reading pause.

Retention/deletion periods, participant-facing disclosures, access/export responsibilities and permission to send public/demo responses to an AI provider remain unresolved. Do not enable public collection or live public AI for visitors until those decisions and any required study information/consent/enrollment have been approved and implemented. Merely knowing a URL does not confer research authorization.

For **local synthetic testing only**, use a temporary database and the following settings (do not source a private production `.env`):

```sh
CASCADE_PROVIDER=mock CASCADE_ALLOW_LIVE=0 \
CASCADE_DB=/tmp/cascade-public-test.sqlite3 \
CASCADE_PUBLIC_RECORDS=1 CASCADE_PUBLIC_AI=1 \
CASCADE_PUBLIC_POLICY_ID=synthetic-test-only \
python3 -m backend.server
```

The policy ID records the operator's configured policy/test purpose; it is not consent, an enrollment mechanism, or proof of research approval. Enabling either storage or AI requires a nonempty policy ID; AI also requires record storage because the existing provider audit stores its structured input. Capabilities are bound at session creation: changing settings cannot silently promote old local-only sessions to collection. Turning the server capability off prevents further public event ingestion/AI. If policy is revoked during a run, unacknowledged events remain on the device for recovery; they are not silently discarded or reassigned.

## AI and session limits

All limits are server-side and shared through durable database transactions. They do not rely on the client claiming an eligible round, approved enrollment or research status.

| Setting | Default | Meaning |
| --- | ---: | --- |
| `CASCADE_MAX_SESSIONS` | 1000 | Total stored session ceiling |
| `CASCADE_MAX_DAILY_SESSIONS` | 50 | New sessions in a rolling 24 hours |
| `CASCADE_MAX_MINUTE_SESSIONS` | 10 | Public starts per rolling minute, globally; retries of the same session are exempt |
| `CASCADE_MAX_DAILY_INTERVENTIONS` | 300 | Accepted interventions per rolling 24 hours |
| `CASCADE_MAX_DAILY_AI_ATTEMPTS` | 300 | Maximum reserved provider attempts per rolling 24 hours; zero disables new model work |
| `CASCADE_MAX_JOBS` | 4 | Global pending work and per-process worker bound |
| `CASCADE_PUBLIC_SESSION_SECONDS` | 86400 | New AI admission lifetime; original credential remains usable for pending-record recovery |
| `CASCADE_PUBLIC_ROUND_INTERVAL` | 120 | Minimum seconds between public interventions; values below 120 allowed only with the mock provider |

Each accepted job reserves **all** configured provider attempts before dispatch, even if fewer are ultimately used. Reservations are not refunded on ambiguous failures. This is a conservative request cap, not a currency estimate; token limits and provider budget controls remain relevant. Global limits deliberately avoid collecting identifying information; one tester can exhaust the shared allowance.

Public AI accepts only registered scenario topology, bridge flags, depot IDs and canonical display names, plus the existing strict bounded context and enumerated anonymous responses. Arbitrary chat prompts, extra fields and altered place names are rejected. A session must be active and within its AI lifetime, the condition must match its server metadata, and later rounds require the preceding round's accepted job and the server's minimum interval. These are demo eligibility checks, not a claim that a remote client proves human gameplay or consent.

The `(session, scenario, round)` database key admits at most one request. Identical retries return the saved/pending result; changed input conflicts. Only the transaction winner submits work to a provider, including across workers. Provider retries remain limited to explicit 429/503 rejections, with bounded backoff, request/body timeouts and output size. Ambiguous timeout/network failures never regenerate a message. Orphaned pending jobs fail after 180 seconds and never regenerate; starting another worker does not fail a live job. Usage caps and unavailable public AI produce explicit unavailable states in the game.

## Local verification

Use `python3 -m unittest discover -s backend/tests -t . -q` for the backend suite. Real HTTP tests use temporary local databases and mock/intercepted providers; no paid calls are needed. `tests/test_access_code_recovery.gd` remains a legacy-record test, not a regular-play screen.

Export `tools/build_web_test.py --godot <Godot> --backend-url http://127.0.0.1:<port>` with a local mock backend that enables the synthetic capabilities above and permits the web host's exact origin. Serve `build/` locally with the usual Godot COOP/COEP headers. Run `node tools/test_public_web.cjs http://127.0.0.1:8000/web-test/` with Playwright installed (`CHROME_BIN` optionally selects local Chrome). Repeat export with `--preset 'Web Participant' --output build/web-test-participant` and pass that URL. These harnesses are excluded from normal exports.

Results and remaining verification limitations are recorded in the change report below; production cloud services, live model calls, Safari/Firefox and PostgreSQL integration were not exercised for this change.

### Results from this change

- Backend suite: **61 tests, zero failures, 11 PostgreSQL tests skipped** (no test PostgreSQL URL configured). The native client portions passed **14** saving/AI/recovery checks, **4** legacy protected-record recovery checks, and **84** intercepted outbound-context checks.
- Final focused tests after export classification and whole-response timeout hardening: **19 tests, zero failures** (11 public-flow tests and 8 provider tests).
- Exported Web and Web Participant release harnesses in local headless Chrome: **both passed**, including direct/repeated Play, practice or participant-approved normal entry, credentials, saving, mock AI, interrupted upload, refresh, identity preservation and no script errors. Each harness deliberately changes the condition once, creating two distinct intentional run identities; refresh creates none. Participant Dev Mode remained unavailable and web Dev Mode began locked.
- Default local-only policy: **11 Godot checks, zero failures**; no event or AI requests, durable records and original identity retained after completion/reload, credentials omitted from recovery exports.
- Rules regression: **507 checks, zero failures**; practice isolation: **10 checks, zero failures**.
- First-play regression: **855 checks, zero failures**. The initial invocation hit a Godot log-file sandbox crash; rerunning with a writable temporary log completed successfully.
- Menu regression: **940 checks, one unresolved decorative-node settling assertion**, reproduced on rerun. Direct Play, repeated clicks, bilingual UI, wrong/correct existing Dev Mode password, all four sandbox scenarios and participant restrictions passed. No menu animation implementation was changed. An optional comparison against the committed menu could not run because automatic approval review hit its usage limit; this was not a safety rejection. Do not interpret this report as a fully green visual suite.
- No live provider, cloud deployment, external account, paid AI call or production database was used. PostgreSQL integration, production hosting, and other browsers remain unverified in this run.

Individual post-outcome forms use the existing public-record permission and local-only defaults. See [form contracts and completion barriers](POST_OUTCOME_FORMS.md). No remote permission or research eligibility is enabled by collecting these forms.
