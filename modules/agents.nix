{ pkgs, lib, config, inputs, ... }:

let
  upstream = inputs.llm-agents.packages.${pkgs.system};
in
{
  options.agents = {
    claude = {
      enable = lib.mkEnableOption "the Claude Code coding agent";

      package = lib.mkOption {
        type = lib.types.package;
        default = upstream.claude-code;
        defaultText = lib.literalExpression
          "inputs.llm-agents.packages.\${pkgs.system}.claude-code";
        description = "The claude-code package to use.";
      };
    };
  };

  config.packages =
    lib.optional config.agents.claude.enable config.agents.claude.package;
}
