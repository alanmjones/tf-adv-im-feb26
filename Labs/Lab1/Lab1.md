
# 🧪 **Scenario Lab: Production CI/CD with Jenkins + Terraform**

**Duration:** ~2 Hours
**Level:** Students already know Terraform (basic + intermediate)

Tools used: **Jenkins + GitHub / Bitbucket + Amazon Web Services + Terraform**

---

## 🧭 LAB FLOW OVERVIEW (Big Picture First)

Students will experience this journey:

![Image](https://assets.northflank.com/northflank_environments_0447528004.png)

![Image](https://images.openai.com/static-rsc-3/1JssT43dRnj6AmZc9EbXImzBQaSLk1WhEXVOojNss6t_YgTlxYCTq3I6Db7m8irYraKbjg60ChYTiVETgOUyVSEeJcorUjJVvTpLWL4BD6Q?purpose=fullsize)

![Image](https://miro.medium.com/v2/resize%3Afit%3A1400/1%2Ael-spbCECAOdp06Iiun-ug.png)

**Flow:**

1️⃣ Developer raises PR → Validation pipeline runs
2️⃣ Merge to *dev* → Auto deploy
3️⃣ Promote to *staging* → Auto deploy
4️⃣ Merge to *main* → Manual approval → Production deploy
5️⃣ Pipeline breaks → Students troubleshoot (state lock & creds)

---

# 🔧 0️⃣ ASSUMPTIONS & DEPENDENCIES

### 💡 Students ALREADY Know

* Terraform modules
* Remote backend basics
* Terraform plan/apply lifecycle

### 🧑‍🏫 Instructor MUST Provide Before Lab

| Component           | Requirement                              |
| ------------------- | ---------------------------------------- |
| Jenkins             | Running & accessible                     |
| Git Repo            | Starter Terraform code uploaded          |
| AWS Account         | IAM user with EC2 + S3 + DynamoDB access |
| S3 Bucket           | For Terraform remote state               |
| DynamoDB Table      | For Terraform state locking              |
| Jenkins Credentials | AWS keys stored securely                 |

---

# 🏗 1️⃣ ARCHITECTURE STUDENTS WILL DEPLOY

Simple but production-relevant infra:

* VPC
* Public Subnet
* Internet Gateway
* EC2 instance

![Image](https://docs.aws.amazon.com/images/vpc/latest/userguide/images/vpc-example-private-subnets.png)

![Image](https://miro.medium.com/1%2Agftv4LSqU_12kRqNwYISJw.png)

![Image](https://docs.aws.amazon.com/images/vpc/latest/userguide/images/how-it-works.png)

---

# 📁 2️⃣ REPOSITORY STRUCTURE (Pre-Created)

```
cloudretail-infra/
 ├── modules/
 │   └── ec2/
 ├── envs/
 │   ├── dev/
 │   ├── staging/
 │   └── prod/
 ├── versions.tf
 └── Jenkinsfile
```

Each environment folder has its own backend config.

---

# 🔒 3️⃣ STEP — Terraform Version & Provider Locking

📌 **Why first?** Pipelines must be reproducible.

Students edit **versions.tf**

```hcl
terraform {
  required_version = "~> 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

✔ Commit and push

---

# ☁️ 4️⃣ STEP — Configure Remote Backend (Per Environment)

📁 `envs/dev/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket         = "cloudretail-tf-state"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
  }
}
```

Students repeat for `staging` and `prod` (changing only key path).

✔ Commit and push

---

# ⚙️ 5️⃣ STEP — Jenkins Multibranch Pipeline Setup

Students create pipeline:

1. Jenkins → New Item
2. Choose **Multibranch Pipeline**
3. Connect to GitHub repo
4. Jenkins auto-detects **Jenkinsfile**

---

# 🧠 6️⃣ STEP — Understanding the Jenkins Pipeline

Instructor walks through:

```groovy
pipeline {
  agent any

  stages {

    stage('Validate') {
      steps { sh 'terraform validate' }
    }

    stage('Plan') {
      steps { sh 'terraform plan -out=tfplan' }
    }

    stage('Approval') {
      when { branch 'main' }
      steps { input message: 'Approve Production Deployment?' }
    }

    stage('Apply') {
      steps { sh 'terraform apply -auto-approve tfplan' }
    }
  }
}
```

💡 Explain:

* PR = validation only
* main branch = production

---

# 🔁 7️⃣ STEP — Feature Branch PR Validation

### Student Task

1. Create branch:

   ```
   feature/add-ec2-tag
   ```
2. Add a new tag in EC2 module
3. Push branch
4. Raise Pull Request

### Expected Result

Pipeline runs:
✔ terraform init (no backend lock)
✔ terraform validate
✔ terraform plan

❌ No apply

---

# 🚀 8️⃣ STEP — Deploy to DEV

Student merges PR into `dev` branch.

Pipeline runs:

✔ Plan
✔ Apply

EC2 instance gets created in AWS.

---

# 🧪 9️⃣ STEP — Simulate State Lock Failure

Instructor secretly runs `terraform apply` manually and cancels midway.

Student pipeline now fails with:

```
Error acquiring the state lock
```

### Student Recovery

Instructor provides lock ID → Students run:

```bash
terraform force-unlock <LOCK_ID>
```

Re-run pipeline → Success

---

# 🔐 🔟 STEP — Simulate Credential Failure

Instructor changes AWS credentials in Jenkins.

Pipeline error:

```
AccessDenied: InvalidClientTokenId
```

### Student Fix

1. Update Jenkins stored credentials
2. Re-run pipeline → Success

---

# 🚦 1️⃣1️⃣ STEP — Production Approval Gate

Students merge to `main`.

Pipeline pauses at:

```
Approve Production Deployment?
```

Students approve → Production infra deploys

Instructor explains **change control & governance**

---

# 🏁 FINAL OUTCOME

Students have successfully:

✔ Built a multi-environment pipeline
✔ Used PR validation safely
✔ Deployed to Dev → Staging → Prod
✔ Handled state lock conflicts
✔ Fixed credential failures
✔ Understood production approval gates

---

## 🎓 What Students Learned (Instructor Wrap-Up)

This lab teaches the difference between:

| Basic Terraform | Production Terraform |
| --------------- | -------------------- |
| Local apply     | CI/CD controlled     |
| No locking      | Remote state locking |
| No approvals    | Governance gates     |
| Manual fix      | Automated recovery   |


