#
# Cookbook:: build_cookbook
# Recipe:: publish
#
# Copyright:: 2018, The Authors, All Rights Reserved.

## NOTE ##
# Please use a secure method of storing / retrieving the token.
# One method in Chef Workflow is with [Chef Vault](https://github.com/chef-cookbooks/delivery-sugar#using-get_chef_vault_data)
compliance_token='the-token'
profile_name='acme-linux-baseline'

if workflow_stage?('build') then
  execute 'login to Automate Compliance service' do
    cwd workflow_workspace_repo
## NOTE ##
# Please use a dedicated Compliance service account instead of 'admin'
# for example 'compliance-pipeline'
    command "inspec compliance login https://automate-server.test --insecure --user='admin' --ent='brewinc' --dctoken=\"#{compliance_token}\""
    ignore_failure false
  end

  execute "cat profile #{profile_name} inspec.yml" do
    cwd "#{workflow_workspace_repo}/files/default"
    command "cat #{profile_name}/inspec.yml"
    live_stream true
    ignore_failure false
  end

  execute "upload profile #{profile_name} to Automate Compliance service" do
    cwd "#{workflow_workspace_repo}/files/default"
    command "inspec compliance upload #{profile_name} --overwrite"
    live_stream true
    ignore_failure false
  end
end
