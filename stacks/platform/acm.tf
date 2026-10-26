# Wildcard certificate for the app Ingresses. The AWS Load Balancer Controller finds it by the
# Ingress TLS host, so charts don't need the ARN.
resource "aws_acm_certificate" "apps" {
  domain_name       = "*.${local.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "apps_validation" {
  for_each = {
    for o in aws_acm_certificate.apps.domain_validation_options : o.domain_name => o
  }

  zone_id         = local.hosted_zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "apps" {
  certificate_arn         = aws_acm_certificate.apps.arn
  validation_record_fqdns = [for r in aws_route53_record.apps_validation : r.fqdn]
}
