# Security Policy

## Reporting

If you find a security issue, please do not open a public issue with exploit details.
Contact the maintainer through the public contact listed in the repository profile, or open an issue asking for a private channel.

## Scope

Relevant areas:

- local database and file storage
- backup encryption and decryption
- material import and text parsing
- notification / reminder handling
- permission use

## Secrets

This repository must never contain:

- signing certificates or private keys
- provisioning profiles
- AppGallery Connect sessions or cookies
- API keys
- user data or backups

If any such material is found, treat it as compromised and rotate it.
