{
  config,
  lib,
  pkgs,
  # injected by default.nix: the compiled server, built with this system's pkgs
  klausurPackage,
  ...
}:
let
  cfg = config.services.klausur;

  # Every *.pdf in ./assets is a paper that can be handed out
  papers = lib.attrNames (
    lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".pdf" (lib.toLower name)) (
      builtins.readDir ./assets
    )
  );

  # Served from a read-only store path holding nothing but the papers
  examDir = pkgs.linkFarm "klausur-papers" (
    map (name: {
      inherit name;
      path = ./assets + "/${name}";
    }) papers
  );
in
{
  options.services.klausur = {
    enable = lib.mkEnableOption "klausur exam paper distributor";

    package = lib.mkOption {
      type = lib.types.package;
      default = klausurPackage;
      defaultText = lib.literalMD "`klausur` from the flake that provides this module";
      description = "The compiled server to run.";
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/klausur/klausur.sock";
      description = "Unix socket the server binds to. Lives under the /run/klausur runtime dir; front it with a reverse proxy via proxy_pass to the socket.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.klausur = {
      description = "Exam paper distributor";
      wantedBy = [ "multi-user.target" ];

      environment = {
        EXAM_DIR = "${examDir}";
        KLAUSUR_SOCKET = cfg.socketPath;
        XDG_CACHE_HOME = "/var/lib/klausur"; # keep bun's runtime caches inside the writable state dir
      };

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        User = "klausur";
        StateDirectory = "klausur";
        # owns /run/klausur where the unix socket lives; 0750 so a proxy
        # user added to the "klausur" group can connect
        RuntimeDirectory = "klausur";
        RuntimeDirectoryMode = "0750";
        Restart = "on-failure";
        RestartSec = "1s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };

    users.users.klausur = {
      isSystemUser = true;
      group = "klausur";
    };
    users.groups.klausur = { };
  };
}
