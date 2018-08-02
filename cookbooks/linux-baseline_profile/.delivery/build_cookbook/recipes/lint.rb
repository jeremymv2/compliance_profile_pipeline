#
# Cookbook:: build_cookbook
# Recipe:: lint
#
# Copyright:: 2018, The Authors, All Rights Reserved.
profile_name='acme-linux-baseline'

execute "lint profile #{profile_name}" do
  cwd "#{workflow_workspace_repo}/files/default"
  command "inspec check #{profile_name}"
  live_stream true
  ignore_failure false
  only_if { workflow_stage?('verify') }
end
