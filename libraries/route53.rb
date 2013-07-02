 #
# Cookbook Name:: route53
# Library:: route53
#
# Copyright 2010, Platform14.com.
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

begin
  require 'fog'
rescue LoadError
  Chef::Log.warn("Missing gem 'fog'")
end

module Opscode
  module Route53
    module Route53
      def find_zone_id(zone_name="")
        zone_id = nil
        options= { :max_items => 200 }
        response = route53.list_hosted_zones(options)
        if response.status == 200
          zones = response.body['HostedZones']
          zones.each { |zone|
            domain_name = zone['Name']
            if domain_name.chop == zone_name
              zone_id = zone['Id'].sub('/hostedzone/', '')
            end
          }
          return zone_id
        end
      end

      def resource_record(zone_id, fqdn, type)
        rr = nil
        options = { :name => fqdn, :type => type }
        response = route53.list_resource_record_sets(zone_id, options)
        if response.status == 200
          records = response.body['ResourceRecordSets']
          records.each { |record|
            Chef::Log.debug("Record : #{record}")
            record_name = record['Name']
            if record_name.chop == fqdn and record['Type'] == type
              rr = record
            end
          }
          return rr
        end
      end

      def update_resource_record(zone_id, fqdn, type, ttl, values, rr=nil)
        if rr.nil?
          rr = resource_record(zone_id, fqdn, type)
        end

        # Create if it doesn't exising in route53 already
        if rr.nil?
          create_resource_record(zone_id, fqdn, type, ttl, values)
        else
          removeRecord = { :name => fqdn, :type => rr['Type'], :ttl => rr['TTL'], :resource_records => rr['ResourceRecords']}
          createRecord = { :name => fqdn, :type => type, :ttl => ttl, :resource_records => values}
          
          if removeRecord == createRecord
          	Chef::Log.info("Not updating #{fqdn}; no changes necessary")
          else
          	removeRecord[:action] = "DELETE"
          	createRecord[:action] = "CREATE"
						change_batch = [removeRecord, createRecord]
						execute_change_batch(zone_id, change_batch, "Update #{type} record for #{fqdn}")
          end
        end
      end

      def create_resource_record(zone_id, fqdn, type, ttl, values )
        record = { :name => fqdn, :type => type, :ttl => ttl, :resource_records => values,
                   :action => "CREATE" }

        change_batch = [record]
        execute_change_batch(zone_id, change_batch, "Create #{type} record for #{fqdn}")
      end
      
      def execute_change_batch(zone_id, change_batch, description)
        options = { :comment => description}
        response = route53.change_resource_record_sets( zone_id, change_batch, options)
        if response.status == 200
          change_id = response.body['Id']
          status = response.body['Status']
        end

        #wait until new zone is live across all name servers
        while status == 'PENDING'
          sleep 2
          response = route53.get_change( change_id)
          if response.status == 200
            change_id = response.body['Id']
            status = response.body['Status']
          end
          Chef::Log.info("Pending execution for: #{description} (#{change_id}) - #{status}")
        end
      end
      
      def delete_resource_record(zone_id, fqdn, type)
        rr = resource_record(zone_id, fqdn, type)
        if rr.nil?
        	Chef::Log.warn("Requested delete of nonexistant record set #{fqdn}/#{type}; ignoring.")
        else
          removeRecord = { :name => fqdn, :type => rr['Name'], :ttl => rr['TTL'], :resource_records => rr['ResourceRecords'],
          		   :action => "DELETE" }
          
          change_batch = [removeRecord]
          execute_change_batch(zone_id, change_batch, "Remove #{type} record for #{fqdn}")
        end
      end

      def route53
        @@route53 ||= Fog::DNS.new(:provider => 'AWS',
              :aws_access_key_id => new_resource.aws_access_key_id,
              :aws_secret_access_key => new_resource.aws_secret_access_key,
              :persistent => false)
       end
    end
  end
end
