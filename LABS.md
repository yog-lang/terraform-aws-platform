# Hands-on Labs

Each lab = one interview topic you'll be able to answer from experience, not from memory.

**Before you start:** dev is deployed (README Step 6) and you're in Git Bash. Most labs run from `envs/dev`:

```bash
cd ~/terraform-aws-platform/envs/dev
```

Commit before each lab (`git commit -am "before lab X"`) so you can always `git checkout .` back to a clean state.

| # | Lab | Interview topic |
|---|---|---|
| 1 | Read the state | What is state, why it matters |
| 2 | Drift: someone opened a port by hand | Detecting and reverting drift |
| 3 | Drift: someone added a tag by hand | Accepting drift, `-refresh-only` |
| 4 | Drift: someone deleted a server | Missing resources |
| 5 | Import a hand-made bucket | `import` blocks, config generation |
| 6 | State locking | Two people running apply at once |
| 7 | Rename without destroying | `moved` blocks, `state mv` |
| 8 | Forget and re-adopt a resource | `state rm` + import |
| 9 | Force a rebuild | `-replace` (the new `taint`) |
| 10 | count vs for_each | Why keys matter |
| 11 | Guardrails | Validation, `prevent_destroy` |
| 12 | Tests, lint, security scan | Quality gates |
| 13 | Workspaces | Workspaces vs directories |
| 14 | Console and debugging | `terraform console`, `TF_LOG` |

---

## Lab 1: Read the state

State is Terraform's notebook: "I built these things, here are their IDs." Without it, Terraform has no idea what it owns.

```bash
terraform state list
terraform state show module.security.aws_security_group.web
terraform output -json
```

Peek at the raw file in S3 (never edit it by hand):

```bash
BUCKET=$(grep bucket ../../backend.hcl | cut -d'"' -f2)
aws s3 ls s3://$BUCKET/ --recursive
aws s3api list-object-versions --bucket $BUCKET --prefix dev/ --query 'Versions[].{v:VersionId,date:LastModified}' --output table
```

Every apply created a new version. That's your undo button if state ever gets corrupted.

**Say in interview:** "State maps code to real resource IDs, stores attributes for dependencies, and speeds up plans. It's sensitive (can contain secrets) so it lives in an encrypted, versioned, private bucket with locking, never in Git."

---

## Lab 2: Drift - someone opened a port by hand

Story: a teammate "temporarily" opened port 8080 in the console to debug something and forgot.

```bash
SG=$(terraform output -raw web_sg_id)
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 8080 --cidr 0.0.0.0/0
```

Now detect it, three ways:

```bash
# 1) Our drift script (refresh-only plan with exit codes)
../../scripts/drift-check.sh dev
echo "exit code: $?"          # 2 = drift found

# 2) A normal plan - shows what apply would do to fix it
terraform plan
```

You'll see the SG with `~ update in-place` and the 8080 rule marked `-` (to be removed). Terraform owns the full rule list (inline rules), so anything extra is drift.

Fix it (code wins):

```bash
terraform apply
../../scripts/drift-check.sh dev    # exit 0, clean again
```

**Say in interview:** "`plan -refresh-only` shows only changes made outside Terraform. `-detailed-exitcode` returns 2 when there's a difference, so I run it on a schedule in CI and open an issue when it fires. To fix, I either apply to revert, or if the manual change was right, I put it in code."

---

## Lab 3: Drift - someone added a tag by hand (accepting drift)

Story: finance added an `Owner` tag in the console, and they want to keep it.

```bash
ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=tfplatform-dev-web-1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ec2 create-tags --resources $ID --tags Key=Owner,Value=finance
```

Option A, accept into **state** only:

```bash
terraform plan -refresh-only      # shows Owner tag appeared
terraform apply -refresh-only     # state now records it
terraform plan                    # ...but plan STILL wants to remove it!
```

Why? State now matches AWS, but **code** still says "no Owner tag". Refresh-only updates the notebook, it doesn't rewrite the instructions.

Option B, accept properly by putting it in code. Add to `terraform.tfvars`:

```hcl
instance_tags = {
  Owner = "finance"
}
```

```bash
terraform plan     # No changes. Code, state and AWS all agree.
```

**Lesson:** there are three things that must agree: **code, state, and real AWS**. Drift is AWS disagreeing with state. Accepting drift for real means updating the code.

---

## Lab 4: Drift - someone deleted a server

```bash
ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=tfplatform-dev-web-1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ec2 terminate-instances --instance-ids $ID
```

Wait a minute, then:

```bash
terraform plan
```

Terraform refreshes, sees the instance is gone, drops it from its view, and plans to **create** a new one. Apply to heal:

```bash
terraform apply
```

**Bonus thought:** what about changes Terraform does NOT see? Our compute module has `ignore_changes = [ami]`, so a newer AMI is never "drift". That's deliberate. Be ready to explain when you'd use `ignore_changes` (fields changed by other systems, like autoscaler desired counts or AMI updates handled by a separate process) and why overusing it hides real drift.

---

## Lab 5: Import a hand-made bucket

Story: before Terraform, someone created an S3 bucket by hand. Bring it under Terraform without recreating it.

```bash
cd ~/terraform-aws-platform/labs/import-lab

# 1) Create the "legacy" bucket by hand
NAME=tfplatform-legacy-$RANDOM
aws s3api create-bucket --bucket $NAME --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
echo $NAME
```

2) In `main.tf`, uncomment the `import` block and put your bucket name in `id`.

3) Let Terraform write the code for you:

```bash
terraform init
terraform plan -generate-config-out=generated.tf
```

Open `generated.tf`: Terraform wrote an `aws_s3_bucket.legacy` resource. Clean it up if needed (remove null values) and:

```bash
terraform plan     # "1 to import, 0 to add, 0 to change, 0 to destroy"
terraform apply
terraform plan     # No changes. It's managed now.
```

After importing you can delete the `import` block (it's a one-time instruction). Clean up:

```bash
terraform destroy
```

**Old way vs new way:** `terraform import aws_s3_bucket.legacy <name>` (CLI) changes state immediately with no plan and you write the code yourself. The `import` block (1.5+) goes through plan/apply, can be reviewed in a PR, works in CI, and can generate the code.

---

## Lab 6: State locking

Open **two Git Bash windows**, both in `envs/dev`.

Window 1:
```bash
terraform apply     # don't answer yes yet, leave it waiting
```

Window 2:
```bash
terraform plan
```

Window 2 fails with `Error acquiring the state lock` and shows who holds it. While window 1 waits, look in S3:

```bash
aws s3 ls s3://$BUCKET/dev/      # terraform.tfstate.tflock is there
```

(If `$BUCKET` is empty in this window, set it again the same way as in Lab 1.)

Type `no` in window 1. The lock file disappears.

If a run crashes and leaves a stale lock:

```bash
terraform force-unlock <LOCK_ID>   # only when you're SURE nobody is running
```

**Say in interview:** "Locking stops two applies from writing state at the same time and corrupting it. We used to need a DynamoDB table for S3 backends; since Terraform 1.11, `use_lockfile = true` locks with a file in S3 itself. In CI I also set a concurrency group so pipelines queue instead of colliding."

---

## Lab 7: Rename without destroying (`moved`)

In `envs/dev/main.tf`, rename `module "compute"` to `module "web"`. Update the two places that reference it (`module.compute.urls` in the check block, and `outputs.tf`).

```bash
terraform plan
```

Scary: it wants to **destroy** the server and create a new one, because to Terraform a new address = a new thing.

Add this to `main.tf`:

```hcl
moved {
  from = module.compute
  to   = module.web
}
```

```bash
terraform plan     # "has moved to module.web" and 0 to destroy
terraform apply
```

The CLI equivalent is `terraform state mv module.compute module.web`, but `moved` blocks are better: reviewed in a PR, work for everyone who uses the module, no manual state commands.

Undo with `git checkout .` and another `moved` back, or keep it.

---

## Lab 8: Forget and re-adopt a resource (`state rm` + import)

```bash
SG=$(terraform output -raw web_sg_id)
terraform state rm module.security.aws_security_group.web
terraform plan
```

Terraform plans to **create** a new SG. The old one still exists in AWS, Terraform just forgot it. `state rm` never deletes real things. (Real-world use: handing a resource to another team's stack.)

Re-adopt it. Add to `envs/dev/main.tf` (use your real SG ID from `echo $SG`):

```hcl
import {
  to = module.security.aws_security_group.web
  id = "sg-xxxxxxxxxxxx"
}
```

```bash
terraform plan     # 1 to import, nothing to create
terraform apply
```

Remove the `import` block afterwards.

---

## Lab 9: Force a rebuild (`-replace`)

Story: a server is acting weird and you want a fresh one, but its config hasn't changed.

```bash
terraform plan  -replace='module.compute.aws_instance.web["web-1"]'
terraform apply -replace='module.compute.aws_instance.web["web-1"]'
```

`terraform taint` did this in older versions; it's deprecated because `-replace` shows you the plan first instead of silently marking state.

---

## Lab 10: count vs for_each

Add a second server in `terraform.tfvars`:

```hcl
instances = {
  "web-1" = "t3.micro"
  "web-2" = "t3.micro"
}
```

Apply. Now remove `web-1` and keep `web-2`. Plan:

```bash
terraform plan    # only web-1 is destroyed, web-2 untouched
```

With `count`, servers are `[0]` and `[1]`. Remove the first and the second slides into slot `[0]`, so Terraform would modify or rebuild it. With `for_each` each server has a name, so removing one never touches the others.

**Rule of thumb:** `count` for "0 or 1 of something" (optional resources, like the budget in bootstrap). `for_each` for collections.

Put it back to just `web-1` and apply.

---

## Lab 11: Guardrails

Try each, read the error, then undo:

```hcl
# terraform.tfvars
instances = { "web-1" = "m5.large" }   # blocked by cost validation
admin_cidr = "0.0.0.0/0"               # blocked: SSH open to the world
vpc_cidr = "10.10.0.0/28"              # blocked: too small
```

```bash
terraform plan
```

Then try deleting the state bucket:

```bash
cd ../../bootstrap
terraform destroy      # refused: prevent_destroy
```

**Say in interview:** "I push guardrails left: validation in variables catches bad input at plan time, before anything touches AWS. `prevent_destroy` protects critical resources like state buckets and databases. For org-wide rules I'd add policy-as-code like OPA/Conftest or Sentinel on top."

---

## Lab 12: Tests, lint, security scan

```bash
cd ~/terraform-aws-platform/modules/network
terraform init
terraform test           # mocked AWS, runs in seconds, costs nothing

cd ~/terraform-aws-platform
terraform fmt -check -recursive
tflint --init && tflint --recursive
checkov -d . --framework terraform --compact
```

Read the checkov findings. Some are real improvements (e.g. VPC flow logs, detailed monitoring), some are accepted risks for a lab (public web server). Being able to say "I triaged the findings and accepted X because Y" is a strong interview answer.

---

## Lab 13: Workspaces

Use the import-lab folder (local state, safe):

```bash
cd ~/terraform-aws-platform/labs/import-lab
terraform workspace list
terraform workspace new test
terraform workspace show
ls terraform.tfstate.d/      # each workspace gets its own state
terraform workspace select default
terraform workspace delete test
```

**Why this project uses directories (envs/dev, envs/prod) instead:** workspaces share the same code and backend config, it's easy to apply to the wrong one by accident, and you can't easily give prod different providers or permissions. Directories make the environment obvious from where you're standing. Workspaces are fine for short-lived copies (like a feature-branch environment).

---

## Lab 14: Console and debugging

```bash
cd ~/terraform-aws-platform/envs/dev
terraform console
```

Try:

```hcl
cidrsubnet("10.10.0.0/16", 8, 5)
local.azs
module.compute.urls
[for k, v in module.compute.public_ips : "${k} => ${v}"]
exit
```

Debug logging:

```bash
export TF_LOG=DEBUG
terraform plan 2> debug.log
unset TF_LOG
grep -i "request" debug.log | head
```

Dependency graph:

```bash
terraform graph > graph.dot     # paste into https://dreampuf.github.io/GraphvizOnline
```

---

When you've done all 14, you've handled more real Terraform incidents than most people who list it on their CV. Don't forget `terraform destroy` at the end of each session.
