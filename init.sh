#!/bin/bash

######################################################################
# Copyright 2024 Massdriver, Inc
#
# This script initializes the requires roles and policies required for
# AWS Application Migration Service (MGN). It also enables the service
# in the region specified during execution. Lastly, it configures
# default replication and launch templates.
#
######################################################################

# add some type of value checking for empty inputs
read -p "Enter the AWS region (e.g., us-east-1): " AWS_REGION
read -p "Set replication server IP type (PUBLIC_IP, PRIVATE_IP): " IP_TYPE
read -p "Set replication server disk type (GP2, GP3, ST1): " DISK_TYPE
read -p "Set replication server EBS encryption (DEFAULT, CUSTOM): " EBS_ENCRYPTION
read -p "Set replication server instance type (e.g., t2.micro): " INSTANCE_TYPE
read -p "Set replication server staging area subnet ID (e.g., subnet-01234abcde): " STAGING_SUBNET
read -p "Set replication server staging area tags (e.g., Key=value,Foo=bar): " STAGING_TAGS

read -p "Do you want to associate a default security group for replication server? (yes/no): " ASSOCIATE_SG
if [[ "$ASSOCIATE_SG" =~ ^(yes|y)$ ]]; then
    ASSOCIATE_SG_ARG="--associate-default-security-group"
else
    ASSOCIATE_SG_ARG="--no-associate-default-security-group"
fi

read -p "Do you want to create a public IP for replication server? (yes/no): " CREATE_PUBLIC_IP
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

read -p "Set launch server boot mode (LEGACY_BIOS, UEFI, USE_SOURCE). USE_SOURCE recommended: " BOOT_MODE
read -p "Set instance state upon launch (STARTED, STOPPED): " LAUNCH_MODE

read -p "Is server BYOL (Bring Your Own Licensing)? (yes/no): " LICENSE
if [[ "$LICENSE" =~ ^(yes|y)$ ]]; then
    LICENSE_ARG="osByol=true"
else
    LICENSE_ARG="osByol=false"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

create_role_attach_policies() {
    local role_name=$1
    local policy_document=$2
    local path=$3
    shift 3
    local policies=("$@")
    echo "Creating role $role_name..."
    aws iam create-role --path "$path" --role-name "$role_name" --assume-role-policy-document "$policy_document" 2>error.log
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
create_role_attach_policies \
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
    "/service-role/" \
    "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationReplicationServerPolicy"

# AWSApplicationMigrationConversionServerRole
create_role_attach_policies \
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
    "/service-role/" \
    "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationConversionServerPolicy"

# AWSApplicationMigrationMGHRole
create_role_attach_policies \
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
    "/service-role/" \
    "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationMGHAccess"

# AWSApplicationMigrationLaunchInstanceWithDrsRole
create_role_attach_policies \
    "AWSApplicationMigrationLaunchInstanceWithDrsRole" \
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
    "/service-role/" \
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
    "arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryEc2InstancePolicy"

# AWSApplicationMigrationLaunchInstanceWithSsmRole
create_role_attach_policies \
    "AWSApplicationMigrationLaunchInstanceWithSsmRole" \
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
    "/service-role/" \
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# AWSApplicationMigrationAgentRole
create_role_attach_policies \
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
    "/service-role/" \
    "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationAgentPolicy_v2"

# AWSApplicationMigrationAgentInstallationRole
echo "Creating role AWSApplicationMigrationAgentInstallationRole..."
aws iam create-role --role-name "AWSApplicationMigrationAgentInstallationRole" --assume-role-policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
          {
            \"Effect\": \"Allow\",
            \"Principal\": {
              \"AWS\": \"arn:aws:iam::$ACCOUNT_ID:root\"
            },
            \"Action\": \"sts:AssumeRole\"
          }
        ]
    }"
if [[ $? -ne 0 ]]; then
    if grep -q "EntityAlreadyExists" error.log; then
        echo "Role AWSApplicationMigrationAgentInstallationRole already exists."
    else
        echo "Error creating role AWSApplicationMigrationAgentInstallationRole:"
        cat error.log
    fi
else
    echo "Role AWSApplicationMigrationAgentInstallationRole created successfully."
fi

echo "Attaching policy arn:aws:iam::aws:policy/AWSApplicationMigrationAgentInstallationPolicy to role AWSApplicationMigrationAgentInstallationRole..."
aws iam attach-role-policy --policy-arn "arn:aws:iam::aws:policy/AWSApplicationMigrationAgentInstallationPolicy" --role-name "AWSApplicationMigrationAgentInstallationRole"
if [[ $? -ne 0 ]]; then
    echo "Error attaching policy to AWSApplicationMigrationAgentInstallationRole:"
    cat error.log
else
    echo "Policy attached successfully to AWSApplicationMigrationAgentInstallationRole."
fi

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
aws mgn create-launch-configuration-template \
    --region $AWS_REGION \
    --boot-mode $BOOT_MODE \
    --launch-disposition $LAUNCH_MODE \
    --licensing $LICENSE_ARG \
    --target-instance-type-right-sizing-method BASIC
    2>error.log

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
