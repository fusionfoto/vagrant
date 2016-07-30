require "tempfile"

require_relative "../../../../lib/vagrant/util/template_renderer"

module VagrantPlugins
  module GuestRedHat
    module Cap
      class ConfigureNetworks
        include Vagrant::Util

        def self.configure_networks(machine, networks)
          comm = machine.communicate

          network_scripts_dir = machine.guest.capability(:network_scripts_dir)

          commands   = []
          interfaces = machine.guest.capability(:network_interfaces)

          networks.each.with_index do |network, i|
            network[:device] = interfaces[network[:interface]]

            # Render a new configuration
            entry = TemplateRenderer.render("guests/redhat/network_#{network[:type]}",
              options: network,
            )

            # Upload the new configuration
            remote_path = "/tmp/vagrant-network-entry-#{network[:device]}-#{Time.now.to_i}-#{i}"
            Tempfile.open("vagrant-redhat-configure-networks") do |f|
              f.binmode
              f.write(entry)
              f.fsync
              f.close
              machine.communicate.upload(f.path, remote_path)
            end

            # Add the new interface and bring it back up
            final_path = "#{network_scripts_dir}/ifcfg-#{network[:device]}"
            commands << <<-EOH.gsub(/^ {14}/, '')
              # Down the interface before munging the config file. This might
              # fail if the interface is not actually set up yet so ignore
              # errors.
              /sbin/ifdown '#{network[:device]}' || true

              # Move new config into place
              mv '#{remote_path}' '#{final_path}'

              # Reload NetworkManager config if possible
              # Fixes regression from b621cc44fb63d93143915d2e744556ab36d80b17
              # of Wed Jun 22 18:37:01 2016 -0700
              if command -v nmcli &>/dev/null; then
                if command -v systemctl &>/dev/null && systemctl -q is-enabled NetworkManager &>/dev/null; then
                  nmcli c load #{final_path}
                elif command -v service &>/dev/null && service NetworkManager status &>/dev/null; then
                  nmcli c load #{final_path}
                fi
              fi

              # Bring the interface up
              ARPCHECK=no /sbin/ifup '#{network[:device]}'
            EOH
          end

          comm.sudo(commands.join("\n"))
        end
      end
    end
  end
end
