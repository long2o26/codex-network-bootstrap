# Security Policy

## Reporting a Vulnerability

Please open a private security advisory on GitHub if the repository is hosted
there. If private advisories are unavailable, open an issue with minimal public
detail and ask for a secure contact path.

## Sensitive Data

Never publish generated deployment summaries or client profiles from a real
server. These files can contain credentials:

- `secrets/*.json`
- `mihomo-codex.yaml`

Rotate server credentials immediately if either file is accidentally exposed.

## Supported Environments

The server setup script targets Ubuntu/Debian servers. Other distributions are
not currently supported.
