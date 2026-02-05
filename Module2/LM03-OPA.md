
# ✅ Docker-based OPA Policy Lab (Terraform + Conftest)

## 1) Folder Structure (same)

```bash
mkdir -p opa-terraform-lab/{terraform,policy}
cd opa-terraform-lab
```

---

## 2) Terraform code (FAIL case first)

### `terraform/main.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-west-2"
}

# ❌ Non-compliant: No encryption
resource "aws_s3_bucket" "demo_bucket" {
  bucket = "opa-demo-bucket-123456"
}
```

---

## 3) OPA Policy (same)

### `policy/s3_encryption.rego`

```rego
package terraform.security

deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket"

  not rc.change.after.server_side_encryption_configuration

  msg := sprintf("S3 bucket '%s' must have encryption enabled", [rc.name])
}
```

---

# 🐳 4) Run everything using Docker

## A) Terraform init/plan (no backend, no AWS calls needed)

We only generate a plan JSON locally. This does not create anything in AWS.

```bash
docker run --rm \
  -v "$PWD/terraform:/work" -w /work \
  hashicorp/terraform:1.6.6 \
  init -backend=false
```

```bash
docker run --rm \
  -v "$PWD/terraform:/work" -w /work \
  hashicorp/terraform:1.6.6 \
  plan -out=tfplan.binary
```

## B) Convert plan to JSON

```bash
docker run --rm \
  -v "$PWD/terraform:/work" -w /work \
  hashicorp/terraform:1.6.6 \
  show -json tfplan.binary > terraform/tfplan.json
```

✅ Now you have: `terraform/tfplan.json`

---

## C) Run OPA policy using Conftest Docker

```bash
docker run --rm \
  -v "$PWD:/project" -w /project \
  openpolicyagent/conftest:v0.45.0 \
  test terraform/tfplan.json --policy policy
```

### Expected Output (FAIL)

```text
FAIL - terraform/tfplan.json - S3 bucket 'demo_bucket' must have encryption enabled
```

---

# ✅ 5) Make Terraform compliant (PASS case)

Update Terraform:

### `terraform/main.tf` (PASS version)

```hcl
provider "aws" {
  region = "us-west-2"
}

resource "aws_s3_bucket" "demo_bucket" {
  bucket = "opa-demo-bucket-123456"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}
```

Rebuild plan JSON:

```bash
docker run --rm -v "$PWD/terraform:/work" -w /work hashicorp/terraform:1.6.6 plan -out=tfplan.binary
docker run --rm -v "$PWD/terraform:/work" -w /work hashicorp/terraform:1.6.6 show -json tfplan.binary > terraform/tfplan.json
```

Run conftest again:

```bash
docker run --rm \
  -v "$PWD:/project" -w /project \
  openpolicyagent/conftest:v0.45.0 \
  test terraform/tfplan.json --policy policy
```

### Expected Output (PASS)

```text
PASS - terraform/tfplan.json - All tests passed
```

---

# ✅ Optional: One-command runner for students

Create this file:

### `run.sh`

```bash
#!/usr/bin/env bash
set -e

echo "== Terraform init =="
docker run --rm -v "$PWD/terraform:/work" -w /work hashicorp/terraform:1.6.6 init -backend=false >/dev/null

echo "== Terraform plan =="
docker run --rm -v "$PWD/terraform:/work" -w /work hashicorp/terraform:1.6.6 plan -out=tfplan.binary >/dev/null

echo "== Terraform plan -> JSON =="
docker run --rm -v "$PWD/terraform:/work" -w /work hashicorp/terraform:1.6.6 show -json tfplan.binary > terraform/tfplan.json

echo "== OPA policy test (Conftest) =="
docker run --rm -v "$PWD:/project" -w /project openpolicyagent/conftest:v0.45.0 \
  test terraform/tfplan.json --policy policy
```

Run:

```bash
chmod +x run.sh
./run.sh
```

