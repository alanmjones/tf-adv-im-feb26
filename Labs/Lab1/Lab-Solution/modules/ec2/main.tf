# provider "aws" {
#   region = "us-west-2"
# }

resource "aws_instance" "this" {
  ami           = data.aws_ami.al2.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  tags = merge({ Name = var.name }, var.tags)
}

data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
