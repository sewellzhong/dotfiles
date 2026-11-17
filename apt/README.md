# Third-party APT signing keys

`keys/` contains **public** OpenPGP keys for the optional sources managed by
`../apt-sources.sh`. The keys were copied from this Debian 13 workstation on
2026-11-18. All corresponding repositories passed an isolated APT `InRelease`
signature check that day. The GitHub CLI bundle contains only its active key,
following the [September 2026 rotation](https://github.com/cli/cli/blob/trunk/docs/install_linux.md).

| Source | Pinned primary fingerprint |
| --- | --- |
| apm | `9D9AA859F75024B1A1ECE16E0E41D354A29A440C` |
| claude-code | `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE` |
| docker | `9DC858229FC7DD38854AE2D88D81803C0EBFCD88` |
| github-cli | `7F38BBB59D064DBCB3D84D725612B36462313325` |
| google-chrome | `EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796` |
| helm | `DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6` |
| mysql | `BCA43417C3B485DD128EC6D4B7B3B788A8D3785C` |
| pritunl | `7568D9BB55FF9E5287D586017AE645C0CF8E292A` |
| spotify | `E1096BCBFF6D418796DE78515384CE82BA52C83A` |
| syncthing | `FBA2E162F2F44657B38F0309E5665F9BD5970C47` |
| typora | `4AC441BE68B4ADAB7439FBF9BA300B7755AFCFAE` |
| zerotier | `74A5E9C458E1A431F1DA57A71657198823E52A61` |

When a vendor rotates a key, obtain its replacement from the vendor's official
HTTPS endpoint, confirm the announced fingerprint, replace the public key file,
and update the matching fingerprint in `lib/apt_sources.py`. Run the offline tests
and an isolated `apt-get update` before distributing the change. Keys with an
expired primary key are rejected at installation time.

The Debian archive keyring and the system TLS CA bundle remain managed by the OS.
