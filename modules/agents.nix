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

    projectLocal = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Relocate this agent's per-user state (config, credentials, session
        history) from the user's global home directory into the project tree
        under $DEVENV_ROOT/.devenv/state/agents/<name>.

        When true, a per-agent environment variable is set for the devenv
        shell that points the agent at the project-local directory. The exact
        variable depends on the agent (CLAUDE_CONFIG_DIR for claude,
        CODEX_HOME for codex, GEMINI_CLI_HOME for gemini). This moves
        everything the agent stores, including user-level config such as
        ~/.claude/CLAUDE.md or ~/.codex/config.toml — not just cache.

        Useful for multi-account setups, ephemeral CI environments, and
        repos that need fully reproducible agent state.

        Not yet supported for opencode or pi; setting it to true for those
        agents is an evaluation error.
      '';
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

  projectLocalPath = name: "${config.devenv.state}/agents/${name}";

  activeProjectLocal = lib.filterAttrs
    (name: _spec:
      config.agents.${name}.enable && config.agents.${name}.projectLocal)
    agents;

  activeProjectLocalSupported = lib.filterAttrs
    (_name: spec: spec.configDirEnvVar != null)
    activeProjectLocal;
in
{
  options.agents = lib.mapAttrs (_name: spec: mkAgent spec) agents;

  config = {
    packages = lib.concatLists (lib.mapAttrsToList
      (name: _spec:
        lib.optional config.agents.${name}.enable config.agents.${name}.package)
      agents);

    env = lib.mapAttrs'
      (name: spec: lib.nameValuePair spec.configDirEnvVar (projectLocalPath name))
      activeProjectLocalSupported;

    enterShell = lib.concatMapStringsSep "\n"
      (name: ''mkdir -p "${projectLocalPath name}"'')
      (lib.attrNames activeProjectLocalSupported);

    assertions = lib.mapAttrsToList
      (name: spec: {
        assertion = !(config.agents.${name}.enable
                   && config.agents.${name}.projectLocal
                   && spec.configDirEnvVar == null);
        message = ''
          agents.${name}.projectLocal = true is not yet supported:
          ${name} has no single environment variable that relocates both
          config and auth. See
          docs/superpowers/specs/2026-04-17-project-local-agent-state-design.md
          — leave projectLocal = false for now.
        '';
      })
      agents;
  };
}
