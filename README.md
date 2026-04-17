# devenv-agents

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/sagikazarmark/devenv-agents/ci.yaml?style=flat-square)](https://github.com/sagikazarmark/devenv-agents/actions/workflows/ci.yaml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/sagikazarmark/devenv-agents/badge?style=flat-square)](https://securityscorecards.dev/viewer/?uri=github.com/sagikazarmark/devenv-agents)
[![built with nix](https://img.shields.io/badge/builtwith-nix-7d81f7?style=flat-square)](https://builtwithnix.org)

A reusable [devenv](https://devenv.sh) module for AI coding agents,
backed by [numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix).

## Usage

Add the module and the `llm-agents` input to your project's `devenv.yaml`:

```yaml
# yaml-language-server: $schema=https://devenv.sh/devenv.schema.json
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  llm-agents:
    url: github:numtide/llm-agents.nix
    inputs:
      nixpkgs:
        follows: nixpkgs
  devenv-agents:
    url: github:sagikazarmark/devenv-agents
imports:
  - devenv-agents
```

> [!IMPORTANT]
> `llm-agents` must be declared in your own `devenv.yaml`.
> devenv does not resolve it transitively from this module's flake.

Then enable the agents you want in `devenv.nix`:

```nix
{ ... }:
{
  agents.claude.enable = true;
  agents.codex.enable = true;
}
```

Run `devenv shell`.

## Supported agents

| Option                   | Upstream package          | Binary     |
| ------------------------ | ------------------------- | ---------- |
| `agents.claude.enable`   | `llm-agents.claude-code`  | `claude`   |
| `agents.codex.enable`    | `llm-agents.codex`        | `codex`    |
| `agents.opencode.enable` | `llm-agents.opencode`     | `opencode` |
| `agents.gemini.enable`   | `llm-agents.gemini-cli`   | `gemini`   |
| `agents.pi.enable`       | `llm-agents.pi`           | `pi`       |

## Overriding the package for an agent

Each agent also exposes a `package` option. Use it to swap the default for a
different build (for example, the version from your own nixpkgs):

```nix
{ pkgs, ... }:
{
  agents.claude = {
    enable = true;
    package = pkgs.claude-code;
  };
}
```

## Per-project agent state

By default each agent stores its per-user state (config, credentials,
session history) in a well-known global directory: `~/.claude`, `~/.codex`,
`~/.gemini`, etc. This is usually what you want — one login works across
all your projects.

For multi-account setups, ephemeral environments (CI, devcontainers,
throwaway worktrees), or per-project experimentation, set `projectLocal`
on the agent to relocate its state into the project tree:

```nix
{ ... }:
{
  agents.claude = {
    enable = true;
    projectLocal = true;
  };
}
```

The state moves to `$DEVENV_ROOT/.devenv/state/agents/<name>`, which is
gitignored by devenv. Caveat: the user-level config in your global home
(Claude plugins, custom sub-agents, `CLAUDE.md`, etc.) is **not** visible
inside this shell. You will be re-prompted to log in the first time.

### Supported agents

| Agent    | Env var             | Supported |
| -------- | ------------------- | --------- |
| claude   | `CLAUDE_CONFIG_DIR` | yes       |
| codex    | `CODEX_HOME`        | yes       |
| gemini   | `GEMINI_CLI_HOME`   | yes (the CLI creates a `.gemini/` subdirectory inside the pointed-at path) |
| opencode | —                   | not yet (opencode has no single env var that relocates both config and auth) |
| pi       | —                   | not yet   |

Setting `projectLocal = true` for an unsupported agent fails at evaluation.

### Related: project-level committed config

This option handles *per-user* state. For *project-level* configuration
that should be committed to git (hooks, sub-agents, MCP servers, slash
commands, `CLAUDE.md`), see the official
[`claude.code.*` devenv integration](https://devenv.sh/integrations/claude-code/).
The two are complementary and can be used together.

## Binary cache

`llm-agents.nix` publishes pre-built binaries at [`cache.numtide.com`](https://cache.numtide.com).
This flake declares the cache in its `nixConfig`, so if your Nix user is in `trusted-users`
(or you pass `--accept-flake-config`) it's picked up automatically.

Otherwise Nix prints *"ignoring untrusted flake configuration setting"*
and falls back to building from source. To opt in permanently,
add the cache to your Nix configuration:

```
extra-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
```

## Example

See [`examples/default/`](./examples/default/) for a minimal working example.

## License

The project is licensed under the [MIT License](LICENSE).
