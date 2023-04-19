{ pkgs, module, ... }:
let
  name = "kvmfr";
  kvmfrConfig = {
    enable = true;
    devices = [
      {
        dimensions = {
          width = 1920;
          height = 1080;
        };

        permissions = { user = "tester"; };
      }
      {
        dimensions = {
          width = 3840;
          height = 2160;
          hdr = true;
        };

        permissions = {
          user = "tester";
          mode = "0777";
        };
      }
    ];
  };
in pkgs.nixosTest ({
  inherit name;

  nodes = {
    machine = { config, pkgs, ... }: {
      imports = [ module ];

      users.users.tester = {
        isNormalUser = true;
        home = "/home/tester";
      };

      # https://github.com/NixOS/nixpkgs/issues/62155
      systemd.services.wait-for-udev-settle-hack = {
        enable = true;
        description =
          "Dummy service that starts after udev-settle so we have a unit we can wait for";
        after = [ "systemd-udev-settle.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          # do noting but keep the unit active
          ExecStart = "${pkgs.busybox}/bin/tail -f /dev/null";
        };
      };

      virtualisation.kvmfr = kvmfrConfig;
      virtualisation.graphics = false;
    };
  };

  testScript = ''
    # Wait for udev to take action
    machine.wait_for_unit("wait-for-udev-settle-hack.service")

    # check kernel parameters
    machine.succeed('grep -q "kvmfr.static_size_mb=32,256" /proc/cmdline')

    # check properties of kvmfr device nodes
    for dev, prop, expected in [
        ("/dev/kvmfr0", "%U", "tester"),
        ("/dev/kvmfr0", "%G", "root"),
        ("/dev/kvmfr0", "%a", "600"),
        ("/dev/kvmfr1", "%U", "tester"),
        ("/dev/kvmfr1", "%G", "root"),
        ("/dev/kvmfr1", "%a", "777"),
    ]:
        exitcode, stdout = machine.execute(f"stat -c '{prop}' '{dev}'")
        stdout = stdout.strip()
        assert exitcode == 0, f"Checking property '{prop}' of '{dev}' failed. Exitcode {exitcode}"
        assert stdout == expected, f"{dev} has wrong {prop}. Expected '{expected}', got '{stdout}'"
  '';
})
