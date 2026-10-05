# Online deployment: itch.io + Render + AWS RDS + Qwen

This is a **synthetic-development / pilot** deployment. It does not authorize recruiting participants or collecting real participant data. Records stay `record_mode=synthetic-development`, `research_eligible=false`.

```
Browser (itch.io page) ──HTTPS──▶ Render web service (backend, holds Qwen key)
                                     ├──verified TLS──▶ AWS RDS PostgreSQL (all records)
                                     └──HTTPS─────────▶ Alibaba Model Studio (Qwen)
```

- **itch.io** hosts only static game files. No secrets are inside them.
- **Render** runs `python3 -m backend.server` in public mode. Render terminates HTTPS.
- **RDS** stores sessions, events, private responses and AI audit records. Render's own disk is never used for data (it is wiped on restart).
- The **study access code** is typed into the game menu by the facilitator. Without it, the backend refuses new sessions, so a stranger who finds the URL cannot spend your Qwen budget.

The backend refuses to start in public mode unless the access code, the database URL, the public host name and https-only origins are all set.

## 0. Cost guards (do this first)

1. **Alibaba Model Studio:** set a spending limit or budget alert for the Beijing workspace.
2. **AWS:** open **Billing and Cost Management** and check which free offer your account has (it depends on account age and plan). Then create a monthly budget under **Budgets**, for example US$5 with an email alert, so any charge is noticed early.
3. **Render:** the Blueprint uses the **free** plan. It sleeps after 15 idle minutes and takes about a minute to wake. The game's upload queue retries through that, so it is fine for testing.

## 1. Put the code on GitHub

Render deploys from a Git repository. Commit and push the repository yourself. `backend/.env`, databases and `backend/certs/*.pem` are git-ignored; check with `git status` that `backend/.env` is **not** listed before pushing.

## 2. Create the RDS database (AWS console)

Participants are in mainland China, so use **Asia Pacific (Singapore) ap-southeast-1** for RDS, paired with Render's **Singapore** region (set in `render.yaml`). Data stored outside mainland China is a cross-border transfer under China's PIPL: participants must be told and give separate consent, and your ethics approval should cover it. Before the real study, check from a mainland connection that the itch.io page and the Render URL load reliably.

1. **RDS → Create database → Standard create → PostgreSQL** (version 15 or later; SSL is then required by default).
2. **Templates:** *Free tier* if offered; otherwise the smallest *Dev/Test* option.
3. **Settings:**
   - DB instance identifier: `cascade-lab-db`
   - Master username: `postgres`
   - Credentials: *Self managed*, with a strong password. Store it in your password manager.
4. **Instance:** the smallest burstable class shown (e.g. `db.t4g.micro` or `db.t3.micro`).
5. **Storage:** 20 GiB, and turn **off** storage autoscaling.
6. **Connectivity:**
   - Public access: **Yes**. Render is outside AWS, so this is needed.
   - VPC security group: *Create new*, named `cascade-lab-db`.
7. **Additional configuration:**
   - Initial database name: `cascade_lab` (not `cascade`, which is a reserved SQL word)
   - Automated backups: on (e.g. 7 days)
   - Encryption: on
   - Deletion protection: on
8. Create the database and wait for **Available**. Copy the **Endpoint** (like `cascade-lab-db.xxxx.us-west-2.rds.amazonaws.com`).

**Firewall.** Edit the `cascade-lab-db` security group's inbound rule (PostgreSQL, port 5432):

- Add **your own IP** (needed for step 3).
- Add **Render's outbound IP ranges**. To find them: Render dashboard → your service → **Connect → Outbound**. These ranges are shared by all Render services in that region, so the password and TLS still matter.

Until the Render service exists (step 4), add only your own IP.

## 3. Create the limited app login (from your Mac)

Run in the repository folder:

```sh
pip install -r backend/requirements.txt
python3 -m backend.fetch_rds_ca
python3 -m backend.db_admin setup --host YOUR-ENDPOINT.rds.amazonaws.com
```

You are asked for the master password, then a new 16+ character password for `cascade_app`. Both prompts are hidden. Save the `cascade_app` password in your password manager.

Then build the connection string. Do not paste it into chat:

```
postgresql://cascade_app:APP_PASSWORD@YOUR-ENDPOINT.rds.amazonaws.com:5432/cascade_lab
```

If the password contains `@ : / ? # %`, URL-encode it, or choose a password made of letters, digits, `-` and `_`.

## 4. Create the Render service

1. Render dashboard → **New → Blueprint**, then connect the GitHub repository. Render reads `render.yaml`.
2. Fill in the secret values it asks for. These are entered only in Render:

   | Variable | Value |
   |---|---|
   | `CASCADE_ALLOWED_HOSTS` | Your service's host name, e.g. `cascade-lab-backend.onrender.com`. If you don't know it yet, enter `pending.invalid` and update it after the first deploy. |
   | `CASCADE_DATABASE_URL` | The connection string from step 3 |
   | `CASCADE_ACCESS_CODE` | A random code. Generate one with `python3 -c "import secrets; print(secrets.token_urlsafe(12))"` and share it only with facilitators. |
   | `QWEN_ENDPOINT` | `https://ws-…cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions` |
   | `DASHSCOPE_API_KEY` | Your Model Studio key |

3. Deploy. In **Logs**, expect one startup line naming public mode, `provider=qwen`, `model=qwen-flash` and `storage=PostgresStorage`. The backend never prints keys, the database URL or the access code.
4. Open `https://YOUR-SERVICE.onrender.com/healthz` and expect `{"ok":true}`.
5. If you used `pending.invalid`, set `CASCADE_ALLOWED_HOSTS` to the real host name (**Environment** tab) and let Render redeploy.
6. Add Render's outbound ranges to the RDS security group (step 2). You can then remove your own IP.

Changing settings later means editing the **Environment** tab, which triggers a redeploy. For example, switch `QWEN_MODEL` to `qwen-plus`. Each saved AI record keeps the model, settings and prompt version it used.

## 5. Build and upload the itch.io game

On your Mac, with Godot 4.7.1 and its Web export templates installed:

```sh
python3 tools/build_web_release.py \
  --godot /Applications/Godot.app/Contents/MacOS/Godot \
  --backend-url https://YOUR-SERVICE.onrender.com
```

This builds the *Web Participant* preset from a temporary copy (your project files are not changed). The build:

- points the game at the Render backend
- hides Dev Mode
- shows the access-code field on the menu

The result is `build/cascade-lab-itch.zip`.

On itch.io, open your project's **Edit** page:

- **Kind of project:** HTML.
- **Upload** the zip and tick *This file will be played in the browser*.
- **Viewport:** 1440 × 900. Enable the fullscreen button.
- **Visibility:** *Draft* or *Restricted* while testing.

The game runs from `https://html-classic.itch.zone` or `https://html.itch.zone`. Both are already in `CASCADE_ORIGINS`. If the browser console reports a CORS or `origin_denied` error naming a different itch origin, add that exact origin to `CASCADE_ORIGINS` in Render.

## 6. Synthetic check

1. Open the itch page and enter the access code. **Play** stays disabled until 12+ characters are entered.
2. Play one round with synthetic answers in an AI condition (Menu → Session setup). The status should go **Saving → Saved**. The AI message should appear only after the 120-second discussion, followed by the 15-second reading pause.
3. From your Mac, confirm records arrived (this prints counts only):

```sh
python3 -m backend.db_admin summary --host YOUR-ENDPOINT.rds.amazonaws.com
```

A wrong code shows `Save error — access code rejected`, and nothing is stored.

## Turning it off

- **Render:** suspend the service (Settings).
- **RDS:** *Stop temporarily*. AWS restarts a stopped instance automatically after 7 days. Delete it (taking a final snapshot if wanted) when you no longer need it.
- **Qwen:** set `CASCADE_ALLOW_LIVE=0` in Render to stop all paid calls. The game then shows the neutral "AI support unavailable" notice.

## Verified in rehearsal (October 4, 2026)

This was run without any paid service. Each stand-in replaced a real service:

- itch.io: an HTTPS game host at `html-classic.itch.zone`
- Render: the backend in public mode behind TLS
- RDS: PostgreSQL 16 that refuses plaintext and requires `verify-full` against a test CA

Results:

- The full browser harness passed, including refresh recovery: contiguous sequences, no duplicates, private/audit/game records in separate tables.
- The release build's menu accepted the code and started a saved session. The code was discarded from browser storage after the session started.
- A missing or wrong code returned `401`, a foreign origin returned `403`, and the backend logged nothing after startup.
- The full backend suite passed on both SQLite and PostgreSQL: 34 tests, including eight simultaneous duplicate batches stored exactly once.

**Not yet verified:** the real Render, RDS and itch.io accounts (their console steps above follow current documentation but may differ slightly), cold-start behaviour of the free Render plan during a session, and Safari/Firefox.

## Remaining limitations before research use

- **Ethics and data:** approval must cover RDS's region and Qwen inference in China (Beijing).
- **Access:** the single shared access code is a pilot measure. Research use needs per-study or per-session provisioning, revocation and expiry.
- **Server:** Python's threaded HTTP server behind Render is adequate for a pilot. Use a production WSGI/ASGI server and a paid instance for real sessions.
- **Scaling:** run a single Render instance. On restart or redeploy, unfinished AI jobs are marked `backend_interrupted` and never regenerated.
- **Data handling:** retention, deletion, export roles and monitoring policies are still to be defined. The AI failure policy remains provisional.
