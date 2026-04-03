# GitHub Actions: Terraform Plan on PR

## Context
Add a GitHub Actions workflow that auto-runs `terraform plan` on pull requests and comments the result.

## Requirements

### 1. Create workflow file
Create `.github/workflows/plan-on-pr.yml`:

```yaml
name: Terraform Plan
on:
  pull_request:
    branches: [main]

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      id-token: write

    steps:
      - uses: actions/checkout@v4

      - uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.11.4

      - name: Terraform Init
        run: terraform init

      - name: Terraform Plan
        id: plan
        run: terraform plan -no-color -var="db_password=placeholder" -var="session_secret=placeholder" -var="smtp_pass=placeholder"
        continue-on-error: true

      - name: Comment PR with Plan
        uses: actions/github-script@v7
        if: github.event_name == 'pull_request'
        with:
          script: |
            const plan = `${{ steps.plan.outputs.stdout }}`.slice(0, 60000);
            const status = '${{ steps.plan.outcome }}' === 'success' ? '✅' : '❌';
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## ${status} Terraform Plan\n\`\`\`\n${plan}\n\`\`\``
            });
```

### 2. Commit and push

## Skills to Use (MANDATORY)
- Run `/commit` to commit
- Run `/revise-claude-md` after completion

## Branch
Work directly on `main`.
