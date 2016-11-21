require_relative '../../../puppet_x/puppetlabs/aws.rb'
require 'base64'

Puppet::Type.type(:efs_instance).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws
  confine feature: :retries

  mk_resource_methods


  def self.instances
    supported_regions = [ 'us-east-1', 'us-east-2', 'us-west-2', 'eu-west-1' ]
    fs = []
    regions.collect do |region|
      begin
        instances = []
        if supported_regions.include? region
          Puppet.debug(region)

          response = efs_client(region).describe_file_systems()
          Puppet.debug(response.data)
          response.data.file_systems.each do |filesystem|
            config = {
               name: filesystem.name,
               id: filesystem.file_system_id,
               region: region,
               life_cycle_state: filesystem.life_cycle_state,
            }
            mount_targets = [ ]
            mt_resp = efs_client(region).describe_mount_targets(file_system_id: filesystem.file_system_id)
            mt_resp.data.mount_targets.each do |mt|
              Puppet.debug("Mount Target: '#{mt}'")
              mt_def = {
                id: mt.mount_target_id,
                subnet_id: mt.subnet_id,
                life_cycle_state: mt.life_cycle_state,
              }
              mtsg_resp = efs_client(region).describe_mount_target_security_groups(mount_target_id: mt.mount_target_id)
              mt_def[:security_groups] = mtsg_resp.data.security_groups
              mount_targets << mt_def
            end
            config[:mount_targets] = mount_targets
#              reservation.instances.each do |instance|
#                hash = instance_to_hash(region, instance, subnets)
#                instances << new(hash) if has_name?(hash)
#              end
#            end
            instances << new(config) if has_name?(config)
          end
        end
        Puppet.debug("Instances '#{instances}'")
        instances
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  def exists?
    Puppet.debug("Checking if instance #{name} exists in region #{target_region}")
  end

end
