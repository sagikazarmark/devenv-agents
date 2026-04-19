{
  description = "Reusable devenv module for AI coding agents";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };
  };

  outputs =
    { ... }:
    {
      # Expose the module for flake-native consumers. The primary distribution
      # path is `devenv.yaml` imports (see README).
      devenvModules.default = ./modules/agents.nix;
    };
}
