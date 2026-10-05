# Synthetic development integration

Qwen is **live-verified for one synthetic smoke call** (October 4, 2026: China (Beijing) workspace, `qwen-flash`, prompt `cascade-zh-2`, 1,477 input / 82 output tokens, structurally valid Direct Recommendation `VERIFY E`). An earlier attempt was rejected by output validation before failure reasons were recorded; rejections now store a reason code and a private copy of the rejected reply. Message quality and role fidelity are not verified; the first live message contained an unsupported inference and needs human review practices before research use. All records are marked `synthetic-development`, `research_eligible=false`. This work does not authorize participant recruitment or collection. The existing scenarios, action rules, structured reasons, conditions, discussion duration, and reading pause are retained.

For the online setup (itch.io + Render + AWS RDS), see [DEPLOYMENT.md](DEPLOYMENT.md).

## Local startup

Requirements: Python 3.10+ (standard library only), Godot 4.7.1 with matching Web export templates. Commands below run from the repository root. On this Mac the Godot executable is `/Applications/Godot.app/Contents/MacOS/Godot`; elsewhere replace that path with `godot`.

Terminal 1, a free, fully offline model test backend:

```sh
CASCADE_PROVIDER=mock python3 -m backend.server
```

The server binds only `127.0.0.1:8787`. Its SQLite database is `backend/data/development.sqlite3`; keep its WAL files with it while running. Only one backend process may use a database. Startup marks any unfinished generation as failed rather than issuing a potentially duplicate paid request.

Terminal 2, native game:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

For the browser, export and serve **only the build directory**, never the repository:

```sh
mkdir -p build/local
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /tmp/cascade-export.log --path . --export-debug Web build/local/index.html
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/local
```

Open `http://127.0.0.1:8000`. `http://localhost:8000` is also allowed. Other origins (including `file:`/`null`) are rejected. The default game configuration in `project.godot` is `cascade/support_provider="backend"`, `cascade/backend_url="http://127.0.0.1:8787"`. For an entirely disconnected mock game, explicitly set the provider to `mock`; saving still queues records and indicates disconnection. `-- --offline-tests` is reserved for automated tests: it selects the mock provider and disables saving.

The backend defaults to a clearly marked mock provider. Configuring the game to use the backend does **not** enable paid calls.

## Private Qwen configuration and opt-in smoke test

Supported regions (Alibaba docs re-checked October 4, 2026): Singapore, China (Beijing), China (Hong Kong) and Japan (Tokyo), each using a workspace-specific endpoint (the console's Base URL plus `/chat/completions`) and an API key created in the same region. The region is recorded with each intervention. A China (Beijing) workspace processes model inputs in mainland China; confirm that is acceptable for your study's data-handling approval. The configured model is exactly `qwen-plus`; there is no fallback model. An operator may choose a supported model/snapshot explicitly through `QWEN_MODEL`, after checking its availability and parameter support in that workspace. The alias can evolve; use a verified pinned model before research.

Sources checked October 3, 2026:

- [OpenAI-compatible endpoint and region/key requirements](https://www.alibabacloud.com/help/en/model-studio/compatibility-of-openai-with-dashscope)
- [Structured JSON output, including Qwen-Plus non-thinking support](https://www.alibabacloud.com/help/en/model-studio/qwen-structured-output)
- [Chat parameters](https://help.aliyun.com/en/model-studio/qwen-api-via-openai-chat-completions)

Only **after explicitly approving a billable live test**, copy the placeholder file and edit it privately on your computer:

```sh
cp backend/.env.example backend/.env
chmod 600 backend/.env
```

Set `CASCADE_PROVIDER=qwen`, `CASCADE_ALLOW_LIVE=1`, your workspace endpoint, and your private `DASHSCOPE_API_KEY` in `backend/.env`. Do not paste the key into chat, Godot settings, frontend files, shell command arguments, or source control. The example contains placeholders only. `.env` files and databases are ignored and excluded from web exports. The backend never returns the provider key and disables routine HTTP access logs.

Start from a private terminal (do not enable shell tracing):

```sh
set -a
. backend/.env
set +a
python3 -m backend.server
```

Then request one synthetic intervention through the running backend:

```sh
python3 -m backend.smoke --expect-provider qwen --allow-billable-call
```

This command intentionally refuses a Qwen test without the explicit billable flag. It never reads the key; only the backend does. It prints the resulting synthetic message, not credentials or private inputs. This verifies the connection, structured result and persistence; repeat the UI walkthrough below to verify a live message's display. Stop the server and return `CASCADE_PROVIDER=mock` / `CASCADE_ALLOW_LIVE=0` afterward unless further paid tests are intended.

For the no-cost equivalent against a mock server:

```sh
python3 -m backend.smoke --expect-provider mock
```

Configuration is listed in [the placeholder example](../backend/.env.example). Both AI roles share temperature, token limit, non-thinking mode, JSON response format, model and allowed inputs. Only system role instructions differ. Output is requested in Simplified Chinese, with the same 90–420 character limit and three-line format. Noto Sans SC and its OFL license are bundled so Chinese renders in web builds without system fonts.

## Synthetic walkthrough

1. Start the mock backend and the game. Choose **Play**, then **Menu → Session setup** and select either AI condition. Condition changes before play close the prior synthetic session and start a fresh identity.
2. Enter three synthetic private responses using the existing fields. For example: danger `E`, action `VERIFY`, target `E`, confidence `4`, reason `gather more information`. Slots `P1`, `P2`, `P3` are stable within the session and stored privately. Do not enter real participant data.
3. Generation begins when the third response is submitted. The allowed projection is frozen then. Wait for the existing 120-second discussion. A completed message remains hidden until the scheduled intervention. If still pending, the game shows a waiting notice.
4. When the actual support message or failure notice appears, the full 15-second minimum reading pause begins. The team must continue manually. Mock output says it is a development simulation. No-AI issues no intervention request and preserves its neutral pause.
5. Watch **Saving → Saved**. Stop the backend, take another action, and observe **Offline / unsent records**. Restart the same backend/database. Pending events retry with their original IDs and sequences; acknowledged duplicates create no additional records.
6. With records still pending, refresh the browser or reopen the native game. The outbox uploads the previous session and records it as interrupted. **Gameplay itself is not resumed.** Starting Play creates a new session. The backend also marks sessions interrupted after five minutes without a heartbeat; recovered events can still upload.
7. Complete all four missions for session completion, or leave early for interruption. Use **Menu → Export recovery JSON** at any stage or the existing results export. This keeps existing game/private exports and adds private AI audit plus unsent records; bootstrap/session credentials are omitted. Exports contain development hidden-state records as before and are not shared-board documents.

If durable browser storage is blocked or full, the UI explicitly shows `Save error — local persistence unavailable; export JSON`. Live uploading can still work, but closing the page may lose unsent memory-only records. Keep one game tab/process per browser profile/native data directory. Private browsing, clearing site data, or disk failure can remove the client outbox. The main menu shows recovery upload status and offers pending-record export; gameplay itself is not resumed.

## Implementation and API

Python's standard library keeps the local setup dependency-free: a localhost `ThreadingHTTPServer`, a bounded worker pool for generation, and SQLite WAL transactions with `synchronous=FULL`. This server is a development adapter, not an internet-facing production server. `Storage` in `backend/storage.py` is the replacement boundary for cloud persistence. Event ingestion never waits for the provider worker. Separate Godot HTTPRequest nodes keep client saving independent of model polling.

| Interface | Method/path | Returns |
|---|---|---|
| Start development session | `POST /v1/sessions` | Session-scoped credential and ID |
| Append event batch | `POST /v1/sessions/{id}/events` | IDs acknowledged after transaction commit |
| Request intervention | `POST /v1/sessions/{id}/interventions/{scenario}/{round}` | Immutable job identity/status |
| Poll intervention | `GET` on the same intervention path | Status, completed message, or safe error code |
| Complete/interruption | `POST /v1/sessions/{id}/completion` | Status after all declared event sequences are durable |

All session paths require `Authorization: Bearer <session credential>`. Start retries require the original random client bootstrap secret, never just a session ID. Credentials are hashed in SQLite. There is no public event/private-input read endpoint. Origins, Host, JSON size, body schemas, action/location IDs and condition/session membership are checked. Limits for concurrent generation, session count, body size, timeout, attempts and tokens are configurable. IDs and sequences are unique per session; conflicting reuse rejects the **entire** transaction.

`game_events`, `private_events`, `audit_events`, intervention audit, and lifecycle records are separate. Records cover scenario order, versions, phase, assigned condition, private answers/confidence, public observations, actions, outcomes, private input snapshots, exact displayed text/time, configured model/settings, prompt version, usage when returned, failures and completion/interruption. The existing game does not implement additional post-message ratings; none were invented.

The sole game-to-model boundary remains `SupportContext`, extended with explicit public rules, costs, display names and legal actions. Hidden pressures, future reports, original source, solution, identities and complete logs never enter it. The backend rejects extra fields recursively and independently recomputes legal actions. The model receives only that projection, with scenario text and responses marked as data. It never receives event batches or full game exports.

A session/scenario/round uniquely identifies a job. Repeated posts reuse pending/completed/failed jobs; changed snapshots or conditions conflict. HTTP 429/503 provider rejections have bounded retries within the same job. Ambiguous network timeouts, malformed output and other rejections are terminal; these do not trigger answer-shopping or silent model changes. A lost client acknowledgment retries the same identity. Restarted pending jobs fail with `backend_interrupted` because the provider may already have accepted them.

Output validation checks JSON shape, character limits, CJK presence, declared/referenced IDs and the structured legal recommendation. **This cannot establish factual correctness, faithful Simplified Chinese, or experimental-role fidelity.** Prompts restrict dissent, but human review is still required to assess its prose. The neutral unavailable notice, deviation log, and retained 15-second pause are a **provisional development failure policy requiring approval before research use**.

## Automated verification

```sh
python3 -m unittest discover -s backend/tests -t . -v
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /tmp/cascade-support-tests.log --path . --script tests/test_async_support.gd -- --offline-tests
```

The Python suite includes a real localhost Godot client test if `GODOT_BIN` or the documented Mac executable is available. All provider calls are mocked. The original `tests/test_*.gd` suites can be run with the same Godot command and `-- --offline-tests`; presentation/UI suites take longer because they exercise animation timers. Do not run `test_backend_client.gd` directly; its Python wrapper supplies a temporary server and outbox.

A separate synthetic browser harness exercises the production scene, HTTP transport, timing and storage. It is excluded from normal exports:

```sh
python3 tools/build_web_test.py --godot /Applications/Godot.app/Contents/MacOS/Godot
python3 -m http.server 8000 --bind 127.0.0.1 --directory build
```

With the mock backend running, open `http://127.0.0.1:8000/web-test/index.html`. The harness automatically submits synthetic responses and advances its injected test clock. The production timers are unchanged. Expect `ready-to-refresh` with an empty failures list, then reload the page and expect `recovered` with an empty list. Each harness build uses its own storage key. Do not share this test harness as a participant build.

### Results recorded October 3, 2026

Run with Godot 4.7.1 (Linux headless) and Python 3.10/3.13, all providers mocked, synthetic data only:

- Python backend suite: 17/17 passed, including the real-localhost native Godot client test (14 checks).
- Godot suites with `-- --offline-tests`: async support 18, support 2003, rules 510, missions 660, mission UI 2452, session UI 144, UI 192, presentation 6082, redesign 1480, scenario fixtures 263, city alignment 134832 checks — 0 failures, no script errors.
- Browser harness (headless Chromium, Web export, mock backend): `ready-to-refresh` and, after reload, `recovered`, both with empty failure lists. Database check: contiguous sequences, no duplicate events, one intervention job, private/audit/game records in separate tables.
- Production Web export loads to the main menu without console errors; neither `.pck` contains backend, test, `.env` or key-name content.
- Mock smoke test passed; the Qwen smoke test correctly refuses without `--allow-billable-call`.
- Alibaba documentation re-checked: Singapore uses `https://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions` (replacing `dashscope-intl`), region-bound keys, and JSON mode requires the word "JSON" in the prompt (present).

Not verified: a live Qwen call (not authorized), Safari/Firefox, and the macOS-native build (tests ran on the Linux build of the same Godot version).

## Remaining work before AWS or research

No deployment is included. AWS will need a production HTTPS API, approved origin configuration, secret management, a durable worker/job queue, and a storage adapter with conditional writes preserving event and intervention idempotency. Use a transaction-capable durable database, backups and a tested restoration procedure. SQLite on ephemeral compute is insufficient; multiple workers must coordinate claims without regenerating ambiguous jobs.

Also required: authentication/provisioning beyond local synthetic sessions, scoped roles for research exports, session expiry/revocation, encrypted storage, retention/deletion procedures, quotas and abuse controls, monitoring without sensitive payloads, and approved interruption/failure and data-handling policies. Model/region availability, output quality and role fidelity still need an authorized live smoke test and study review. This implementation is neither research-approved nor internet-hardened, and does not provide online rooms or separate-device play.
