{
  config,
  lib,
  pkgs,
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

    port = lib.mkOption {
      type = lib.types.port;
      default = 8383;
      description = "Port the local server binds to (bound to 127.0.0.1; front it with a reverse proxy).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.klausur = {
      description = "Exam paper distributor";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        KLAUSUR_EXAM_DIR = "${examDir}";
        KLAUSUR_PORT = toString cfg.port;
        PYTHONDONTWRITEBYTECODE = "1";
        PYTHONUNBUFFERED = "1";
      };

      serviceConfig = {
        ExecStart = "${pkgs.python3.interpreter} ${./klausur-serve.py}";
        User = "klausur";
        StateDirectory = "klausur";
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
