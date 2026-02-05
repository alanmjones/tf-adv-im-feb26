# 📘 Module 1: Deep CI/CD Integration

### Jenkins + GitHub / Bitbucket + Terraform

**Duration:** 2 Hours
**Audience:** DevOps Engineers, Cloud Engineers, Platform Teams

This module focuses on building **production-ready CI/CD pipelines** using **Jenkins**, integrated with Git platforms like **GitHub** and **Bitbucket**, and infrastructure provisioning using **Terraform**. Learners will understand how to design resilient pipelines that handle failures, state locking, approvals, and secure authentication.

---

## 🎯 Learning Objectives

By the end of this module, you will understand:

* How to design **multi-environment CI/CD pipelines**
* How to enforce **PR-based validations and approval gates**
* How to implement **Terraform version and module locking**
* How to securely manage **remote state, authentication, and locking**
* How to diagnose and recover from **real production pipeline failures**

---

## 🤔 Why Do We Need Deep CI/CD Design?

### Real-World Problem

In production:

* Multiple engineers push code daily
* Infrastructure changes affect live environments
* A single bad deployment can cause downtime

Basic pipelines that just run `terraform apply` are **dangerous** because they:

* Skip validation steps
* Lack approval controls
* Fail unpredictably due to state locks or credential issues

### Solution

A properly designed CI/CD pipeline:

* Controls **who deploys**
* Controls **what gets deployed**
* Ensures **safe Terraform execution**
* Recovers from **pipeline failures automatically**

---

# 🧩 Topic 1: End-to-End Production Pipeline Design

### Key Concepts

| Stage          | Purpose                  |
| -------------- | ------------------------ |
| Feature Branch | Developer testing        |
| Staging        | Integration & validation |
| Production     | Live deployment          |

### Typical Flow

```
Developer → Feature Branch → Pull Request
        ↓
 Automated Validation (Terraform Plan)
        ↓
 Manual Approval
        ↓
 Merge to Staging → Apply
        ↓
 Merge to Production → Apply
```

### Jenkins Pipeline Structure (Example)

```groovy
pipeline {
  agent any

  stages {
    stage('Validate') {
      steps {
        sh 'terraform init'
        sh 'terraform validate'
      }
    }

    stage('Plan') {
      steps {
        sh 'terraform plan -out=tfplan'
      }
    }

    stage('Approval') {
      steps {
        input message: "Approve Terraform Apply?"
      }
    }

    stage('Apply') {
      steps {
        sh 'terraform apply tfplan'
      }
    }
  }
}
```

### 🗣 Speaker Notes

* Explain that **pipelines must mirror environment promotion**
* Emphasize: *Feature → Staging → Prod is not just branching — it’s risk control*
* Highlight why **manual approval is mandatory** for production infra
* Mention auditability — approvals create change traceability

---

# 🔁 Topic 2: PR-Based Automated Validation

When a developer raises a PR:

Pipeline should automatically run:

✔ `terraform fmt`
✔ `terraform validate`
✔ `terraform plan`

### Example Jenkins PR Validation Stage

```groovy
stage('PR Validation') {
  when { changeRequest() }
  steps {
    sh 'terraform init -backend=false'
    sh 'terraform validate'
    sh 'terraform plan -lock=false'
  }
}
```

### Why Backend Disabled?

We don’t want PR pipelines locking the real state.

### 🗣 Speaker Notes

* Explain difference between **PR pipeline vs deployment pipeline**
* PR pipeline = *validation only*, no state lock
* This prevents multiple developers from blocking each other

---

# 🔒 Topic 3: Terraform Version & Module Locking

### Problem

Without version control:

* Pipeline may use different Terraform versions
* Modules may change unexpectedly

### Solution

#### Terraform Version Pinning

```hcl
terraform {
  required_version = "~> 1.6.0"
}
```

#### Provider Version Lock

```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
}
```

#### Module Version Lock

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"
}
```

### 🗣 Speaker Notes

* Explain **pipeline consistency**
* Without pinning → pipeline may break overnight
* Version locking ensures **reproducible infrastructure**

---

# 🔐 Topic 4: Authentication & Remote State Management

Pipelines must securely access:

* Cloud provider credentials (AWS/Azure/GCP)
* Remote backend (S3, Azure Storage, etc.)

### Example Remote Backend (AWS S3)

```hcl
backend "s3" {
  bucket         = "company-terraform-state"
  key            = "prod/vpc.tfstate"
  region         = "us-west-2"
  dynamodb_table = "terraform-locks"
}
```

### Jenkins Credentials Usage

```groovy
withCredentials([usernamePassword(credentialsId: 'aws-creds',
  usernameVariable: 'AWS_ACCESS_KEY_ID',
  passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
    sh 'terraform apply'
}
```

### 🗣 Speaker Notes

* Never hardcode credentials in pipeline
* Explain **state locking using DynamoDB**
* State = single source of truth → must be protected

---

# 🚨 Topic 5: Handling Pipeline Failures

## 1️⃣ Authentication Failures

**Symptoms**

* “Access Denied”
* “Invalid AWS credentials”

**Fix**

* Check Jenkins credential bindings
* Verify IAM role permissions

---

## 2️⃣ State Lock Conflicts

**Error Example**

```
Error acquiring the state lock
```

### Recovery Command

```bash
terraform force-unlock LOCK_ID
```

### Best Practice

Only unlock if you are sure no other pipeline is running.

---

## 3️⃣ Corrupted State Recovery

```bash
terraform state pull > backup.tfstate
```

Then restore backend from backup.

### 🗣 Speaker Notes

* Explain why state locks happen (pipeline crash)
* Emphasize: **force-unlock is a last resort**
* Mention importance of **state backups**

---

# 🏁 Module Summary

In this session, we covered:

✔ Designing **multi-stage production pipelines**
✔ PR-based validation and approval gates
✔ Terraform version and module locking
✔ Secure authentication and remote state
✔ Diagnosing and recovering from pipeline failures

