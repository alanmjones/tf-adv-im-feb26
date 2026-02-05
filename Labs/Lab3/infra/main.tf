provider "aws" {
  region = "us-west-2"
}

data "aws_secretsmanager_secret_version" "api" {
  secret_id = "prod/app/api_key"
}

resource "aws_instance" "secure_app" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = "t3.micro"

  user_data = templatefile("userdata.sh", {
    api_key = data.aws_secretsmanager_secret_version.api.secret_string
  })

  tags = {
    Name = "Secure-App-Server"
  }
}
