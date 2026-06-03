#Create S3 bucket for terraform state file
aws s3api create-bucket --bucket smarthelmet-terraform-state --region ap-south-1 --create-bucket-configuration LocationConstraint=ap-south-1

#Enable Versioning 
aws s3api put-bucket-versioning --bucket smarthelmet-terraform-state --versioning-configuration Status=Enabled

#Create DynamoDB table for state locking
aws dynamodb create-table --table-name terraform-state-lock --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region ap-south-1