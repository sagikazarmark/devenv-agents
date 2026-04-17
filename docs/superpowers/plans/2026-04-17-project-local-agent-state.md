# Project-local agent state — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in `agents.<name>.projectLocal` boolean that relocates each supported agent's per-user state (config, credentials, session history) from the user's global home directory (`~/.claude`, `~/.codex`, `~/.gemini`) into `$DEVENV_ROOT/.devenv/state/agents/<name>` — so the state lives inside the project tree and can be wiped, versioned, or isolated per project.

**Architecture:** One new per-agent option in `modules/agents.nix`. When set to `true`, the module adds an entry to `config.env` (agent-specific env var pointing at the project-local path) and appends a `mkdir -p` to `config.enterShell`. Agents that lack a clean single-env-var override (opencode, pi) are rejected via `config.assertions` with a descriptive error. Tests live as a sibling `examples/project-local/` plus CI smoke commands that read the resulting `env`.

**Tech Stack:** Nix (nixpkgs module system), devenv, `llm-agents.nix` flake input. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-04-17-project-local-agent-state-design.md`

---

## File map

- **Modify:** `modules/agents.nix` — extend the `agents` attrset and `mkAgent` helper; add `projectLocal` option; add config logic (env var, enterShell mkdir, assertions).
- **Create:** `examples/project-local/devenv.nix` — example enabling the flag for claude, codex, gemini.
- **Create:** `examples/project-local/devenv.yaml` — mirror of `examples/default/devenv.yaml`.
- **Modify:** `.github/workflows/ci.yaml` — add a CI job that builds the new example and asserts the env var appears in its shell.
- **Modify:** `README.md` — add a "Per-project agent state" section and cross-link to the upstream `claude.code.*` integration.

No new files in `modules/` or `flake.nix`. No `checks/` directory — we rely on examples + CI (spec's fallback option), per Testing section of the spec.

---

## Task 0: Verify risk assumptions before writing code

**Why:** The spec flags three risks that can invalidate the design. Settle them first — if any turns up a blocker, update the spec before proceeding.

**Files:** none modified.

- [ ] **Step 1: Verify `.devenv/` is gitignored in this repo**

Run:
```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
grep -F '.devenv' .gitignore
```

Expected output includes `.devenv*`. (Already present in this repo — just confirm it hasn't been changed.)

If missing, stop and add `.devenv*` to `.gitignore` before continuing.

- [ ] **Step 2: Check whether `config.devenv.state` is exposed by devenv's module system**

Grep the devenv source:
```bash
gh search code --repo cachix/devenv 'devenv.state' --limit 10
```

Also look at the options reference:
```bash
gh api repos/cachix/devenv/contents/src/modules/top-level.nix --jq '.content' | base64 -d | grep -A5 -E '(devenv\.state|state\s*=\s*lib\.mkOption)' | head -30
```

Record the result. If `config.devenv.state` is declared as an option (with a default value like `"${config.devenv.root}/.devenv/state"`), use it in Task 3. If it is only an environment variable with no Nix-side attribute, hardcode the path instead.

- [ ] **Step 3: Verify GC does not prune `.devenv/state/agents/<name>/`**

In a throwaway directory:
```bash
mkdir -p /tmp/devenv-gc-check && cd /tmp/devenv-gc-check
devenv init
mkdir -p .devenv/state/agents/claude
echo "canary" > .devenv/state/agents/claude/auth.json
devenv shell -c true
devenv gc
ls .devenv/state/agents/claude/auth.json && cat .devenv/state/agents/claude/auth.json
```

Expected: file still exists and contains `canary`.

If `devenv gc` removes the file, stop. Update the spec: either pick a different path or document the GC caveat. Do not proceed with the current design.

- [ ] **Step 4: Verify the scope of `CLAUDE_CONFIG_DIR`**

```bash
mkdir -p /tmp/claude-scope && CLAUDE_CONFIG_DIR=/tmp/claude-scope claude --version
# Then briefly interact or just inspect:
ls -la /tmp/claude-scope
```

Record what directories/files Claude Code creates. Confirm it includes at minimum: settings, credentials, session history, plugins. Nice-to-have: `projects/`, `todos/`, user-level `agents/`, user-level `commands/`.

If the env var does not relocate the expected files, soften the option description in Task 2 to list only what actually moves. Otherwise proceed with the wording as designed.

- [ ] **Step 5: Record findings in a short note**

Write a 5-line note somewhere (commit message of the first real task, or a transient `NOTES.md` you delete later) capturing:
- `.devenv/` gitignored: yes / no
- `config.devenv.state` exposed: yes / no → which form of `stateRoot` to use
- GC preserves `.devenv/state/`: yes / no
- `CLAUDE_CONFIG_DIR` scope: list what relocates

This drives decisions in later tasks.

---

## Task 1: Extend the `agents` attrset with `configDirEnvVar`

**Goal:** Add a data-only field to each agent's spec entry, without yet wiring any behavior. This is a pure refactor — the helper ignores the new field for now.

**Files:**
- Modify: `modules/agents.nix`

- [ ] **Step 1: Read the current module**

```bash
cat modules/agents.nix
```

Confirm the current `agents` attrset has five entries (claude, codex, opencode, gemini, pi), each with `upstreamName` and `description`.

- [ ] **Step 2: Add `configDirEnvVar` to every agent entry**

Edit `modules/agents.nix`. Replace the `agents = { ... };` attrset with:

```nix
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
```

- [ ] **Step 3: Extend `mkAgent` to accept (but ignore) `configDirEnvVar`**

In `modules/agents.nix`, change the `mkAgent` definition from:

```nix
  mkAgent = { upstreamName, description }: {
    enable = lib.mkEnableOption description;

    package = lib.mkOption {
      ...
    };
  };
```

to:

```nix
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
```

The only change is the destructuring pattern: `{ upstreamName, description }` → `{ upstreamName, description, configDirEnvVar }`. The body is unchanged — Nix will simply ignore `configDirEnvVar` for now.

- [ ] **Step 4: Verify the flake still evaluates**

```bash
nix flake check
```

Expected: no errors. No behavior has changed — this is a pure refactor.

- [ ] **Step 5: Verify the example still builds**

```bash
cd examples/default
devenv build shell
cd -
```

Expected: builds successfully, same output as before.

- [ ] **Step 6: Commit**

```bash
git add modules/agents.nix
git commit -m "refactor(agents): add configDirEnvVar field to agent specs

Threads a new data-only field through the mkAgent helper without wiring
any behavior yet. Claude/Codex/Gemini get their respective env var names;
opencode/pi are marked null to flag that single-env-var relocation isn't
available for them.

Design: docs/superpowers/specs/2026-04-17-project-local-agent-state-design.md"
```

---

## Task 2: Add the `projectLocal` option to each agent submodule

**Goal:** Surface the new boolean on every agent, but do not yet translate it into shell env or enterShell. Keep behavior unchanged so this commit is reviewable in isolation.

**Files:**
- Modify: `modules/agents.nix`

- [ ] **Step 1: Add the `projectLocal` option to `mkAgent`'s return value**

Edit `modules/agents.nix`. In the `mkAgent` helper, after the `package = lib.mkOption { ... };` block, add a new option. The final helper should look like:

```nix
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
```

- [ ] **Step 2: Verify the option is visible**

```bash
nix eval --impure --json --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import <nixpkgs> {};
    module = flake.devenvModules.default;
    evaluated = pkgs.lib.evalModules {
      modules = [
        module
        ({ ... }: {
          _module.args = {
            inputs = { llm-agents = { packages.${pkgs.system} = { claude-code = pkgs.hello; codex = pkgs.hello; opencode = pkgs.hello; gemini-cli = pkgs.hello; pi = pkgs.hello; }; }; };
            pkgs = pkgs;
          };
        })
      ];
    };
  in
    evaluated.options.agents.claude.projectLocal.default
'
```

Expected output: `false`

If this errors with "module argument not defined" for `config.devenv.root`, the module expects `config.devenv.*` too — that's fine; the next task adds the config logic that depends on it, and in those cases we will test via examples instead of `evalModules`.

If `evalModules` complains about `config` access, skip this step — Task 3 will test behavior via a real devenv example.

- [ ] **Step 3: Verify `nix flake check` still passes**

```bash
nix flake check
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add modules/agents.nix
git commit -m "feat(agents): add projectLocal option (surface only)

Adds the option to every agent's submodule with default = false. Does not
yet translate the flag into shell env or enterShell behavior — that lands
in the next commit so the option surface can be reviewed independently."
```

---

## Task 3: Wire `projectLocal` to `env` and `enterShell`, and reject unsupported agents

**Goal:** Produce the actual behavior. When `projectLocal = true` on a supported agent, set the env var and create the directory. When set on opencode or pi, fail evaluation with a descriptive message.

**Files:**
- Modify: `modules/agents.nix`

- [ ] **Step 1: Pick the `stateRoot` form based on Task 0 findings**

From the Task 0 note:
- If `config.devenv.state` is exposed by devenv, use it.
- Otherwise fall back to `"${config.devenv.root}/.devenv/state"`.

For the rest of this task, pseudocode uses `stateRoot`. Replace with whichever form Task 0 confirmed.

- [ ] **Step 2: Add helper bindings inside the `let ... in` block**

Edit `modules/agents.nix`. Inside the existing `let` block (after the `agents = { ... };` attrset and before the final `in { ... }`), add:

```nix
  # Path used when `projectLocal = true`.
  # PREFER: config.devenv.state if exposed; OTHERWISE: "${config.devenv.root}/.devenv/state"
  stateRoot = config.devenv.state or "${config.devenv.root}/.devenv/state";

  projectLocalPath = name: "${stateRoot}/agents/${name}";

  # Agents that are both enabled and have projectLocal toggled on.
  activeProjectLocal = lib.filterAttrs
    (name: _spec:
      config.agents.${name}.enable && config.agents.${name}.projectLocal)
    agents;

  # Supported subset (configDirEnvVar != null). Used to build env/enterShell.
  activeProjectLocalSupported = lib.filterAttrs
    (_name: spec: spec.configDirEnvVar != null)
    activeProjectLocal;
```

**Important:** use `config.devenv.state or ...` only if Task 0 confirmed `config.devenv.state` exists. If Task 0 showed it does NOT exist, hardcode:

```nix
  stateRoot = "${config.devenv.root}/.devenv/state";
```

(`foo.bar or default` only works if `bar` is a legitimate attrpath lookup; for a non-existent module option it may still fail. Pick whichever form you confirmed works.)

- [ ] **Step 3: Replace the `{ ... }` body after `in` with a config that also sets env, enterShell, and assertions**

The current body is:

```nix
{
  options.agents = lib.mapAttrs (_name: spec: mkAgent spec) agents;

  config.packages = lib.concatLists (lib.mapAttrsToList
    (name: _spec:
      lib.optional config.agents.${name}.enable config.agents.${name}.package)
    agents);
}
```

Replace with:

```nix
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
```

- [ ] **Step 4: Manually verify the supported-agent path**

In a scratch directory outside the repo:

```bash
mkdir -p /tmp/pl-test && cd /tmp/pl-test
cat > devenv.yaml <<'EOF'
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  llm-agents:
    url: github:numtide/llm-agents.nix
    inputs:
      nixpkgs:
        follows: nixpkgs
  devenv-agents:
    url: path:/Users/mark/Projects/sagikazarmark/devenv-agents
imports:
  - devenv-agents
EOF

cat > devenv.nix <<'EOF'
{ ... }:
{
  agents.claude = {
    enable = true;
    projectLocal = true;
  };
}
EOF

devenv shell -c 'echo "$CLAUDE_CONFIG_DIR"'
devenv shell -c 'test -d "$CLAUDE_CONFIG_DIR" && echo DIR_EXISTS'
```

Expected:
- First command prints an absolute path ending in `.devenv/state/agents/claude`.
- Second command prints `DIR_EXISTS`.

- [ ] **Step 5: Manually verify the unsupported-agent error path**

In the same `/tmp/pl-test`, overwrite `devenv.nix`:

```bash
cat > devenv.nix <<'EOF'
{ ... }:
{
  agents.opencode = {
    enable = true;
    projectLocal = true;
  };
}
EOF

devenv shell -c true
```

Expected: evaluation fails. The error message must include the text "`agents.opencode.projectLocal = true is not yet supported`" and reference the spec doc path.

- [ ] **Step 6: Verify default-off parity**

Overwrite `devenv.nix` with the original `examples/default/devenv.nix` (all `enable = true`, no `projectLocal`):

```bash
cat > devenv.nix <<'EOF'
{ ... }:
{
  agents.claude.enable = true;
  agents.codex.enable = true;
  agents.opencode.enable = true;
  agents.gemini.enable = true;
  agents.pi.enable = true;
}
EOF

devenv shell -c 'env | grep -E "^(CLAUDE_CONFIG_DIR|CODEX_HOME|GEMINI_CLI_HOME)=" || echo "none set"'
```

Expected: prints `none set`. None of the three env vars should be exported when `projectLocal` is unset or `false`.

- [ ] **Step 7: Clean up scratch**

```bash
rm -rf /tmp/pl-test
```

- [ ] **Step 8: Back in the repo, run flake checks**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
nix flake check
cd examples/default && devenv build shell && cd -
```

Expected: both succeed.

- [ ] **Step 9: Commit**

```bash
git add modules/agents.nix
git commit -m "feat(agents): implement projectLocal wiring

Translates projectLocal = true into:
- env.<VAR> set to \$DEVENV_ROOT/.devenv/state/agents/<name>
- enterShell snippet that creates that directory
- config.assertions rejecting the flag for opencode/pi with a descriptive
  error, since neither has a single env var that relocates both config
  and auth."
```

---

## Task 4: Add `examples/project-local/` covering the new flag

**Goal:** A standalone example that demonstrates and regression-tests the flag. CI will build it on every PR.

**Files:**
- Create: `examples/project-local/devenv.yaml`
- Create: `examples/project-local/devenv.nix`
- Modify: `.github/workflows/ci.yaml`

- [ ] **Step 1: Create `examples/project-local/devenv.yaml`**

This mirrors `examples/default/devenv.yaml` exactly (same pattern: relative `path:../..` input so the example uses the local repo's module):

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
    url: path:../..
imports:
  - devenv-agents
```

- [ ] **Step 2: Create `examples/project-local/devenv.nix`**

```nix
{ ... }:

{
  agents.claude = {
    enable = true;
    projectLocal = true;
  };

  agents.codex = {
    enable = true;
    projectLocal = true;
  };

  agents.gemini = {
    enable = true;
    projectLocal = true;
  };
}
```

Note: opencode and pi intentionally omitted — the example must not trigger the unsupported-agent assertion.

- [ ] **Step 3: Verify the example builds**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents/examples/project-local
devenv build shell
```

Expected: builds successfully.

- [ ] **Step 4: Verify the env vars and directories**

From the same directory:

```bash
devenv shell -c '
  set -e
  for var in CLAUDE_CONFIG_DIR CODEX_HOME GEMINI_CLI_HOME; do
    printf "%s=%s\n" "$var" "${!var}"
    test -n "${!var}"
    test -d "${!var}"
  done
  echo OK
'
```

Expected: each `VAR=/...path...` line prints, and the last line prints `OK`. The paths should end in `.devenv/state/agents/{claude,codex,gemini}` respectively.

```bash
cd -
```

- [ ] **Step 5: Add a CI job that builds and smoke-tests the new example**

Edit `.github/workflows/ci.yaml`. After the existing `example` job (the final job in the file), append:

```yaml

  example-project-local:
    name: Example (project-local)
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

      - name: Install Nix
        uses: cachix/install-nix-action@616559265b40713947b9c190a8ff4b507b5df49b # v31.10.4
        with:
          github_access_token: ${{ github.token }}

      - name: Configure cachix
        uses: cachix/cachix-action@1eb2ef646ac0255473d23a5907ad7b04ce94065c # v17
        with:
          name: devenv

      - name: Install devenv
        shell: bash
        run: nix profile add --accept-flake-config github:cachix/devenv/latest#devenv
        env:
          NIX_CONFIG: "accept-flake-config = true"

      - name: Build example shell
        working-directory: examples/project-local
        run: devenv build shell

      - name: Smoke-test env vars
        working-directory: examples/project-local
        run: |
          devenv shell -c '
            set -euo pipefail
            for var in CLAUDE_CONFIG_DIR CODEX_HOME GEMINI_CLI_HOME; do
              val="${!var}"
              [ -n "$val" ] || { echo "$var not set"; exit 1; }
              [ -d "$val" ] || { echo "$var directory missing: $val"; exit 1; }
              case "$val" in
                */.devenv/state/agents/claude|*/.devenv/state/agents/codex|*/.devenv/state/agents/gemini) ;;
                *) echo "$var has unexpected suffix: $val"; exit 1 ;;
              esac
            done
            echo "all env vars set and directories exist"
          '
```

Double-check indentation matches the existing YAML (2 spaces).

- [ ] **Step 6: Commit**

```bash
git add examples/project-local/ .github/workflows/ci.yaml
git commit -m "test: add project-local example and CI smoke check

Adds examples/project-local/ with projectLocal = true for claude, codex,
and gemini, plus a CI job that builds the example shell and asserts that
CLAUDE_CONFIG_DIR, CODEX_HOME, and GEMINI_CLI_HOME are set to paths ending
in .devenv/state/agents/<name> and that those directories exist."
```

---

## Task 5: Update README

**Goal:** Document the new option, its tradeoffs, and its relationship to the upstream `claude.code.*` devenv integration.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the current README**

```bash
cat README.md
```

Locate the "Supported agents" and "Overriding the package for an agent" sections. The new section belongs between "Overriding the package for an agent" and "Binary cache".

- [ ] **Step 2: Insert the new section**

Open `README.md`. Find the line that starts with `## Binary cache`. Immediately before it, insert the content below. (The fence below uses four backticks so the inner triple-backtick code blocks render — copy only the content, not the four-backtick fence itself.)

````markdown
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
(Claude plugins, custom sub-agents, CLAUDE.md, etc.) is **not** visible
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
````

- [ ] **Step 3: Render-check**

```bash
grep -n '^##' README.md
```

Expected: the ordering runs `## Usage`, `## Supported agents`, `## Overriding the package for an agent`, `## Per-project agent state`, `## Binary cache`, `## Example`, `## License`. Confirm visually.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document agents.<name>.projectLocal

Adds a README section explaining the new flag, its target path, its cost
(global user-level config hidden inside the shell), and its relationship
to the upstream claude.code.* devenv integration."
```

---

## Done

After Task 5, the feature is implemented, tested, and documented. Final sanity check:

- [ ] **Run the full check suite from a clean state**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
nix flake check
(cd examples/default && devenv build shell)
(cd examples/project-local && devenv build shell)
(cd examples/project-local && devenv shell -c 'echo "$CLAUDE_CONFIG_DIR"')
```

Expected: all four commands succeed. The last one prints a path ending in `.devenv/state/agents/claude`.

- [ ] **Review the commit log**

```bash
git log --oneline main..HEAD
```

Expected: five commits matching the titles from Tasks 1–5 (Task 0 produced no commits — it was a verification-only phase).

Done. Invoke the finishing-a-development-branch skill to decide how to integrate (PR, direct merge, etc.).
