# A dedicated, minimal EC2 instance whose only job is to be a distinct IAM
# identity for the AWS auth method demo - see guide/04-configuration.md and
# the decision log. Deliberately not the Vault nodes' own role: a real app
# shouldn't authenticate to Vault as the Vault server itself. This instance
# has no AWS permissions beyond SSM access (to reach it for testing) - its
# IAM role existing at all is the only thing Vault auth cares about.

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_iam_policy_document" "inventory_service_instance_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "inventory_service_instance" {
  name               = "inventory-service"
  assume_role_policy = data.aws_iam_policy_document.inventory_service_instance_trust.json
}

resource "aws_iam_role_policy_attachment" "inventory_service_instance_ssm" {
  role       = aws_iam_role.inventory_service_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "inventory_service_instance" {
  name = "inventory-service"
  role = aws_iam_role.inventory_service_instance.name
}

resource "aws_security_group" "inventory_service_instance" {
  name        = "inventory-service-instance"
  description = "AWS auth demo client - no ingress, egress only (SSM + package installs via NAT)"
  vpc_id      = data.terraform_remote_state.prerequisites.outputs.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "inventory_service_instance" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = "t3.micro"
  subnet_id              = data.terraform_remote_state.prerequisites.outputs.vault_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.inventory_service_instance.id]
  iam_instance_profile   = aws_iam_instance_profile.inventory_service_instance.name

  # No public IP - private subnet, reached only via SSM, same access
  # pattern as the Vault nodes themselves.
  associate_public_ip_address = false

  # Vault CLI only - this instance never runs a Vault server, just needs
  # the client to exercise `vault login -method=aws` during testing.
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y dnf-plugins-core
    dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    dnf install -y vault
  EOF

  tags = {
    Name = "inventory-service-instance"
  }
}
