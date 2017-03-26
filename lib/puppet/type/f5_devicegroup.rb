Puppet::Type.newtype(:f5_devicegroup) do
    @doc = "F5 device group"

    feature :descriptions, "Manages an F5 device group. Manages manual configsync operations when auto-sync disabled"

    apply_to_device

    ensurable do
        newvalue(:present) do
            provider.create
        end
        defaultto :present
    end

    newparam(:name, :namevar=>true) do
        desc "devicegroup name"
    end

    newproperty(:config_ensure) do
        desc "Set to in_sync to ensure config is synched"
    end

end
