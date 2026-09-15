# IBM security flags the public AMIs this module looks up by default
# (Canonical's own Ubuntu AMI, owner 099720109477) as unapproved. Pulling the
# latest internally-published, approved image instead - same OS/version
# (Ubuntu 22.04, matching the module's own default `ec2_os_distro`), just a
# different, vetted publisher. See guide/03-installation.md and the decision
# log for why this is a safe drop-in swap rather than an OS change.
data "aws_ami" "hc_base_ubuntu_2204" {
  owners      = ["888995627335"] # ami-prod account
  most_recent = true

  filter {
    name   = "name"
    values = ["hc-base-ubuntu-2204-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
