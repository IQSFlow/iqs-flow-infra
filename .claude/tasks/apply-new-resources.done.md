# Apply New Terraform Resources

## Context
All existing GCP resources have been imported into Terraform state. The plan shows 41 to add, 9 to change, 0 to destroy. This task applies the new resources (service accounts, scheduler jobs, task queues, monitoring alerts, new APIs).

## Requirements

### 1. Set PATH for Terraform
```bash
export PATH="/c/Users/joshu/bin:$PATH"
```

### 2. Run terraform plan and review
```bash
cd /c/Users/joshu/Flow/iqs-flow-infra
terraform plan -no-color
```
Verify: **0 to destroy**. If any destroy actions exist, DO NOT proceed — investigate and fix the .tf files first.

### 3. Apply
```bash
terraform apply -auto-approve
```

### 4. Verify new service accounts
```bash
gcloud iam service-accounts list --format="table(email,displayName)"
```
Expected: `iqs-api@`, `iqs-web@`, `iqs-build@`, `iqs-scheduler@`

### 5. Verify new APIs
```bash
gcloud services list --enabled --filter="config.name:cloudscheduler OR config.name:cloudtasks OR config.name:gmail OR config.name:maps OR config.name:clouderrorreporting" --format="value(config.name)"
```

## Skills to Use (MANDATORY)
- Run `/sp-verification-before-completion` after apply
- Run `/commit` to commit any .tf fixes
- Run `/revise-claude-md` after completion

## Branch
Work directly on `main` — these are infra changes, not feature work.
