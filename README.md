# Codex Network Bootstrap

Self-hosted network bootstrap scripts for developers who want a stable Codex,
OpenAI, and GitHub development path from supported regions.

The project deploys two Ubuntu nodes, currently optimized for Tokyo and
Singapore, and generates a mihomo-compatible client profile with automatic
latency testing and fallback.

## What It Does

- Deploys `Xray VLESS + REALITY + Vision` on TCP 443.
- Deploys `Hysteria2` on UDP 8443 as a secondary transport.
- Creates a non-root sudo user and can disable SSH password login after a public
  key is installed.
- Exports local node summaries into `secrets/*.json`.
- Generates a `mihomo-codex.yaml` profile with rules for OpenAI, ChatGPT,
  Codex-related domains, GitHub, and common developer CDNs.
- Keeps generated credentials out of version control.

## Why This Exists

Codex work often depends on several services being reachable with low latency:
OpenAI, ChatGPT, GitHub, package registries, and documentation sites. This
project packages the repeatable parts of setting up two lightweight developer
egress nodes and a client routing profile, so maintainers can spend less time
debugging network drift.

The default topology is:

- Primary node: Tokyo, Japan
- Backup node: Singapore
- Client: mihomo/Clash-compatible desktop client

Japan and Singapore are preferred here because they are commonly available cloud
regions and are in OpenAI-supported geography. Do not use unsupported regions as
the OpenAI/Codex egress location.

## Requirements

- Two Ubuntu 24.04 LTS servers.
- SSH access with a local public key, for example `~/.ssh/id_ed25519.pub`.
- Local Node.js 20+ for generating the mihomo profile.
- A mihomo-compatible client such as Clash Verge Rev, FlClash, or Mihomo Party.

Recommended firewall openings:

- SSH: TCP 22, ideally restricted to your own public IP.
- Xray: TCP 443.
- Hysteria2: UDP 8443.

## Quick Start

Deploy Tokyo:

```bash
chmod +x scripts/deploy-node.sh server/setup-node.sh

./scripts/deploy-node.sh \
  --host ubuntu@TOKYO_PUBLIC_IP \
  --node-name tokyo \
  --server-ip TOKYO_PUBLIC_IP \
  --ssh-public-key-file ~/.ssh/id_ed25519.pub
```

Deploy Singapore:

```bash
./scripts/deploy-node.sh \
  --host ubuntu@SINGAPORE_PUBLIC_IP \
  --node-name singapore \
  --server-ip SINGAPORE_PUBLIC_IP \
  --ssh-public-key-file ~/.ssh/id_ed25519.pub
```

Generate the mihomo profile:

```bash
node client/generate-mihomo-config.mjs \
  --tokyo secrets/tokyo.json \
  --singapore secrets/singapore.json \
  --out mihomo-codex.yaml
```

Import `mihomo-codex.yaml` into your client and select `AUTO-CODEX`.

## Validation

Run local checks:

```bash
npm test
```

Check server ports after deployment:

```bash
nc -vz TOKYO_PUBLIC_IP 443
nc -vz SINGAPORE_PUBLIC_IP 443
```

UDP 8443 should be validated from the mihomo client because a basic TCP port
probe does not test Hysteria2.

Target behavior:

- Tokyo VLESS usually stays below 200 ms.
- Singapore acts as a backup when Tokyo routes degrade.
- If both regions are consistently above 250 ms during peak hours, test Seoul or
  another supported nearby cloud region and replace the weaker node.

## Generated Files

The deploy script writes sensitive summaries to:

```text
secrets/<node-name>.json
```

The client generator writes:

```text
mihomo-codex.yaml
```

Both paths are intentionally ignored by git.

## Rollback

Before importing a new profile, back up your current mihomo/Clash profile.

To disable services on a server:

```bash
sudo systemctl disable --now xray
sudo systemctl disable --now hysteria-server.service
```

## Project Status

This is an early open-source release candidate. The scripts are intentionally
small and auditable. Contributions are welcome for:

- Additional supported cloud regions.
- Safer config validation.
- More client profile templates.
- Better latency benchmark reporting.
- CI checks for generated mihomo YAML.

## References

- Xray-core and installer: https://github.com/XTLS/Xray-install
- Hysteria2: https://github.com/apernet/hysteria
- mihomo: https://github.com/MetaCubeX/mihomo
- MetaCubeX rules data: https://github.com/MetaCubeX/meta-rules-dat
