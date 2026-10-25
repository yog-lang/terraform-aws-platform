# Terraform Interview Q&A

Short answers you can say out loud, each tied to something you actually built in this repo. Interviewers love "here's how I did it in my project" more than textbook definitions.

---

## 1. Basics

**Q: What is Terraform and why use it over clicking in the console?**
It's infrastructure as code: you describe what you want, Terraform works out how to get there. Benefits: repeatable (dev and prod built the same way), reviewable (changes go through PRs), versioned (Git history = infra history), and self-documenting. Console clicks can't be reviewed, repeated, or rolled back.

**Q: Declarative vs imperative?**
Declarative = "I want 2 servers" (Terraform). Imperative = "create a server, then create another" (a bash script). Run a declarative config twice and you still have 2 servers; run the script twice and you have 4.

**Q: Explain the core workflow.**
`init` (download providers, connect backend) → `plan` (show the diff between code and reality) → `apply` (make the changes) → `destroy` (tear down). In this repo I also save the plan with `-out=tfplan` and apply that file, so what gets applied is exactly what was reviewed.

**Q: What's a provider?**
A plugin that translates Terraform into API calls for one platform (AWS, Kubernetes, GitHub...). Like a translator between Terraform and AWS. Pinned in `versions.tf` with `~> 6.0`.

**Q: What does `terraform init` actually do?**
Downloads providers and modules, sets up the backend (where state lives), and writes `.terraform.lock.hcl`.

**Q: What's `.terraform.lock.hcl` and do you commit it?**
Yes, commit it. It pins exact provider versions and checksums, so my laptop and CI use the identical provider. `terraform init -upgrade` updates it deliberately.

**Q: Version constraints: `~> 6.0` vs `>= 6.0`?**
`~> 6.0` means 6.x but not 7.0 (no surprise major upgrades). I use `~>` in root modules and the looser `>= 6.0` in reusable modules so they don't fight the caller's choice.

---

## 2. State

**Q: What is Terraform state?**
Terraform's notebook of what it built: maps each resource in code to a real ID in AWS, plus its attributes. Without it, Terraform can't know that `aws_instance.web["web-1"]` is `i-0abc123`.

**Q: Why remote state? Where do you keep it?**
Local state on a laptop can't be shared, gets lost, and has no locking. I keep it in S3: versioned (undo button), encrypted (state can hold secrets), public access blocked, and locked. See `bootstrap/`.

**Q: How does state locking work?**
When a run starts it takes a lock; anyone else gets "Error acquiring the state lock". Prevents two applies corrupting state. Since Terraform 1.11, S3 has native locking with `use_lockfile = true` (a `.tflock` file next to the state), so the DynamoDB table is no longer needed. I demoed it with two terminals (Lab 6).

**Q: How do you create the state bucket if Terraform needs state to create it?**
Chicken-and-egg. I have a separate `bootstrap` stack with local state that creates the bucket once. Everything else uses the bucket. Alternatives: create it by hand/CLI, or migrate bootstrap's own state into the bucket afterwards with `terraform init -migrate-state`.

**Q: Someone corrupted the state file. What do you do?**
Don't panic. The bucket is versioned, so restore the previous version of the object. Then run `terraform plan` to confirm it matches reality. For smaller problems use `terraform state` commands rather than editing JSON by hand.

**Q: `state mv`, `state rm`, `import` - when do you use each?**
- `state mv`: rename/move a resource address without recreating it (now usually a `moved` block instead)
- `state rm`: make Terraform forget a resource without deleting it (e.g. handing it to another stack)
- `import`: adopt an existing resource into Terraform
All practiced in Labs 5, 7, 8.

**Q: Is state sensitive?**
Yes. Marking a variable `sensitive` only hides it from CLI output, the value is still in state in plain text. So encrypt the bucket, restrict who can read it, and prefer fetching secrets at runtime (Secrets Manager, Vault) over passing them through Terraform.

---

## 3. Drift (they WILL ask this)

**Q: What is drift?**
When real infrastructure no longer matches what Terraform's state says, because someone changed it outside Terraform: a console click, a script, another tool. Like a room someone rearranged while you weren't looking; your floor plan is now wrong.

**Q: How do you detect drift?**
- `terraform plan` shows it mixed with code changes
- `terraform plan -refresh-only` shows only outside changes
- add `-detailed-exitcode` (0 = none, 1 = error, 2 = drift) for automation

In this project, `.github/workflows/drift-detection.yml` runs that every morning for dev and prod, opens a GitHub issue with the diff, and turns the job red. `scripts/drift-check.sh` does the same locally.

**Q: You found drift. Now what?**
Find out why first (who changed it and was it an emergency fix?). Then either:
1. **Code is right** → `terraform apply` reverts AWS to match code (Lab 2)
2. **The manual change is right** → put it in code; `terraform apply -refresh-only` updates state, but the code must change too or the next apply undoes it (Lab 3)

**Q: Difference between `terraform refresh` and `-refresh-only`?**
`terraform refresh` updates state silently with no review (deprecated). `plan -refresh-only` / `apply -refresh-only` shows you what would change in state and asks first.

**Q: How do you prevent drift?**
Remove console write access in prod (read-only for humans, changes through the pipeline), scheduled drift detection, SCPs/IAM policies, and a culture of "emergency fix = follow-up PR". Use `ignore_changes` only for attributes another system legitimately owns.

**Q: A resource was deleted by hand. What does Terraform do?**
On refresh it sees the resource is gone, removes it from state, and plans to create it again (Lab 4).

**Q: When is `ignore_changes` appropriate?**
When something else legitimately manages that field: autoscaler's desired count, tags added by a cost tool, or here the AMI (`modules/compute`) so a new Amazon Linux release doesn't replace every server on the next plan. Overusing it hides real drift.

---

## 4. Code and modules

**Q: What's a module? How do you structure them?**
A reusable folder of Terraform, like a function. Here: `network`, `security`, `compute`. Modules never configure providers (no region/credentials); root modules in `envs/` do that and wire modules together.

**Q: How do you manage multiple environments?**
Separate root directories (`envs/dev`, `envs/prod`) calling the same modules with different `terraform.tfvars` and separate state keys. Clear, safe, and prod can get stricter permissions. Workspaces work too but it's easy to apply to the wrong one (Lab 13). Terragrunt is a common tool to remove the remaining copy-paste between env folders.

**Q: `count` vs `for_each`?**
`count` gives numbered copies `[0] [1]`; remove one in the middle and the rest shift and get rebuilt. `for_each` gives named copies `["web-1"]`; remove one and only that one goes (Lab 10). I use `count` only for "create 0 or 1" (the budget and OIDC role in bootstrap).

**Q: What's a `dynamic` block?**
A loop that generates nested blocks, like the ingress rules in `modules/security` from a list variable.

**Q: `locals` vs `variables` vs `outputs`?**
Variables = inputs (function arguments). Locals = internal helper values (computed once, reused). Outputs = return values, readable by other modules or `terraform output`.

**Q: How do you validate inputs?**
`validation` blocks in variables. Mine block expensive instance types, SSH open to the world, and bad CIDRs at plan time (Lab 11).

**Q: What are data sources?**
Read-only lookups. I use them for the latest AMI, available AZs, and the account ID, so nothing is hard-coded.

**Q: Implicit vs explicit dependencies?**
Implicit: referencing another resource's attribute (`vpc_id = module.network.vpc_id`), Terraform figures out the order. Explicit: `depends_on` when there's a hidden dependency Terraform can't see (I use it for the S3 lifecycle rule needing versioning first). Prefer implicit.

**Q: Name the lifecycle arguments.**
- `create_before_destroy`: build new before deleting old (security group)
- `prevent_destroy`: refuse to delete (state bucket)
- `ignore_changes`: don't treat these fields as drift (AMI)
- `replace_triggered_by`: rebuild when something else changes
- `precondition` / `postcondition`: assertions (instance must have a public IP)

**Q: What are `check` blocks?**
Continuous validation (1.5+). They run on every plan/apply and warn, not fail. Mine checks the website returns HTTP 200.

**Q: `moved` blocks?**
Tell Terraform "this resource was renamed, don't destroy it". Reviewed in a PR, unlike `state mv` (Lab 7).

**Q: How do you test Terraform?**
`terraform validate` and `fmt` for syntax, `tflint` for mistakes, `checkov` for security, and `terraform test` with `mock_provider` for module logic without touching AWS (`modules/network/tests`). For real integration tests, apply to a throwaway environment and assert, e.g. with Terratest.

---

## 5. CI/CD and team workflow

**Q: Walk me through your Terraform pipeline.**
PR → fmt, tflint, module tests, checkov → plan for dev and prod, plan posted as a PR comment. Merge to main → apply the saved plan to dev → prod waits for manual approval (GitHub environment) → apply. A concurrency group stops two runs overlapping.

**Q: Why apply a saved plan file?**
Between review and apply, someone else could change things. Applying the saved plan guarantees you apply exactly what was approved; if state moved on, it fails safely instead of doing something new.

**Q: How does CI authenticate to AWS?**
OIDC. GitHub issues a short-lived token per run, AWS trusts GitHub's identity provider, and the role only trusts my repo (`bootstrap/main.tf`). No long-lived access keys stored anywhere. Like a hotel key card that expires, instead of a house key.

**Q: How do you handle secrets?**
Never in `.tf` or `.tfvars` in Git. Read them at runtime from Secrets Manager/Vault with a data source, or pass via `TF_VAR_` environment variables in CI. Mark them `sensitive`. Remember they still land in state, so lock state down.

**Q: How do you upgrade a provider safely?**
Read the changelog for breaking changes, bump the constraint, `terraform init -upgrade`, run plan in dev, look for unexpected replacements, then roll forward through environments.

**Q: `-target`: when is it OK?**
Emergencies only (fix one broken resource fast). Regular use means your state and code drift apart in confusing ways.

---

## 6. Scenario questions

**Q: Plan shows a resource will be destroyed and recreated, but you only renamed it.**
Add a `moved` block. Check the plan says "has moved" and 0 to destroy before applying.

**Q: Apply failed halfway. What state are you in?**
Terraform saves state after each resource, so whatever succeeded is recorded. Fix the error and run apply again; it continues from where reality is.

**Q: Lock is stuck after a CI runner died.**
Confirm nothing is actually running, then `terraform force-unlock <ID>`.

**Q: You need to bring 50 existing resources under Terraform.**
`import` blocks (can use `for_each` on import blocks in 1.7+) plus `terraform plan -generate-config-out` to draft the code, then clean up the generated code into modules. Do it in small batches, aiming for "0 to change" after each import.

**Q: Two teams need each other's outputs (e.g. VPC ID).**
`terraform_remote_state` data source, or better, publish the values somewhere neutral (SSM Parameter Store) and read them with a data source so teams aren't coupled to each other's state.

**Q: Terraform vs Ansible?**
Terraform builds the infrastructure (servers, networks). Ansible configures what's inside (packages, files). Here I used `user_data` for the small nginx setup; at scale I'd bake an image with Packer or use Ansible.

**Q: Terraform vs CloudFormation?**
CloudFormation is AWS-only and AWS manages state for you. Terraform works across clouds and SaaS (one tool for AWS + Kubernetes + GitHub + Datadog), bigger module ecosystem, but you manage state yourself.

**Q: What's OpenTofu?**
The open-source fork of Terraform after HashiCorp changed the license (BSL) in 2023, now under the Linux Foundation. Mostly compatible syntax and workflow.

**Q: Terraform with Kubernetes?**
Common pattern: Terraform builds the cluster and cloud bits (VPC, EKS/GKE, IAM, node pools), then a GitOps tool like Argo CD deploys apps into it. Terraform can manage K8s objects via the kubernetes/helm providers, but app deploys change often and fit GitOps better.

---

## 7. Questions to ask THEM at the end

- How do you organize Terraform across teams: monorepo, module registry, Terragrunt?
- How do you handle drift today, and who has console write access in prod?
- What's your policy-as-code setup (OPA, Sentinel, checkov in CI)?
