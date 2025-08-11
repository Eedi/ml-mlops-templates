# ML Ops Templates


## Building an image
Use `build.yml` in a github workflow in the ML project, like:  
```
build-dev:
    needs: pre-commit
    if: github.ref == 'refs/heads/prime/deploy'
    uses: Eedi/ml-mlops-templates/.github/workflows/build.yml@main
    with:
        environment: anet-dev
        environment_config_file: config-infra-anet-dev.yml
        ml_env_name: ml-azua-litserve-env # must match the environment name in the deployment config
        ml_env_description: "Environment for ml-azua serving"
        target_layer: litserve
        tags: "'team=data-science' 'repo=ml-azua' 'model=dynamic-vae'"
        maximise_disk_space: false
    secrets: inherit
    permissions:
        id-token: write
        contents: read
```

Arguments:
- environment: Name of the github environment
- environment_config_file: Name of the project's environment config file.
- ml_env_name: Name of the Azure ML environment resource. Must match the environment name in the deployment config yaml.
- ml_env_description: Description for the Azure ML environment resource
- tags: Tags for the Azure ML environment resource
- target_layer: Docker layer to build. Inference layers should be lightweight. Dev python deps should be segegated using Docker layering and Poetry grouping.
- maximise_disk_space: Allows you to build larger images. Inference layers shouldn't need this. Removes pre-installed resources from the github agent, at the cost of a slightly longer run time.

## Deployment to an Azure ML Realtime Endpoint

Use `deploy_realtime.yml` in a github workflow in the ML project, like:

```
deploy-nbq-dev:
needs: build-dev
uses: Eedi/ml-mlops-templates/.github/workflows/deploy_realtime.yml@main
with:
    environment: anet-dev
    environment_config_file: config-infra-anet-dev.yml
    deploy: false
    run_load_test: false
    load_test_config: ./mlops/azureml/configs/project_prime/load_test_nbq.yml
    load_test_name: nbq-allcandidates_alltargets_10x # must change if test plan changes
    endpoint_name: anet-ep-dev
    deployment_name: anet-eedi
    endpoint_config: ./mlops/azureml/configs/project_prime/endpoint_dev.yml
    deployment_config: ./mlops/azureml/configs/project_prime/deployment_dev.yml
secrets: inherit
permissions:
    id-token: write
    contents: read
```

Required Arguments:
- environment: Name of the github environment
- environment_config_file: Name of the project's environment config file.
- deploy: whether to update the endpoint and deploy (including shadow deployment) or just to update endpoint resources e.g. diagnostic settings, load test, alert rules.
- run_load_test: true if a load test run is required
- endpoint_name: name of the endpoint resource
- endpoint_config: path to config file of endpoint resource
- deployment_name: name of primary deployment
- deployment_config: path to config file of primary deployment


Optional Arguments:
- load_test_config: config file path for load test
- load_test_name: this must be changed if the test plan (e.g. locustfile) changes
- shadow_deployment_name: deployment_name of shadow deployment
- shadow_deployment_config: deployment_config path of shadow deployment
- shadow_deploment_mirror_percentage: % of traffic to mirror to shadow deployment
- shadow_deployment_traffic_percentage: % of live traffic to send to shadow deployment. Can't be set when creating/updating a shadow deployment. The traffic % to the primary endpoint will be set to 100 - shadow_deployment_traffic_percentage

Controlling deployment behaviour:
- Deploying a primary deployment:
    - Unset any shadow deployment vars
- Updating diagnostic settings or alerts without deploying
    - Set deploy to false
- Running a load test:
    - Set run_load_test to true
- Shadow deployments:
    - Creating or updating a shadow deployment
        - Define `shadow_deployment_config` and `shadow_deploment_mirror_percentage`
    - Routing live traffic to a shadow deployment
        - Define `shadow_deployment_traffic_percentage`
    - Updating a shadow deployment and routing live traffic to it in one go
        - Don't. Test first.

### Shadow Deployment Run Book
- Create new deployment config. Don't give the deployment the name of `xxx_shadow` or similar - it will become the primary deployment when 100% of the live traffic is routed to it!
- Deploy and load test on dev as usual
- Then with an existing deployment already on a production endpoint...
- Run workflow to do shadow deployment and mirror some traffic to it
- Test the shadow deployment. Check it's stats from the mirrored data.
- Run workflow again to update traffic %s
- Once the former shadow deployment is at 100% live  traffic, the old deployment can be deleted. Currently a manual process.
- Cleanup: 
    - Udpate the primary deployment name to be the same as the former shadow deployment name
    - Remove the redundant config. 
    - Remove the shadow deployment params from the workflow

#### In short:
- Run once to create shadow deployment
- Test
- Run again to route live traffic to it

#### For updating traffic to 100% wouldn't it be better to simply change the primary deployment?
No, it causes an outage.

#### Does the primary deployment update if a shadow deployment is defined?
No.

#### How do load testing, logs, alerts work with shadow deployments?
- Load testing should be done on dev, shadow deployment on prod.
- Alert rules are defined at the endpoint level.
- Diagnostic settings (for logging) are defined at the endpoint level.

To make updates to endpoint level resources, no shadow deployment variables should be defined.

#### How are container images managed for shadow deployments?
Assuming the shadow deployment config points at <proj>.azurecr.io/envname:latest then it will simply use the latest environment image.

