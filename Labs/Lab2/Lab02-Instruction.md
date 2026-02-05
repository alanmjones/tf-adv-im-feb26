## Lab 11: Automated Validation Pipeline (Terraform + tflint + checkov)

### Lab outcome

By the end of this lab, students will be able to:

* Add **static validation gates** (lint + security/compliance) to a Jenkins pipeline
* **Fail builds/PR checks** on policy violations (e.g., public S3, open SG, missing tags)
* Fix Terraform code and re-run until the pipeline is **green**, then merge safely

---

# 1) Assumptions (Read First)

### Student prerequisites (already completed)

* Terraform basic + intermediate (providers, modules, variables, state basics, for_each, etc.)
* Basic Git branching + PR flow
* Basic Jenkins pipeline understanding

### Lab assumptions

* You have a **Jenkins server** reachable by students (or shared demo Jenkins).
* Jenkins agent/node can run Docker OR has tools installed locally.
* Terraform code is in a Git repo (GitHub/Bitbucket).
* No AWS access keys/secret keys are used. If needed, Jenkins agent uses an **IAM Role** (instance profile) to call AWS APIs.
  *Note:* This lab focuses on static scans; it does **not** need real AWS calls.

---

# 2) Dependencies (What you must have before the lab)

## A) Jenkins & Plugins

1. **Jenkins** (LTS recommended)
2. Plugins:

   * **Pipeline**
   * **Git**
   * **Credentials Binding** (optional)
   * **Multibranch Pipeline** (recommended for PR/branch automation)
   * **GitHub Branch Source** OR Bitbucket equivalent (for PR discovery)

## B) Runtime option (choose ONE)

### Option 1 (recommended): Docker available on Jenkins Agent

You’ll run tflint/checkov using containers (no need to install binaries).

* Docker installed and Jenkins user can run `docker` (Linux: in `docker` group)

### Option 2: Tools installed on Jenkins Agent

* `terraform`
* `tflint`
* `checkov`
* (Optional) `python3`, `pip` (if installing checkov via pip)
* Git client

## C) Repo Structure (minimum)

Your repo must contain:

* Terraform code folder (e.g., `infra/`)
* Jenkinsfile at repo root
* tflint config (`.tflint.hcl`)

---

# 3) Lab Files You Will Create

You will create these files in the repo:

```
.
├── Jenkinsfile
├── .tflint.hcl
├── .checkov.yml                 (optional but recommended)
└── infra
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf               (optional)
    └── versions.tf              (optional)
```

---

# 4) Policy Targets (what should fail)

Pipeline must fail if it detects:

* **Unencrypted S3 bucket**
* **Open security group (0.0.0.0/0)**
* **Missing required tags** (we’ll enforce via checkov custom policy or baseline tag checks)

> Reality check: Checkov has built-in checks for many AWS issues. For “required tags”, you can enforce via either:

* Checkov built-in tag checks (some exist depending on resource), AND/OR
* A simple custom policy (recommended in enterprise), AND/OR
* A local “terraform validate + grep” style check (not recommended, but simple)

In this lab, we’ll do:

* Built-in Checkov checks for S3 + SG
* A simple “required tags” enforcement using **Checkov custom policy** (clear and teachable)

---

# 5) Step-by-Step Lab Instructions

## Step 1 — Create a new branch for the lab

```bash
git checkout -b feature/security-scan
```

---

## Step 2 — Add intentionally “bad” Terraform code (to trigger failures)

Create `infra/main.tf`:

```hcl
provider "aws" {
  region = "us-west-2"
}

# ❌ BAD: Missing encryption, missing tags
resource "aws_s3_bucket" "bad_bucket" {
  bucket = "lab11-bad-bucket-demo-12345"
}

# ❌ BAD: Open to the world
resource "aws_security_group" "bad_sg" {
  name        = "lab11-open-sg"
  description = "Open SG for lab"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # <-- should fail
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

> Note: bucket name must be globally unique if you ever apply, but we are only scanning. Keep it as-is for scan-only labs.

---

## Step 3 — Add tflint configuration

Create `.tflint.hcl` at repo root:

```hcl
plugin "aws" {
  enabled = true
  version = "0.35.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  format = "compact"
}

rule "terraform_required_version" {
  enabled = true
}
```

---

## Step 4 — Add Checkov custom policy (Required tags)

Create a folder `.checkov/custom_policies/` and a policy file:

**`.checkov/custom_policies/required_tags.yaml`**

```yaml
metadata:
  name: "Require standard tags on AWS resources"
  id: "CKV_LAB_001"
  category: "CONVENTION"

definition:
  cond_type: "attribute"
  resource_types:
    - "aws_s3_bucket"
    - "aws_security_group"
  attribute: "tags"
  operator: "exists"
```

This checks that `tags` exists. Next, enforce specific keys.

Create another file:

**`.checkov/custom_policies/required_tag_keys.yaml`**

```yaml
metadata:
  name: "Require Owner and Environment tags"
  id: "CKV_LAB_002"
  category: "CONVENTION"

definition:
  and:
    - cond_type: attribute
      resource_types:
        - aws_s3_bucket
        - aws_security_group
      attribute: "tags.Owner"
      operator: "exists"
    - cond_type: attribute
      resource_types:
        - aws_s3_bucket
        - aws_security_group
      attribute: "tags.Environment"
      operator: "exists"
```

---

## Step 5 — Add optional Checkov config

Create `.checkov.yml` at repo root:

```yaml
quiet: true
download-external-modules: false
framework:
  - terraform
external-checks-dir:
  - .checkov/custom_policies
```

---

## Step 6 — Create the Jenkinsfile (Static Validation Gate)

Create `Jenkinsfile` at repo root.

### Recommended approach (Docker-based tools)

```groovy
pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
  }

  environment {
    TF_DIR = "infra"
  }

  stages {
    stage("Checkout") {
      steps {
        checkout scm
      }
    }

    stage("Terraform fmt (check)") {
      steps {
        sh """
          cd ${TF_DIR}
          terraform fmt -check -diff
        """
      }
    }

    stage("Terraform validate") {
      steps {
        sh """
          cd ${TF_DIR}
          terraform init -backend=false
          terraform validate
        """
      }
    }

    stage("tflint") {
      steps {
        sh """
          cd ${TF_DIR}
          # Run tflint via docker (no local install needed)
          docker run --rm \
            -v "$PWD:/data" -w /data \
            ghcr.io/terraform-linters/tflint:latest \
            --init

          docker run --rm \
            -v "$PWD:/data" -w /data \
            ghcr.io/terraform-linters/tflint:latest \
            --recursive
        """
      }
    }

    stage("checkov") {
      steps {
        sh """
          # Run checkov via docker and scan terraform directory
          docker run --rm \
            -v "$PWD:/repo" -w /repo \
            bridgecrew/checkov:latest \
            -d ${TF_DIR} \
            --config-file .checkov.yml
        """
      }
    }
  }

  post {
    always {
      echo "Static validation completed."
    }
  }
}
```

### If you are NOT using Docker (local tools installed)

Replace the `tflint` and `checkov` stages with:

```groovy
stage("tflint") {
  steps {
    sh """
      cd ${TF_DIR}
      tflint --init
      tflint --recursive
    """
  }
}

stage("checkov") {
  steps {
    sh """
      checkov -d ${TF_DIR} --config-file .checkov.yml
    """
  }
}
```

---

## Step 7 — Commit and push the branch

```bash
git add .
git commit -m "Lab11: Add tflint + checkov static validation in Jenkins"
git push -u origin feature/security-scan
```

---

# 6) Jenkins Setup (How to make it run automatically)

## Option A (Best): Multibranch Pipeline

1. Jenkins → **New Item** → **Multibranch Pipeline**
2. Branch Source:

   * GitHub / Bitbucket repo
3. Enable:

   * Discover branches
   * Discover PRs (recommended)
4. Save → “Scan Repository Now”

✅ Jenkins will automatically build:

* `feature/security-scan`
* PRs targeting `main` (if configured)

## Option B: Single Pipeline Job (manual branch build)

* Jenkins → Pipeline job → configure SCM
* Build with parameter `BRANCH_NAME` (or change branch in SCM config)

---

# 7) Validate the “Block Merge” behavior (PR gating)

## Step 8 — Create a PR

* Create PR: `feature/security-scan` → `main`
* Jenkins should run automatically on PR (multibranch PR discovery)

## Step 9 — Confirm build fails (expected)

You should see failures such as:

* Checkov: public SG / S3 encryption missing
* Custom policies: tags missing

✅ This is the “merge block” moment:

* In GitHub: require status checks to pass before merge
* In Bitbucket: merge checks / build must pass

> Dependency reminder: Repo settings must enforce “required checks.”
> Otherwise, Jenkins failing won’t block merge automatically.

---

# 8) Fix the violations (Make pipeline green)

## Step 10 — Fix Terraform: add encryption + tags + restrict SG

Update `infra/main.tf`:

```hcl
provider "aws" {
  region = "us-west-2"
}

locals {
  common_tags = {
    Owner       = "training"
    Environment = "dev"
  }
}

resource "aws_s3_bucket" "good_bucket" {
  bucket = "lab11-good-bucket-demo-12345"

  tags = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.good_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_security_group" "good_sg" {
  name        = "lab11-locked-sg"
  description = "Restricted SG for lab"

  # Example: restrict SSH to a private CIDR (training LAN/VPN)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}
```

> Note: We replaced the bad resources with good ones to avoid lingering scan findings.

---

## Step 11 — Commit and push again

```bash
git add infra/main.tf
git commit -m "Lab11: Fix checkov violations (encryption, tags, restricted SG)"
git push
```

✅ Jenkins should re-run and become **GREEN**.

---

# 9) Verification Checklist (What to confirm)

Students must capture screenshots/log snippets showing:

### A) Failed run evidence

* `checkov` stage failed
* Findings show:

  * S3 encryption missing
  * SG open to 0.0.0.0/0
  * tags missing (CKV_LAB_001/002)

### B) Fixed run evidence

* All stages pass:

  * `terraform fmt -check`
  * `terraform validate`
  * `tflint`
  * `checkov`

### C) PR gate evidence

* Merge was blocked when pipeline failed
* Merge allowed after green build

---

# 10) Common Issues & Troubleshooting (Instructor cheat sheet)

### 1) Docker permission denied

**Symptom:** `permission denied while trying to connect to the Docker daemon socket`
**Fix:** add Jenkins user to docker group and restart agent, or run on node where Docker is permitted.

### 2) Checkov finds “unknown” or noisy results

* Ensure you are scanning the correct directory: `-d infra`
* Keep `download-external-modules: false` in `.checkov.yml` to reduce noise

### 3) PR not triggering automatically

* Ensure Multibranch has PR discovery enabled
* Ensure webhook is configured (GitHub/Bitbucket)
* Try “Scan repository now”

### 4) “Required checks” not blocking merge

* Repo settings must enforce “status checks required”
* The Jenkins check name must match the required check name

---

# 11) Student Deliverables (What to submit)

1. Repo with:

   * Jenkinsfile
   * `.tflint.hcl`
   * `.checkov.yml`
   * `.checkov/custom_policies/*`
   * Terraform code (bad + fixed via commits)
2. PR link (feature → main)
3. Evidence:

   * 1 failed build log snippet
   * 1 successful build log snippet
   * Screenshot showing merge blocked then allowed

