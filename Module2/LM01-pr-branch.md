
# 🎯 What You Want

Run **different pipeline logic when the build is triggered by a Pull Request** vs a normal branch build (like `main`, `develop`, etc.)

In Jenkins **Multibranch Pipelines**, PRs are detected automatically, and Jenkins exposes special environment variables + conditions.

---

# 🧠 1️⃣ Simplest Way — `when { changeRequest() }`

This is the cleanest and most modern approach.

```groovy
pipeline {
    agent any

    stages {

        stage('PR Validation') {
            when {
                changeRequest()
            }
            steps {
                echo "This stage runs ONLY for Pull Requests"
                sh 'terraform init'
                sh 'terraform validate'
                sh 'terraform plan'
            }
        }

        stage('Branch Deployment') {
            when {
                not {
                    changeRequest()
                }
            }
            steps {
                echo "This runs for normal branch builds (main, dev, etc.)"
                sh 'terraform apply -auto-approve'
            }
        }
    }
}
```

### ✅ What `changeRequest()` Means

It becomes **true** when the build is triggered by:

* GitHub PR
* Bitbucket PR
* GitLab MR

---

# 🔍 2️⃣ Target Only PRs Merging Into a Specific Branch

Example: Only run if PR target branch is **main**

```groovy
stage('PR → Main Validation') {
    when {
        allOf {
            changeRequest()
            branch 'main'
        }
    }
    steps {
        echo "PR is targeting MAIN branch"
    }
}
```

---

# 🧪 3️⃣ Use PR Metadata (Very Useful)

Jenkins exposes these variables during PR builds:

| Variable        | Meaning                          |
| --------------- | -------------------------------- |
| `CHANGE_ID`     | PR number                        |
| `CHANGE_BRANCH` | Source branch of PR              |
| `CHANGE_TARGET` | Target branch PR is merging into |
| `CHANGE_AUTHOR` | PR author                        |

### Example

```groovy
stage('Print PR Info') {
    when { changeRequest() }
    steps {
        echo "PR Number: ${env.CHANGE_ID}"
        echo "Source Branch: ${env.CHANGE_BRANCH}"
        echo "Target Branch: ${env.CHANGE_TARGET}"
        echo "Author: ${env.CHANGE_AUTHOR}"
    }
}
```

---

# 🛡️ 4️⃣ Only Run Security Scan for PRs

```groovy
stage('Security Scan - PR Only') {
    when {
        changeRequest()
    }
    steps {
        sh 'tflint'
        sh 'checkov -d .'
    }
}
```

This is **best practice**:
👉 PR = Validate
👉 Main branch = Deploy

---

# 🚀 5️⃣ Skip Deployment on PR Builds

Very common in Terraform pipelines.

```groovy
stage('Terraform Apply') {
    when {
        not {
            changeRequest()
        }
        branch 'main'
    }
    steps {
        sh 'terraform apply -auto-approve'
    }
}
```

---

# 🧩 6️⃣ Scripted Condition (Advanced)

If you want custom logic:

```groovy
stage('Custom PR Logic') {
    when {
        expression {
            return env.CHANGE_ID != null && env.CHANGE_TARGET == "main"
        }
    }
    steps {
        echo "PR targeting main detected via expression"
    }
}
```

---

# 🏗️ 7️⃣ Full Real-World Example (Terraform PR Workflow)

```groovy
pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }

        stage('Terraform Validate') {
            steps {
                sh 'terraform validate'
            }
        }

        stage('Terraform Plan (PR Only)') {
            when { changeRequest() }
            steps {
                sh 'terraform plan -out=tfplan'
            }
        }

        stage('Manual Approval') {
            when {
                allOf {
                    not { changeRequest() }
                    branch 'main'
                }
            }
            steps {
                input message: "Approve Production Deployment?"
            }
        }

        stage('Terraform Apply (Main Only)') {
            when {
                allOf {
                    not { changeRequest() }
                    branch 'main'
                }
            }
            steps {
                sh 'terraform apply -auto-approve'
            }
        }
    }
}
```

---

# 🧠 Summary

| Condition                 | Use Case                             |
| ------------------------- | ------------------------------------ |
| `changeRequest()`         | Run only for PR builds               |
| `not { changeRequest() }` | Skip PRs (run only on branch builds) |
| `branch 'main'`           | Only for specific branch             |
| `env.CHANGE_TARGET`       | Check PR destination branch          |
| `env.CHANGE_BRANCH`       | Check PR source branch               |

