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
- **Per-project experimentation.** Trying a different model configuration,
  plugin set, or sub-agent definition without polluting global state.

`devenv` already provides a conventional location for per-project state:
`$DEVENV_STATE` (`$DEVENV_ROOT/.devenv/state`), conventionally gitignored
(see Risks below). Several of the supported agents (not all — see the env
var mapping below) expose a single environment variable that relocates
their per-user state. Wiring these together is a good fit for this module.

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
  history). Some agents expose finer-grained overrides (e.g. codex's
  `CODEX_SQLITE_HOME` for just the state DB); we ignore those and use the
  single top-level env var that moves everything. Keeping a uniform "one
  dir per agent" mental model is worth more than the flexibility.
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
| `gemini`   | `GEMINI_CLI_HOME`   | supported (see note below) |
| `opencode` | — no single override | **unsupported** — evaluation error |
| `pi`       | — unknown          | **unsupported** — evaluation error |

**Gemini quirk.** `GEMINI_CLI_HOME` is a *parent* directory; the CLI
creates a `.gemini/` subdirectory inside it. So for gemini specifically the
actual data lives at `$DEVENV_ROOT/.devenv/state/agents/gemini/.gemini/`
— one level deeper than the other agents. We still point
`GEMINI_CLI_HOME` at `.../agents/gemini` (not `.../agents/`) to keep the
per-agent namespace clean and avoid gemini scattering `.gemini/` next to
other agents' directories. README must call this out so users are not
surprised by the extra nesting.

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

Two changes in `modules/agents.nix`:

1. Extend the `agents` attrset used to generate submodules with each
   agent's env-var name (or `null` to mark unsupported).
2. Extend the `mkAgent` helper (which currently takes
   `{ upstreamName, description }` and returns `{ enable, package }`) to
   also accept `configDirEnvVar` and add the `projectLocal` option to the
   submodule it produces.

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
2. Computes `path = "${stateRoot}/agents/${name}"` where `stateRoot` is
   `config.devenv.state` if devenv exposes that attribute (preferred, so
   we auto-follow any upstream convention change) or
   `"${config.devenv.root}/.devenv/state"` as a fallback, and `name` is
   the attribute name bound by `lib.mapAttrs` (e.g. `"claude"`).
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

## Risks to verify during implementation

- **Garbage collection.** If `devenv gc` or `nix-collect-garbage` prunes
  anything under `.devenv/state/`, the user's auth tokens and session
  history get wiped without warning — breaking the feature the first time
  a user runs GC. The implementation plan must verify GC behavior against
  `.devenv/state/agents/<name>/` on a real devenv install before we ship.
  If GC does touch that path, we need either a different location, a
  documented caveat, or a GC-exclusion mechanism.
- **Gitignore coverage.** The spec assumes `.devenv/` is conventionally
  gitignored by devenv itself. Verify on a fresh project; if not, the
  implementation must add `.devenv/` to the repo's gitignore or document
  that users must do so.
- **Full scope of `CLAUDE_CONFIG_DIR`.** Docs explicitly list settings,
  credentials, session history, and plugins. Verify that `projects/`,
  `todos/`, user-level `agents/`, and user-level `commands/` also relocate
  — otherwise the claim "moves everything" in the option description is
  misleading and needs softening.

## Testing

The repo currently has no `checks/` or `tests/` directory — coverage today
is limited to `examples/default/` evaluating via CI. This design introduces
evaluation-time branching (the `projectLocal` assertion) that should be
tested without requiring a running agent. The implementation plan must
choose one of:

1. **Add a minimal `checks/` attribute** to `flake.nix` that imports
   `modules/agents.nix` with various option combinations and runs
   `nix flake check`. Preferred — catches regressions automatically.
2. **Add sibling examples** under `examples/` covering the projectLocal
   paths, plus a CI job that runs `devenv shell -c true` on each. Weaker
   but zero new scaffolding.

Regardless of harness, the cases to cover are:

- Enabling `projectLocal` on `claude`, `codex`, or `gemini` evaluates
  successfully and produces an `env.<VAR>` attribute pointing at
  `$DEVENV_ROOT/.devenv/state/agents/<name>` and an `enterShell` line that
  creates the directory.
- Enabling `projectLocal` on `opencode` or `pi` fails at evaluation with the
  documented error message.
- With `projectLocal = false` (the default), no env-var additions or
  `enterShell` lines are produced — verified by evaluating the module with
  the option explicitly `false` and again with the option unset, and
  asserting the resulting `env` and `enterShell` attrs are identical.
- Shell-level smoke check: in a configuration with
  `agents.claude.projectLocal = true`, `devenv shell -c env` prints a
  `CLAUDE_CONFIG_DIR` whose value is an absolute path ending in
  `.devenv/state/agents/claude`, and that directory exists on disk.

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
