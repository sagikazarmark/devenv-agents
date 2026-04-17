# devenv-agents: reusable devenv module for AI coding agents

## Summary

A reusable [devenv](https://devenv.sh) module that lets consumers enable AI coding
agents in their devshells with a simple `agents.<name>.enable = true` syntax.
Packages come from [numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix)
by default.

## Goals

- Provide a clean, opinionated module surface: `agents.<name>.enable`,
  `agents.<name>.package`.
- Ship a curated set of well-known agents in v1: **claude, codex, opencode,
  gemini, pi**.
- Make it trivial to extend with additional agents over time.
- Let consumers override any agent's package without forking the module.

## Non-goals (YAGNI)

- Per-agent env vars, scripts, wrapper config, or settings files.
- An `overlays.shared-nixpkgs`-style rewiring path (v1 uses llm-agents' pinned
  packages directly).
- An auto-generated "all packages from llm-agents.nix" variant.
- Per-agent version pinning beyond what `package` override already allows.

## Consumer experience

`devenv.yaml`:

```yaml
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  devenv-agents:
    url: github:sagikazarmark/devenv-agents
imports:
  - devenv-agents
```

`devenv.nix`:

```nix
{ ... }:
{
  agents.claude.enable = true;
  agents.codex.enable = true;
}
```

Overriding a package:

```nix
{ pkgs, ... }:
{
  agents.claude = {
    enable = true;
    package = pkgs.claude-code;  # e.g. pin to nixpkgs version
  };
}
```

## Module surface

### Initial agent list

| Option                    | llm-agents.nix package | Binary     |
|---------------------------|------------------------|------------|
| `agents.claude.enable`    | `claude-code`          | `claude`   |
| `agents.codex.enable`     | `codex`                | `codex`    |
| `agents.opencode.enable`  | `opencode`             | `opencode` |
| `agents.gemini.enable`    | `gemini-cli`           | `gemini`   |
| `agents.pi.enable`        | `pi`                   | `pi`       |

The option names are the agents' common short names; the upstream package name
in llm-agents.nix is an internal mapping detail.

### Per-agent options

Each agent exposes two options, nothing more:

- `agents.<name>.enable` — `bool`, default `false`. Standard `mkEnableOption`.
- `agents.<name>.package` — `package`, default
  `inputs.llm-agents.packages.${pkgs.system}.<upstream-name>`.

When `enable` is true, the `package` is appended to the devshell's `packages`
list.

## Repository layout

```
devenv-agents/
├── devenv.yaml          # declares llm-agents input for transitive resolution
├── devenv.lock
├── flake.nix            # standalone flake, used for local dev and checks
├── flake.lock
├── modules/
│   └── agents.nix       # the devenv module
├── examples/
│   └── default/         # smoke-test consumer (devenv.yaml + devenv.nix)
├── .editorconfig
├── .gitignore
├── LICENSE
└── README.md
```

### `modules/agents.nix`

Sketch:

```nix
{ pkgs, lib, config, inputs, ... }:
let
  upstream = inputs.llm-agents.packages.${pkgs.system};

  mkAgent = { name, upstreamName, description }: {
    enable = lib.mkEnableOption description;
    package = lib.mkOption {
      type = lib.types.package;
      default = upstream.${upstreamName};
      defaultText = lib.literalExpression
        "inputs.llm-agents.packages.\${pkgs.system}.${upstreamName}";
      description = "The package providing ${name}.";
    };
  };

  agents = {
    claude   = { upstreamName = "claude-code"; description = "Claude Code"; };
    codex    = { upstreamName = "codex";       description = "OpenAI Codex CLI"; };
    opencode = { upstreamName = "opencode";    description = "opencode"; };
    gemini   = { upstreamName = "gemini-cli";  description = "Gemini CLI"; };
    pi       = { upstreamName = "pi";          description = "pi-mono coding agent"; };
  };
in {
  options.agents = lib.mapAttrs
    (name: spec: mkAgent (spec // { inherit name; }))
    agents;

  config.packages = lib.concatLists (lib.mapAttrsToList
    (name: _: lib.optional config.agents.${name}.enable config.agents.${name}.package)
    agents);
}
```

Adding a new agent later = adding one entry to the `agents` attrset.

### `devenv.yaml` (of this repo)

```yaml
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  llm-agents:
    url: github:numtide/llm-agents.nix
    inputs:
      nixpkgs:
        follows: nixpkgs
```

`llm-agents.nix` is declared here so consumers who add this repo as an input
inherit it transitively and the module can reference `inputs.llm-agents` without
the consumer having to declare it themselves.

### `flake.nix`

Minimal flake that:

- Takes `nixpkgs` and `llm-agents` as inputs.
- Exposes `devenvModules.default = ./modules/agents.nix` (for consumers who want
  to use it from a flake-native setup rather than `devenv.yaml` imports).
- Exposes a formatter so `nix fmt` works.

The primary distribution channel is the `devenv.yaml` import path; the flake is
a secondary escape hatch.

## Key assumption to verify during implementation

The design relies on devenv's `devenv.yaml` input resolution being **transitive**:
when a consumer adds `devenv-agents` as an input and imports it, the
`llm-agents` input declared inside `devenv-agents/devenv.yaml` should be
available as `inputs.llm-agents` inside the module.

If that assumption turns out to be false, the fallback is to require the
consumer to declare `llm-agents` in their own `devenv.yaml`, and document that
requirement prominently in the README. This is an implementation-time
verification, not a design blocker.

## Validation

A minimal `examples/default/` directory containing a consumer `devenv.yaml` and
`devenv.nix` that enables one or two agents. Running `devenv build shell` (or
`devenv shell -- claude --version`) inside that example is the smoke test for
the module working end-to-end.

`nix flake check` on the root flake runs any formatting and evaluation checks.

## Open questions

None at design time. The input-transitivity question above is a verification
step, not a design decision.
