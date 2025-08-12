#!/bin/bash

set -e

is_set() {
    local val="$1"
    [[ -n "$val" && "$val" != "0" && "$val" != "false"]]
}

## Deployment checks
if is_set "$deploy_blue" && is_set "$deploy_green"; then
    echo "Error: Cannot deploy both blue and green at the same time."
    exit 1
fi


## Live traffic checks
traffic_percentage_sum=$(($green_traffic_percentage + $blue_traffic_percentage))
if [ "$traffic_percentage_sum" -ne 100 ]; then
    echo "Live traffic must sum to 100."
    exit 1
fi

if is_set "$deploy_blue" && is_set "$blue_traffic_percentage" && is_set "$green_deployment_name"; then
    echo "Error: If making a new blue deployment, do not send live traffic to it."
    exit 1
fi

if is_set "$deploy_green" && is_set "$green_traffic_percentage" && is_set "$blue_deployment_name"; then
    echo "Error: If making a new green deployment, do not send live traffic to it."
    exit 1
fi

if is_set "$blue_deployment_name" && ! is_set "$blue_traffic_percentage" && ! is_set "$blue_mirror_traffic_percentage"; then
    echo "Error: blue_traffic_percentage or blue_mirror_traffic_percentage must also be set if a blue deployment is defined."
    exit 1
fi

if is_set "$green_deployment_name" && ! is_set "$green_traffic_percentage" && ! is_set "$green_mirror_traffic_percentage"; then
    echo "Error: green_traffic_percentage or green_mirror_traffic_percentage must also be set if a green deployment is defined."
    exit 1
fi

## Mirror traffic checks
if is_set "$blue_mirror_traffic_percentage" && is_set "$green_mirror_traffic_percentage"; then
    echo "Error: Cannot set mirror traffic for both blue and green deployments at the same time."
    exit 1
fi

if is_set "$green_traffic_percentage" && is_set "$green_mirror_traffic_percentage"; then
    echo "Error: green_deployment_name cannot have both traffic and mirror traffic settings."
    exit 1
fi

if is_set "$blue_traffic_percentage" && is_set "$blue_mirror_traffic_percentage"; then
    echo "Error: blue_deployment_name cannot have both traffic and mirror traffic settings."
    exit 1
fi