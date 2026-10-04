# --- Cloud Scheduler jobs ---
#
# LIVE IS THE SOURCE OF TRUTH. Every job below mirrors what
# `gcloud scheduler jobs list --location=us-central1` returned on 2026-10-04,
# field for field (name, schedule, time zone, method, URI, OIDC SA + audience,
# attempt deadline, retry config, description). The live jobs were created and
# tuned with gcloud over time and they work, so this file describes them rather
# than "correcting" them. Change a job here AND live together, never only one.
#
# Facts about the live fleet that this file encodes on purpose:
#   * Every live job authenticates as the API SA (iqs-api@), not iqs-scheduler@.
#     verifyCronAuth() in iqs-flow-api/src/routes/cron.ts accepts both. If
#     var.api_allow_public_invoke is ever flipped off, the run.invoker grant in
#     cloud-run.tf (api_scheduler_invoke) must cover iqs-api@ too.
#   * The OIDC audience is set explicitly. For the per-shift digests the URI
#     carries ?shift=N but the audience is the bare route.
#   * Time zones are NOT uniform (America/New_York, UTC, Etc/UTC) and dev/prod
#     differ for escalation-sweep. Keep the exact strings.
#   * Dev job names mostly end in "-dev"; the two oldest dev jobs
#     (iqs-flow-daily-cleanup, iqs-weekly-report) have no suffix.
#
# A job has an entry for a workspace ONLY if it is live in that environment.
# Never add an entry for a job that is not live: applying it would start a
# brand-new cron. Create the job live first (gcloud), then add it here as
# "import". Each per-workspace entry carries a `status`:
#   "managed" - live and already in Terraform state for that workspace.
#   "import"  - live but not yet in state; the import block below adopts it, so
#               plan shows an import instead of a create. After the first apply
#               that performs the import, flip it to "managed".
#
# Routes in cron.ts with NO live job in either env (deliberately absent here):
# generate-daily-tasks, process-scheduled-tickets, gate-turns, sync-flights.
# Also not live: daily-digest (combined) in dev, cleanup and weekly-digest in
# prod.
#
# Base URI: read from the live Cloud Run service via a data source instead of
# google_cloud_run_v2_service.api.uri. The managed prod API service is marked
# tainted in state, so its uri plans as "(known after apply)", which would make
# every prod job plan an in-place update. The run.app URL is deterministic per
# service name, so the live value is also the post-replace value.

data "google_cloud_run_v2_service" "api_live" {
  name     = "iqs-flow-api${local.env_suffix}"
  location = var.region
}

locals {
  cron_base_uri = "${data.google_cloud_run_v2_service.api_live.uri}/api/cron"
  cron_sa_email = google_service_account.api.email

  # What Cloud Scheduler stores when a job is created without retry flags.
  scheduler_default_retry = {
    retry_count          = 0
    max_retry_duration   = "0s"
    min_backoff_duration = "5s"
    max_backoff_duration = "3600s"
    max_doublings        = 5
  }

  scheduler_retry_3 = merge(local.scheduler_default_retry, { retry_count = 3 })

  scheduler_job_defaults = {
    http_method      = "POST"
    attempt_deadline = "180s"
    description      = null
    query            = ""
    retry            = local.scheduler_default_retry
  }

  # key => common settings + `env` = { dev = {...}, prod = {...} }. A workspace
  # missing from `env` has no such job. Per-env entries may override any common
  # setting (description, time_zone, ...).
  scheduler_job_specs = {
    # --- Live in both dev and prod ---

    compute_benchmarks = {
      path        = "compute-benchmarks"
      http_method = "GET"
      schedule    = "30 2 * * *"
      time_zone   = "Etc/UTC"
      env = {
        dev  = { status = "import", name = "iqs-flow-compute-benchmarks-dev" }
        prod = { status = "import", name = "iqs-flow-compute-benchmarks-prod" }
      }
    }

    compute_vas = {
      path      = "compute-vas"
      schedule  = "0 2 * * *"
      time_zone = "UTC"
      env = {
        dev  = { status = "import", name = "iqs-flow-compute-vas-dev", description = "Nightly VAS computation (dev)" }
        prod = { status = "import", name = "iqs-flow-compute-vas-prod", description = "Nightly VAS computation (prod)" }
      }
    }

    # Per-shift digests: URI has ?shift=N, OIDC audience is the bare route.
    daily_digest_shift1 = {
      path      = "daily-digest"
      query     = "?shift=1"
      schedule  = "15 14 * * *"
      time_zone = "America/New_York"
      env = {
        dev  = { status = "import", name = "iqs-flow-daily-digest-shift1-dev" }
        prod = { status = "import", name = "iqs-flow-daily-digest-shift1-prod" }
      }
    }

    daily_digest_shift2 = {
      path      = "daily-digest"
      query     = "?shift=2"
      schedule  = "15 22 * * *"
      time_zone = "America/New_York"
      env = {
        dev  = { status = "import", name = "iqs-flow-daily-digest-shift2-dev" }
        prod = { status = "import", name = "iqs-flow-daily-digest-shift2-prod" }
      }
    }

    daily_digest_shift3 = {
      path      = "daily-digest"
      query     = "?shift=3"
      schedule  = "15 6 * * *"
      time_zone = "America/New_York"
      env = {
        dev  = { status = "import", name = "iqs-flow-daily-digest-shift3-dev" }
        prod = { status = "import", name = "iqs-flow-daily-digest-shift3-prod" }
      }
    }

    # Advance emergency notification ladders every minute.
    emergency_ladder = {
      path             = "emergency-ladder"
      schedule         = "* * * * *"
      time_zone        = "Etc/UTC"
      attempt_deadline = "55s"
      description      = "Advance emergency notification ladders (every minute)"
      env = {
        dev  = { status = "import", name = "iqs-flow-emergency-ladder-dev" }
        prod = { status = "import", name = "iqs-flow-emergency-ladder-prod" }
      }
    }

    # Timer-driven escalation sweep (unassigned/overdue tickets, tasks, WOs).
    # Live time zones differ between envs; harmless for a */15 schedule.
    escalation_sweep = {
      path     = "escalation-sweep"
      schedule = "*/15 * * * *"
      env = {
        dev  = { status = "import", name = "iqs-flow-escalation-sweep-dev", time_zone = "Etc/UTC" }
        prod = { status = "import", name = "iqs-flow-escalation-sweep-prod", time_zone = "America/New_York" }
      }
    }

    expire_stale_runs = {
      path        = "expire-stale-runs"
      http_method = "GET"
      schedule    = "0 */6 * * *"
      time_zone   = "Etc/UTC"
      env = {
        dev  = { status = "import", name = "iqs-flow-expire-stale-runs-dev" }
        prod = { status = "import", name = "iqs-flow-expire-stale-runs-prod" }
      }
    }

    form_proposal_sweep = {
      path        = "form-proposal-sweep"
      http_method = "GET"
      schedule    = "0 4 * * *"
      time_zone   = "Etc/UTC"
      env = {
        dev  = { status = "import", name = "iqs-flow-form-proposal-sweep-dev" }
        prod = { status = "import", name = "iqs-flow-form-proposal-sweep-prod" }
      }
    }

    learn_geofences = {
      path        = "learn-geofences"
      http_method = "GET"
      schedule    = "30 4 * * *"
      time_zone   = "Etc/UTC"
      env = {
        dev  = { status = "import", name = "iqs-flow-learn-geofences-dev" }
        prod = { status = "import", name = "iqs-flow-learn-geofences-prod" }
      }
    }

    process_pm_plans = {
      path      = "process-pm-plans"
      schedule  = "0 6 * * *"
      time_zone = "UTC"
      env = {
        dev  = { status = "import", name = "iqs-flow-process-pm-plans-dev", description = "Daily PM plan processing (dev)" }
        prod = { status = "import", name = "iqs-flow-process-pm-plans-prod", description = "Daily PM plan processing (prod)" }
      }
    }

    rollup_zone_metrics = {
      path        = "rollup-zone-metrics"
      http_method = "GET"
      schedule    = "0 1 * * *"
      time_zone   = "Etc/UTC"
      env = {
        dev  = { status = "import", name = "iqs-flow-rollup-zone-metrics-dev" }
        prod = { status = "import", name = "iqs-flow-rollup-zone-metrics-prod" }
      }
    }

    # --- Live in one env only ---

    # Nightly housekeeping. Live in dev only (legacy unsuffixed name, already in
    # dev state). NOT live in prod, so no prod entry.
    daily_cleanup = {
      path             = "cleanup"
      schedule         = "0 3 * * *"
      time_zone        = "America/New_York"
      attempt_deadline = "300s"
      description      = "Runs daily cleanup of old location events, audit logs, sessions, and notifications"
      retry            = local.scheduler_retry_3
      env = {
        dev = { status = "managed", name = "iqs-flow-daily-cleanup" }
      }
    }

    # Combined daily manager digest. Prod job was created by hand on 2026-10-03.
    # NOT live in dev, so no dev entry.
    daily_digest = {
      path        = "daily-digest"
      schedule    = "0 7 * * *"
      time_zone   = "America/New_York"
      description = "Daily manager digest (combined run: ADMIN and MANAGER; supervisors only via per-shift opt-in)"
      retry       = local.scheduler_retry_3
      env = {
        prod = { status = "import", name = "iqs-flow-daily-digest-prod" }
      }
    }

    # Weekly digest. Live in dev only as the legacy iqs-weekly-report job (no
    # retryConfig at all, already in dev state). NOT live in prod, so no prod
    # entry.
    weekly_digest = {
      path        = "weekly-digest"
      schedule    = "0 8 * * 1"
      time_zone   = "America/New_York"
      description = "Generate weekly inspection summary"
      retry       = null
      env = {
        dev = { status = "managed", name = "iqs-weekly-report" }
      }
    }

    feedback_digest = {
      path        = "feedback-digest"
      http_method = "GET"
      schedule    = "0 8 * * 1"
      time_zone   = "America/New_York"
      env = {
        prod = { status = "import", name = "iqs-flow-feedback-digest-prod" }
      }
    }

    scheduled_inspections_roll = {
      path        = "scheduled-inspections-roll"
      http_method = "GET"
      schedule    = "0 5 * * *"
      time_zone   = "America/New_York"
      env = {
        prod = { status = "import", name = "iqs-flow-sched-insp-roll-prod" }
      }
    }

    scheduled_reports = {
      path        = "scheduled-reports"
      http_method = "GET"
      schedule    = "0 7 * * *"
      time_zone   = "America/New_York"
      env = {
        prod = { status = "import", name = "iqs-flow-scheduled-reports-prod" }
      }
    }
  }

  # Jobs that exist in the current workspace, with defaults and per-env
  # overrides applied.
  scheduler_jobs = {
    for key, spec in local.scheduler_job_specs : key => merge(
      local.scheduler_job_defaults,
      { for attr, value in spec : attr => value if attr != "env" },
      try(spec.env[local.env_label], {}),
    ) if contains(keys(spec.env), local.env_label)
  }
}

resource "google_cloud_scheduler_job" "cron" {
  for_each = local.scheduler_jobs

  name             = each.value.name
  description      = each.value.description
  schedule         = each.value.schedule
  time_zone        = each.value.time_zone
  attempt_deadline = each.value.attempt_deadline

  http_target {
    http_method = each.value.http_method
    uri         = "${local.cron_base_uri}/${each.value.path}${each.value.query}"

    oidc_token {
      service_account_email = local.cron_sa_email
      audience              = "${local.cron_base_uri}/${each.value.path}"
    }
  }

  dynamic "retry_config" {
    for_each = each.value.retry == null ? [] : [each.value.retry]
    content {
      retry_count          = retry_config.value.retry_count
      max_retry_duration   = retry_config.value.max_retry_duration
      min_backoff_duration = retry_config.value.min_backoff_duration
      max_backoff_duration = retry_config.value.max_backoff_duration
      max_doublings        = retry_config.value.max_doublings
    }
  }
}

# Adopt live jobs that are not yet in this workspace's state (status "import").
# import-block for_each needs Terraform >= 1.7 (see main.tf).
import {
  for_each = { for key, job in local.scheduler_jobs : key => job if job.status == "import" }
  to       = google_cloud_scheduler_job.cron[each.key]
  id       = "projects/${var.project_id}/locations/${var.region}/jobs/${each.value.name}"
}

# Dev state already tracks these two under their old per-job addresses.
moved {
  from = google_cloud_scheduler_job.daily_cleanup
  to   = google_cloud_scheduler_job.cron["daily_cleanup"]
}

moved {
  from = google_cloud_scheduler_job.weekly_report
  to   = google_cloud_scheduler_job.cron["weekly_digest"]
}
