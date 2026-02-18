# DocumentDB - datacore
module "docdb_datacore" {
  source  = "cloudposse/documentdb-cluster/aws"
  version = "0.20.0"

  name = "datacore-${var.environment}"

  cluster_size = 2

  engine         = "docdb"
  engine_version = "5.0.0"
  cluster_family = "docdb5.0"

  cluster_parameters = [{ name = "tls", value = "disabled", apply_method = null }]

  master_username = "datacore_udb"

  instance_class = var.docdb_datacore_configurations.instance_class

  vpc_id     = module.vpc_main.vpc_id
  subnet_ids = module.vpc_main.database_subnets

  allowed_cidr_blocks = [module.vpc_main.private_subnets_cidr_blocks[0], module.vpc_main.private_subnets_cidr_blocks[1], "${module.ec2_mgmt.private_ip}/32"]

  preferred_maintenance_window = "Mon:00:00-Mon:03:00"
  preferred_backup_window      = "03:00-06:00"

  storage_encrypted = true

  enabled_cloudwatch_logs_exports = ["audit"]

  auto_minor_version_upgrade = true

  retention_period = 7

  skip_final_snapshot = true
  deletion_protection = true

  enable_performance_insights = true

  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

# DocumentDB - datacore - ASM
resource "aws_secretsmanager_secret" "docdb_datacore" {
  name = "docdb-datacore-${var.environment}-${uuid()}"

  lifecycle {
    ignore_changes = [
      name
    ]
  }

  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "docdb_datacore" {
  secret_id     = aws_secretsmanager_secret.docdb_datacore.id
  secret_string = <<EOF
   {
    "host": "${module.docdb_datacore.endpoint}",
    "username": "${module.docdb_datacore.master_username}",
    "password": "${module.docdb_datacore.master_password}"
   }
EOF 
}
