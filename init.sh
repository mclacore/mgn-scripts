#!/bin/bash

# add some type of value checking for empty inputs
read -p "Enter the AWS region (e.g., us-east-1): " AWS_REGION
read -p "Set type of IP (PUBLIC_IP, PRIVATE_IP): " IP_TYPE
read -p "Set disk type (GP2, GP3, ST1): " DISK_TYPE
read -p "Set EBS encryption (DEFAULT, CUSTOM): " EBS_ENCRYPTION
read -p "Set replication server instance type (e.g., t2.micro): " INSTANCE_TYPE
read -p "Set staging area subnet ID (e.g., subnet-01234abcde): " STAGING_SUBNET
read -p "Set staging area tags (e.g., Key=value,Foo=bar): " STAGING_TAGS

read -p "Do you want to associate a default security group? (yes/no): " ASSOCIATE_SG
if [[ "$ASSOCIATE_SG" =~ ^(yes|y)$ ]]; then
    ASSOCIATE_SG_ARG="--associate-default-security-group"
else
    ASSOCIATE_SG_ARG="--no-associate-default-security-group"
fi

read -p "Do you want to create a public IP? (yes/no): " CREATE_PUBLIC_IP
if [[ "$CREATE_PUBLIC_IP" =~ ^(yes|y)$ ]]; then
    CREATE_PUBLIC_IP_ARG="--create-public-ip"
else
    CREATE_PUBLIC_IP_ARG="--no-create-public-ip"
fi

read -p "Do you want to use a dedicated replication server? (yes/no): " USE_DEDICATED_REPLICATION_SERVER
if [[ "$USE_DEDICATED_REPLICATION_SERVER" =~ ^(yes|y)$ ]]; then
    DEDICATED_REPLICATION_SERVER_ARG="--use-dedicated-replication-server"
else
    DEDICATED_REPLICATION_SERVER_ARG="--no-use-dedicated-replication-server"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

create_role_with_error_handling() {
    local role_name=$1
    local policy_document=$2
    shift 2
    local policies=("$@")
    echo "Creating role $role_name..."
    aws iam create-role --path "/service-role/" --role-name "$role_name" --assume-role-policy-document "$policy_document" 2>error.log
    if [[ $? -ne 0 ]]; then
        if grep -q "EntityAlreadyExists" error.log; then
            echo "Role $role_name already exists."
        else
            echo "Error creating role $role_name:"
            cat error.log
        fi
    else
        echo "Role $role_name created successfully."
    fi

    for policy in "${policies[@]}"; do
        echo "Attaching policy $policy to role $role_name..."
        aws iam attach-role-policy --policy-arn "$policy" --role-name "$role_name" 2>error.log
        if [[ $? -ne 0 ]]; then
            echo "Error attaching policy $policy to role $role_name:"
            cat error.log
        else
            echo "Policy $policy attached successfully."
        fi
    done
}

# AWSApplicationMigrationReplicationServerRole
create_role_with_error_handling \
    "AWSApplicationMigrationReplicationServerRole" \
    '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": { "Service": "ec2.amazonaws.com" },
                "Action": "sts:AssumeRole"
            }
        ]
    }' \
    "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationReplicationServerPolicy"

# AWSApplicationMigrationConversionServerRole
create_role_with_error_handling \
    "AWSApplicationMigrationConversionServerRole" \
    '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": { "Service": "ec2.amazonaws.com" },
                "Action": "sts:AssumeRole"
            }
        ]
    }' \
    "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationConversionServerPolicy"

# AWSApplicationMigrationMGHRole
create_role_with_error_handling \
    "AWSApplicationMigrationMGHRole" \
    '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": { "Service": "mgn.amazonaws.com" },
                "Action": "sts:AssumeRole"
            }
        ]
    }' \
    "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationMGHAccess"

# AWSApplicationMigrationLaunchInstanceWithDrsRole
create_role_with_error_handling \
    "AWSApplicationMigrationLaunchInstanceWithDrsRole" \
    '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": { "Service": "mgn.amazonaws.com" },
                "Action": "sts:AssumeRole"
            }
        ]
    }' \
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
    "arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryEc2InstancePolicy"

# AWSApplicationMigrationLaunchInstanceWithSsmRole
create_role_with_error_handling \
    "AWSApplicationMigrationLaunchInstanceWithSsmRole" \
    '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": { "Service": "mgn.amazonaws.com" },
                "Action": "sts:AssumeRole"
            }
        ]
    }' \
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# AWSApplicationMigrationAgentRole
create_role_with_error_handling \
    "AWSApplicationMigrationAgentRole" \
    "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Principal\": {
            \"Service\": \"mgn.amazonaws.com\"
          },
          \"Action\": [
            \"sts:AssumeRole\",
            \"sts:SetSourceIdentity\"
          ],
          \"Condition\": {
            \"StringLike\": {
              \"sts:SourceIdentity\": \"s-*\",
              \"aws:SourceAccount\": \"$ACCOUNT_ID\"
            }
          }
        }
      ]
    }" \
    "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationAgentPolicy_v2"

# AWSApplicationMigrationAgentInstallationRole
create_role_with_error_handling \
    "AWSApplicationMigrationAgentInstallationRole" \
    "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
          \"Principal\": {
            \"AWS\": \"arn:aws:iam::$ACCOUNT_ID:root\"
          },
          \"Action\": \"sts:AssumeRole\",
          \"Condition\": {}
      }
    ]
    }" \
    "arn:aws:iam::aws:policy/AWSApplicationMigrationAgentInstallationPolicy"

echo "Initializing MGN service..."
aws mgn initialize-service --region "$AWS_REGION" 2>error.log
if [[ $? -ne 0 ]]; then
    if grep -q "AlreadyInitialized" error.log; then
        echo "MGN service is already initialized in region $AWS_REGION."
    else
        echo "Error initializing MGN service:"
        cat error.log
    fi
else
    echo "MGN service initialized successfully."
fi

echo "Creating replication configuration template..."
aws mgn create-replication-configuration-template \
    --region "$AWS_REGION" \
    --bandwidth-throttling 0 \
    --data-plane-routing "$IP_TYPE" \
    --default-large-staging-disk-type "$DISK_TYPE" \
    --ebs-encryption "$EBS_ENCRYPTION" \
    --replication-server-instance-type "$INSTANCE_TYPE" \
    --staging-area-subnet-id "$STAGING_SUBNET" \
    --staging-area-tags "$STAGING_TAGS" \
    --replication-servers-security-groups-ids \
    $ASSOCIATE_SG_ARG \
    $CREATE_PUBLIC_IP_ARG \
    $DEDICATED_REPLICATION_SERVER_ARG \
    2>error.log

if [[ $? -ne 0 ]]; then
    if grep -q "ServiceQuotaExceededException" error.log; then
        echo "Replication configuration template already exists for region $AWS_REGION."
    else
        echo "Error creating replication configuration template:"
        cat error.log
    fi
else
    echo "Replication configuration template created successfully."
fi

echo "Creating launch configuration template..."
aws mgn create-launch-configuration-template --region $AWS_REGION 2>error.log

if [[ $? -ne 0 ]]; then
    if grep -q "ServiceQuotaExceededException" error.log; then
        echo "Launch configuration template already exists for region $AWS_REGION."
    else
        echo "Error creating replication configuration template:"
        cat error.log
    fi
else
    echo "Replication configuration template created successfully."
fi
