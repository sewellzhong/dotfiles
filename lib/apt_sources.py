#!/usr/bin/env python3
"""Install selected third-party APT sources and their pinned public keys."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


REPO = Path(__file__).resolve().parents[1]
KEYS = REPO / "apt" / "keys"
RELEASES = {("debian", "13"): "trixie", ("ubuntu", "24.04"): "noble", ("ubuntu", "26.04"): "resolute"}


@dataclass(frozen=True)
class Source:
    key_file: str
    fingerprint: str
    uri: str
    suite: str
    components: str = ""
    types: str = "deb"
    arch: str = ""
    debian_only: bool = False


SOURCES = {
    "apm": Source("apm.gpg", "9D9AA859F75024B1A1ECE16E0E41D354A29A440C", "https://d.spark-app.store/apm-deb-source", "/", debian_only=True),
    "claude-code": Source("claude-code.asc", "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE", "https://downloads.claude.ai/claude-code/apt/stable", "stable", "main"),
    "docker": Source("docker.gpg", "9DC858229FC7DD38854AE2D88D81803C0EBFCD88", "https://download.docker.com/linux/{os}", "{suite}", "stable"),
    "github-cli": Source("github-cli.gpg", "7F38BBB59D064DBCB3D84D725612B36462313325", "https://cli.github.com/packages", "stable", "main"),
    "google-chrome": Source("google-chrome.gpg", "EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796", "https://dl.google.com/linux/chrome-stable/deb/", "stable", "main", arch="amd64"),
    "helm": Source("helm.asc", "DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6", "https://packages.buildkite.com/helm-linux/helm-debian/any/", "any", "main"),
    "mysql": Source("mysql.gpg", "BCA43417C3B485DD128EC6D4B7B3B788A8D3785C", "http://repo.mysql.com/apt/{os}", "{suite}", "mysql-apt-config mysql-8.4-lts mysql-tools", types="deb deb-src", arch="amd64"),
    "pritunl": Source("pritunl.gpg", "7568D9BB55FF9E5287D586017AE645C0CF8E292A", "https://repo.pritunl.com/stable/apt", "{suite}", "main"),
    "spotify": Source("spotify.gpg", "E1096BCBFF6D418796DE78515384CE82BA52C83A", "https://repository.spotify.com", "stable", "non-free", arch="amd64"),
    "syncthing": Source("syncthing.gpg", "FBA2E162F2F44657B38F0309E5665F9BD5970C47", "https://apt.syncthing.net/", "syncthing", "stable-v2"),
    "typora": Source("typora.gpg", "4AC441BE68B4ADAB7439FBF9BA300B7755AFCFAE", "https://downloads.typora.io/linux", "./"),
    "zerotier": Source("zerotier.gpg", "74A5E9C458E1A431F1DA57A71657198823E52A61", "https://download.zerotier.com/debian/{suite}", "{suite}", "main"),
}


def os_release(path: Path = Path("/etc/os-release")) -> tuple[str, str]:
    values = {}
    for line in path.read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            values[k] = v.strip('"')
    return values.get("ID", ""), values.get("VERSION_ID", "")


def key_fingerprints(path: Path) -> set[str]:
    result = subprocess.run(["gpg", "--batch", "--show-keys", "--with-colons", str(path)], text=True, capture_output=True)
    if result.returncode:
        raise ValueError(f"Cannot read OpenPGP key {path}: {result.stderr.strip()}")
    fingerprints: set[str] = set()
    current_pub = False
    for line in result.stdout.splitlines():
        fields = line.split(":")
        if fields[0] == "pub":
            current_pub = not fields[6] or int(fields[6]) > time.time()
        elif fields[0] in ("sub", "uid"):
            current_pub = False
        elif fields[0] == "fpr" and current_pub:
            fingerprints.add(fields[9].upper())
            current_pub = False
    return fingerprints


def parse_sources(path: Path) -> list[dict[str, str]]:
    text = path.read_text()
    entries: list[dict[str, str]] = []
    if path.suffix == ".sources":
        for block in re.split(r"\n\s*\n", text):
            fields = {}
            for line in block.splitlines():
                if line.startswith(("#", " ", "\t")) or ":" not in line:
                    continue
                key, value = line.split(":", 1)
                fields[key.lower()] = value.strip()
            if fields.get("uris") and fields.get("enabled", "yes").lower() != "no":
                entries.append(fields)
    else:
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            match = re.match(r"^(deb(?:-src)?)\s+(?:\[([^]]+)\]\s+)?(\S+)\s+(\S+)(?:\s+(.*))?$", line)
            if match:
                opts = dict(re.findall(r"([\w-]+)=([^\s]+)", match[2] or ""))
                entries.append({"types": match[1], "uris": match[3], "suites": match[4],
                                "components": match[5] or "", "signed-by": opts.get("signed-by", "")})
    return entries


def norm_uri(uri: str) -> str:
    return uri.rstrip("/")


class Manager:
    def __init__(self, distro: tuple[str, str], root: Path = Path("/"), dry_run: bool = False,
                 update=None, arch: str | None = None):
        self.distro = distro
        self.root = root
        self.dry_run = dry_run
        self.update = update or (lambda: subprocess.run(
            ["sudo", "apt-get", "update", "-o", "APT::Update::Error-Mode=any"], check=True))
        self.arch = arch or subprocess.run(["dpkg", "--print-architecture"], text=True,
                                          capture_output=True, check=True).stdout.strip()
        self.sources_dir = root / "etc/apt/sources.list.d"
        self.keyrings_dir = root / "etc/apt/keyrings"

    def resolve(self, name: str) -> tuple[Source, str, str]:
        if name not in SOURCES:
            raise ValueError(f"Unknown source: {name}")
        if self.distro not in RELEASES:
            raise ValueError(f"Unsupported distribution: {self.distro[0]} {self.distro[1]}")
        source = SOURCES[name]
        if source.debian_only and self.distro[0] != "debian":
            raise ValueError(f"{name} is verified only on Debian 13")
        if source.arch and source.arch != self.arch:
            raise ValueError(f"{name} requires {source.arch}, detected {self.arch}")
        suite = RELEASES[self.distro]
        return source, source.uri.format(os=self.distro[0], suite=suite), source.suite.format(suite=suite)

    def source_path(self, name: str) -> Path:
        return self.sources_dir / f"dotfiles-{name}.sources"

    def key_path(self, name: str) -> Path:
        return self.keyrings_dir / f"dotfiles-{name}{Path(SOURCES[name].key_file).suffix}"

    def entries(self) -> list[tuple[Path, dict[str, str]]]:
        found = []
        paths = sorted(self.sources_dir.iterdir()) if self.sources_dir.exists() else []
        legacy = self.root / "etc/apt/sources.list"
        if legacy.is_file():
            paths.append(legacy)
        for path in paths:
            if path.is_file() and path.suffix in (".list", ".sources"):
                found.extend((path, entry) for entry in parse_sources(path))
        return found

    def find(self, name: str) -> Path | None:
        source, uri, suite = self.resolve(name)
        target = self.source_path(name)
        matches = []
        for path, entry in self.entries():
            uris = entry.get("uris", "").split()
            if norm_uri(uri) not in {norm_uri(u) for u in uris}:
                continue
            if (suite not in entry.get("suites", "").split() or
                set(source.components.split()) != set(entry.get("components", "").split()) or
                not set(source.types.split()).issubset(set(entry.get("types", "").split()))):
                raise ValueError(f"Conflicting APT entry for {name}: {path}")
            signed = entry.get("signed-by", "").split()
            if len(signed) != 1 or not signed[0].startswith("/"):
                raise ValueError(f"Missing or ambiguous Signed-By for {name}: {path}")
            key = self.root / signed[0].lstrip("/")
            if not key.is_file() or source.fingerprint not in key_fingerprints(key):
                raise ValueError(f"Unexpected signing key for {name}: {key}")
            matches.append(path)
        if len(matches) > 1:
            raise ValueError(f"Duplicate APT entries for {name}: {', '.join(map(str, matches))}")
        if target.is_symlink():
            raise ValueError(f"APT source path is a symlink: {target}")
        if target.exists() and target not in matches:
            raise ValueError(f"Unmanaged file blocks {name}: {target}")
        return matches[0] if matches else None

    def render(self, name: str) -> str:
        source, uri, suite = self.resolve(name)
        lines = [f"Types: {source.types}", f"URIs: {uri}", f"Suites: {suite}"]
        if source.components:
            lines.append(f"Components: {source.components}")
        if source.arch:
            lines.append(f"Architectures: {source.arch}")
        lines.append(f"Signed-By: /etc/apt/keyrings/{self.key_path(name).name}")
        return "\n".join(lines) + "\n"

    def put(self, source: Path, target: Path) -> None:
        if self.root == Path("/"):
            subprocess.run(["sudo", "install", "-d", "-m", "0755", str(target.parent)], check=True)
            subprocess.run(["sudo", "install", "-m", "0644", str(source), str(target)], check=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            target.chmod(0o644)

    def install(self, names: list[str]) -> None:
        if not names:
            raise ValueError("Specify at least one source name")
        pending = []
        for name in dict.fromkeys(names):
            source, _, _ = self.resolve(name)
            asset = KEYS / source.key_file
            if not asset.is_file() or key_fingerprints(asset) != {source.fingerprint}:
                raise ValueError(f"Bundled key fingerprint mismatch: {asset}")
            existing = self.find(name)
            if existing:
                print(f"{name}: already configured in {existing}")
            else:
                target_key = self.key_path(name)
                if target_key.is_symlink():
                    raise ValueError(f"Signing key path is a symlink: {target_key}")
                if target_key.exists() and key_fingerprints(target_key) != {source.fingerprint}:
                    raise ValueError(f"Conflicting signing key: {target_key}")
                pending.append(name)
        for name in pending:
            source = SOURCES[name]
            key = self.key_path(name)
            dest = self.source_path(name)
            print(f"{name}: install {key} and {dest}")
            if self.dry_run:
                continue
            if not key.exists():
                self.put(KEYS / source.key_file, key)
            with tempfile.TemporaryDirectory(prefix="dotfiles-apt-") as temp:
                staged = Path(temp) / dest.name
                staged.write_text(self.render(name))
                self.put(staged, dest)
        print("Run apt-get update once to verify repository metadata and signatures")
        if not self.dry_run:
            self.update()

    def verify(self, names: list[str]) -> None:
        checked = 0
        for name in names or list(SOURCES):
            try:
                existing = self.find(name)
            except ValueError as exc:
                if not names and ("verified only" in str(exc) or "Unsupported distribution" in str(exc)):
                    continue
                raise
            if not existing:
                if names:
                    raise ValueError(f"Source is not installed: {name}")
                continue
            print(f"{name}: verified ({existing})")
            checked += 1
        if not checked:
            print("No selected third-party sources are installed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="show changes without writing or refreshing APT")
    parser.add_argument("action", choices=("list", "install", "verify"))
    parser.add_argument("names", nargs="*")
    args = parser.parse_args()
    manager = Manager(os_release(), dry_run=args.dry_run)
    try:
        if args.action == "list":
            if args.names:
                raise ValueError("list does not take source names")
            for name in SOURCES:
                try:
                    manager.resolve(name)
                    status = "installed" if manager.find(name) else "available"
                except ValueError as exc:
                    status = f"unavailable ({exc})"
                print(f"{name:14} {status}")
        elif args.action == "install":
            manager.install(args.names)
        else:
            manager.verify(args.names)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f"apt-sources: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
