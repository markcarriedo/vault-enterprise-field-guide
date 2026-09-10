variable "aws_region" {
  description = "AWS region for the Vault deployment"
  type        = string
  default     = "ap-southeast-2"
}

variable "vpc_cidr" {
  description = "Must match terraform/prerequisites' vpc_cidr - used only to restrict load balancer ingress to in-VPC traffic (see net_ingress_lb_cidr_blocks in main.tf)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "asg_node_count" {
  description = "Number of Vault nodes. Module default is 6; 3 is the standard Raft HA quorum minimum, and plenty for a sandbox."
  type        = number
  default     = 3
}
