module "s3_bucket_unagi_profiles" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.14.0"

  bucket = "unagi-profiles-${var.environment}"

  acl = "public-read"

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  # force_destroy = true

  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

module "s3_bucket_unagi_files" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.14.0"

  bucket = "unagi-files-${var.environment}"

  acl = "public-read"

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  # force_destroy = true

  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_user" "s3_storageservice_user" {
  name = "s3-storageservice-user-${var.environment}"

  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_access_key" "s3_storageservice_user_access_key" {
  user = aws_iam_user.s3_storageservice_user.name
}

resource "aws_iam_user_policy" "s3_storageservice_user_policy" {
  name   = "s3-storageservice-user-policy-${var.environment}"
  user   = aws_iam_user.s3_storageservice_user.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
              "arn:aws:s3:::unagi-profiles-${var.environment}/",
              "arn:aws:s3:::unagi-files-${var.environment}/"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::unagi-profiles-${var.environment}/*",
        "arn:aws:s3:::unagi-files-${var.environment}/*"
      ]
    }
  ]
}
EOF
}

resource "aws_secretsmanager_secret" "s3_storageservice_user" {
  name = "s3-storageservice-user-${var.environment}-${uuid()}"

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

resource "aws_secretsmanager_secret_version" "s3_storageservice_user" {
  secret_id     = aws_secretsmanager_secret.s3_storageservice_user.id
  secret_string = <<EOF
   {
    "access_key": "${aws_iam_access_key.s3_storageservice_user_access_key.id}",
    "secret_key": "${aws_iam_access_key.s3_storageservice_user_access_key.secret}"
   }
EOF 
}

module "s3_bucket_unagi_assets" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.14.0"

  bucket = "unagi-assets-${var.environment}"

  acl = "public-read"

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  # force_destroy = true

  tags = {
    Terraform   = "true"
    Project     = var.project
    Environment = var.environment
  }
}
