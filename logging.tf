resource "aws_cloudtrail" "s3_cloudtrail" {
  count                         = var.logging ? 1 : 0
  depends_on                    = [aws_iam_role_policy_attachment.s3_cloudtrail_policy_attachment]
  name                          = format("%s-%s-S3", var.bucket_name, data.aws_caller_identity.current.account_id)
  s3_bucket_name                = module.log_bucket[0].s3_bucket_id
  s3_key_prefix                 = "log"
  include_global_service_events = false
  enable_logging                = true
  enable_log_file_validation    = true
  cloud_watch_logs_role_arn     = aws_iam_role.s3_cloudtrail_cloudwatch_role[0].arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.s3_cloudwatch[0].arn}:*"
  kms_key_id                    = module.kms_key[0].key_arn
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }
  tags = merge(
    { "Name" = format("%s-%s-S3", var.bucket_name, data.aws_caller_identity.current.account_id) },
    local.tags,
  )
}

resource "aws_cloudwatch_log_group" "s3_cloudwatch" {
  count      = var.logging ? 1 : 0
  name       = format("%s-%s-S3", var.bucket_name, data.aws_caller_identity.current.account_id)
  kms_key_id = module.kms_key[0].key_arn
  provisioner "local-exec" {
    command = "sleep 10"
  }
  tags = merge(
    { "Name" = format("%s-%s-S3", var.bucket_name, data.aws_caller_identity.current.account_id) },
    local.tags,
  )
}

resource "aws_iam_role" "s3_cloudtrail_cloudwatch_role" {
  count              = var.logging ? 1 : 0
  name               = format("%s-cloudtrail-cloudwatch-S3", var.bucket_name)
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role[0].json
  tags = merge(
    { "Name" = format("%s-cloudtrail-cloudwatch-S3", var.bucket_name) },
    local.tags,
  )
}

data "aws_iam_policy_document" "cloudtrail_assume_role" {
  count = var.logging ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "s3_cloudtrail_cloudwatch_policy" {
  count  = var.logging ? 1 : 0
  name   = format("%s-cloudtrail-cloudwatch-S3", var.bucket_name)
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailCreateLogStream2014110",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream"
      ],
      "Resource": [
        "arn:aws:logs:${data.aws_region.region.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.bucket_name}-${data.aws_caller_identity.current.account_id}-S3:log-stream:*"
      ]
    },
    {
      "Sid": "AWSCloudTrailPutLogEvents20141101",
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:${data.aws_region.region.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.bucket_name}-${data.aws_caller_identity.current.account_id}-S3:log-stream:*"
      ]
    }
  ]
}
EOF
  tags = merge(
    { "Name" = format("%s-cloudtrail-cloudwatch-S3", var.bucket_name) },
    local.tags,
  )
}



resource "aws_iam_role_policy_attachment" "s3_cloudtrail_policy_attachment" {
  count      = var.logging ? 1 : 0
  role       = aws_iam_role.s3_cloudtrail_cloudwatch_role[0].name
  policy_arn = aws_iam_policy.s3_cloudtrail_cloudwatch_policy[0].arn
}




module "log_bucket" {
  count                                 = var.logging ? 1 : 0
  source                                = "terraform-aws-modules/s3-bucket/aws"
  version                               = "3.10.0"
  bucket                                = format("%s-%s-log-bucket", var.bucket_name, data.aws_caller_identity.current.account_id)
  force_destroy                         = true
  attach_elb_log_delivery_policy        = true
  attach_lb_log_delivery_policy         = true
  attach_deny_insecure_transport_policy = true
  # S3 bucket-level Public Access Block configuration
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  attach_policy           = true
  policy                  = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSCloudTrailAclCheck20150319",
            "Effect": "Allow",
            "Principal": {"Service":"cloudtrail.amazonaws.com"},
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${var.bucket_name}-${data.aws_caller_identity.current.account_id}-log-bucket"
        },
        {
            "Sid": "AWSCloudTrailWrite20150319",
            "Effect": "Allow",
            "Principal": {"Service":"cloudtrail.amazonaws.com"},
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${var.bucket_name}-${data.aws_caller_identity.current.account_id}-log-bucket/log/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        }
    ]
}
POLICY
}

module "kms_key" {
  count      = var.logging ? 1 : 0
  depends_on = [data.aws_iam_policy_document.default]
  source     = "clouddrove/kms/aws"
  version    = "0.15.0"

  name                    = format("%s-%s-kms-03", var.bucket_name, data.aws_caller_identity.current.account_id)
  enabled                 = true
  description             = "KMS key for cloudtrail"
  deletion_window_in_days = 15
  policy                  = data.aws_iam_policy_document.default[0].json
  enable_key_rotation     = true
}

data "aws_iam_policy_document" "default" {
  count   = var.logging ? 1 : 0
  version = "2012-10-17"
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
  statement {
    sid    = "Allow CloudTrail to encrypt logs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:XXXXXXXXXXXX:trail/*"]
    }
  }

  statement {
    sid    = "Allow CloudTrail to describe key"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow principals in the account to decrypt log files"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "kms:Decrypt",
      "kms:ReEncryptFrom"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values = [
      "XXXXXXXXXXXX"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:XXXXXXXXXXXX:trail/*"]
    }
  }

  statement {
    sid    = "Allow alias creation during setup"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:CreateAlias"]
    resources = ["*"]
  }
}
