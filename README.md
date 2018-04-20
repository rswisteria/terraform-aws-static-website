# Teffaform Configuration for Static Web Hosting

[terraform]: https://terraform.io
[aws]: https://aws.amazon.com/
[awscli]: https://aws.amazon.com/cli

This repository is the [terraform] setting file for configuring static website with AWS S3, CloudFront, Route53 and Certificate Manager.

## Prerequisite

- [terraform]
- [awscli]
- Route 53 zone setting

## Quickstart

First, copy `aws_static_website.tfvars.sample` to `aws_static_website.tfvars`, then you can configure the project specific variables.

|key||
|---|---|
|awscli_profile|This is the AWS profile name as set in the shared credentials files(.aws/config, .aws/credential).|
|region|This is the AWS region.|
|bucket_name|This is the S3 bucket name which is created by terraform.|
|hosted_domain_name|This is the domain name to use the endpoint of CloudFront edge location.|
|route53_zone_name|This is the Route53 zone name to be added new record for this website. This must ends with dot(.). (cf. `example.com.`)|

You have to create Route 53 Hosted Zone manually. Because you can create multiple websites on same domain, and you can create and destroy them individualy. If it is included that configuration of Route 53 Hosted zone, it destroys all domain settings when `terraform destroy` executes. It is very dangerous.

You can check if that's configuration is valid by running follows,

```
terraform plan -var-file=aws_static_website.tfvars
```

Then you can create website by running follows,

```
terraform apply -var-file=aws_static_website.tfvars
```
