#
# Cookbook Name:: route53
# Recipe:: ec2
#
# Copyright:: 2010, Opscode, Inc <legal@opscode.com>, Platform14.com <jamesc.000@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'route53'

aws = Chef::EncryptedDataBagItem.load("aws", "route53")

desiredHostName = node["analytics"]["host_name"]
# existingInstanceHostName = node["analytics"]["host_name"]

friendlyFqdn = "#{desiredHostName}.#{node[:route53][:zone]}"
instanceIdFqdn = "#{node[:ec2][:instance_id]}.#{node[:route53][:zone]}"
ec2PublicHostName = "#{node[:ec2][:public_hostname]}."

route53_rr "#{ec2PublicHostName} => #{friendlyFqdn}" do
  zone node[:route53][:zone]

  aws_access_key_id aws["access_key"]
  aws_secret_access_key aws["secret_key"]

  fqdn friendlyFqdn
  type "CNAME"
  values([ec2PublicHostName])

  action :update
end

route53_rr "#{ec2PublicHostName} => #{instanceIdFqdn}" do
  zone node[:route53][:zone]

  aws_access_key_id aws["access_key"]
  aws_secret_access_key aws["secret_key"]

  fqdn instanceIdFqdn
  type "CNAME"
  values([ec2PublicHostName])

  action :update
end

new_hostname = desiredHostName      
new_fqdn = friendlyFqdn

hostsfile_entry '127.0.0.1' do
  hostname  new_fqdn
  aliases   [new_hostname, 'localhost']
  comment   'Created by chef::route53::ec2'
  action    :create
end

execute "hostname --file /etc/hostname" do
  action :nothing
end

file "/etc/hostname" do
  content "#{new_fqdn}"
  notifies :run, resources(:execute => "hostname --file /etc/hostname"), :immediately
end

service "networking" do
  supports :status => true, :restart => true, :reload => true
  action :nothing
end

node.automatic_attrs["hostname"] = new_hostname
node.automatic_attrs["fqdn"] = new_fqdn

template "/etc/dhcp/dhclient.conf" do
  source "dhclient.conf.erb"
  owner "root"
  group "root"
  mode 0644
  notifies :restart, resources(:service => "networking"), :immediately
end
