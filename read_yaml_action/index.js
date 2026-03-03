const core = require('@actions/core');
const github = require('@actions/github');
const yaml = require('js-yaml');
const fs = require('fs');

function safeString(value) {
    return value != null ? String(value) : "";
}

function safeBool(value) {
    return value === "true" || value === true;
}

function checkGenerateEntity(entity){
    return entity.includes("$");
}

try {
    const configData = core.getInput('config');
    fs.readFile(configData, 'utf8', (err, data) => {
    if (err) {
      console.error(err);
      return;
    }
    console.log(data);
    const SCHEMA = yaml.FAILSAFE_SCHEMA;
    const configYaml = yaml.load(data, { schema: SCHEMA });
    const vars = configYaml["variables"];

    const namespace = safeString(vars["namespace"]);
    const postfix = safeString(vars["postfix"]);
    const environment = safeString(vars["environment"]);
    var enable_aml_computecluster = safeBool(vars["enable_aml_computecluster"]);
    var enable_monitoring = safeBool(vars["enable_monitoring"]);
    var resource_group = safeString(vars["resource_group"]);
    var location = safeString(vars["location"]);
    var aml_workspace = safeString(vars["aml_workspace"]);

    var terraform_version = safeString(vars["terraform_version"]);
    var terraform_workingdir = safeString(vars["terraform_workingdir"]);
    var terraform_st_location = safeString(vars["terraform_st_location"]);
    var terraform_st_resource_group = safeString(vars["terraform_st_resource_group"]);
    var terraform_st_storage_account = safeString(vars["terraform_st_storage_account"]);
    var terraform_st_container_name = safeString(vars["terraform_st_container_name"]);
    var terraform_st_key = safeString(vars["terraform_st_key"]);

    if(checkGenerateEntity(terraform_st_location)){
      terraform_st_location = location;
    }
    if(checkGenerateEntity(resource_group)){
        resource_group = namespace+"-"+postfix+environment;
    }
    if(checkGenerateEntity(aml_workspace)){
        aml_workspace = "mlw-"+namespace+"-"+postfix+environment;
    }

    if(checkGenerateEntity(terraform_st_resource_group)){
      terraform_st_resource_group = "rg-"+namespace+"-"+postfix+environment+"-tf";
    }
    if(checkGenerateEntity(terraform_st_storage_account)){
      terraform_st_storage_account = "st"+namespace+postfix+environment+"tf";
    }

    const safe_namespace = namespace.replace(/-/g, '');
    const safe_postfix = postfix.replace(/-/g, '');
    const safe_environment = environment.replace(/-/g, '');

    const batch_endpoint_name = "bep-"+namespace+"-"+postfix+environment;
    const online_endpoint_name = "oep-"+namespace+"-"+postfix+environment;
    const storage_account = "st"+safe_namespace+safe_postfix+safe_environment;
    const key_vault = "kv-"+namespace+"-"+postfix+environment;
    const app_insights = "appi-"+namespace+"-"+postfix+environment;
    const load_test_resource = "lt"+namespace+postfix+environment;
    const action_group_name = "ag-"+namespace+"-"+postfix+"-"+environment;

    core.setOutput("location",location);
    core.setOutput("namespace",namespace);
    core.setOutput("postfix",postfix);
    core.setOutput("environment",environment);
    core.setOutput("enable_monitoring",enable_monitoring);
    core.setOutput("enable_aml_computecluster",enable_aml_computecluster);
    core.setOutput("resource_group",resource_group);
    core.setOutput("aml_workspace", aml_workspace);
    core.setOutput("storage_account", storage_account);
    core.setOutput("key_vault", key_vault);
    core.setOutput("app_insights", app_insights);
    core.setOutput("load_test_resource", load_test_resource);
    core.setOutput("action_group_name", action_group_name);
    core.setOutput("bep", batch_endpoint_name);
    core.setOutput("oep", online_endpoint_name);
    core.setOutput("terraform_version", terraform_version);
    core.setOutput("terraform_workingdir", terraform_workingdir);
    core.setOutput("terraform_st_location", terraform_st_location);
    core.setOutput("terraform_st_resource_group", terraform_st_resource_group);
    core.setOutput("terraform_st_storage_account", terraform_st_storage_account);
    core.setOutput("terraform_st_container_name", terraform_st_container_name);
    core.setOutput("terraform_st_key", terraform_st_key);
    core.setOutput("model_registry_name", safeString(vars["model_registry_name"]));
  });

} catch (error) {
  core.setFailed(error.message);
}
