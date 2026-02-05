Below is the **updated Lab 12 student manual** using a **real prod-style CloudApp stack**:

✅ **VPC (default VPC)**
✅ **Security Groups**
✅ **Launch Template** (user_data installs Apache + shows version/env)
✅ **Auto Scaling Group**
✅ **Application Load Balancer (ALB)**
✅ **Target Group + Listener**
✅ **Terraform Graph** becomes meaningful (ALB → TG → ASG → LT → SG → EC2)

Assumptions remain the same:

* **No access keys/secret keys** → Jenkins/agent VM has **IAM role**
* Backend = **S3 + DynamoDB lock**
* Branches: **staging** auto apply, **main** manual approval before apply

---

# Lab 12 (Student Manual – Real Prod Topology): ALB + ASG + Launch Template

## 0) Dependencies (must be ready)

### Tools on Jenkins Agent / Student VM

```bash
terraform -version
aws --version
git --version
dot -V
```

Install Graphviz if missing:

```bash
sudo apt-get update
sudo apt-get install -y graphviz
dot -V
```

### AWS side (provided by instructor/admin)

* S3 bucket (state): `cloudapp-tf-state`
* DynamoDB table (lock): `cloudapp-tf-locks` (PK: `LockID` string)
* Your Jenkins/agent **IAM role** can access:

  * S3 state bucket + key prefix
  * DynamoDB lock table
  * EC2, ELBv2, AutoScaling (create/read/update/delete as needed)

---

# 1) Repo Structure (same as before)

```bash
mkdir -p cloudapp-iac/{envs/staging,envs/prod,docs}
cd cloudapp-iac
git init
```

---

# 2) Version Pinning (required)

Create `versions.tf` in both envs.

```bash
cat > envs/staging/versions.tf << 'EOF'
terraform {
  required_version = "~> 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}
EOF
```

```bash
cat > envs/prod/versions.tf << 'EOF'
terraform {
  required_version = "~> 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}
EOF
```

---

# 3) Backend + Locking (required)

### staging backend

```bash
cat > envs/staging/backend.tf << 'EOF'
terraform {
  backend "s3" {
    bucket         = "cloudapp-tf-state"
    key            = "staging/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "cloudapp-tf-locks"
    encrypt        = true
  }
}
EOF
```

### prod backend

```bash
cat > envs/prod/backend.tf << 'EOF'
terraform {
  backend "s3" {
    bucket         = "cloudapp-tf-state"
    key            = "prod/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "cloudapp-tf-locks"
    encrypt        = true
  }
}
EOF
```

---

# 4) Variables + Provider (both envs)

### `providers.tf` (staging & prod)

```bash
cat > envs/staging/providers.tf << 'EOF'
provider "aws" {
  region = var.aws_region
}
EOF
```

```bash
cat > envs/prod/providers.tf << 'EOF'
provider "aws" {
  region = var.aws_region
}
EOF
```

### `variables.tf` (staging)

```bash
cat > envs/staging/variables.tf << 'EOF'
variable "aws_region" { type = string  default = "us-west-2" }
variable "env"        { type = string  default = "staging" }
variable "app_version"{ type = string  default = "v3.0" }

variable "instance_type" { type = string default = "t3.micro" }
variable "desired"       { type = number default = 2 }
variable "min"           { type = number default = 1 }
variable "max"           { type = number default = 3 }
EOF
```

### `variables.tf` (prod)

```bash
cat > envs/prod/variables.tf << 'EOF'
variable "aws_region" { type = string  default = "us-west-2" }
variable "env"        { type = string  default = "prod" }
variable "app_version"{ type = string  default = "v3.0" }

variable "instance_type" { type = string default = "t3.micro" }
variable "desired"       { type = number default = 2 }
variable "min"           { type = number default = 2 }
variable "max"           { type = number default = 4 }
EOF
```

### tfvars (staging)

```bash
cat > envs/staging/terraform.tfvars << 'EOF'
aws_region   = "us-west-2"
env          = "staging"
app_version  = "v3.0"
instance_type= "t3.micro"
desired      = 2
min          = 1
max          = 3
EOF
```

### tfvars (prod)

```bash
cat > envs/prod/terraform.tfvars << 'EOF'
aws_region   = "us-west-2"
env          = "prod"
app_version  = "v3.0"
instance_type= "t3.micro"
desired      = 2
min          = 2
max          = 4
EOF
```

---

# 5) Real Prod CloudApp Stack (ALB + ASG + Launch Template)

Create `main.tf` in staging and copy to prod.

### `envs/staging/main.tf`

```bash
cat > envs/staging/main.tf << 'EOF'
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -----------------------------
# Security Groups
# -----------------------------
# ALB SG: allow inbound HTTP from internet
resource "aws_security_group" "alb_sg" {
  name        = "cloudapp-${var.env}-alb-sg"
  description = "ALB SG for ${var.env}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    App = "CloudApp"
    Env = var.env
  }
}

# App SG: allow HTTP only from ALB SG
resource "aws_security_group" "app_sg" {
  name        = "cloudapp-${var.env}-app-sg"
  description = "App instances SG for ${var.env}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    App = "CloudApp"
    Env = var.env
  }
}

# -----------------------------
# Launch Template
# -----------------------------
locals {
  user_data = base64encode(<<-EOT
    #!/bin/bash
    yum -y install httpd
    systemctl enable httpd
    echo "CloudApp ${var.app_version} - ${var.env}" > /var/www/html/index.html
    systemctl start httpd
  EOT
  )
}

resource "aws_launch_template" "cloudapp_lt" {
  name_prefix   = "cloudapp-${var.env}-lt-"
  image_id      = data.aws_ami.amzn2.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app_sg.id]
  user_data              = local.user_data

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "cloudapp-${var.env}"
      App     = "CloudApp"
      Env     = var.env
      Version = var.app_version
    }
  }

  tags = {
    App = "CloudApp"
    Env = var.env
  }
}

# -----------------------------
# Target Group + ALB + Listener
# -----------------------------
resource "aws_lb_target_group" "cloudapp_tg" {
  name     = "cloudapp-${var.env}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    App = "CloudApp"
    Env = var.env
  }
}

resource "aws_lb" "cloudapp_alb" {
  name               = "cloudapp-${var.env}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    App = "CloudApp"
    Env = var.env
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.cloudapp_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cloudapp_tg.arn
  }
}

# -----------------------------
# Auto Scaling Group
# -----------------------------
resource "aws_autoscaling_group" "cloudapp_asg" {
  name                = "cloudapp-${var.env}-asg"
  vpc_zone_identifier = data.aws_subnets.default.ids

  desired_capacity = var.desired
  min_size         = var.min
  max_size         = var.max

  health_check_type         = "ELB"
  health_check_grace_period = 120

  target_group_arns = [aws_lb_target_group.cloudapp_tg.arn]

  launch_template {
    id      = aws_launch_template.cloudapp_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "cloudapp-${var.env}"
    propagate_at_launch = true
  }

  tag {
    key                 = "App"
    value               = "CloudApp"
    propagate_at_launch = true
  }

  tag {
    key                 = "Env"
    value               = var.env
    propagate_at_launch = true
  }
}

# -----------------------------
# Outputs
# -----------------------------
output "alb_dns_name" {
  value = aws_lb.cloudapp_alb.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.cloudapp_tg.arn
}

output "asg_name" {
  value = aws_autoscaling_group.cloudapp_asg.name
}
EOF
```

Copy to prod:

```bash
cp envs/staging/main.tf envs/prod/main.tf
```

---

# 6) Local dry run (student check before Jenkins)

### Staging init/plan

```bash
cd envs/staging
terraform init -input=false
terraform validate
terraform plan -out=tfplan -input=false
cd ../../
```

### Graph generation

```bash
cd envs/staging
terraform graph | dot -Tpng > infra-graph.png
ls -lh infra-graph.png
cd ../../
```

✅ Your graph now shows **ALB → Listener → TG → ASG → Launch Template → SG** dependencies.

---

# 7) Jenkinsfile (same logic, but validation now uses ALB output)

Create repo root `Jenkinsfile`:

```bash
cat > Jenkinsfile << 'EOF'
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    AWS_REGION = "us-west-2"
  }

  stages {
    stage("Checkout") {
      steps { checkout scm }
    }

    stage("Select Environment") {
      steps {
        script {
          if (env.BRANCH_NAME == "staging") {
            env.TF_DIR = "envs/staging"
          } else if (env.BRANCH_NAME == "main") {
            env.TF_DIR = "envs/prod"
          } else {
            env.TF_DIR = "envs/staging"
          }
          echo "Branch=${env.BRANCH_NAME} -> TF_DIR=${env.TF_DIR}"
        }
      }
    }

    stage("Terraform Init") {
      steps {
        sh '''
          set -e
          cd ${TF_DIR}
          terraform version
          terraform init -input=false
        '''
      }
    }

    stage("Terraform Validate") {
      steps {
        sh '''
          set -e
          cd ${TF_DIR}
          terraform fmt -check
          terraform validate
        '''
      }
    }

    stage("Terraform Plan") {
      steps {
        sh '''
          set -e
          cd ${TF_DIR}
          terraform plan -out=tfplan -input=false
        '''
      }
    }

    stage("Generate Infra Graph") {
      steps {
        sh '''
          set -e
          cd ${TF_DIR}
          terraform graph | dot -Tpng > infra-graph.png
          ls -lh infra-graph.png
        '''
      }
    }

    stage("Publish Artifacts") {
      steps {
        archiveArtifacts artifacts: "${TF_DIR}/infra-graph.png", fingerprint: true
        archiveArtifacts artifacts: "${TF_DIR}/tfplan", fingerprint: true
      }
    }

    stage("Manual Approval (PROD only)") {
      when { branch "main" }
      steps {
        input message: "Approve PROD terraform apply (CloudApp v3.0)?", ok: "Approve"
      }
    }

    stage("Terraform Apply") {
      when { anyOf { branch "staging"; branch "main" } }
      steps {
        sh '''
          set -e
          cd ${TF_DIR}
          terraform apply -input=false tfplan
        '''
      }
    }

    stage("Post Deployment Validation") {
      steps {
        sh '''
          set -e
          aws sts get-caller-identity
          cd ${TF_DIR}
          ALB_DNS=$(terraform output -raw alb_dns_name)
          echo "ALB DNS: $ALB_DNS"
          echo "Validating endpoint..."
          curl -I "http://$ALB_DNS" | head -n 5
          curl -s "http://$ALB_DNS" | head -n 5
        '''
      }
    }
  }
}
EOF
```

---

# 8) Commit and push (student steps)

```bash
git add .
git commit -m "Lab12 real prod: ALB + ASG + LT + manual approval + graph artifacts"
```

Create branches and push:

```bash
git branch -M main
git checkout -b staging
git push -u origin staging

git checkout main
git push -u origin main
```

---

# 9) Jenkins multibranch job (student steps)

1. Jenkins → New Item → **Multibranch Pipeline**
2. Connect Git source and scan branches
3. Ensure `staging` and `main` show
4. Trigger build

✅ **Expected for staging:** auto plan + graph + apply
✅ Artifacts: `infra-graph.png`, `tfplan`

---

# 10) Production release flow (manual approval)

Merge staging → main (or PR merge):

```bash
git checkout main
git merge staging
git push origin main
```

Jenkins `main` build:

* init → validate → plan → graph → artifacts
* stops at **Manual Approval**
* Approver clicks **Approve**
* applies to prod
* validates via `curl http://<alb_dns>`

---

# 11) Simulate state lock conflict + force unlock (mandatory)

### 11.1 Terminal A: hold a lock

```bash
cd envs/prod
terraform init -input=false
terraform apply
```

When it asks “Do you want to perform these actions?”
**do not type yes** (leave it hanging).

### 11.2 Terminal B: trigger conflict

```bash
cd envs/prod
terraform init -input=false
terraform plan
```

Copy the **Lock ID** from the error.

### 11.3 Force unlock

```bash
terraform force-unlock <LOCK_ID>
```

Stop Terminal A (`Ctrl+C`).

---

# 12) Final validation (student proof)

### Get ALB DNS

```bash
cd envs/prod
terraform output -raw alb_dns_name
```

### Validate response

```bash
ALB=$(terraform output -raw alb_dns_name)
curl -I "http://$ALB" | head -n 5
curl -s "http://$ALB" | head -n 5
```

Expected page contains:
`CloudApp v3.0 - prod`

---

# 13) Optional: commit graph into /docs

From your pipeline artifact download OR local file:

```bash
cp envs/prod/infra-graph.png docs/infra-graph-prod.png
git add docs/infra-graph-prod.png
git commit -m "docs: add production infra graph"
git push origin main
```

---

# Student Submission Checklist

1. Screenshot: Jenkins **Manual Approval** stage for `main`
2. Artifact: `infra-graph.png` (downloaded from Jenkins)
3. Screenshot/log: **state lock error** showing Lock ID
4. Screenshot/log: `terraform force-unlock <LOCK_ID>`
5. Proof: `curl http://<alb_dns>` showing CloudApp page


