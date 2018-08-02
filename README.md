# Chef Compliance Profile Reference Pipeline

## Overview
The goal of this repo is to demonstrate a working Pipeline for publishing changes to
your organization's Compliance Profiles.

The benefits of this pattern are:

- Transparency of changes
- Consistent method for validation
- Peer Review and Approval
- Dedicated Automate Compliance user that publishes

The Compliance Profile will be housed inside a Chef Cookbook and sent through the Pipeline.
In this case I'm demonstrating a Chef Workflow Pipeline. However the principles can
easily be ported to any other Pipeline implementation such as Jenkins.

## The Profile Cookbook

Start by generating a cookbook for your Profile.
For this example, I will be creating a [wrapper](https://blog.chef.io/2017/07/06/understanding-inspec-profile-inheritance/)
profile of [dev-sec/linux-baseline](https://github.com/dev-sec/linux-baseline) for my organization "ACME Inc"

```
chef generate cookbook linux-baseline_profile
```

Next let's generate a profile inside the cookbook's `files/default` directory.

```
cd linux-baseline_profile
mkdir -p files/default
inspec init profile acme-linux-baseline
```

The result will be:

```
files/default/
└── acme-linux-baseline
    ├── README.md
    ├── controls
    │   └── example.rb
    ├── inspec.yml
    └── libraries
```

Since `acme-linux-baseline` will be a wrapper profile, we need to modify its [inspec.yml](https://github.com/jeremymv2/compliance_profile_pipeline/blob/master/cookbooks/linux-baseline_profile/files/default/acme-linux-baseline/inspec.yml)
to this:

```
name: acme-linux-baseline
title: ACME InSpec wrapper profile of dev-sec/linux-baseline
maintainer: The Authors
copyright: The Authors
copyright_email: you@example.com
license: Apache-2.0
summary: An InSpec Compliance Profile
version: 0.1.1
depends:
  - name: linux-baseline
    compliance: admin/linux-baseline
```

The upstream `linux-baseline` profile exists in our Chef Automate Compliance asset store.

## Local Development

As with any pipeline, the first step is local development.

We will need to make our wrapper profile customizations next,
in [files/default/acme-linux-baseline/controls/example.rb](https://github.com/jeremymv2/compliance_profile_pipeline/blob/master/cookbooks/linux-baseline_profile/files/default/acme-linux-baseline/controls/example.rb) we make some changes:

```
# encoding: utf-8
# copyright: 2018, The Authors

include_controls "linux-baseline" do
  skip_control 'os-05'
  control 'sysctl-05' do
    impact 0.1
  end
  # any other customizations..
end
```

### Test Kitchen + Inspec

In order to test these changes on a target system we can use [kitchen inspec](https://github.com/inspec/kitchen-inspec)

Modify the `linux-baseline_profile` cookbook's [.kitchen.yml](https://github.com/jeremymv2/compliance_profile_pipeline/blob/master/cookbooks/linux-baseline_profile/.kitchen.yml) and choose a suitable target OS.

```
verifier:
  name: inspec

platforms:
  - name: ubuntu-16.04

suites:
  - name: default
    run_list:
      - recipe[linux-baseline_profile::kitchen]
    verifier:
      inspec_tests:
        # point at the embedded wrapper profile
        - files/default/acme-linux-baseline
    attributes:
```

You may find that you wish to ensure the profile works on a realistic set up
for your organization. To do so, you can choose to include recipes to configure
the test kitchen node. You will of course have to declare the dependencies
in the cookbook [metadata.rb](https://github.com/jeremymv2/compliance_profile_pipeline/blob/master/cookbooks/linux-baseline_profile/metadata.rb)

The [kitchen.rb](https://github.com/jeremymv2/compliance_profile_pipeline/blob/master/cookbooks/linux-baseline_profile/recipes/kitchen.rb) recipe.

```
#
# Cookbook:: linux-baseline_profile
# Recipe:: kitchen
#
# Copyright:: 2018, The Authors, All Rights Reserved.

# Example cookbook + recipe to use for profile validation
# targetting the Test Kitchen node
# ex.
# include_recipe 'apache2::mod_ssl'
```

Finally, run the tests on the Test Kitchen node to validate your
Profile changes.

You will need to `inspec login ..` because `kitchen-inspec` will need to be able
to fetch the upstream `linux-baseline` Profile from the Compliance asset store.

```
inspec compliance login https://automate-server.test --ent='brewinc' --user='admin' --insecure --dctoken='the-token'
```

Run [Test Kitchen](https://kitchen.ci/)

```
kitchen converge
kitchen verify
```

Repeat the above steps until you are confident your Profile is ready to publish.

## Setting up the Workflow Pipeline

Modify the `linux-baseline_profile` cookbook's [.devliery/config.json](https://github.com/jeremymv2/compliance_profile_pipeline/blob/master/cookbooks/linux-baseline_profile/.delivery/config.json)

```
{
  "version": "2",
  "build_cookbook": {
    "name": "build_cookbook",
    "path": ".delivery/build_cookbook"
  },
  "skip_phases": [
     "unit",
     "syntax",
     "quality",
     "security",
     "deploy",
     "smoke",
     "functional"
  ],
  "job_dispatch": {
    "version": "v2"
  },
  "dependencies": []
}
```

We skip all [Phases](https://docs.chef.io/workflow.html#pipelines) except:

- `Lint` we only execute it in the `Verify` stage.
- `Publish` which we only execute in the `Build` stage.

In order to implement those phases we'll modify the `linux-baseline_profile` build cookbook's recipes.

Lint [.delivery/build_cookbook/recipes/lint.rb](https://github.com/jeremymv2/compliance_profile_pipeline/blob/master/cookbooks/linux-baseline_profile/.delivery/build_cookbook/recipes/lint.rb)

```
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
```

Publish [.delivery/build_cookbook/recipes/publish.rb](https://github.com/jeremymv2/compliance_profile_pipeline/blob/master/cookbooks/linux-baseline_profile/.delivery/build_cookbook/recipes/publish.rb)

**Note** 
Please use a secure method of storing / retrieving the token.
One method in Chef Workflow is with [Chef Vault](https://github.com/chef-cookbooks/delivery-sugar#using-get_chef_vault_data)
Additionally, please use a dedicated Compliance service account instead of `admin`
for example, a user such as `compliance-pipeline`

```
#
# Cookbook:: build_cookbook
# Recipe:: publish
#
# Copyright:: 2018, The Authors, All Rights Reserved.

compliance_token='the-token'
profile_name='acme-linux-baseline'

if workflow_stage?('build') then
  execute 'login to Automate Compliance service' do
    cwd workflow_workspace_repo
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
```

## Run the Pipeline

Finally you are ready to push your changes through the Pipeline!

Don't forget to bump the Profile version in [files/default/acme-linux-baseline/inspec.yml](https://github.com/jeremymv2/compliance_profile_pipeline/blob/master/cookbooks/linux-baseline_profile/files/default/acme-linux-baseline/inspec.yml) if necessary.

```
# bump version in acme-linux-baseline/inspec.yml
git add -u
git commit -sm "an important change message"
delivery review
```

Have a Peer review the change.

When approved, your `acme-linux-baseline` Profile will show up in the Compliance Asset store!
