# Designed based on: https://kevincox.ca/2022/12/09/valheim-server-nixos-v2/

# satisfactory.nix
{config, pkgs, lib, ...}:

let
    # The Steam Game "Dedicated Server" App ID
    # Set to {id}-{branch}-{password} for betas.
    steam-game-server-app-id    = "1690800";  # Satisfactory Dedicated Server App ID
    steam-game-beta-id          = "";
    steam-game-beta-password    = "";

    # Game Server Install Folder
    server-install-directory    = "/var/lib/satisfactory";

    # Secret Variables
    # Import secrets as a variable from another file
    # Example ./secrets.nix content:
    # {
    #     server-game-port-udp    = "7777";
    #     server-beacon-port-udp  = "15000";
    #     server-query-port-udp   = "15777";
    # }
    secrets                     = import ./secrets.nix;

    # Game Server Network Port Settings
    # https://satisfactory.fandom.com/wiki/Dedicated_servers#Port_forwarding_and_firewall_settings

    # Logging Variables
    log-folder                  = "/var/log/satisfactory";
    log-file-stdout             = "stdout.log";
    log-file-stderr             = "stderr.log";
in {
    users.users.satisfactory = {
        isSystemUser = true;
        # Satisfactory puts save data in the home directory.
        home         = "/home/satisfactory";
        createHome   = true;
        homeMode     = "750";
        group        = "satisfactory";
    };

    users.groups.satisfactory = {};

    # Service to run the game
    systemd.services.satisfactory = {

        # https://satisfactory.fandom.com/wiki/Dedicated_servers/Running_as_a_Service
        wantedBy = [
            "multi-user.target"
        ];

        wants = [
            "network-online.target"
        ];
        after = [
            "network.target"
            "network-online.target"
            "nss-lookup.target"
            "syslog.target"
        ];

        serviceConfig = {
            # Download the game
            # Then fix those binaries using patchelf
            ExecStartPre = "${pkgs.resholve.writeScript "steam" {
                interpreter = "${pkgs.zsh}/bin/zsh";
                inputs = with pkgs; [
                    patchelf
                    steamcmd
                    findutils   # Adds 'find'
                ];
                execer = with pkgs; [
                    "cannot:${steamcmd}/bin/steamcmd"
                ];
            } ''
                set -eux

                dir="${server-install-directory}"
                app_id="${steam-game-server-app-id}"
                beta_id="${steam-game-beta-id}"
                beta_password="${steam-game-beta-password}"

                # These are arguments you will always
                cmds=(
                    +force_install_dir $dir
                    +login anonymous
                    +app_update $app_id
                    validate
                )

                # Add optional beta arguments if a beta is present
                if [[ $beta_id ]]; then
                    cmds+=(-beta $beta_id)

                    # If the beta has a password...
                    if [[ $beta_password ]]; then
                        cmds+=(-betapassword $beta_password)
                    fi
                fi

                # add the final quit argument
                cmds+=(+quit)

                # Execute the Command and its Arguments
                steamcmd $cmds

                # Iterate over the downloaded files
                for f in $(find "$dir"); do

                    # Skip if not
                    # - A file
                    # - Executable
                    if ! [[ -f $f && -x $f ]]; then
                        continue
                    fi

                    # Update the interpreter to the path on NixOS.
                    patchelf --set-interpreter ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 $f || true
                done
            ''}";

            TimeoutStartSec = "180";

            ExecStart = lib.escapeShellArgs [
                "${server-install-directory}/FactoryServer.sh"
                "-multihome=0.0.0.0"                            # Need to force IPv4
                "-BeaconPort=${secrets.server-beacon-port-udp}"
                "-Port=${secrets.server-game-port-udp}"
                "-ServerQueryPort=${secrets.server-query-port-udp}"
                # https://satisfactory.fandom.com/wiki/Dedicated_servers#Command_line_options
            ];
            Nice                = "-5";
            PrivateTmp          = true;
            Restart             = "on-failure";
            User                = "satisfactory";
            Group               = "satisfactory";
            WorkingDirectory    = "~";

            # Logging Settings
            StandardOutput      = "append:${log-folder}/${log-file-stdout}";
            StandardError       = "append:${log-folder}/${log-file-stderr}";
        };

        environment = {
            # linux64 directory is required by Satisfactory.
            LD_LIBRARY_PATH     = "${server-install-directory}/linux64:${pkgs.glibc}/lib";
        };
    };

    networking.firewall.allowedUDPPorts = [
        # # https://satisfactory.fandom.com/wiki/Dedicated_servers#Port_forwarding_and_firewall_settings
        # Satisfactory Beacon Port
        (lib.toInt secrets.server-beacon-port-udp)
        # Satisfactory Game Port
        (lib.toInt secrets.server-game-port-udp)
        # Satisfactory Query Port
        (lib.toInt secrets.server-query-port-udp)
    ];

    # Enable Logrotate
    services.logrotate = {
        enable = true;
    };

    # Add Logrotate config for satisfactory stdout logs
    services.logrotate.settings.satisfactory_stdout = {
        files           = "${log-folder}/${log-file-stdout}";

        compress        = true;
        create          = "640 satisfactory satisfactory";
        dateext         = true;
        delaycompress   = true;
        frequency       = "daily";
        missingok       = true;
        notifempty      = true;
        su              = "satisfactory satisfactory";
        rotate          = 31;
    };

    # Add Logrotate config for satisfactory stderr logs
    services.logrotate.settings.satisfactory_stderr = {
        files           = "${log-folder}/${log-file-stderr}";

        compress        = true;
        create          = "640 satisfactory satisfactory";
        dateext         = true;
        delaycompress   = true;
        frequency       = "daily";
        missingok       = true;
        notifempty      = true;
        su              = "satisfactory satisfactory";
        rotate          = 31;
    };

    # Pre-Create Files and Folders
    systemd.tmpfiles.rules = [
        # Game Install Directory
        "d ${server-install-directory} 0750 satisfactory satisfactory -"

        # Log Files and Folders
        "d ${log-folder} 0770 satisfactory satisfactory -"
        "f ${log-folder}/${log-file-stdout} 0640 satisfactory satisfactory -"
        "f ${log-folder}/${log-file-stderr} 0640 satisfactory satisfactory -"
    ];
}
