provider "aws" {
  region = "us-east-1"
}


resource "aws_kms_key" "objects" {
  description             = "KMS key is used to encrypt bucket objects"
  deletion_window_in_days = 7
}


module "s3_bucket" {
  source = "./modules/s3-bucket"

  bucket        = var.my_s3_bucket_name
  acl           = "private"
  force_destroy = true


  tags = {
    Owner = "john"
  }

  versioning = {
    enabled = true
  }

  lifecycle_rule = [
    {
      id                                     = "objectdeletion"
      enabled                                = true
      prefix                                 = "/"
      abort_incomplete_multipart_upload_days = 7

      noncurrent_version_transition = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 60
          storage_class = "ONEZONE_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        },
      ]

      noncurrent_version_expiration = {
        days = 356
      }
    }
  ]

  # S3 bucket-level Public Access Block configuration
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.objects.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

}



module "ec2_role_custom" {
  source = "./modules/iam/modules/iam-assumable-role"

  trusted_role_services = [
    "ec2.amazonaws.com"
  ]

  create_role = true

  role_name         = "ec2rolefors3"
  role_requires_mfa = false

  custom_role_policy_arns = [
    module.iam_policy_for_s3.arn
  ]
}


data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid       = "AllowFullS3Access"
    actions   = ["s3:*"]
    resources = [module.s3_bucket.this_s3_bucket_arn,"${module.s3_bucket.this_s3_bucket_arn}/*"]
  }
}

module "iam_policy_for_s3" {
  source = "./modules/iam/modules/iam-policy"

  name        = "iampolicyforjohns3"
  path        = "/"
  description = "Policy to allow all s3 access to ${module.s3_bucket.this_s3_bucket_arn} bucket and objects"

  policy = data.aws_iam_policy_document.bucket_policy.json
}


module "vpc" {
  source = "./modules/vpc"

  name = "john-interview-vpc"

  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a","us-east-1b"]
  public_subnets  = ["10.0.0.0/24","10.0.2.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.12.0/24"]
  database_subnets = ["10.0.20.0/24", "10.0.22.0/24"]

  public_subnet_tags = {
    Name = "PublicSubnets"
  }

  private_subnet_tags = {
    Name = "PrivateSubnets"
  }

  database_subnet_tags = {
    Name = "DatabaseSubnets"
  }

  tags = {
    Owner       = "john"
    Environment = "interview"
  }

}

module "security_group" {
  source  = "./modules/sg"

  name        = "EC2 Security group for SSH"
  description = "EC2 Security group for SSH"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp"]
  egress_rules        = ["all-all"]
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "ssh_pvt_key" {
    sensitive_content     = tls_private_key.ssh.private_key_pem
    filename = "ssh-pvt.pem"
    file_permission = 0400
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = module.ec2_role_custom.this_iam_role_name
  role = module.ec2_role_custom.this_iam_role_name
}

module "alb-sg" {
  source = "./modules/sg/modules/http-80"

  name        = "alb-sg"
  description = "Security group for alb"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["https-443-tcp"]
}


module "alb" {
  source = "./modules/alb/"

  name = "alb"

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  security_groups = [module.alb-sg.this_security_group_id]
  subnets         = module.vpc.public_subnets

  http_tcp_listeners = [
    {
      port        = 80
      protocol    = "HTTP"
      action_type = "redirect"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  ]

  https_listeners = [
    {
      port               = 443
      protocol           = "HTTPS"
      certificate_arn    = var.certificate-arn
      target_group_index = 0
    }
  ]

  target_groups = [
    {
      name_prefix          = "h1"
      backend_protocol     = "HTTPS"
      backend_port         = 443
      target_type          = "instance"
      deregistration_delay = 10
      health_check = {
        enabled             = true
        interval            = 300
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 6
        protocol            = "HTTPS"
        matcher             = "200-399"
      }
    }
  ]
  target_group_tags = {
    Name = "targetgroup"
  }
}


module "asg-sg" {
  source = "./modules/sg/"

  name        = "asg-sg"
  description = "Security group for autoscaling group"
  vpc_id      = module.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "https-443-tcp"
      source_security_group_id = module.alb-sg.this_security_group_id
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 1  

  egress_with_cidr_blocks = [
    {
      from_port = 0
      to_port = 65535
      protocol    = -1
      description = "Allow all outbound traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

resource "aws_launch_configuration" "this" {
  name_prefix   = "gl-"
  image_id      = var.image-id
  instance_type = var.instance-type
  user_data = templatefile("./userdata.sh",{})
  lifecycle {
    create_before_destroy = true
  }
  key_name = aws_key_pair.ec2_key.key_name
  # Security group
  security_groups = [module.asg-sg.this_security_group_id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

}

module "autoscaling" {
  source = "./modules/autoscaling/"

  name = "asg-server"

  # Use of existing launch configuration (created outside of this module)
  launch_configuration = aws_launch_configuration.this.name

  create_lc = false
  # create_lc = true

  recreate_asg_when_lc_changes = true

  # Auto scaling group
  asg_name                  = "gl-asg"
  vpc_zone_identifier       = module.vpc.private_subnets
  health_check_type         = "EC2"
  min_size                  = 0
  max_size                  = 1
  desired_capacity          = 1
  wait_for_capacity_timeout = 0

  # target group
  target_group_arns = module.alb.target_group_arns

}

module "postgres-sg" {
  source = "./modules/sg/"

  name        = "postgres-sg"
  description = "Security group for postgres"
  vpc_id      = module.vpc.vpc_id
  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "postgresql-tcp"
      source_security_group_id = module.alb-sg.this_security_group_id
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 1
}

module "postgres-rds" {
  source = "./modules/rds/"

  identifier = "postgres-ha"

  engine            = "postgres"
  engine_version    = "11.9"
  instance_class    = "db.t2.large"
  allocated_storage = 20
  storage_encrypted = false

  # kms_key_id        = "arm:aws:kms:<region>:<account id>:key/<kms key id>"
  name = "postgres"

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  username = var.dbuser

  password = var.dbpassword
  port     = "5432"

  vpc_security_group_ids = [module.postgres-sg.this_security_group_id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  # disable backups to create DB faster
  backup_retention_period = 15

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # DB subnet group
  subnet_ids = module.vpc.database_subnets

  # DB parameter group
  family = "postgres11"

  # DB option group
  major_engine_version = "11"

  # Snapshot name upon DB deletion
  final_snapshot_identifier = "postgres-finalsnapshot"

  # Database Deletion Protection
  deletion_protection = false
}
