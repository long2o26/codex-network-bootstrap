# Contributing

Thanks for considering a contribution.

## Development Setup

This repository has no runtime npm dependencies. Use Node.js 20+.

```bash
npm test
```

## Pull Request Checklist

- Keep generated credentials out of git.
- Run `npm test`.
- Update `README.md` when a command, port, file path, or default region changes.
- Keep scripts compatible with Ubuntu/Debian unless the change explicitly adds a
  new platform path.

## Security Boundaries

Do not include:

- Private keys.
- Server IPs from private deployments.
- Generated `secrets/*.json` files.
- Generated `mihomo-codex.yaml` files.
- API keys or account tokens.

## Maintainer Notes

The project favors small, readable shell and Node.js scripts over complex
frameworks. If a new dependency is needed, include the reason in the pull
request.
