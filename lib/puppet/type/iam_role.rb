Puppet::Type.newtype(:iam_role) do
  @doc = 'Type representing IAM Roles.'

  ensurable

  newparam(:name, namevar: true) do
    desc 'The name of the role to manage.'
    validate do |value|
      fail Puppet::Error, 'Empty usernames are not allowed' if value == ''
    end
  end

  newproperty(:path) do
    desc 'The path for the Role. - defaults to /'
    defaultto '/'
    validate do |value|
       fail Puppet::Error, 'Empty paths are not allowed' if value == ''
       fail Puppet::Error, 'Path must begin/end with /' if value !~ /^\/(.+\/)?$/
    end
  end

  newproperty(:arn) do
    desc 'The ARN of the role'
    validate do |value|
      fail Puppet::Error, 'ARN is read only.'
    end
  end

  newproperty(:role_id) do
    desc 'The id of the role'
    validate do |value|
      fail Puppet::Error, 'role_id is read only.'
    end
  end

  newproperty(:assume_role_policy_document) do
    isrequired
  end
end
