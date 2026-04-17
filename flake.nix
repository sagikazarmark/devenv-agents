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
