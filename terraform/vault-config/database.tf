# A small Postgres instance whose only purpose is to demonstrate Vault's
# database secrets engine - dynamic, short-lived DB credentials generated on
# demand, the same story as the AWS secrets engine but for a real database
# connection instead of AWS STS. Deliberately minimal (single-AZ, no
# multi-AZ failover, no deletion protection) - this holds no real data, so
# it doesn't need production durability, just to exist and answer queries.

data "aws_security_group" "vault_node" {
  filter {
    name   = "group-name"
    values = ["vault-sg"]
  }
}

resource "aws_db_subnet_group" "vault_demo" {
  name       = "vault-demo-postgres"
  subnet_ids = data.terraform_remote_state.prerequisites.outputs.vault_subnet_ids
}

resource "aws_security_group" "vault_demo_postgres" {
  name        = "vault-demo-postgres"
  description = "Postgres access for the database secrets engine demo - Vault nodes (connection management) and inventory-service (using issued credentials) only"
  vpc_id      = data.terraform_remote_state.prerequisites.outputs.vpc_id

  ingress {
    description     = "Vault nodes manage/create/revoke roles on this connection"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_security_group.vault_node.id]
  }

  ingress {
    description     = "inventory-service actually uses the credentials it is issued"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.inventory_service_instance.id]
  }
}

# Initial master password - Terraform sets it once at creation, then it's
# deliberately rotated out from under Terraform once Vault takes ownership
# (see the "rotate root credentials" step in guide/04-configuration.md).
# Verified this is safe: the provider's read function never sets the
# password back into state from Vault's API (it's write-only, Vault never
# returns it), so a later `terraform plan` can't detect - or silently
# revert - the rotation.
resource "random_password" "vault_demo_postgres_master" {
  length  = 32
  special = true
  # RDS master passwords reject "/", "@", '"', and space specifically.
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "vault_demo" {
  identifier     = "vault-demo-postgres"
  engine         = "postgres"
  engine_version = "17.11" # confirmed available in ap-southeast-2 before pinning it

  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = "inventoryservice"
  username = "vaultroot"
  password = random_password.vault_demo_postgres_master.result

  db_subnet_group_name   = aws_db_subnet_group.vault_demo.name
  vpc_security_group_ids = [aws_security_group.vault_demo_postgres.id]
  publicly_accessible    = false

  # Sandbox demo instance, no real data - none of these matter here the way
  # they would for a production database.
  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 0
}

resource "vault_database_secret_backend_connection" "postgres" {
  backend       = vault_mount.this["database"].path
  name          = "postgres"
  allowed_roles = ["inventory-service"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${aws_db_instance.vault_demo.endpoint}/${aws_db_instance.vault_demo.db_name}?sslmode=require"
    username       = aws_db_instance.vault_demo.username
    password       = random_password.vault_demo_postgres_master.result
  }

  # Defaults to true - Vault actually connects and authenticates at apply
  # time, not just saving config it hasn't verified works.
  verify_connection = true
}

# Short TTLs are the entire point being demonstrated - real, working,
# revocable credentials that exist for minutes, not a static password
# checked into config somewhere.
resource "vault_database_secret_backend_role" "inventory_service" {
  backend = vault_mount.this["database"].path
  name    = "inventory-service"
  db_name = vault_database_secret_backend_connection.postgres.name

  # The GRANT "{{name}}" TO vaultroot below is required, not decorative - a
  # real gotcha found by testing, not documented in Vault's own Postgres
  # plugin docs: RDS's master user is deliberately not a true Postgres
  # superuser, and REASSIGN OWNED BY (used on revocation, below) only
  # succeeds for a superuser OR a direct/indirect member of the role being
  # reassigned. Without this grant, revocation fails outright with
  # "permission denied to reassign objects" (SQLSTATE 42501) and the
  # generated role is silently left behind.
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
    "GRANT \"{{name}}\" TO vaultroot;",
  ]
  revocation_statements = [
    "REASSIGN OWNED BY \"{{name}}\" TO vaultroot;",
    "DROP OWNED BY \"{{name}}\";",
    "DROP ROLE IF EXISTS \"{{name}}\";",
  ]

  default_ttl = 300  # 5m
  max_ttl     = 3600 # 1h
}
