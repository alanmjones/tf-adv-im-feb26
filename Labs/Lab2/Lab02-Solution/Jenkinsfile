pipeline {
  agent any

  options {
    timestamps()
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

    // stage("tflint") {
    //   steps {
    //     sh """
    //       cd ${TF_DIR}
    //       # Run tflint via docker (no local install needed)
    //       docker run --rm \
    //         -v "$PWD:/data" -w /data \
    //         ghcr.io/terraform-linters/tflint:latest \
    //         --init

    //       docker run --rm \
    //         -v "$PWD:/data" -w /data \
    //         ghcr.io/terraform-linters/tflint:latest \
    //         --recursive
    //     """
    //   }
    // }
    stage("Terraform plan") {
      steps {
        sh """
          cd ${TF_DIR}
          terraform plan   -out=tfplan
          terraform show -json tfplan > tfplan.json

        """
      }
    }
    stage("checkov") {
      steps {
        sh """
          docker run --rm \
            -v "${WORKSPACE}:/repo" -w /repo \
            bridgecrew/checkov:latest \
            -d /repo/infra \
            --config-file /repo/infra/.checkov.yml \
            --external-checks-dir /repo/.checkov/custom_policies
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