# RDS - msgc - security group
module "security_group_rds_msgc" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0.0"

  name   = "rds-msgc-${var.environment}"
  vpc_id = module.vpc_main.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = module.vpc_main.private_subnets_cidr_blocks[0]
    },
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = module.vpc_main.private_subnets_cidr_blocks[1]
    },
    {
      description = "Access from MGMT node"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = "${module.ec2_mgmt.private_ip}/32"
    }
  ]

  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

# RDS - msgc - password
resource "random_password" "rds_msgc" {
  length  = "50"
  special = false
}

# RDS - msgc
module "rds_msgc" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 5.9.0"

  identifier = "msgc-${var.environment}"

  engine               = "postgres"
  engine_version       = "15.3"
  major_engine_version = "15"
  family               = "postgres15"

  auto_minor_version_upgrade = true

  instance_class = var.rds_msgc_instance_configurations.instance_class

  allocated_storage     = var.rds_msgc_instance_configurations.allocated_storage
  max_allocated_storage = var.rds_msgc_instance_configurations.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name                = "msgc_db"
  username               = "msgc_udb"
  port                   = 5432
  create_random_password = false
  password               = random_password.rds_msgc.result

  multi_az             = true
  db_subnet_group_name = module.vpc_main.database_subnet_group

  vpc_security_group_ids = [module.security_group_rds_msgc.security_group_id]

  parameters = [{ name = "rds.force_ssl", value = "0", apply_method = null }]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  backup_retention_period = 7

  enabled_cloudwatch_logs_exports        = ["postgresql", "upgrade"]
  cloudwatch_log_group_retention_in_days = 7

  skip_final_snapshot = true
  deletion_protection = true

  performance_insights_enabled = true

  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

# RDS - msgc - ASM
resource "aws_secretsmanager_secret" "rds_msgc" {
  name = "rds-msgc-${var.environment}-${uuid()}"

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

resource "aws_secretsmanager_secret_version" "rds_msgc" {
  secret_id     = aws_secretsmanager_secret.rds_msgc.id
  secret_string = <<EOF
   {
    "host": "${module.rds_msgc.db_instance_address}",
    "db_name": "${module.rds_msgc.db_instance_name}",
    "username": "${module.rds_msgc.db_instance_username}",
    "password": "${random_password.rds_msgc.result}"
   }
EOF 
}
