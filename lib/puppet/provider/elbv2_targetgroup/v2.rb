require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:elbv2_targetgroup).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do

  confine feature: :aws

  mk_resource_methods

  def self.instances()
    Puppet.debug('Fetching ELBv2 Target Groups (instances)')
    regions.collect do |region|
      vpc_names = {}
      vpc_response = ec2_client(region).describe_vpcs()
      vpc_response.data.vpcs.each do |vpc|
        vpc_name = name_from_tag(vpc)
        vpc_names[vpc.vpc_id] = vpc_name if vpc_name
      end
    Puppet.debug("instances region: #{region}")
      target_groups = []
      tgs(region) do |tg|
        target_groups << new(target_group_to_hash(region, tg, vpc_names) )
      end

      target_groups
    end.flatten
  end

  def self.prefetch(resources)
    instances.each do |prov|
      Puppet.debug("Prefetching #{prov.name}")
      if resource = resources[prov.name] # rubocop:disable Lint/AssignmentInCondition
        resource.provider = prov if resource[:region] == prov.region
      end
    end
  end

  def self.tgs(region)
    Puppet.debug('Fetching ELBv2 Target Groups (tgs)')
#    regions.collect do |region|
      region_client = elbv2_client(region)

      response = region_client.describe_target_groups()
      marker = response.next_marker

      response.target_groups.each do |tg|
        yield tg
      end

      while marker
        Puppet.debug("Calling for marked TargetGroup description")
        response = region_client.describe_target_groups( {
          marker: marker
        })
        marker = response.next_marker
        response.target_group_descriptions.each do |tg|
          yield tg
        end
      end
#    end
  end

  def self.target_group_to_hash(region, target_group, vpcs)
    Puppet.debug("target_group_to_hash for #{target_group.target_group_name}")

    attributes = { }
    response = elbv2_client(region).describe_target_group_attributes(target_group_arn: target_group.target_group_arn)
    response.attributes.collect do |attribute|
      attributes[attribute.key] = attribute.value
    end

    tag_response = elbv2_client(region).describe_tags(
      resource_arns: [ target_group.target_group_arn ]
    )
    tags = {}
    unless tag_response.tag_descriptions.nil? || tag_response.tag_descriptions.empty?
      tag_response.tag_descriptions.first.tags.each do |tag|
        tags[tag.key] = tag.value
      end
    end

    load_balancers = []

    {
      name: target_group.target_group_name,
      arn:  target_group.target_group_arn,
      ensure: :present,
      region: region,
      vpc: vpcs[target_group.vpc_id],
      protocol: target_group.protocol,
      port: target_group.port,
      load_balancers: load_balancers,
      healthy_threshold: target_group.healthy_threshold_count,
      unhealthy_threshold: target_group.unhealthy_threshold_count,
      health_check_path: target_group.health_check_path,
      health_check_port: target_group.health_check_port,
      health_check_protocol: target_group.health_check_protocol,
      health_check_interval: target_group.health_check_interval_seconds,
      health_check_success_codes: target_group.matcher.http_code,
      health_check_timeout: target_group.health_check_timeout_seconds,
      deregistration_delay: attributes['deregistration_delay.timeout_seconds'],
      stickiness: (attributes['stickiness.enabled'] == true ? :enabled : :disabled),
      stickiness_duration: attributes['stickiness.lb_cookie.duration_seconds'],
      tags: tags,
    }
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def healthy_threshold=(value)
    Puppet.debug("Updating target group #{name} healthy_threshold")
    elbv2_client(region).modify_target_group( {
      target_group_arn: arn,
      healthy_threshold_count: value,
    })
  end

  def unhealthy_threshold=(value)
    Puppet.debug("Updating target group #{name} unhealthy_threshold")
    elbv2_client(region).modify_target_group( {
      target_group_arn: arn,
      unhealthy_threshold_count: value,
    })
  end

  def health_check_path=(value)
    Puppet.debug("Updating target group #{name} health_check_path")
    elbv2_client(region).modify_target_group( {
      target_group_arn: arn,
      health_check_path: value,
    })
  end

  def health_check_port=(value)
    Puppet.debug("Updating target group #{name} health_check_port")
    elbv2_client(region).modify_target_group( {
      target_group_arn: arn,
      health_check_port: value,
    })
  end

  def health_check_protocol=(value)
    Puppet.debug("Updating target group #{name} health_check_protocol")
    elbv2_client(region).modify_target_group( {
      target_group_arn: arn,
      health_check_protocol: value,
    })
  end

  def health_check_interval=(value)
    Puppet.debug("Updating target group #{name} health_check_interval")
    elbv2_client(region).modify_target_group( {
      target_group_arn: arn,
      health_check_interval_seconds: value,
    })
  end

  def health_check_success_codes=(value)
    Puppet.debug("Updating target group #{name} #{arn} health_check_success_codes")
    elbv2_client(region).modify_target_group( {
      target_group_arn: arn,
      matcher: { http_code: value },
    })
  end

  def health_check_timeout=(value)
    Puppet.debug("Updating target group #{name} health_check_timeout")
    elbv2_client(region).modify_target_group( {
      target_group_arn: arn,
      health_check_timeout_seconds: value,
    })
  end

  def stickiness=(value)
    Puppet.debug("Updating target group #{name} stickiness to '#{value.to_s}'")
    elbv2_client(region).modify_target_group_attributes( {
      target_group_arn: arn,
      attributes: [ { key: 'stickiness.enabled',
                      value: ( value == :enabled ? 'true' : 'false' ), } ],
    })
    @property_hash[:stickiness] = value
  end

  def stickiness_duration=(value)
    Puppet.debug("Updating target group #{name} stickiness_duration")
    elbv2_client(region).modify_target_group_attributes( {
      target_group_arn: arn,
      attributes: [ { key: 'stickiness.lb_cookie.duration_seconds',
                      value: value.to_s } ],
    })
    @property_hash[:stickiness_duration] = value
  end

  def create
    Puppet.debug("Creating target group #{name} #{resource[:protocol]} #{resource[:port]} in region #{target_region}")
    fail('You must specify the AWS region') unless target_region != :absent
    fail('You must specify the Target protocol') if resource[:protocol].nil?
    fail('You must specify the Target port') if resource[:port].nil?

    vpc_name = resource[:vpc]
    if vpc_name
      vpc_response = ec2_client(target_region).describe_vpcs(filters: [
        {name: 'tag:Name', values: [vpc_name]}
      ])
      fail("No VPC found called #{vpc_name}") if vpc_response.data.vpcs.count == 0
      vpc_id = vpc_response.data.vpcs.first.vpc_id
      Puppet.warning "Multiple VPCs found called #{vpc_name}, using #{vpc_id}" if vpc_response.data.vpcs.count > 1
      @property_hash[:vpc_id] = vpc_id
      @property_hash[:vpc] = vpc_name
    end

    config = { 
      name: resource[:name],
      vpc_id: vpc_id,
      protocol: resource[:protocol],
      port: resource[:port],
    }

    config[:health_check_protocol] = resource[:health_check_protocol] unless resource[:health_check_protocol].nil?
    config[:health_check_port] = resource[:health_check_port] unless resource[:health_check_port].nil?
    config[:health_check_path] = resource[:health_check_path] unless resource[:health_check_path].nil?
    config[:health_check_interval_seconds] = resource[:health_check_interval] unless resource[:health_check_interval].nil?
    config[:health_check_timeout_seconds] = resource[:health_check_timeout] unless resource[:health_check_timeout].nil?
    config[:healthy_threshold_count] = resource[:healthy_threshold] unless resource[:healthy_threshold].nil?
    config[:unhealthy_threshold_count] = resource[:unhealthy_threshold] unless resource[:unhealthy_threshold].nil?
    config[:matcher] = { http_code: resource[:health_check_success_codes] } unless resource[:health_check_success_codes].nil?

    tg_response = elbv2_client(target_region).create_target_group(config)
    Puppet.info("Config: #{tg_response.data}")
    
    tg_arn = tg_response.data.target_groups.first.target_group_arn

    attrs = []
    attrs << { key: 'stickiness.enabled',
               value: resource[:stickiness] } unless resource[:stickiness].nil?
    attrs << { key: 'stickiness.lb_cookie.duration_seconds',
               value: resource[:stickiness_duration] } unless resource[:stickiness_duration].nil?

    mtga_response = elbv2_client(target_region).modify_target_group_attributes( {
      targetgrouparn: tg_arn,
      attributes: attrs,
    }) unless attrs.empty?

  end

  def destroy
    Puppet.debug("Deleting target group #{name} in region #{target_region}")
    elbv2 = elbv2_client(target_region)
    elbv2.delete_target_group(target_group_arn: arn)
    @property_hash[:ensure] = :absent
  end
end
