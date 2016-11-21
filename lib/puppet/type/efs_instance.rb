require_relative '../../puppet_x/puppetlabs/property/tag.rb'

Puppet::Type.newtype(:efs_instance) do
  @doc = 'Type representing an EFS instance.'

  ensurable

  newparam(:name, namevar: true) do
    desc 'The name of the instance.'
    validate do |value|
      fail 'Instances must have a name' if value == ''
      fail 'name should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:security_groups, :array_matching => :all) do
    desc 'The security groups to associate the instance.'
    def insync?(is)
      is.to_set == should.to_set
    end
    validate do |value|
      fail 'security_groups should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:tags, :parent => PuppetX::Property::AwsTag) do
    desc 'The tags for the instance.'
  end

  newproperty(:region) do
    desc 'The region in which to launch the instance.'
    validate do |value|
      fail 'region should not contain spaces' if value =~ /\s/
      fail 'region should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:mount_targets)
  newproperty(:life_cycle_state)
  newproperty(:performance_mode)

  newproperty(:availability_zone) do
    desc 'The availability zone in which to place the instance.'
    validate do |value|
      fail 'availability_zone should not contain spaces' if value =~ /\s/
      fail 'availability_zone should not be blank' if value == ''
      fail 'availability_zone should be a String' unless value.is_a?(String)
    end
  end

end
