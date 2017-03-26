require 'puppet/provider/f5'

Puppet::Type.type(:f5_devicegroup).provide(:f5_devicegroup, :parent => Puppet::Provider::F5) do
    @doc = "Manages F5 devicegroup"

    confine        :feature => :posix
    defaultfor     :feature => :posix

    def wsdl
        self.class.wsdl
    end

    def create
        # TODO - implement hostgroup create/destroy
    end

    def destroy
        # TODO - implement hostgroup create/destroy
    end

    def exists?
        true
    end

    def config_ensure
        sync_status[:member_state].downcase.sub /^member_state_/, ''
    end

    def config_ensure=(value)
        api_call 'System.ConfigSync', :synchronize_to_group_v2, { group: resource[:name], device: sync_source_device,  force: 'false' }
    end

    def sync_status
        @sync_status ||= api_call('Management.DeviceGroup', :get_sync_status, { device_groups: { item: [ resource[:name] ] } })
    end

    def device_sync_status
        @device_sync_status ||= begin
            devices = api_call('Management.DeviceGroup', :get_device, { device_groups: { item: [ resource[:name] ] } })
            statuses = api_call('Management.DeviceGroup', :get_device_sync_status, { device_groups: { item: [ resource[:name] ] }, devices: { item: { item: devices } } })
            Hash[devices.zip(statuses)]
        end
    end

    def sync_source_device
        @sync_source_device ||= begin
            device_sync_status.keys.max_by do |name|
                time = device_sync_status[name][:commit_id][:sync_time]
                DateTime.iso8601 sprintf("%04d-%02d-%02dT%02d:%02d:%02d",
                    time[:year], time[:month], time[:day], time[:hour], time[:minute], time[:second])
            end
        end
    end

end
