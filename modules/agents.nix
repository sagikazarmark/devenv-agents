{ pkgs, lib, config, inputs, ... }:

let
  upstream = inputs.llm-agents.packages.${pkgs.system};

  mkAgent = { upstreamName, description }: {
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
    };
    codex = {
      upstreamName = "codex";
      description = "the OpenAI Codex CLI coding agent";
    };
    opencode = {
      upstreamName = "opencode";
      description = "the opencode coding agent";
    };
    gemini = {
      upstreamName = "gemini-cli";
      description = "the Gemini CLI coding agent";
    };
    pi = {
      upstreamName = "pi";
      description = "the pi-mono coding agent";
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
