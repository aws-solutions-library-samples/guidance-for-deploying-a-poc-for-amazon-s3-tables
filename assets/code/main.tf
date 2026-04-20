# Guidance for Deploying a PoC for Amazon S3 Tables — Terraform
# Equivalent to assets/code/s3-tables-poc.yaml

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============ VARIABLES ============

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "s3-tables-poc"
}

variable "instance_type" {
  type    = string
  default = "t3.xlarge"
  validation {
    condition     = contains(["t3.large", "t3.xlarge", "t3.2xlarge", "m5.xlarge", "m5.2xlarge"], var.instance_type)
    error_message = "Allowed: t3.large, t3.xlarge, t3.2xlarge, m5.xlarge, m5.2xlarge"
  }
}

variable "table_bucket_name" {
  type    = string
  default = "s3-tables-poc"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-]{1,61}[a-z0-9]$", var.table_bucket_name))
    error_message = "Lowercase alphanumeric and hyphens only."
  }
}

variable "default_namespace" {
  type    = string
  default = "poc_data"
}

# ============ DATA SOURCES ============

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  az               = data.aws_availability_zones.available.names[0]
  table_bucket_fqn = "${var.table_bucket_name}-${local.account_id}"
}

# ============ NETWORKING ============

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.stack_name}-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = local.az
  tags = { Name = "${var.stack_name}-public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = local.az
  tags = { Name = "${var.stack_name}-private-subnet" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.stack_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.stack_name}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.stack_name}-nat-eip" }
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "${var.stack_name}-nat" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.stack_name}-private-rt" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ============ VPC ENDPOINTS ============

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

resource "aws_security_group" "endpoints" {
  name_prefix = "${var.stack_name}-endpoint-"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "HTTPS from VPC"
  }

  tags = { Name = "${var.stack_name}-endpoint-sg" }
}

locals {
  interface_endpoints = ["ssm", "ssmmessages", "ec2messages", "s3tables", "glue", "athena"]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = { Name = "${var.stack_name}-${each.key}-endpoint" }
}

# ============ SECURITY GROUPS ============

resource "aws_security_group" "ec2" {
  name_prefix = "${var.stack_name}-ec2-"
  description = "S3 Tables PoC EC2 instance (no inbound, SSM only)"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to AWS services and internet"
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for package downloads"
  }

  tags = { Name = "${var.stack_name}-ec2-sg" }
}

# ============ IAM ============

resource "aws_iam_role" "ec2" {
  name = "${var.stack_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "s3tables_access" {
  name = "S3TablesAccess"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3TablesFullAccess"
        Effect = "Allow"
        Action = ["s3tables:*"]
        Resource = [
          "arn:aws:s3tables:${var.aws_region}:${local.account_id}:bucket/${local.table_bucket_fqn}",
          "arn:aws:s3tables:${var.aws_region}:${local.account_id}:bucket/${local.table_bucket_fqn}/*"
        ]
      },
      {
        Sid    = "S3DataAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          aws_s3_bucket.athena_results.arn,
          "${aws_s3_bucket.athena_results.arn}/*"
        ]
      },
      {
        Sid    = "GlueCatalogAccess"
        Effect = "Allow"
        Action = ["glue:GetCatalog", "glue:GetCatalogs", "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:GetPartitions", "glue:BatchGetPartition"]
        Resource = ["*"]
      },
      {
        Sid    = "AthenaAccess"
        Effect = "Allow"
        Action = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults", "athena:GetWorkGroup"]
        Resource = [aws_athena_workgroup.main.arn]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.stack_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ============ S3 (Athena Results) ============

resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.stack_name}-athena-results-${local.account_id}"
  tags   = { Name = "${var.stack_name}-athena-results" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============ S3 TABLE BUCKET ============

resource "aws_s3tables_table_bucket" "main" {
  name = local.table_bucket_fqn
}

# ============ ATHENA ============

resource "aws_athena_workgroup" "main" {
  name = "${var.stack_name}-workgroup"

  configuration {
    enforce_workgroup_configuration = false
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/results/"
    }
  }
}

# ============ EC2 INSTANCE ============

resource "aws_instance" "main" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash -xe
    dnf install -y java-17-amazon-corretto-headless
    SPARK_VERSION="3.5.4"
    curl -sL "https://archive.apache.org/dist/spark/spark-$${SPARK_VERSION}/spark-$${SPARK_VERSION}-bin-hadoop3.tgz" | tar -xz -C /opt/
    ln -s /opt/spark-$${SPARK_VERSION}-bin-hadoop3 /opt/spark
    echo 'export SPARK_HOME=/opt/spark' >> /etc/profile.d/spark.sh
    echo 'export PATH=$SPARK_HOME/bin:$PATH' >> /etc/profile.d/spark.sh
    echo "S3 Tables PoC instance ready" > /tmp/setup-complete.txt
  EOF
  )

  tags = { Name = "${var.stack_name}-test-host" }

  depends_on = [
    aws_vpc_endpoint.s3_gateway,
    aws_vpc_endpoint.interface,
    aws_nat_gateway.main
  ]
}

# ============ OUTPUTS ============

output "ec2_instance_id" {
  description = "EC2 Instance ID (use with SSM Session Manager)"
  value       = aws_instance.main.id
}

output "ssm_session_command" {
  description = "CLI command to connect via Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.main.id} --region ${var.aws_region}"
}

output "table_bucket_arn" {
  description = "ARN of the S3 table bucket"
  value       = aws_s3tables_table_bucket.main.arn
}

output "table_bucket_name" {
  description = "Name of the S3 table bucket"
  value       = local.table_bucket_fqn
}

output "athena_workgroup_name" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.main.name
}

output "athena_results_bucket_name" {
  description = "S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.id
}

output "ec2_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2.arn
}

output "region" {
  description = "Deployment region"
  value       = var.aws_region
}
