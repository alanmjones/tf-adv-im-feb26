
# 🧩 Use Case Scenario (Enterprise Production)

## Story

Your org runs a **multi-team AWS production platform**:

* **Network Team** owns VPC, subnets, NAT, routes
* **App Team** owns ALB + ASG/EC2 + Security Groups
* **Data Team** owns RDS + private access

Everything is managed with Terraform, but **production issues happen**:

1. **State corruption / accidental overwrite**
2. **Manual deletion in AWS** (drift)
3. **Emergency change** caused wrong update
4. Team refactors module paths → state addresses must move safely
5. Need **dependency visibility** before change (terraform graph)
6. Must align with **enterprise change control** (PR → plan → review → approval → apply)

This module teaches Terraform as an **operated production platform**, not “just provisioning.” 

---

# 🧪 Lab Manual: Production Ops + State DR + Emergency Recovery

## 🎯 Lab Objectives

By end of this lab, students will be able to:

* Build an **enterprise Terraform repo layout** (multi-env + multi-team)
* Configure **remote backend** (S3 + DynamoDB lock)
* Enable **state DR** (S3 versioning + optional CRR concept)
* Generate infra dependency diagram using **terraform graph**
* Handle drift and emergencies using **terraform state** commands safely
* Follow a **governed pipeline workflow** (PR plan-only + main apply)

(These align directly to the module goals.) 

---

## ✅ Assumptions / Dependencies

### Tools

* Terraform >= 1.5
* AWS CLI configured on your lab VM OR (preferred) **VM has IAM Role** already
* Graphviz installed (`dot`) for terraform graph visualization

### AWS Permissions (IAM Role / User)

Minimum for this lab:

* S3: create bucket, versioning, read/write objects
* DynamoDB: create table, read/write locks
* EC2/VPC: create VPC, subnets, SG, EC2
* (Optional) S3 replication if you do CRR demo

### Region & Naming

* Region: `us-west-2` (change if needed)
* Project name: `cloudapp`
* Environments: `dev`, `stage`, `prod`

---

# 1) Enterprise Repo Structure

Create this structure (live + reusable modules) :

```
terraform-live/
  environments/
    dev/
      network/
      app/
      data/
    stage/
      network/
      app/
      data/
    prod/
      network/
      app/
      data/
  modules/
    vpc/
    ec2-app/
    rds/
    security-groups/
```

### Why this structure works (production)

* Teams own their folder (blast radius control)
* Reusable modules
* Environment separation
* Easier governance + approvals 

---

# 2) Build Remote Backend + DR (S3 + Versioning + DynamoDB Lock)

## Step 2.1 Create backend resources (one-time bootstrap)

Create folder:

`terraform-live/bootstrap-backend/`

### `provider.tf`

```hcl
provider "aws" {
  region = "us-west-2"
}
```

### `main.tf`

```hcl
resource "aws_s3_bucket" "tf_state" {
  bucket = "cloudapp-prod-terraform-state-12345" # must be globally unique
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "tf_locks" {
  name         = "cloudapp-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket" { value = aws_s3_bucket.tf_state.bucket }
output "lock_table"   { value = aws_dynamodb_table.tf_locks.name }
```

Run:

```bash
cd terraform-live/bootstrap-backend
terraform init
terraform apply -auto-approve
```

✅ You now have:

* S3 bucket with **versioning** (key DR feature) 
* DynamoDB lock table (prevents concurrent applies) 

---

# 3) Configure Backend in Each Layer (Network/App/Data)

Example: `terraform-live/environments/prod/network/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket         = "cloudapp-prod-terraform-state-12345"
    key            = "prod/network/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "cloudapp-terraform-locks"
    encrypt        = true
  }
}
```

Do similarly for:

* `prod/app` → key `prod/app/terraform.tfstate`
* `prod/data` → key `prod/data/terraform.tfstate`

This is the exact best practice described in the module. 

---

# 4) Create Minimal Modules + Environment Wiring

## 4.1 Module: VPC (modules/vpc)

`modules/vpc/variables.tf`

```hcl
variable "env" { type = string }
variable "vpc_cidr" { type = string }
```

`modules/vpc/main.tf`

```hcl
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags = { Name = "cloudapp-${var.env}-vpc" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
  tags = { Name = "cloudapp-${var.env}-public-a" }
}

output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_id" { value = aws_subnet.public_a.id }
```

## 4.2 Prod Network Layer (environments/prod/network)

`environments/prod/network/main.tf`

```hcl
provider "aws" { region = "us-west-2" }

module "vpc" {
  source   = "../../../modules/vpc"
  env      = "prod"
  vpc_cidr = "10.10.0.0/16"
}

output "vpc_id"           { value = module.vpc.vpc_id }
output "public_subnet_id" { value = module.vpc.public_subnet_id }
```

Run:

```bash
cd terraform-live/environments/prod/network
terraform init
terraform apply -auto-approve
```

---

# 5) Visualize Dependencies with terraform graph

In `prod/network`:

```bash
terraform graph | dot -Tpng > infra-graph.png
ls -lh infra-graph.png
```

✅ Students will see dependencies: VPC → Subnet etc.
This is specifically called out in Module 4. 

---

# 6) Production Drift Simulation + Safe Recovery

## 6.1 Simulate drift (manual delete)

Go to AWS Console:

* Delete the subnet created by Terraform

Now run:

```bash
terraform plan
```

Expected:

* Terraform detects missing subnet and plans to recreate (drift detection)

### Optionally refresh state (older TF had refresh)

```bash
terraform refresh
terraform plan
```

Module notes drift + reconciliation workflows. 

---

# 7) Emergency State Operations (State Surgery)

> **Rule in real prod:** always take a backup + record ticket/CAB reference before state surgery.

## 7.1 Backup state locally

```bash
terraform state pull > state-backup-prod-network.json
```

## 7.2 `terraform state rm` (remove from state only)

Use case: resource exists but you want Terraform to stop managing it (temporary manual ownership).

Example:

```bash
terraform state list
terraform state rm aws_subnet.public_a
```

✅ It removes mapping from state but does NOT destroy in AWS. 

## 7.3 `terraform state mv` (refactor safe move)

Use case: you renamed a resource or moved it under a module path.

Example (illustrative):

```bash
terraform state mv aws_subnet.public_a module.vpc.aws_subnet.public_a
```

✅ This avoids destroy/recreate during refactors. 

---

# 8) DR: Recover from Corrupted / Bad State Version (S3 Versioning)

## 8.1 Simulate a bad state push

(For training only) you can simulate a wrong change by applying a config that deletes something important.

Then you “recover” using S3 versioning.

### Steps (conceptual recovery flow)

1. Find previous S3 object versions (in console)
2. Restore the last known good version
3. Validate:

   ```bash
   terraform state list
   terraform plan
   ```

This is exactly the DR approach described in module: “restore previous S3 version.” 

---

# 9) Governance Workflow (PR → Plan → Review → CAB → Apply)

## 9.1 PR pipeline (plan only, backend disabled)

Use this for PR validation to avoid touching locks/state (your earlier requirement).

```bash
terraform init -backend=false
terraform validate
terraform plan -no-color
```

## 9.2 Main branch (controlled apply)

* `terraform init` (real backend)
* manual approval gate
* `terraform apply`

This matches the enterprise workflow described (review/approval gates, CAB, controlled apply). 

---

# ✅ Student Deliverables Checklist

Students must submit:

1. Screenshot or file: `infra-graph.png`
2. Proof of remote backend working:

   * `terraform init` shows S3 backend
3. Drift demo output:

   * plan shows recreate after manual delete
4. State backup file:

   * `state-backup-prod-network.json`
5. One state surgery command executed (with explanation):

   * state rm OR state mv
6. Short “change record” note:

   * what was changed, why, what validation done

---

# 🧯 Instructor Troubleshooting Cheatsheet

* **Lock stuck**: check DynamoDB item; last resort:

  ```bash
  terraform force-unlock <LOCK_ID>
  ```
* **Graphviz missing**:

  * Ubuntu:

    ```bash
    sudo apt-get update && sudo apt-get install -y graphviz
    ```
* **Backend init issues**:

  * verify bucket/table names exactly match backend.tf
* **Drift not detected**:

  * ensure you deleted a Terraform-managed resource, not a different one

