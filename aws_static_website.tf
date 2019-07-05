variable "bucket_name" {}
variable "hosted_domain_name" {}
variable "route53_zone_name" {}
variable "awscli_profile" {}
variable "region" {}

provider "aws" {
  profile = "${var.awscli_profile}"
  region  = "${var.region}"
}

provider "aws" {
  alias   = "global"
  profile = "${var.awscli_profile}"
  region  = "us-east-1"
}

data "aws_route53_zone" "selected" {
  name = "${var.route53_zone_name}"
  private_zone = false
}

resource "aws_s3_bucket" "web_hosting_bucket" {
  bucket = "${var.bucket_name}"
  acl    = "public-read"

  website {
    index_document = "index.html"
    error_document = "error.html"
  }
}

resource "aws_s3_bucket_policy" "web_hosting_bucket" {
  bucket = "${aws_s3_bucket.web_hosting_bucket.bucket}"
  policy = <<POLICY
{
  "Id": "Policy1524134364829",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1524134363397",
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.web_hosting_bucket.bucket}/*",
      "Condition": {
        "StringEquals": {
          "aws:UserAgent": "Amazon CloudFront"
        }
      },
      "Principal": "*"
    }
  ]
}
POLICY
}

resource "aws_acm_certificate" "web_certificate" {
  provider          = "aws.global"
  domain_name       = "${var.hosted_domain_name}"
  validation_method = "DNS"
}

resource "aws_route53_record" "web_certificate_validation" {
  zone_id = "${data.aws_route53_zone.selected.id}"
  name    = "${aws_acm_certificate.web_certificate.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.web_certificate.domain_validation_options.0.resource_record_type}"
  records = ["${aws_acm_certificate.web_certificate.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}

data "aws_iam_policy_document" "lambda-assume-role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda-edge" {
  name = "lambda-edge"
  assume_role_policy = "${data.aws_iam_policy_document.lambda-assume-role.json}"
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = "${aws_iam_role.lambda-edge.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "basic_auth" {
  type        = "zip"
  source_dir  = "lambda/basic_auth"
  output_path = "lambda/dst/basic_auth.zip"
}

resource "aws_acm_certificate_validation" "web_certificate" {
  provider                = "aws.global"
  certificate_arn         = "${aws_acm_certificate.web_certificate.arn}"
  validation_record_fqdns = ["${aws_route53_record.web_certificate_validation.fqdn}"]
}

resource "aws_lambda_function" "basic_auth" {
  provider         = "aws.global"
  filename         = "${data.archive_file.basic_auth.output_path}"
  function_name    = "basic_auth"
  role             = "${aws_iam_role.lambda-edge.arn}"
  handler          = "index.handler"
  source_code_hash = "${data.archive_file.basic_auth.output_base64sha256}"
  runtime          = "nodejs8.10"

  publish          = true

  memory_size = 128
  timeout     = 3
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.web_hosting_bucket.website_endpoint}"
    origin_id   = "S3-Website-${aws_s3_bucket.web_hosting_bucket.website_domain}"

    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  price_class         = "PriceClass_200"
  comment             = "Created by Terraform"
  default_root_object = "index.html"

  aliases = ["${var.hosted_domain_name}"]

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "S3-Website-${aws_s3_bucket.web_hosting_bucket.website_domain}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type = "viewer-request"
      lambda_arn = "${aws_lambda_function.basic_auth.qualified_arn}"
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300
    max_ttl                = 31536000
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = "${aws_acm_certificate.web_certificate.arn}"
    minimum_protocol_version       = "TLSv1.1_2016"
    ssl_support_method             = "sni-only"
  }
}

resource "aws_route53_record" "web_domain" {
  zone_id = "${data.aws_route53_zone.selected.id}"
  name    = "${var.hosted_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.s3_distribution.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.s3_distribution.hosted_zone_id}"
    evaluate_target_health = false
  }
}
