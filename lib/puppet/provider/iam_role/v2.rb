require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:iam_role).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws

  mk_resource_methods

  def self.get_roles
    role_results = iam_client.list_roles()
    roles = role_results.roles

    truncated = role_results.is_truncated
    marker = role_results.marker

    while truncated and marker
      Puppet.debug('iam_role results truncated, proceeding with discovery')
      response = iam_client.list_roles({marker: marker})
      response.roles.each {|u| roles << u }
      truncated = response.is_truncated
      marker = response.marker
    end

    roles
  end

  def self.instances
    roles = get_roles()
    roles.collect do |role|
      Puppet.debug("Role: #{role}")
      new({
        name: role.role_name,
        ensure: :present,
        path: role.path,
        role_id: role.role_id,
        arn: role.arn,
        assume_role_policy_document: URI.unescape(role.assume_role_policy_document)
      })
    end
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

  def exists?
    Puppet.debug("Checking if IAM role #{name} exists")
    @property_hash[:ensure] == :present
  end

  def create
    Puppet.info("Creating IAM role #{name}")
    response = iam_client.create_role({ role_name: name,
                             path: resource[:path],
                             assume_role_policy_document: resource[:assume_role_policy_document] })
    Puppet.debug("create response #{response.role}")
    response.role.each {|u| @property_hash << u }
    @property_hash[:ensure] = :present
  end

  def destroy
    Puppet.info("Deleting IAM role #{name}")
    roles = iam_client.list_roles.roles.select { |role| role.role_name == name }
    roles.each do |role|
      begin
        iam_client.delete_login_profile({role_name: role.role_name})
      rescue => e
        Puppet.debug("Failed to delete the login profile for role #{role.role_name}: #{e.message}")
      end

      begin
        iam_client.list_access_keys({role_name: role.role_name}).access_key_metadata.each {|k|
          pp k
          iam_client.delete_access_key({
            role_name: role.role_name,
            access_key_id: k['access_key_id'],
          })
        }
      rescue => e
        Puppet.debug("Failed to delete the access keys for role #{role.role_name}: #{e.message}")
      end

      begin
        iam_client.list_mfa_devices({role_name: role.role_name}).mfa_devices.each {|k|

          iam_client.deactivate_mfa_device({
            role_name: role.role_name,
            serial_number: k['serial_number'],
          })

          iam_client.delete_virtual_mfa_device({
            serial_number: k['serial_number'],
          })
        }
      rescue => e
        Puppet.debug("Failed to delete the MFA devices for role #{role.role_name}: #{e.message}")
      end

      iam_client.delete_role({role_name: role.role_name})
    end
    @property_hash[:ensure] = :absent
  end

end
