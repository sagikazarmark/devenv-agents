{ ... }:

{
  # This example exists to verify that setting projectLocal = true on an
  # unsupported agent (opencode) fails at evaluation with a descriptive
  # error message. The CI job example-project-local-unsupported builds
  # this example and expects the build to fail.
  agents.opencode = {
    enable = true;
    projectLocal = true;
  };
}
