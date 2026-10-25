# Terraform AWS Platform

A production-style Terraform project on AWS: reusable modules, separate dev and prod environments, remote state with locking, CI/CD with GitHub Actions (OIDC, no stored keys), automated tests, security scanning, and **scheduled drift detection**.

It deploys a small web tier (VPC, subnets, security group, nginx on EC2) so you can see real infrastructure come up, break it on purpose, and fix it with Terraform.

---

## What's inside

```
terraform-aws-platform/
├── bootstrap/            # Run once: S3 state bucket, budget alert, GitHub OIDC role
├── modules/
│   ├── network/          # VPC, subnets, internet gateway, routes (+ unit tests)
│   ├── security/         # Security group with dynamic rules + guardrails
│   └── compute/          # EC2 + nginx via user_data, for_each, lifecycle rules
├── envs/
│   ├── dev/              # Root module for dev  (1 server)
│   └── prod/             # Root module for prod (2 servers, private subnets)
├── labs/import-lab/      # Safe sandbox for the import lab
├── scripts/drift-check.sh
├── .github/workflows/
│   ├── terraform.yml       # PR: lint + test + plan  |  main: apply dev -> prod
│   └── drift-detection.yml # Daily drift check, opens a GitHub issue
├── LABS.md               # Hands-on: drift, import, state surgery, moved, locking...
└── INTERVIEW-QA.md       # Interview questions mapped to this code
```

### Architecture

```
                    Internet
                        |
               [Internet Gateway]
                        |
   +------------------- VPC 10.10.0.0/16 -------------------+
   |                                                        |
   |   Public subnet (AZ a)          Public subnet (AZ b)   |
   |   10.10.0.0/24                  10.10.1.0/24           |
   |   [EC2 web-1 nginx]             [EC2 web-2 nginx]*     |
   |        \___ Security group: 80 open, 22 admin-only ___/ |
   |                                                        |
   |   Private subnet (AZ a)*        Private subnet (AZ b)* |
   |   10.10.100.0/24                10.10.101.0/24         |
   +--------------------------------------------------------+
                                             * prod only

   State: s3://<project>-tfstate-<account-id>/{dev,prod}/terraform.tfstate
          (versioned, encrypted, locked with S3 native lockfile)
```

### Terraform features covered

| Feature | Where |
|---|---|
| Remote state + S3 native locking (`use_lockfile`) | `bootstrap/`, `envs/*/backend.tf` |
| Partial backend configuration | `backend.hcl` + `envs/*/backend.tf` |
| Modules (reusable, provider-free) | `modules/*` |
| `for_each` with stable keys, conditional `for_each` | `modules/network`, `modules/compute` |
| `count` for optional resources | `bootstrap/main.tf` |
| `dynamic` blocks | `modules/security` |
| Variable validation (incl. cost and security guardrails) | `variables.tf` everywhere |
| `locals`, `for` expressions, `cidrsubnet`, `templatefile`, `try` | all over |
| Data sources | AMI lookup, AZ lookup, caller identity |
| `lifecycle`: `prevent_destroy`, `create_before_destroy`, `ignore_changes`, `postcondition` | bootstrap, security, compute |
| `check` blocks (continuous validation) | `envs/*/main.tf` |
| `default_tags` | `versions.tf` |
| `terraform test` with `mock_provider` | `modules/network/tests` |
| `import` blocks + config generation | `labs/import-lab` |
| `moved` blocks, `state mv/rm`, `-replace` | `LABS.md` |
| Drift detection (`-refresh-only`, `-detailed-exitcode`) | `scripts/`, `.github/workflows/drift-detection.yml` |
| CI/CD: fmt, tflint, checkov, plan on PR, saved-plan apply, approval gate | `.github/workflows/terraform.yml` |
| OIDC auth from GitHub to AWS (no access keys) | `bootstrap/main.tf` |

---

## Cost

Everything here is small: `t3.micro` servers, no NAT gateway, no load balancer. New AWS accounts get free-tier credits, and even without them a dev environment running for a few hours costs a few rupees. **The rule: always `terraform destroy` when you're done for the day.** The bootstrap stack also sets a budget alert to email you if spending looks off.

---

## Step-by-step: from nothing to running

These steps assume **Windows with Git Bash**. Mac/Linux commands are the same once tools are installed.

### Step 1: Create an AWS account and a Terraform user

1. Sign up at https://aws.amazon.com (needs a card; you won't be charged if you stay small).
2. Log in as root, then turn on **MFA for the root user** (IAM > Dashboard). Interviewers love hearing you did this.
3. Create a user for yourself so you never use root day to day:
   - IAM > Users > **Create user** > name: `terraform-admin`
   - Permissions: **Attach policies directly** > `AdministratorAccess` (fine for a personal lab)
   - Open the user > **Security credentials** > **Create access key** > choose **Command Line Interface (CLI)**
   - Save the Access Key ID and Secret. You only see the secret once.

### Step 2: Install the tools

Open **PowerShell as Administrator**:

```powershell
winget install Hashicorp.Terraform
winget install Amazon.AWSCLI
winget install Git.Git          # skip if you already have Git Bash
```

Optional but used in the CI pipeline (and good to show):

```powershell
choco install tflint            # needs Chocolatey: https://chocolatey.org/install
pip install checkov             # needs Python 3
```

Close and reopen Git Bash, then check:

```bash
terraform -version     # needs 1.11 or newer
aws --version
```

> Tip: if you later need multiple Terraform versions, look up `tfenv` (Mac/Linux) or `tfswitch` (Windows). Good interview answer for "how do you manage Terraform versions?".

### Step 3: Connect the AWS CLI to your account

```bash
aws configure
# AWS Access Key ID:     <from step 1>
# AWS Secret Access Key: <from step 1>
# Default region name:   ap-south-1
# Default output format: json

aws sts get-caller-identity    # should print your account ID and terraform-admin
```

Terraform reads the same credentials automatically. Nothing secret ever goes into the `.tf` files.

### Step 4: Get the project and put it in Git

```bash
cd ~
unzip terraform-aws-platform.zip     # or extract it in Explorer
cd terraform-aws-platform
git init
git add .
git commit -m "first version of terraform aws platform"
```

### Step 5: Bootstrap the state bucket (run once)

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: put your email in budget_email

terraform init      # downloads the AWS provider
terraform plan      # read it! should say 6 to add
terraform apply     # type: yes
```

When it finishes, copy the `next_step` output. Then go back to the root and create `backend.hcl`:

```bash
cd ..
cp backend.hcl.example backend.hcl
# edit backend.hcl: replace the bucket name with the state_bucket_name output
```

AWS will send a "confirm subscription" email for the budget alert. Click it.

**Why is this a separate step?** Terraform needs the bucket to store state, but the bucket is itself infrastructure. So we build it once with local state. This "chicken and egg" problem is a common interview question.

### Step 6: Deploy dev

```bash
cd envs/dev
terraform init -backend-config=../../backend.hcl
terraform fmt -recursive ../..   # tidy formatting
terraform validate
terraform plan -out=tfplan        # save the plan
terraform apply tfplan            # apply exactly what you reviewed
```

You'll see `website_urls` at the end. **Wait about 60 seconds** (nginx is installing), then open the URL in your browser. You should see "Hello from web-1".

The `check "website_is_up"` block may show a warning on the very first apply because nginx isn't ready yet. Run `terraform plan` again after a minute and the warning disappears. That's expected and a nice thing to explain.

Look around:

```bash
terraform output
terraform state list
terraform state show 'module.compute.aws_instance.web["web-1"]'
```

> Tip: always wrap addresses that contain `["..."]` in single quotes, otherwise the shell eats the double quotes.

### Step 7: Deploy prod (optional, same pattern)

```bash
cd ../prod
terraform init -backend-config=../../backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

Prod has 2 servers in 2 AZs plus private subnets. Same modules, different `terraform.tfvars`. Destroy it once you've seen it work.

### Step 8: Do the labs

Open **[LABS.md](LABS.md)**. This is where the interview prep really happens: drift, import, state moves, locking, replace, tests. Each lab takes 5 to 15 minutes.

### Step 9: Set up CI/CD on GitHub (optional, great for interviews)

1. Create an empty repo on GitHub, e.g. `terraform-aws-platform` (public, so you can share the link).
2. Tell the bootstrap stack about it so it creates the OIDC role:
   ```bash
   cd bootstrap
   # in terraform.tfvars set: github_repo = "your-username/terraform-aws-platform"
   terraform apply
   terraform output github_actions_role_arn
   ```
3. In GitHub: **Settings > Secrets and variables > Actions > New repository secret**
   - `AWS_ROLE_ARN` = the role ARN from above
   - `TF_STATE_BUCKET` = your state bucket name
4. **Settings > Environments**: create `dev` and `prod`. On `prod`, tick **Required reviewers** and add yourself.
5. Push:
   ```bash
   git remote add origin https://github.com/your-username/terraform-aws-platform.git
   git branch -M main
   git push -u origin main
   ```
6. Make a change on a branch (e.g. change a tag), open a pull request, and watch the plan get posted as a PR comment. Merge it and watch dev apply, then prod wait for your approval.

The **drift-detection** workflow runs daily at 09:00 IST and opens an issue if anything was changed by hand. You can also run it manually from the Actions tab.

### Step 10: Clean up (do this every time you're done)

```bash
cd envs/prod && terraform destroy     # if you deployed prod
cd ../dev    && terraform destroy
```

To remove everything including the state bucket (only when you're completely finished with the project):

```bash
cd ../../bootstrap
# 1. In main.tf, change prevent_destroy = true  ->  false
# 2. Then:
terraform apply      # updates the lifecycle setting
terraform destroy
```

---

## How to pitch this in an interview (30 seconds)

> "I built a Terraform platform on AWS with reusable network, security and compute modules, separate dev and prod root modules, and remote state in S3 with native locking. Changes go through GitHub Actions: on a PR it runs fmt, tflint, checkov and module tests, then posts the plan as a comment. On merge it applies the saved plan to dev, and prod waits for an approval. CI authenticates with OIDC so there are no AWS keys in GitHub. A scheduled job runs a refresh-only plan every morning and opens an issue if someone changed infrastructure by hand. I also practiced drift recovery, imports, moved blocks and state surgery on it."

Then let them pick a thread to dig into. **[INTERVIEW-QA.md](INTERVIEW-QA.md)** has the follow-up questions.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Error acquiring the state lock` | Someone (or a crashed run) holds the lock. Wait, or see Lab 6 for `force-unlock`. |
| `BucketAlreadyExists` on bootstrap | Change `project` in `terraform.tfvars`. |
| `No valid credential sources found` | Run `aws configure` / `aws sts get-caller-identity`. |
| Website doesn't load | Wait 60s after apply. Check the SG allows port 80. Make sure you used `http://`, not `https://`. |
| `Unsupported Terraform Core version` | Upgrade Terraform to 1.11+ (`winget upgrade Hashicorp.Terraform`). |
| Want to see what Terraform is doing | `export TF_LOG=DEBUG` then run the command. `unset TF_LOG` to stop. |
