{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.wyoming.faster-whisper;

  inherit (lib)
    escapeShellArgs
    mkOption
    mkEnableOption
    mkPackageOption
    types
    ;

  inherit (builtins)
    toString
    ;

in

{
  options.services.wyoming.faster-whisper = with types; {
    package = mkPackageOption pkgs "wyoming-faster-whisper" { };

    servers = mkOption {
      default = { };
      description = ''
        Attribute set of faster-whisper instances to spawn.
      '';
      type = types.attrsOf (
        types.submodule (
          { ... }:
          {
            options = {
              enable = mkEnableOption "Wyoming faster-whisper server";

              model = mkOption {
                type = str;
                default = "tiny-int8";
                example = "Systran/faster-distil-whisper-small.en";
                description = ''
                  Name of the voice model to use.

                  Check the [2.0.0 release notes](https://github.com/rhasspy/wyoming-faster-whisper/releases/tag/v2.0.0) for possible values.
                '';
              };

              uri = mkOption {
                type = strMatching "^(tcp|unix)://.*$";
                example = "tcp://0.0.0.0:10300";
                description = ''
                  URI to bind the wyoming server to.
                '';
              };

              device = mkOption {
                # https://opennmt.net/CTranslate2/python/ctranslate2.models.Whisper.html#
                type = types.enum [
                  "cpu"
                  "cuda"
                  "auto"
                ];
                default = "cpu";
                description = ''
                  Determines the platform faster-whisper is run on. CPU works everywhere, CUDA requires a compatible NVIDIA GPU.
                '';
              };

              language = mkOption {
                type = enum [
                  # https://github.com/home-assistant/addons/blob/master/whisper/config.yaml#L20
                  "auto"
                  "af"
                  "am"
                  "ar"
                  "as"
                  "az"
                  "ba"
                  "be"
                  "bg"
                  "bn"
                  "bo"
                  "br"
                  "bs"
                  "ca"
                  "cs"
                  "cy"
                  "da"
                  "de"
                  "el"
                  "en"
                  "es"
                  "et"
                  "eu"
                  "fa"
                  "fi"
                  "fo"
                  "fr"
                  "gl"
                  "gu"
                  "ha"
                  "haw"
                  "he"
                  "hi"
                  "hr"
                  "ht"
                  "hu"
                  "hy"
                  "id"
                  "is"
                  "it"
                  "ja"
                  "jw"
                  "ka"
                  "kk"
                  "km"
                  "kn"
                  "ko"
                  "la"
                  "lb"
                  "ln"
                  "lo"
                  "lt"
                  "lv"
                  "mg"
                  "mi"
                  "mk"
                  "ml"
                  "mn"
                  "mr"
                  "ms"
                  "mt"
                  "my"
                  "ne"
                  "nl"
                  "nn"
                  "no"
                  "oc"
                  "pa"
                  "pl"
                  "ps"
                  "pt"
                  "ro"
                  "ru"
                  "sa"
                  "sd"
                  "si"
                  "sk"
                  "sl"
                  "sn"
                  "so"
                  "sq"
                  "sr"
                  "su"
                  "sv"
                  "sw"
                  "ta"
                  "te"
                  "tg"
                  "th"
                  "tk"
                  "tl"
                  "tr"
                  "tt"
                  "uk"
                  "ur"
                  "uz"
                  "vi"
                  "yi"
                  "yo"
                  "zh"
                ];
                example = "en";
                description = ''
                  The language used to to parse words and sentences.
                '';
              };

              beamSize = mkOption {
                type = ints.unsigned;
                default = 1;
                example = 5;
                description = ''
                  The number of beams to use in beam search.
                '';
                apply = toString;
              };

              extraArgs = mkOption {
                type = listOf str;
                default = [ ];
                description = ''
                  Extra arguments to pass to the server commandline.
                '';
                apply = escapeShellArgs;
              };
            };
          }
        )
      );
    };
  };

  config =
    let
      inherit (lib)
        mapAttrs'
        mkIf
        nameValuePair
        ;
    in
    mkIf (cfg.servers != { }) {
      systemd.services = mapAttrs' (
        server: options:
        nameValuePair "wyoming-faster-whisper-${server}" {
          inherit (options) enable;
          description = "Wyoming faster-whisper server instance ${server}";
          wants = [
            "network-online.target"
          ];
          after = [
            "network-online.target"
          ];
          wantedBy = [
            "multi-user.target"
          ];
          # https://github.com/rhasspy/wyoming-faster-whisper/issues/27
          environment."HF_HUB_CACHE" = "/tmp";
          serviceConfig = {
            DynamicUser = true;
            User = "wyoming-faster-whisper";
            StateDirectory = "wyoming/faster-whisper";
            # https://github.com/home-assistant/addons/blob/master/whisper/rootfs/etc/s6-overlay/s6-rc.d/whisper/run
            ExecStart = ''
              ${cfg.package}/bin/wyoming-faster-whisper \
                --data-dir $STATE_DIRECTORY \
                --download-dir $STATE_DIRECTORY \
                --uri ${options.uri} \
                --device ${options.device} \
                --model ${options.model} \
                --language ${options.language} \
                --beam-size ${options.beamSize} ${options.extraArgs}
            '';
            CapabilityBoundingSet = "";
            DeviceAllow =
              if
                builtins.elem options.device [
                  "cuda"
                  "auto"
                ]
              then
                [
                  # https://docs.nvidia.com/dgx/pdf/dgx-os-5-user-guide.pdf
                  "char-nvidia-uvm"
                  "char-nvidia-frontend"
                  "char-nvidia-caps"
                  "char-nvidiactl"
                ]
              else
                "";
            DevicePolicy = "closed";
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            PrivateUsers = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectProc = "invisible";
            # "all" is required because faster-whisper accesses /proc/cpuinfo to determine cpu capabilities
            ProcSubset = "all";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
            ];
            UMask = "0077";
          };
        }
      ) cfg.servers;
    };
}
