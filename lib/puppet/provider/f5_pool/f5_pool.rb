require 'puppet/provider/f5'

Puppet::Type.type(:f5_pool).provide(:f5_pool, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 pool"

  confine :feature => :posix
  defaultfor :feature => :posix

  def self.wsdl
    'LocalLB.Pool'
  end

  def wsdl
    self.class.wsdl
  end

  def self.instances
    Array(transport[wsdl].get(:get_list)).collect do |name|
      new(:name => name)
    end
  end

  methods = {
    'action_on_service_down'          => 'actions',
    'allow_nat_state'                 => 'states',
    'allow_snat_state'                => 'states',
    'client_ip_tos'                   => 'values',
    'client_link_qos'                 => 'values',
    'gateway_failsafe_device'         => 'devices',
    'lb_method'                       => 'lb_methods',
    'minimum_active_member'           => 'values',
    'minimum_up_member'               => 'values',
    'minimum_up_member_action'        => 'actions',
    'minimum_up_member_enabled_state' => 'states',
    'server_ip_tos'                   => 'values',
    'server_link_qos'                 => 'values',
    'simple_timeout'                  => 'simple_timeouts',
    'slow_ramp_time'                  => 'values'
  }

  methods.each do |method, message|
    define_method(method.to_sym) do
      transport[wsdl].get("get_#{method}".to_sym, { pool_names: { item: resource[:name] }})
    end
    define_method("#{method}=") do |value|
      message = { pool_names: { item: resource[:name] }, message => { item: resource[method.to_sym] }}
      transport[wsdl].call("set_#{method}".to_sym, message: message)
    end
  end

  def members
    result = {}
    addressport = []
    members = []

    members << transport[wsdl].get(:get_member_v2, { pool_names: { item: resource[:name] }})

    members.flatten.each do |hash|
      # If no members are set, you get back a hash with an array in it.
      next unless hash[:address]
      address = hash[:address]
      port    = hash[:port]

      result["#{address}:#{port}"] = {}
      addressport = { address: address, port: port }

      [
        'connection_limit',
        'dynamic_ratio',
        'priority',
        'ratio',
      ].each do |method|
        message = { pool_names: { items: resource[:name] }, members: { items: { items: addressport}}}
        response = transport[wsdl].get("get_member_#{method}".to_sym, message)
        result["#{address}:#{port}"][method] = response
      end
    end
    result
  end

  def members=(value)
    response = []
    response << transport[wsdl].get(:get_member_v2, { pool_names: { item: resource[:name]}})

    current_members = response.flatten.collect { |system|
      next unless system[:address]
      "#{system[:address]}:#{system[:port]}"
    }

    #members = resource[:member].keys
    members = resource[:members].collect { |member| 
        "#{member['name']}:#{member['port']}"
    }

    # Should add new members first to avoid removing all members of the pool.
    (members - current_members).each do |node|
      Puppet.debug "Puppet::Provider::F5_Pool: adding member #{node}"
      message = { pool_names: { items: resource[:name] }, members: { items: { items: { address: network_address(node), port: network_port(node) }}}}
      transport[wsdl].call(:add_member_v2, message: message)
    end

    # When provisioning a new pool we won't have members.
    if current_members != [nil]
      (current_members - members).each do |node|
        Puppet.debug "Puppet::Provider::F5_Pool: removing member #{node}"
        message = { pool_names: { items: resource[:name] }, members: { items: { items: {address: network_address(node), port: network_port(node)}}} }
        transport[wsdl].call(:remove_member_v2, message: message)
      end
    end

    # #TODO - is any of this necessary if we define the node separately?
##    properties = {
#      'connection_limit' => 'limits',
#      'dynamic_ratio'    => 'dynamic_ratios',
#      'priority'         => 'priorities',
#      'ratio'            => 'ratios',
#    }

    #properties.each do |name, message_name|
    #  value.each do |node,hash|
    #    puts "PRESPLIT"
    #    #address, port = address.split(':')
    #    address = node['name']
    #    port = node['port']
#
#        puts "POSTSPLIT #{hash}"
#        #message = { pool_names: {items: resource[:name] }, members: {items: { items: { address: address, port: port }}}, message_name => { items: { items: hash[name]}}}
#        message = { pool_names: {items: resource[:name] }, members: {items: { items: { address: address, port: port }}} }
#        #, message_name => { items: { items: hash[name]}}}
#        puts "HERE MESSAGE #{message}" 
#        #transport[wsdl].call("set_member_#{name}".to_sym, message: message)
#      end
#    end
  end

  def health_monitors
    association = nil

    monitor = transport[wsdl].get(:get_monitor_association, { pool_names: { item: resource[:name] }})
   #MON {:pool_name=>"/Common/tomcat-prd-main_http_pool", :monitor_rule=>{:type=>"MONITOR_RULE_TYPE_AND_LIST", :quorum=>"0", :monitor_templates=>{:item=>["/Common/gateway_icmp", "/Common/TCP_slowcheck"]}}} 
    if monitor && monitor[:monitor_rule]
      association = {
        'type'              => monitor[:monitor_rule][:type],
        'quorum'            => monitor[:monitor_rule][:quorum],
      }
      if !monitor[:monitor_rule][:monitor_templates].nil? and monitor[:monitor_rule][:monitor_templates][:item]
        association['monitor_templates'] = monitor[:monitor_rule][:monitor_templates][:item]
      end
    end
    association
  end



  def health_monitors=(value)

    quorum = resource[:availability_requirement] || "all"

    config_monitors = resource[:health_monitors]
    
    current_association = transport[wsdl].get(:get_monitor_association, { pool_names: { item: resource[:name] }})
    current_monitor_rule = current_association[:monitor_rule]

    new_monitor_rule = build_monitor_config quorum, config_monitors
    if configs_differ(current_monitor_rule, new_monitor_rule)
      newval = { :pool_name => resource[:name], :monitor_rule => new_monitor_rule }
      msg = { monitor_associations: { items: newval } }
      transport[wsdl].call(:set_monitor_association, message: { monitor_associations: { items: newval }})
    end
  end

  def availability_requirement
    transport[wsdl].get(:get_monitor_association, { pool_names: { item: resource[:name] }})
  end
  
  def availability_requirement=(value)

    quorum = resource[:availability_requirement] || "all"

    config_monitors = resource[:health_monitors]
    
    current_association = transport[wsdl].get(:get_monitor_association, { pool_names: { item: resource[:name] }})
    current_monitor_rule = current_association[:monitor_rule]

    new_monitor_rule = build_monitor_config quorum, config_monitors
    if configs_differ(current_monitor_rule, new_monitor_rule)
      newval = { :pool_name => resource[:name], :monitor_rule => new_monitor_rule }
      msg = { monitor_associations: { items: newval } }
      transport[wsdl].call(:set_monitor_association, message: { monitor_associations: { items: newval }})
    end
  end

  def configs_differ(a, b) 
    if a[:type] != b[:type] 
      return true
    end
    if a[:quorum] != b[:quorum]
      return true
    end
    if a[:monitor_templates][:item]
      if a[:monitor_templates][:item].instance_of? Array
        diff = a[:monitor_templates][:item] - b[:monitor_templates][:item]
        return ! diff.empty?
      else
        return a[:monitor_templates][:item] != b[:monitor_templates][:item]
      end
    else
      return a[:monitor_templates] != b[:monitor_templates] 
    end
    false
  end

  def build_monitor_config(quorum = 'all', monitors = [])
    if monitors.empty?
      {:type => "MONITOR_RULE_TYPE_NONE", :quorum => "0", :monitor_templates => {:item => []}}
    else
      if monitors.size == 1
        {:type =>"MONITOR_RULE_TYPE_SINGLE", :quorum =>"0", :monitor_templates => {:item => monitors[0]}}
      else
        if quorum == 'all' or quorum.empty? or quorum == 0 or quorum == '0'
          {:type => "MONITOR_RULE_TYPE_AND_LIST", :quorum => "0", :monitor_templates => {:item => monitors}}
        else
          {:type => "MONITOR_RULE_TYPE_M_OF_N", :quorum => "#{quorum}", :monitor_templates => {:item => monitors}}
        end 
      end
    end
  end 

  def create
    Puppet.debug("Puppet::Provider::F5_Pool: creating F5 pool #{resource[:name]}")
    # [[]] because we will add members later using member=...
    message = { pool_names: { item: resource[:name] }, lb_methods: { item: resource[:lb_method] }, members: {}}
    transport[wsdl].call(:create_v2, message: message)

    methods = [
      'action_on_service_down',
      'allow_nat_state',
      'allow_snat_state',
      'client_ip_tos',                      # Array
      'client_link_qos',                    # Array
      'gateway_failsafe_device',
      'lb_method',
      'minimum_active_member',              # Array
      'minimum_up_member',                  # Array
      'minimum_up_member_action',
      'minimum_up_member_enabled_state',
      'server_ip_tos',
      'server_link_qos',
      'simple_timeout',
      'slow_ramp_time',
      'health_monitors',
      'members'
    ]

    methods.each do |method|
      self.send("#{method}=", resource[method.to_sym]) if resource[method.to_sym]
    end
  end

  def destroy
    Puppet.debug("Puppet::Provider::F5_Pool: destroying F5 pool #{resource[:name]}")
    transport[wsdl].call(:delete_pool, message: { pool_names: { item: resource[:name]}})
  end

  def exists?
    transport[wsdl].get(:get_list).include?(resource[:name])
    #moo
    #false
  end
end
