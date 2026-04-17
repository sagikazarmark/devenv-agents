# Project-local agent state

## Summary

Add an opt-in `projectLocal` boolean option to each agent in the `agents.*`
module. When set to `true`, the agent's per-user state — config, credentials,
session history, and any other files the agent keeps in its home directory —
is relocated from the user's global home (e.g. `~/.claude`, `~/.codex`) into
the devenv-native state location inside the project tree.

The option is **off by default**. The target path is **fixed by convention**
and not user-configurable.

## Motivation

Each supported agent stores per-user state in a well-known global directory:
`~/.claude`, `~/.codex`, `~/.gemini`, and so on. For some workflows this is
wrong:

- **Multi-account or multi-org setups.** A developer may want a different
  login for their work repo and their personal repo.
- **Ephemeral / reproducible environments** (CI, devcontainers, throwaway
  worktrees). Sharing state with `$HOME` defeats the purpose.
- **Isolation after compromise.** If a project's auth token is leaked,
  blasting `.devenv/` is a cleaner recovery than editing global state.

`devenv` already provides a conventional location for per-project state:
`$DEVENV_STATE` (`$DEVENV_ROOT/.devenv/state`), which is gitignored. All
supported agents support relocating their home via an environment variable.
Wiring these together is a good fit for this module.

It is **not** the right default: the common case is a single developer with a
single global login across projects. Making it default would force re-auth on
every new project, hide the user's carefully curated global config (Claude
plugins, sub-agents, custom commands), and surprise anyone who runs the agent
both inside and outside the devenv shell.

## Non-goals

- **Project config** (hooks, sub-agents, MCP servers, slash commands,
  `CLAUDE.md`). The official upstream [`claude.code.*` devenv
  integration](https://devenv.sh/integrations/claude-code/) already handles
  this well by writing committed files under `.claude/` at the repo root.
  This design is orthogonal and does not overlap with it. The README should
  briefly point users at the upstream integration.
- **Hybrid state layouts** (relocating only credentials, or only session
  history). All supported env vars move everything together; we do not try
  to paper over that.
- **Making the target path user-configurable.** Deliberately one convention.
  If that turns out to be wrong later, adding configurability is a
  backwards-compatible change; removing it is not.

## Design

### Option surface

Extend each agent's submodule in `modules/agents.nix` with one new option:

```nix
agents.<name> = {
  enable = lib.mkEnableOption "...";
  package = lib.mkOption { ... };

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
      CODEX_HOME for codex, ...). This moves everything the agent stores,
      including the user-level config at ~/.claude/CLAUDE.md or
      ~/.codex/config.toml — not just cache.

      Useful for multi-account setups, ephemeral CI environments, and
      repos that need fully reproducible agent state.
    '';
  };
};
```

User-facing usage:

```nix
# devenv.nix
{
  agents.claude = {
    enable = true;
    projectLocal = true;
  };

  agents.codex.enable = true;        # stays global (~/.codex)
}
```

### Target path

Fixed, by convention:

```
$DEVENV_ROOT/.devenv/state/agents/<agent-name>
```

- `.devenv/state` is the documented devenv per-project state location
  (`$DEVENV_STATE`). The whole `.devenv/` tree is conventionally gitignored
  (devenv itself writes a `.gitignore` inside `.devenv/`); implementation
  should verify this holds in a fresh project and, if not, document that
  users must add `.devenv/` to their own `.gitignore`.
- `agents/` sub-namespace avoids collision with any other module writing
  under `.devenv/state/`.
- `<agent-name>` matches the attribute name in `agents.*` (e.g. `claude`,
  `codex`) — not the upstream package name, to keep the directory tree
  predictable from the config surface.

### Per-agent env var mapping

| Agent      | Env var           | Support in first cut |
|------------|-------------------|---------------------|
| `claude`   | `CLAUDE_CONFIG_DIR` | supported |
| `codex`    | `CODEX_HOME`        | supported |
| `gemini`   | `GEMINI_CLI_HOME`   | supported (gemini creates `.gemini/` inside the pointed-at path) |
| `opencode` | — no single override | **unsupported** — evaluation error |
| `pi`       | — unknown          | **unsupported** — evaluation error |

For agents without a clean single-env-var override, setting
`projectLocal = true` must produce a descriptive evaluation error naming the
agent and pointing users at this design document, rather than silently
half-isolating state. Example:

```
agents.opencode.projectLocal = true is not yet supported: opencode splits
config and auth across separate XDG directories and has no single
environment variable that relocates both. Track upstream or leave
projectLocal = false for now.
```

### Implementation shape

In `modules/agents.nix`, extend the `agents` attrset used to generate
submodules with each agent's env-var name (or `null` to mark unsupported):

```nix
agents = {
  claude = {
    upstreamName = "claude-code";
    description = "...";
    configDirEnvVar = "CLAUDE_CONFIG_DIR";
  };
  codex = {
    upstreamName = "codex";
    description = "...";
    configDirEnvVar = "CODEX_HOME";
  };
  gemini = {
    upstreamName = "gemini-cli";
    description = "...";
    configDirEnvVar = "GEMINI_CLI_HOME";
  };
  opencode = {
    upstreamName = "opencode";
    description = "...";
    configDirEnvVar = null;   # not yet supported
  };
  pi = {
    upstreamName = "pi";
    description = "...";
    configDirEnvVar = null;   # not yet supported
  };
};
```

The config section then, for each enabled agent with `projectLocal = true`:

1. Asserts `configDirEnvVar != null`; otherwise throws the evaluation error
   above.
2. Computes `path = "${config.devenv.root}/.devenv/state/agents/<name>"`.
3. Adds `env.<VAR> = path;` to the devenv shell environment.
4. Adds an `enterShell` snippet that runs `mkdir -p "$path"` so the first
   invocation of the agent does not fail on a missing directory.

All three of `env`, `enterShell`, and option definitions are merged across
agents using devenv/nixpkgs module-system merge rules — no bespoke plumbing.

### Interaction with the upstream `claude.code.*` module

None. The upstream integration writes project-committed files under
`.claude/` at the repo root and does not touch `CLAUDE_CONFIG_DIR`. A user
can simultaneously:

- Enable `agents.claude.enable = true; agents.claude.projectLocal = true;`
  (this module) — binaries + isolated user state.
- Enable `claude.code.enable = true;` + hooks/subagents/commands (upstream
  devenv module) — committed project config.

Both write to different locations and cooperate. The README should document
this explicitly.

## Error handling

The only new failure mode is asking for `projectLocal = true` on an
unsupported agent. This is a static configuration error and must fail at
evaluation time (via `assert` or `throw` in the module), not at runtime.

## Testing

- **Eval test:** enabling `projectLocal` on `claude`, `codex`, `gemini`
  evaluates successfully and produces the expected `env` attrs and
  `enterShell` lines.
- **Eval test:** enabling `projectLocal` on `opencode` or `pi` fails at
  evaluation with the documented error message.
- **Shell-level test (examples/):** extend (or add a sibling to) the
  existing `examples/default` with a variant that sets
  `agents.claude.projectLocal = true`; `devenv shell -c env | grep
  CLAUDE_CONFIG_DIR` prints the expected path, and the directory exists.
- Default path remains unset (`env` attrs unchanged) when `projectLocal` is
  left at its `false` default — covered implicitly by the existing example.

## Documentation

- New README section: "Per-project agent state" — explains what the flag
  does, the path it uses, and the cost (global user-level config is not
  visible in this shell).
- Cross-link to the upstream `claude.code.*` devenv integration as the
  right tool for project-level committed config, making clear the two
  features do not overlap.

## Future work (not in this change)

- Support for `opencode` (requires upstream config/auth-path survey or a
  wrapper approach that rewrites `XDG_DATA_HOME` scoped only to opencode).
- Support for `pi` (requires surveying pi's config/auth location).
- A top-level convenience like `agents.projectLocal = true;` that flips all
  enabled agents at once. Only worth adding if real usage shows repeated
  per-agent toggling.
- Per-agent path override, if and only if the fixed convention proves
  insufficient.
