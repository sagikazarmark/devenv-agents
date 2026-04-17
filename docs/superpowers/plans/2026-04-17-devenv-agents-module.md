# devenv-agents Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable devenv module at `github:sagikazarmark/devenv-agents` that lets consumers enable AI coding agents in a devshell via `agents.<name>.enable = true`, with packages sourced by default from [numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix).

**Architecture:** A devenv module file at `modules/agents.nix` defines per-agent `enable` + `package` options using Nix's standard module system. The root `devenv.nix` imports that module. The repo's own `devenv.yaml` declares `llm-agents.nix` as an input so it is resolved transitively when a consumer adds `devenv-agents` as an input. A minimal consumer example under `examples/default/` serves as an end-to-end smoke test.

**Tech Stack:** Nix, devenv, [numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix).

**Spec:** `docs/superpowers/specs/2026-04-17-devenv-agents-module-design.md`

**Testing strategy:** Nix modules don't have traditional unit tests. The validation loop is:
1. `nix flake check` — syntactic/eval validation of the flake.
2. Running `devenv build shell` inside `examples/default/` — integration test that the module evaluates and enabled agents produce a buildable shell.
3. Running `devenv shell -- <agent> --version` (or `--help`) — confirms the binary is actually in `PATH`.

---

## Task 1: Scaffold repo basics

**Files:**
- Create: `.gitignore`
- Create: `.editorconfig`
- Create: `LICENSE`
- Create: `README.md`

- [ ] **Step 1: Write `.gitignore`**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/.gitignore`:

```
.devenv*
.direnv
/devenv.local.nix

# Nix
result
result-*
```

- [ ] **Step 2: Write `.editorconfig`**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/.editorconfig`:

```
root = true

[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8
indent_style = space
indent_size = 2
trim_trailing_whitespace = true

[*.md]
trim_trailing_whitespace = false
```

- [ ] **Step 3: Write `LICENSE` (MIT)**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/LICENSE`:

```
MIT License

Copyright (c) 2026 Mark Sagi-Kazar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Write README stub**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/README.md`:

```markdown
# devenv-agents

A reusable [devenv](https://devenv.sh) module for AI coding agents, backed by
[numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix).

> Full usage docs are written in Task 5 of the implementation plan.
```

- [ ] **Step 5: Commit**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
git add .gitignore .editorconfig LICENSE README.md
git commit -m "Scaffold repo (gitignore, editorconfig, license, readme stub)"
```

---

## Task 2: Add flake and devenv inputs

**Files:**
- Create: `flake.nix`
- Create: `devenv.yaml`

- [ ] **Step 1: Write `flake.nix`**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/flake.nix`:

```nix
{
  description = "Reusable devenv module for AI coding agents";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, ... }: {
    # Expose the module for flake-native consumers. The primary distribution
    # path is `devenv.yaml` imports (see README).
    devenvModules.default = ./modules/agents.nix;
  };
}
```

Note: `modules/agents.nix` does not exist yet; it is created in Task 3. The
flake will still evaluate because `outputs` only references the path literally
without reading it.

- [ ] **Step 2: Write `devenv.yaml`**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/devenv.yaml`:

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
```

- [ ] **Step 3: Stage files so Nix sees them**

Nix flake evaluation only sees git-tracked files when the working tree has
been `git add`-ed. Stage them before running flake commands:

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
git add flake.nix devenv.yaml
```

- [ ] **Step 4: Verify flake evaluates and lock inputs**

Run:

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
nix flake metadata
```

Expected: no errors, prints flake metadata including `nixpkgs` and
`llm-agents` inputs. This also produces `flake.lock`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
git add flake.nix flake.lock devenv.yaml
git commit -m "Add flake.nix and devenv.yaml with nixpkgs + llm-agents inputs"
```

Note: `devenv.lock` is not produced until a `devenv` command runs (Task 3);
it will be committed then.

---

## Task 3: Minimal module with just the `claude` agent + passing smoke test

This task establishes the full end-to-end pipeline (root `devenv.nix` → module
→ example consumer → running `claude`) with a single agent. Task 4 extends the
module with the remaining four agents once the pipeline is proven.

**Files:**
- Create: `modules/agents.nix`
- Create: `devenv.nix`
- Create: `examples/default/devenv.yaml`
- Create: `examples/default/devenv.nix`

- [ ] **Step 1: Write `modules/agents.nix` with just `claude`**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/modules/agents.nix`:

```nix
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
```

- [ ] **Step 2: Write root `devenv.nix` that imports the module**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/devenv.nix`:

```nix
{ ... }:

{
  imports = [ ./modules/agents.nix ];
}
```

- [ ] **Step 3: Write `examples/default/devenv.yaml`**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/examples/default/devenv.yaml`:

```yaml
# yaml-language-server: $schema=https://devenv.sh/devenv.schema.json
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  devenv-agents:
    url: path:../..
imports:
  - devenv-agents
```

- [ ] **Step 4: Write `examples/default/devenv.nix`**

Create `/Users/mark/Projects/sagikazarmark/devenv-agents/examples/default/devenv.nix`:

```nix
{ ... }:

{
  agents.claude.enable = true;
}
```

- [ ] **Step 5: Stage all new files so Nix sees them**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
git add modules/agents.nix devenv.nix examples/default/devenv.yaml examples/default/devenv.nix
```

- [ ] **Step 6: Build the example shell (integration test)**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents/examples/default
devenv build shell
```

Expected: a successful build. The output derivation is a shell with
`claude-code` in its `PATH`.

**Troubleshooting — `inputs.llm-agents` not found.** If the build fails with
an error like `attribute 'llm-agents' missing` in `modules/agents.nix`, the
transitive-inputs assumption (see spec "Key assumption to verify") is wrong.
Fall back by adding `llm-agents` explicitly to `examples/default/devenv.yaml`:

```yaml
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

Re-run `devenv build shell`. If this fallback works, the README (Task 5) must
document that consumers need to declare `llm-agents` themselves.

- [ ] **Step 7: Verify the `claude` binary is in the shell**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents/examples/default
devenv shell -- claude --version
```

Expected: prints a version string (something like `1.x.x (Claude Code)`),
exit 0. If `claude` isn't found, the module's `config.packages` wiring is
wrong — fix and rebuild.

- [ ] **Step 8: Commit**

Include the lock files produced by the devenv build:

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
git add modules/agents.nix devenv.nix devenv.lock \
        examples/default/devenv.yaml examples/default/devenv.nix examples/default/devenv.lock
git commit -m "Add agents module with claude + smoke-test example"
```

---

## Task 4: Add the remaining four agents

**Files:**
- Modify: `modules/agents.nix`
- Modify: `examples/default/devenv.nix`

- [ ] **Step 1: Replace `modules/agents.nix` with the full agent list**

Overwrite `/Users/mark/Projects/sagikazarmark/devenv-agents/modules/agents.nix`:

```nix
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
```

Invariant to sanity-check before moving on: every attr name in `agents`
(`claude`, `codex`, `opencode`, `gemini`, `pi`) matches the option surface the
consumer writes (`agents.claude.enable`, etc.); every `upstreamName`
(`claude-code`, `codex`, `opencode`, `gemini-cli`, `pi`) matches an attribute
in `inputs.llm-agents.packages.${pkgs.system}`.

- [ ] **Step 2: Update `examples/default/devenv.nix` to enable all agents**

Overwrite `/Users/mark/Projects/sagikazarmark/devenv-agents/examples/default/devenv.nix`:

```nix
{ ... }:

{
  agents.claude.enable = true;
  agents.codex.enable = true;
  agents.opencode.enable = true;
  agents.gemini.enable = true;
  agents.pi.enable = true;
}
```

- [ ] **Step 3: Rebuild the example shell**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents/examples/default
devenv build shell
```

Expected: successful build. If any agent's package doesn't exist in
`llm-agents.nix` under the assumed upstream name, fix the `upstreamName` in
`modules/agents.nix` (check `nix eval --raw 'github:numtide/llm-agents.nix#<name>.name'`
or browse the repo's `packages/` dir) and rebuild.

- [ ] **Step 4: Verify each binary is on `PATH`**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents/examples/default
for bin in claude codex opencode gemini pi; do
  devenv shell -- "$bin" --version 2>&1 | head -1 || echo "FAIL: $bin"
done
```

Expected: each loop iteration prints a version string. Any `FAIL:` line means
that agent's upstream package doesn't expose the binary under the name the
option implies — investigate its `meta.mainProgram` in llm-agents.nix and
either rename the option or (if the binary name differs from the option name)
accept that for now and document the exact command in the README.

- [ ] **Step 5: Commit**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
git add modules/agents.nix examples/default/devenv.nix examples/default/devenv.lock
git commit -m "Add codex, opencode, gemini, pi agents"
```

---

## Task 5: Write the README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace README with full usage docs**

Overwrite `/Users/mark/Projects/sagikazarmark/devenv-agents/README.md`:

````markdown
# devenv-agents

A reusable [devenv](https://devenv.sh) module for AI coding agents, backed by
[numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix).

## Usage

Add the module to your project's `devenv.yaml`:

```yaml
# yaml-language-server: $schema=https://devenv.sh/devenv.schema.json
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  devenv-agents:
    url: github:sagikazarmark/devenv-agents
imports:
  - devenv-agents
```

Then enable the agents you want in `devenv.nix`:

```nix
{ ... }:
{
  agents.claude.enable = true;
  agents.codex.enable = true;
}
```

Run `devenv shell` and the enabled agents are on `PATH`.

## Supported agents

| Option                    | Upstream package           | Binary     |
|---------------------------|----------------------------|------------|
| `agents.claude.enable`    | `llm-agents.claude-code`   | `claude`   |
| `agents.codex.enable`     | `llm-agents.codex`         | `codex`    |
| `agents.opencode.enable`  | `llm-agents.opencode`      | `opencode` |
| `agents.gemini.enable`    | `llm-agents.gemini-cli`    | `gemini`   |
| `agents.pi.enable`        | `llm-agents.pi`            | `pi`       |

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

## How it works

Each option adds its `package` to the devshell's `packages` list when `enable`
is true. Default packages come from `inputs.llm-agents.packages.${system}.*`,
which is declared in this repo's `devenv.yaml` and inherited transitively when
you add `devenv-agents` as an input.

## Example

See `examples/default/` for a minimal working consumer.

## License

MIT — see [LICENSE](./LICENSE).
````

- [ ] **Step 2: Commit**

```bash
cd /Users/mark/Projects/sagikazarmark/devenv-agents
git add README.md
git commit -m "Write README with usage docs"
```

---

## Done

After Task 5: the repo contains a working, tested reusable devenv module.
A consumer can add `github:sagikazarmark/devenv-agents` to their
`devenv.yaml` inputs, import it, and toggle agents on/off with `agents.*.enable`.
