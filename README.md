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
