#!/usr/bin/env bash
#
# One-time Terraform backend bootstrap.
#
# The state bucket cannot be managed by Terraform - it is the backend that every
# stack depends on - so this script is the documented substitute. Run it once
# per AWS account before any `terraform init`.
#
# Safe to re-run: the bucket is only created if it is missing, and every other
# operation is idempotent.

set -euo pipefail

BUCKET="smarthelmet-terraform-state"
REGION="ap-south-1"

# create-bucket rejects LocationConstraint for us-east-1, so the region is
# passed explicitly rather than relying on the ambient default.
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket already exists: $BUCKET"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION"
fi

# Versioning, so a bad apply can be recovered from a previous state object.
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# SSE-S3. The backend also sets `encrypt = true`; this covers objects written by
# anything other than Terraform.
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# State files carry every resource attribute, and a misconfigured resource can
# put secrets in them.
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Deliberately no DynamoDB lock table. Every stack's backend sets
# `use_lockfile = true`, which locks using S3 conditional writes. An account
# bootstrapped from an older version of this script may still have an unused
# `terraform-state-lock` table; deleting it is a manual step, because it is not
# this script's to remove.
echo "State backend ready: s3://$BUCKET ($REGION)"
