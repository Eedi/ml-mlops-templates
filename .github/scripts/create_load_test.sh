#!/bin/bash

set -e


# Check if required environment variables are set
if [[ -z "$aml_workspace" || -z "$resource_group" || -z "$load_test_config" || -z "$endpoint_name" || -z "$load_test_name" ]]; then
    echo "Error: Missing required environment variables."
    exit 1
fi

az configure --defaults workspace="$aml_workspace" group="$resource_group"

## LOAD TEST CONFIGURATION ##

# Define the load test configuration. If the locustfile changes then the test_id should change as well.
test_id="lt-$endpoint_name-$load_test_name"

# Set the api key for the endpoint
echo "🔑 Getting endpoint key..."
secret_name="api-key-$endpoint_name"

az keyvault secret set \
  --vault-name $keyvault_name \
  --name $secret_name \
  --value $(az ml online-endpoint get-credentials -n $endpoint_name -o tsv --query primaryKey | sed 's/[[:space:]]//g') \
  --output none

secret_url=$(az keyvault secret show \
  --vault-name $keyvault_name \
  --name $secret_name \
  --query "id" -o tsv | sed 's/[[:space:]]//g')

# Check if the load test already exists
echo "🔍 Checking if load test $load_test_resource already exists..."

existing_test=$(az load test show \
  --name "$load_test_resource" \
  --resource-group "$resource_group" \
  --test-id "$test_id" \
  --query "testId" -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)

if [ -n "$existing_test" ]; then
    echo "Load test $load_test_resource already exists."
else
    echo "📡 Fetching endpoint details..."
    uri=$(az ml online-endpoint show -n "$endpoint_name" --query "scoring_uri" -o tsv | awk -F'/score' '{print $1}')
    scoring_uri="${uri}/score"


    # Log files in config directory
    echo "Current working directory: $(pwd)"
    echo "Listing contents of: $(dirname "$load_test_config")"
    ls -l "$(dirname "$load_test_config")"

    echo "Creating load test $load_test_resource for endpoint: $endpoint_name"
    az load test create \
      --name "$load_test_resource" \
      --resource-group "$resource_group" \
      --test-id "$test_id" \
      --load-test-config-file "$load_test_config" \
      --env "ENDPOINT_URL=$uri" \
      --secret "API_KEY=$secret_url" \
      --output none \
      --debug
fi




## CREATE RUN ##
echo "📊 Creating load test run"
git_commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
test_run_id="commit-$git_commit_hash"

az load test-run create \
    --name "$load_test_resource" \
    --resource-group "$resource_group" \
    --test-id "$test_id" \
    --test-run-id "$test_run_id" \
    --output none \
    --no-wait
