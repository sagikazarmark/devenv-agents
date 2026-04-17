{ pkgs, lib, config, inputs, ... }:

let
  upstream = inputs.llm-agents.packages.${pkgs.system};

  mkAgent = { upstreamName, description, configDirEnvVar }: {
    enable = lib.mkEnableOption description;

    package = lib.mkOption {
      type = lib.types.package;
      default = upstream.${upstreamName};
      defaultText = lib.literalExpression
        "inputs.llm-agents.packages.\${pkgs.system}.${upstreamName}";
      description = "The ${upstreamName} package to use.";
    };
  };

  agents = {
    claude = {
      upstreamName = "claude-code";
      description = "the Claude Code coding agent";
      configDirEnvVar = "CLAUDE_CONFIG_DIR";
    };
    codex = {
      upstreamName = "codex";
      description = "the OpenAI Codex CLI coding agent";
      configDirEnvVar = "CODEX_HOME";
    };
    opencode = {
      upstreamName = "opencode";
      description = "the opencode coding agent";
      configDirEnvVar = null;
    };
    gemini = {
      upstreamName = "gemini-cli";
      description = "the Gemini CLI coding agent";
      configDirEnvVar = "GEMINI_CLI_HOME";
    };
    pi = {
      upstreamName = "pi";
      description = "the pi-mono coding agent";
      configDirEnvVar = null;
    };
  };
in
{
  options.agents = lib.mapAttrs (_name: spec: mkAgent spec) agents;

  config.packages = lib.concatLists (lib.mapAttrsToList
    (name: _spec:
      lib.optional config.agents.${name}.enable config.agents.${name}.package)
    agents);
}
