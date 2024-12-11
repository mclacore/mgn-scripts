#!/bin/bash

##############################################################
# Copyright 2024 Massdriver, Inc
#
# This script checks for (or creates) an inventory CSV file
# for configuring an MGN inventory. This CSV file is useful
# when application servers have multiple dependencies on other
# servers, or when a migration is to be done in multiple waves.
#
##############################################################

CSV_FILE="./aws-application-migration-service-import.csv"

HEADER="mgn:account-id,mgn:region,mgn:wave:name,mgn:wave:tag:Wave,mgn:wave:description,mgn:app:name,mgn:app:tag:App,mgn:app:description,mgn:server:user-provided-id,mgn:server:platform,mgn:server:tag:Name,mgn:server:fqdn-for-action-framework,mgn:launch:nic:0:network-interface-id,mgn:launch:nic:0:subnet-id,mgn:launch:nic:0:security-group-id:0,mgn:launch:nic:0:private-ip:0,mgn:launch:instance-type,mgn:launch:placement:tenancy,mgn:launch:iam-instance-profile:name,mgn:launch:placement:host-id,mgn:launch:volume:foo:type"

if [[ ! -f $CSV_FILE ]]; then
    echo "File does not exist. Creating file and adding headers."
    echo "$HEADER" > "$CSV_FILE"
fi

add_row() {
    local row=()
    IFS=',' read -ra fields <<< "$HEADER"
    for field in "${fields[@]}"; do
        read -p "Enter value for $field: " value
        row+=("$value")
    done

    echo "$(IFS=','; echo "${row[*]}")" >> "$CSV_FILE"
    echo "Row appended successfully to $CSV_FILE"
}

while true; do
    echo "Add a new row:"
    add_row
    read -p "Do you want to add another row? (yes/no): " add_another
    if [[ ! "$add_another" =~ ^(yes|y)$ ]]; then
        echo "Finished adding rows."
        break
    fi
done
