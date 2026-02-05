terraform {
  backend "s3" {
    bucket       = "tf-state-vishwa-feb26"
    key          = "lab2/terraform.tfstate"
    region       = "us-west-2"
    use_lockfile = true
    # dynamodb_table = "terraform-locks"
  }
}
