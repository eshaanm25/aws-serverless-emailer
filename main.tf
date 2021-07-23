terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}


# Configure the AWS Provider. Done twice due to a big with Terraform.
provider "aws" {
  region = var.aws-region
  alias = "us-east-1"
  access_key = var.access-key
  secret_key = var.secret-key
}

provider "aws" {
  region = var.aws-region
}

###The first step is to provision an AWS static website. This code is from the Terraform Module "cloudmaniac/static-website/aws"  

## Route 53
# Provides details about the zone
data "aws_route53_zone" "main" {
  name         = var.site-domain
  private_zone = false
}

## ACM (AWS Certificate Manager)
# Creates the wildcard certificate *.<yourdomain.com>
resource "aws_acm_certificate" "wildcard_website" {
  provider                  = aws.us-east-1
  domain_name               = var.site-domain
  subject_alternative_names = ["*.${var.site-domain}"]
  validation_method         = "DNS"

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [tags["Changed"]]
  }

}

# Validates the ACM wildcard by creating a Route53 record (as `validation_method` is set to `DNS` in the aws_acm_certificate resource)
resource "aws_route53_record" "wildcard_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard_website.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  name            = each.value.name
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
  records         = [each.value.record]
  allow_overwrite = true
  ttl             = "60"
}

# Triggers the ACM wildcard certificate validation event
resource "aws_acm_certificate_validation" "wildcard_cert" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.wildcard_website.arn
  validation_record_fqdns = [for k, v in aws_route53_record.wildcard_validation : v.fqdn]
}


# Get the ARN of the issued certificate
data "aws_acm_certificate" "wildcard_website" {
  provider = aws.us-east-1

  depends_on = [
    aws_acm_certificate.wildcard_website,
    aws_route53_record.wildcard_validation,
    aws_acm_certificate_validation.wildcard_cert,
  ]

  domain      = var.site-domain
  statuses    = ["ISSUED"]
  most_recent = true
}

## S3
# Creates bucket to store logs
resource "aws_s3_bucket" "website_logs" {
  bucket = "${var.site-domain}-logs"
  acl    = "log-delivery-write"

  # Comment the following line if you are uncomfortable with Terraform destroying the bucket even if this one is not empty
  force_destroy = true


  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [tags["Changed"]]
  }
}

# Creates bucket to store the static website
resource "aws_s3_bucket" "website_root" {
  bucket = "${var.site-domain}-root"
  acl    = "public-read"

  # Comment the following line if you are uncomfortable with Terraform destroying the bucket even if not empty
  force_destroy = true

  logging {
    target_bucket = aws_s3_bucket.website_logs.bucket
    target_prefix = "${var.site-domain}/"
  }

  website {
    index_document = "index.html"
    error_document = "404.html"
  }

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [tags["Changed"]]
  }
}

# Creates bucket for the website handling the redirection (if required), e.g. from https://www.example.com to https://example.com
resource "aws_s3_bucket" "website_redirect" {
  bucket        = "${var.site-domain}-redirect"
  acl           = "public-read"
  force_destroy = true

  logging {
    target_bucket = aws_s3_bucket.website_logs.bucket
    target_prefix = "${var.site-domain}-redirect/"
  }

  website {
    redirect_all_requests_to = "https://${var.site-domain}"
  }

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [tags["Changed"]]
  }
}

## CloudFront
# Creates the CloudFront distribution to serve the static website
resource "aws_cloudfront_distribution" "website_cdn_root" {
  enabled     = true
  price_class = "PriceClass_All"
  # Select the correct PriceClass depending on who the CDN is supposed to serve (https://docs.aws.amazon.com/AmazonCloudFront/ladev/DeveloperGuide/PriceClass.html)
  aliases = [var.site-domain]

  origin {
    origin_id   = "origin-bucket-${aws_s3_bucket.website_root.id}"
    domain_name = aws_s3_bucket.website_root.website_endpoint

    custom_origin_config {
      origin_protocol_policy = "http-only"
      # The protocol policy that you want CloudFront to use when fetching objects from the origin server (a.k.a S3 in our situation). HTTP Only is the default setting when the origin is an Amazon S3 static website hosting endpoint, because Amazon S3 doesn’t support HTTPS connections for static website hosting endpoints.
      http_port            = 80
      https_port           = 443
      origin_ssl_protocols = ["TLSv1.2", "TLSv1.1", "TLSv1"]
    }
  }

  default_root_object = "index.html"

  logging_config {
    bucket = aws_s3_bucket.website_logs.bucket_domain_name
    prefix = "${var.site-domain}/"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "origin-bucket-${aws_s3_bucket.website_root.id}"
    min_ttl          = "0"
    default_ttl      = "300"
    max_ttl          = "1200"

    viewer_protocol_policy = "redirect-to-https" # Redirects any HTTP request to HTTPS
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.wildcard_website.arn
    ssl_support_method  = "sni-only"
  }

  custom_error_response {
    error_caching_min_ttl = 300
    error_code            = 404
    response_page_path    = "/404.html"
    response_code         = 404
  }

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [
      tags["Changed"],
      viewer_certificate,
    ]
  }
}

# Creates the DNS record to point on the main CloudFront distribution ID
resource "aws_route53_record" "website_cdn_root_record" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.site-domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_cdn_root.domain_name
    zone_id                = aws_cloudfront_distribution.website_cdn_root.hosted_zone_id
    evaluate_target_health = false
  }
}


# Creates policy to allow public access to the S3 bucket
resource "aws_s3_bucket_policy" "update_website_root_bucket_policy" {
  bucket = aws_s3_bucket.website_root.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "PolicyForWebsiteEndpointsPublicContent",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": [
        "${aws_s3_bucket.website_root.arn}/*",
        "${aws_s3_bucket.website_root.arn}"
      ]
    }
  ]
}
POLICY
}

# Creates the CloudFront distribution to serve the redirection website (if redirection is required)
resource "aws_cloudfront_distribution" "website_cdn_redirect" {
  enabled     = true
  price_class = "PriceClass_All"
  # Select the correct PriceClass depending on who the CDN is supposed to serve (https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PriceClass.html)
  aliases = [var.site-redirect]

  origin {
    origin_id   = "origin-bucket-${aws_s3_bucket.website_redirect.id}"
    domain_name = aws_s3_bucket.website_redirect.website_endpoint

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  logging_config {
    bucket = aws_s3_bucket.website_logs.bucket_domain_name
    prefix = "${var.site-redirect}/"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "origin-bucket-${aws_s3_bucket.website_redirect.id}"
    min_ttl          = "0"
    default_ttl      = "300"
    max_ttl          = "1200"

    viewer_protocol_policy = "redirect-to-https" # Redirects any HTTP request to HTTPS
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.wildcard_website.arn
    ssl_support_method  = "sni-only"
  }

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  })

  lifecycle {
    ignore_changes = [
      tags["Changed"],
      viewer_certificate,
    ]
  }
}

# Creates the DNS record to point on the CloudFront distribution ID that handles the redirection website
resource "aws_route53_record" "website_cdn_redirect_record" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.site-redirect
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_cdn_redirect.domain_name
    zone_id                = aws_cloudfront_distribution.website_cdn_redirect.hosted_zone_id
    evaluate_target_health = false
  }
}

#Creating DynamoDB Table
resource "aws_dynamodb_table" "dynamodb-table-email" {
  name           = "UserData"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "email"

  attribute {
    name = "email"
    type = "S"
  }

}

#Create Lambda Function IAM Policy
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam-for-lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
    ]
}
EOF
}

#Create a policy to allow Lambda to add to a DyanmoDB Table
resource "aws_iam_policy" "DynamoDB-Policy" {
  name        = "DYNAMODB_Policy"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "dynamodb:PutItem",
            "Resource": "${aws_dynamodb_table.dynamodb-table-email.arn}"
        }
    ]
  })
}

#Attach DynamoDB-Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "DynamoDB-policy-attachment" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.DynamoDB-Policy.arn
}

#Import Lambda Function
resource "aws_lambda_function" "EmailLambda" {
  filename      = "lambdaTerraform.zip"
  function_name = "EmailLambda"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "index.handler"

  source_code_hash = filebase64sha256("lambdaTerraform.zip")

  runtime = "nodejs14.x"

  environment {
    variables = {
      SENDGRID_API_KEY = var.sendgrid-api-key
      SENDGRID_FROM_ADDRESS = var.from-address
      SENDGRID_TEMPLATE_ID = var.sendgrid-template-id
      TABLE_NAME = aws_dynamodb_table.dynamodb-table-email.name
      AWS_DYNAMODB_REGION = var.aws-region
    }
  }
}

###Create a REST API with API Gateway
resource "aws_api_gateway_rest_api" "serverlessapi" {
  name        = "ServerlessAPI"
  description = "Terraform Serverless Application Example"
}

#Create API
resource "aws_api_gateway_resource" "path" {
  rest_api_id = "${aws_api_gateway_rest_api.serverlessapi.id}"
  parent_id   = "${aws_api_gateway_rest_api.serverlessapi.root_resource_id}"
  path_part   = "email"
}

#Create POST Method
resource "aws_api_gateway_method" "method" {
  rest_api_id   = "${aws_api_gateway_rest_api.serverlessapi.id}"
  resource_id   = "${aws_api_gateway_resource.path.id}"
  http_method   = "POST"
  authorization = "NONE"
}

#Create Request Template for method
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.serverlessapi.id}"
  resource_id = "${aws_api_gateway_method.method.resource_id}"
  http_method = "${aws_api_gateway_method.method.http_method}"

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.EmailLambda.invoke_arn

  request_templates = {
    "application/json" = <<EOF
{
    "mailaddress": $input.json('$.mailaddress'),
    "firstname": $input.json('$.firstname')
}
EOF
}
}

#Allow API gateway to trigger lambda function
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.EmailLambda.function_name
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_rest_api.serverlessapi.execution_arn}/*/*"
}

#Configure API Gateway Method Response
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.serverlessapi.id
  resource_id = aws_api_gateway_resource.path.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

#Configure API Gateway Integration Response
resource "aws_api_gateway_integration_response" "MyDemoIntegrationResponse" {
  rest_api_id = aws_api_gateway_rest_api.serverlessapi.id
  resource_id = aws_api_gateway_resource.path.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

#Deploys API to prod environment
resource "aws_api_gateway_deployment" "stage" {
  depends_on = [
    aws_api_gateway_integration.lambda,
  ]

  rest_api_id = "${aws_api_gateway_rest_api.serverlessapi.id}"
  stage_name  = "prod"
}

resource "local_file" "apiscriptfile" {
    content       = "$(\"#submitButton\").on(\"click\",function(){return $.ajax({type:\"POST\",url:\"${aws_api_gateway_deployment.stage.invoke_url}${aws_api_gateway_resource.path.path}\",data:JSON.stringify({mailaddress:$(\"#email\").val(),firstname:$(\"#firstname\").val()}),contentType:\"application/json\",success:function(e){$(\"entries\").html(\"\"),$(\"#entries\").append(\"<p><center> Thanks so much <b>\"+e+\"</b> glad to meet you!<center><p>\"),setTimeout(function(){window.location.replace(\"${var.redirectlink}\")},3e3)}}),!1});"
    filename = "./websitefiles/js/apiscript.js"
}

### Now we will upload our static website resources to an S3 Bucket

variable "mime_types" {
  default = {
    htm   = "text/html"
    html  = "text/html"
    css   = "text/css"
    ttf   = "font/ttf"
    js    = "application/javascript"
    map   = "application/javascript"
    json  = "application/json"
    DS_Store = "text/html" #Sneaky Mac File
    jpeg = "image/jpeg"
  }
}

resource "aws_s3_bucket_object" "website_files" {
  for_each      = fileset("websitefiles/", "**/*.*")
  bucket        = aws_s3_bucket.website_root.id
  key           = replace(each.value, "websitefiles/", "")
  source        = "websitefiles/${each.value}"
  acl           = "public-read"
  etag          = filemd5("websitefiles/${each.value}")
  content_type  = lookup(var.mime_types, split(".", each.value)[length(split(".", each.value)) - 1])
}