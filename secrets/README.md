# Release secrets (local / CI only)

This directory holds signing material that must **never** be committed.

| File | Purpose |
| --- | --- |
| `sparkle_eddsa_private.key` | Sparkle edDSA private key (export via `generate_keys -x`) |

## Sparkle key account

Keys were generated with account name `college-planner`:

```bash
GENERATE_KEYS="$(find ~/Library/Developer/Xcode/DerivedData -path '*/Sparkle/bin/generate_keys' 2>/dev/null | head -1)"
"$GENERATE_KEYS" --account college-planner -p          # print public key
"$GENERATE_KEYS" --account college-planner -x secrets/sparkle_eddsa_private.key
"$GENERATE_KEYS" --account college-planner -f secrets/sparkle_eddsa_private.key  # import on another Mac
```

Public key is committed in `College/Info.plist` → `SUPublicEDKey`.

For CI, store the private key contents as GitHub secret `SPARKLE_PRIVATE_KEY`.
