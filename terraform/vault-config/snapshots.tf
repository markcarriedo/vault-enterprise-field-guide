# A durable, versioned destination for Raft snapshots - see
# guide/05-operations.md for the actual save/restore runbook. Snapshots are
# taken and uploaded manually (an operator running `vault operator raft
# snapshot save` then `aws s3 cp`), not Vault's own Enterprise automated
# snapshot agent - that would need its own IAM grant on the Vault nodes'
# role and a Vault-API-side config this provider has no dedicated resource
# for; worth revisiting later, not needed to prove the core save/restore
# mechanism works.
resource "random_id" "snapshot_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "vault_snapshots" {
  bucket = "vault-enterprise-field-guide-raft-snapshots-${random_id.snapshot_bucket_suffix.hex}"

  tags = {
    Project = "vault-enterprise-field-guide"
  }
}

resource "aws_s3_bucket_versioning" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "vault_snapshots_deny_insecure_transport" {
  bucket = aws_s3_bucket.vault_snapshots.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.vault_snapshots.arn,
          "${aws_s3_bucket.vault_snapshots.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Sandbox retention - real production use would size this to actual RPO/RTO
# requirements, not a fixed 30 days.
resource "aws_s3_bucket_lifecycle_configuration" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  rule {
    id     = "expire-old-snapshots"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
