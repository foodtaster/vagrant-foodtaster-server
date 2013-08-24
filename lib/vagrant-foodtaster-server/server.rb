class VagrantFoodtasterServer
  class Server
    def initialize(app, env)
      @env = env
      @app = app

      @sahara = Sahara::Session::Command.new(@app, @env)
    end

    def redirect_stdstreams(stdout, stderr)
      $stdout = stdout
      $stderr = stderr
    end

    def prepare_vm(vm_name)
      vm = get_vm(vm_name)

      if vm.state.id.to_s != 'running'
        vm.action(:up, provision_enabled: false)
      end

      unless @sahara.is_snapshot_mode_on?(vm)
        @sahara.on(vm)
      end
    end

    def rollback_vm(vm_name)
      vm = get_vm(vm_name)

      @sahara.rollback(vm)
    end

    def vm_defined?(vm_name)
      @env.machine_names.include?(vm_name)
    end

    def run_chef_on_vm(vm_name, current_run_config)
      vm = get_vm(vm_name)
      chef_solo_config = vm.config.vm.provisioners.find { |p| p.name == :chef_solo }

      unless chef_solo_config
        raise RuntimeError, <<-EOT
          VM '#{vm_name}' doesn't have a configured chef-solo provisioner, which is requied by Foodtaster to run specs on this VM.
          Please, add dummy chef-solo provisioner to your Vagrantfile, like this:

          config.vm.provision :chef_solo do |chef|
            chef.cookbooks_path = %w[site-cookbooks]
          end
        EOT
      end

      provisioner_klass = Vagrant.plugin("2").manager.provisioners[:chef_solo]
      provisioner = provisioner_klass.new(vm, chef_solo_config.config)

      current_run_chef_solo_config = apply_current_run_config(vm.config, current_run_config)
      provisioner.configure(current_run_chef_solo_config)

      provisioner.provision
    end

    def execute_command_on_vm(vm_name, command)
      vm = get_vm(vm_name)
      exec_result = {}

      exec_result[:exit_status] = vm.communicate.sudo(command, error_check: false) do |stream_type, data|
        exec_result[stream_type] = exec_result[stream_type].to_s + data
      end

      exec_result
    end

    private

    def get_vm(vm_name)
      @env.machine(vm_name, :virtualbox)
    end

    def apply_current_run_config(vm_config, current_run_config)
      modified_config = vm_config.dup
      modified_config.vm.provisioners[0].config.run_list = current_run_config[:run_list]
      modified_config.vm.provisioners[0].config.json = current_run_config[:json]

      modified_config
    end
  end
end