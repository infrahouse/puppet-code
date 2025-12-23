# Terraform Requirements for Jumphost CloudWatch Logging

## Overview
The `terraform-aws-jumphost` module needs to provide specific resources and facts 
to enable CloudWatch logging integration with Puppet.

## Required Terraform Resources

### 1. CloudWatch Log Group
```hcl
resource "aws_cloudwatch_log_group" "jumphost" {
  name              = "/aws/ec2/jumphost/${var.environment}"
  retention_in_days = var.log_retention_days # Recommend 365 for compliance

  tags = merge(
    var.tags,
    {
      Name        = "jumphost-logs-${var.environment}"
      Environment = var.environment
      Purpose     = "Security and compliance logging"
    }
  )
}
```

### 2. IAM Role Permissions
Add to the existing jumphost IAM role:
```hcl
data "aws_iam_policy_document" "cloudwatch_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      aws_cloudwatch_log_group.jumphost.arn,
      "${aws_cloudwatch_log_group.jumphost.arn}:*"
    ]
  }

  # CloudWatch agent also needs EC2 metadata access
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus"
    ]
    resources = ["*"]
  }

  # For CloudWatch metrics (optional but recommended)
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Jumphost/System"]
    }
  }
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name   = "cloudwatch-logs"
  role   = aws_iam_role.jumphost.id
  policy = data.aws_iam_policy_document.cloudwatch_logs.json
}
```

### 3. Custom Facts via User Data
Provide the CloudWatch log group name to Puppet via custom facts:

```hcl
locals {
  custom_facts = {
    jumphost = {
      cloudwatch_log_group = aws_cloudwatch_log_group.jumphost.name
      environment          = var.environment
      role                 = "jumphost"
    }
  }
}

# In your user_data script:
resource "aws_instance" "jumphost" {
  # ... other configuration ...

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    custom_facts = jsonencode(local.custom_facts)
  })
}
```

#### user_data.sh.tpl example:
```bash
#!/bin/bash

# Create custom facts directory
mkdir -p /etc/facter/facts.d

# Write custom facts for Puppet
cat > /etc/facter/facts.d/jumphost.json <<'EOF'
${custom_facts}
EOF

# ... rest of your user data script ...
```

### 4. Security Group Rules (if needed)
If you're using VPC endpoints for CloudWatch:
```hcl
resource "aws_security_group_rule" "cloudwatch_vpc_endpoint" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.jumphost.id
  prefix_list_ids   = [data.aws_prefix_list.s3.id] # If using VPC endpoints
  description       = "Allow HTTPS to CloudWatch VPC endpoint"
}
```

## Required Module Outputs

Add these outputs to the Terraform module:

```hcl
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for jumphost logs"
  value       = aws_cloudwatch_log_group.jumphost.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for jumphost logs"
  value       = aws_cloudwatch_log_group.jumphost.arn
}

output "iam_role_name" {
  description = "Name of the IAM role with CloudWatch permissions"
  value       = aws_iam_role.jumphost.name
}
```

## Module Variables to Add

```hcl
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 365 # For compliance

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for the jumphost"
  type        = bool
  default     = true
}

variable "cloudwatch_namespace" {
  description = "CloudWatch namespace for custom metrics"
  type        = string
  default     = "Jumphost/System"
}
```

## Puppet Integration

Once Terraform provides the facts, Puppet will:

1. Check for the fact:
```puppet
if $facts['jumphost'] and $facts['jumphost']['cloudwatch_log_group'] {
  # Configure CloudWatch agent
}
```

2. Use the log group name in CloudWatch agent configuration:
```erb
"log_group_name": "<%= @cloudwatch_log_group %>",
```

## Testing the Integration

### 1. Verify Facts on Instance
```bash
# SSH to jumphost
sudo facter -p jumphost
# Should show:
# {
#   "cloudwatch_log_group": "/aws/ec2/jumphost/development",
#   "environment": "development",
#   "role": "jumphost"
# }
```

### 2. Verify IAM Permissions
```bash
# On the jumphost
aws sts get-caller-identity
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/jumphost"
```

### 3. Test Log Writing
```bash
# After CloudWatch agent is configured
echo "Test log entry" | sudo tee -a /var/log/test.log
# Check CloudWatch console for the log entry
```

## Complete Example Integration

Here's how it all fits together:

```hcl
module "jumphost" {
  source = "infrahouse/jumphost/aws"

  # ... existing configuration ...

  # CloudWatch logging configuration
  log_retention_days      = 365  # Compliance requirement
  enable_cloudwatch_logs  = true
  cloudwatch_namespace    = "Jumphost/System"

  tags = {
    Environment = var.environment
    Compliance  = "SOC2,ISO27001"
  }
}

# Use the outputs
output "jumphost_logs" {
  value = {
    log_group = module.jumphost.cloudwatch_log_group_name
    role_name = module.jumphost.iam_role_name
  }
}
```

## Migration Path

For existing jumphosts without CloudWatch:

1. **Phase 1**: Add CloudWatch resources to Terraform
2. **Phase 2**: Apply Terraform to create log groups and update IAM
3. **Phase 3**: Update user data to provide facts
4. **Phase 4**: Reboot instances or manually create facts file
5. **Phase 5**: Puppet will automatically configure CloudWatch agent

## Cost Considerations

### Estimated Monthly Costs (per jumphost)
- **Log Ingestion**: ~$0.50/GB
- **Log Storage**: ~$0.03/GB/month
- **Metrics**: ~$0.30 for first 10,000 metrics

### For a typical jumphost:
- 5GB logs/month = $2.50 ingestion + $0.15 storage
- System metrics = $0.30
- **Total**: ~$3/month per jumphost

## Security Considerations

1. **Encryption**: CloudWatch log groups are encrypted by default with AWS managed keys
2. **Access Control**: Use IAM policies to restrict who can read logs
3. **VPC Endpoints**: Consider using VPC endpoints to keep traffic private
4. **Log Tampering**: Once in CloudWatch, logs are immutable

## Compliance Benefits

With this setup, you get:
- ✅ Centralized, immutable audit trail (SOC2 CC7.1)
- ✅ 365-day retention for compliance audits
- ✅ Real-time security monitoring capability
- ✅ Automated log rotation (no disk space issues)
- ✅ Integration with AWS CloudWatch Insights for analysis
- ✅ Ability to create CloudWatch alarms on log patterns

## Next Steps

1. **Update terraform-aws-jumphost module** with above changes
2. **Test in development** environment first
3. **Create CloudWatch dashboard** for jumphost monitoring
4. **Set up CloudWatch alarms** for security events
5. **Document runbooks** for incident response using these logs
