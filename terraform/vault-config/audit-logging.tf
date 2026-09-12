# Audit logging - a file audit device (Vault's own record of every request)
# shipped to CloudWatch Logs via the AWS-managed CloudWatch Agent, installed
# and configured fleet-wide through SSM State Manager rather than baking it
# into the Vault nodes' own launch template. The HVD module's
# custom_startup_script_template *replaces* its entire built-in install
# script rather than extending it - reimplementing that just to add one
# agent install wasn't worth the risk. SSM associations also apply to any
# future instance the ASG launches, not just the ones running today.
resource "vault_audit" "file" {
  type = "file"

  options = {
    file_path = "/var/log/vault/audit.log"
  }
}

resource "aws_cloudwatch_log_group" "vault_audit" {
  name              = "/vault/audit"
  retention_in_days = 30
}

# CloudWatch Agent config, pulled from this parameter by the
# AmazonCloudWatch-ManageAgent SSM document below - not the launch
# template, so updating it doesn't require rebuilding any node.
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name = "/vault/cloudwatch-agent-config"
  type = "String"

  value = jsonencode({
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path       = "/var/log/vault/audit.log"
              log_group_name  = aws_cloudwatch_log_group.vault_audit.name
              log_stream_name = "{instance_id}"
            }
          ]
        }
      }
    }
  })
}

# Vault nodes' own role needs permission to ship logs and read its agent
# config - an inline policy added to that existing role from this state,
# same pattern as the sts:AssumeRole grant in dynamic-secrets.tf.
data "aws_iam_policy_document" "vault_node_cloudwatch" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vault_audit.arn}:*"]
  }

  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.cloudwatch_agent_config.arn]
  }
}

resource "aws_iam_role_policy" "vault_node_cloudwatch" {
  name   = "ship-audit-logs-to-cloudwatch"
  role   = data.aws_iam_role.vault_node.name
  policy = data.aws_iam_policy_document.vault_node_cloudwatch.json
}

# Two SSM associations, applied fleet-wide by tag (the same
# aws:autoscaling:groupName tag AWS already propagates onto every ASG
# instance) rather than by instance ID, so new nodes pick both up
# automatically: install the agent, then configure + start it from the
# parameter above.
resource "aws_ssm_association" "install_cloudwatch_agent" {
  name = "AWS-ConfigureAWSPackage"

  parameters = {
    action = "Install"
    name   = "AmazonCloudWatchAgent"
  }

  targets {
    key    = "tag:aws:autoscaling:groupName"
    values = ["vault-asg"]
  }
}

resource "aws_ssm_association" "configure_cloudwatch_agent" {
  name = "AmazonCloudWatch-ManageAgent"

  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cloudwatch_agent_config.name
    optionalRestart               = "yes"
  }

  targets {
    key    = "tag:aws:autoscaling:groupName"
    values = ["vault-asg"]
  }

  # Without this, State Manager only applies the association once, when
  # created or when its targets change - on a genuinely new instance, this
  # can race the install association above and fail if it runs first (hit
  # exactly this on first apply; the install-then-configure ordering is
  # request-time only, not execution-time). A recurring schedule means a
  # fresh instance that loses that race self-heals within 30 minutes
  # instead of silently having no audit-log shipping forever.
  schedule_expression = "rate(30 minutes)"

  depends_on = [aws_ssm_association.install_cloudwatch_agent]
}
