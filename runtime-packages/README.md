# Bundled Agent Runtime Packages

These archives are release-build inputs, not development dependencies.

- `node-v24.18.0-win-x64.zip`: portable Node.js from nodejs.org.
- `claude-code-2.1.211-win-x64.zip`: Claude CLI 2.1.211 with its Windows x64 native launcher.

The release workflow extracts both archives into `nodejs/` and `claude-cli/`,
then verifies the launchers before assembling the installer.
