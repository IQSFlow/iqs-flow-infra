# Migrate marketing site: Next.js on Cloud Run → static HTML on GCS + CDN

**Author:** Joshua Hinton
**Date:** 2026-04-22
**Status:** in progress (scripts written, awaiting new HTML upload)

## Goal

Replace the Next.js-based `iqs-flow-marketing` Cloud Run service with a static HTML site served directly from a GCS bucket through the existing Cloud Load Balancer. Keep `iqsflow.com` / `www.iqsflow.com`, keep the SSL cert, keep the DNS. The only swap is the LB's default backend.

## Why

- Marketing is 15 pages, mostly content. A Node runtime on Cloud Run is overkill.
- GCS + Cloud CDN is cheaper (~$1–2/mo vs ~$15–30/mo), more secure (no compute surface), and faster at the edge.
- New site arrives as a folder of HTML/CSS/JS — native to static hosting.

## Architecture after migration

```
DNS iqsflow.com (A record)
    ↓
LB IP 107.178.245.169
    ↓
Forwarding rules (iqs-flow-http-rule / iqs-flow-https-rule)   ← unchanged
    ↓
Target proxies + SSL cert iqs-flow-cert                       ← unchanged
    ↓
URL map iqs-flow-urlmap                                       ← default backend changes
    ↓
BEFORE:  backend-service iqs-flow-backend → Cloud Run iqs-flow-marketing
AFTER:   backend-bucket  iqsflow-marketing-backend → GCS gs://iqsflow-marketing-static
                                                     + Cloud CDN

Forms:   LB path matcher routes iqsflow.com/api/forms/* →
         Cloud Function marketing-forms-handler                ← new, deferred
```

## Sequence

### 1. Archive current repo state (one-time)

Before blowing away Next.js from the repo, tag the current state so we can recover if needed:
```
cd iqs-flow-marketing
git tag -a archive-nextjs-2026-04-22 -m "Last commit before static site migration"
git push origin archive-nextjs-2026-04-22
```

### 2. Stand up GCS + backend bucket + Cloud CDN

Run from anywhere with gcloud authenticated:
```
cd iqs-flow-infra/scripts
./marketing-static-setup.sh
```

Idempotent — safe to re-run. Creates:
- GCS bucket `gs://iqsflow-marketing-static` (public read, website config)
- LB backend bucket `iqsflow-marketing-backend` with Cloud CDN enabled (3600s TTL)

Nothing on the live site changes yet. URL map still points at Cloud Run.

### 3. Rewrite the marketing repo

User drops the new HTML folder. Then:
```
cd iqs-flow-marketing
git rm -r src/ app/ public/ content/ scripts/ screenshots/ \
         next.config.ts next-env.d.ts tsconfig.json tsconfig.tsbuildinfo \
         package.json package-lock.json Dockerfile
# drop the new folder at repo root as ./site/
git add site/
# replace cloudbuild.yaml (see iqs-flow-marketing/cloudbuild.yaml for new version)
git commit -m "feat: replace Next.js site with static HTML"
git push origin main
```

The new `cloudbuild.yaml` is a single step: `gsutil -m rsync -d -r site/ gs://iqsflow-marketing-static/`. No container, no npm install.

### 4. Verify the bucket serves before cutover

Hit the bucket directly (bypasses LB + CDN):
```
curl -I https://storage.googleapis.com/iqsflow-marketing-static/index.html
# expect 200 OK
```

Load a few sub-pages the same way. Verify forms render. Confirm image/CSS/JS asset paths are relative (not absolute `/` — GCS doesn't do clean URL rewriting without rules).

### 5. Cutover

```
cd iqs-flow-infra/scripts
./marketing-static-cutover.sh
```

Prompts for confirmation. Swaps URL map default backend. Takes < 5 seconds. LB edge cache has a 1h TTL so first unknown paths may still hit Cloud Run briefly; force-refresh to verify.

### 6. Verify production

- `https://iqsflow.com` → new site
- `https://www.iqsflow.com` → new site
- Try a form submission (once forms handler is wired)
- Smoke-test 5–10 sub-pages

Rollback at any time:
```
./marketing-static-rollback.sh
```
Single URL map flip back to Cloud Run. No data loss, no DNS change, no cert change.

### 7. Wire forms (deferred — not blocking the site launch)

- Cloud Function `marketing-forms-handler` with single `POST /submit` endpoint
- LB URL map path matcher: `iqsflow.com/api/forms/*` → the function
- Validation + rate limit (10/min per IP) + SendGrid email to sales inbox
- Write submissions to a dedicated Firestore collection `marketing_submissions` (not in the main product DB)

### 8. Decommission old Cloud Run service

After 24 hours of clean operation on the static site:
```
cd iqs-flow-infra/scripts
./marketing-static-teardown.sh
```

Removes:
- Cloud Run `iqs-flow-marketing`
- Backend service `iqs-flow-backend`
- Associated NEG(s)

Keeps everything else intact.

### 9. Follow-up (Terraform import)

The existing LB was provisioned out-of-band and is not in Terraform state. Post-migration, import the whole front-end stack so future changes go through IaC:
- `google_compute_global_forwarding_rule.http`
- `google_compute_global_forwarding_rule.https`
- `google_compute_target_http_proxy`
- `google_compute_target_https_proxy`
- `google_compute_url_map.main`
- `google_compute_backend_bucket.marketing`
- `google_compute_managed_ssl_certificate.iqsflow`
- `google_storage_bucket.marketing_static`

Budget half a day for the import + plan-verification cycle. Not urgent.

## Costs

| Resource | Monthly est |
|---|---|
| GCS storage (~50 MB site) | $0.001 |
| Cloud CDN cache fills | $0.01 |
| Cloud CDN egress (10 GB typical) | ~$0.80 |
| LB forwarding rules | unchanged (~$18) |
| Cloud Run `iqs-flow-marketing` after teardown | $0 (was ~$10–30) |
| **Net change** | **–$10–30/mo** |

LB cost doesn't change because the same LB still serves `app.iqsflow.com` via the `iqs-flow-web-prod` backend (shared infra).

## Risks

| Risk | Mitigation |
|---|---|
| New site has broken absolute paths | Verify at step 4 before cutover |
| Cloud CDN caches a stale broken page | Use `gcloud compute url-maps invalidate-cdn-cache` or short TTL during transition |
| Forms break because no handler wired yet | Launch without forms or mark them "coming soon"; wire handler as follow-up |
| Rollback window expires (URL map quota) | None — URL map swaps are free and unlimited |
| Someone triggers the old Cloud Build marketing deploy mid-migration | Disable the old trigger first, then enable the new one |
