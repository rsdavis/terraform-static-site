provider "aws" {
    profile = "default"
    region  = "us-east-1"
}

resource "aws_s3_bucket" "bucket" {

    bucket  = "balloons.boutique"
    acl     = "public-read"
    policy  = file("policy.json")

    website {
        index_document = "index.html"
        error_document = "error.html"
    }

    tags = {
        Project = "balloons"
    }

}

resource "aws_acm_certificate" "cert" {

    domain_name         = "balloons.boutique"
    validation_method   = "DNS"

    tags = {
        Project = "balloons"
    }

    lifecycle {
        create_before_destroy = true
    }

}

data "aws_route53_zone" "zone" {
    name            = "balloons.boutique"
    private_zone    = false
}

resource "aws_route53_record" "rec" {

    for_each = {
        for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
            name    = dvo.resource_record_name
            record  = dvo.resource_record_value
            type    = dvo.resource_record_type
        }
    }

    allow_overwrite = true
    name            = each.value.name
    records         = [each.value.record]
    ttl             = 60
    type            = each.value.type
    zone_id         = data.aws_route53_zone.zone.zone_id

}

resource "aws_cloudfront_distribution" "distribution" {

    origin {

        domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
        origin_id = "my-origin-id"

    }

    enabled             = true
    is_ipv6_enabled     = true
    default_root_object = "index.html"
    aliases             = ["balloons.boutique"]

    default_cache_behavior {

        allowed_methods = [ "GET", "HEAD" ]
        cached_methods  = [ "GET", "HEAD" ]
        target_origin_id = "my-origin-id"

        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }

        viewer_protocol_policy  = "redirect-to-https"
        min_ttl                 = 0
        default_ttl             = 3600
        max_ttl                 = 86400

    }

    price_class = "PriceClass_100"

    restrictions {
        geo_restriction {
            restriction_type    = "whitelist"
            locations           = ["US", "CA"]
        }
    }

    tags = {
        Project = "balloons"
    }

    viewer_certificate {
        acm_certificate_arn = aws_acm_certificate.cert.arn
        ssl_support_method  = "sni-only"
    }

}

resource "aws_route53_record" "alias" {

    zone_id = data.aws_route53_zone.zone.zone_id
    name    = "balloons.boutique"
    type    = "A"

    alias {
        name    = aws_cloudfront_distribution.distribution.domain_name
        zone_id = aws_cloudfront_distribution.distribution.hosted_zone_id
        evaluate_target_health = false
    }

}