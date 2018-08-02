# encoding: utf-8
# copyright: 2018, The Authors

include_controls "linux-baseline" do
  skip_control 'os-05'
  control 'sysctl-05' do
    impact 0.1
  end
  # any other customizations..
end
