"""Offline checks for the independent third-party APT source installer."""

from pathlib import Path
import importlib.util
import shutil
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("apt_sources", ROOT / "lib/apt_sources.py")
apt_sources = importlib.util.module_from_spec(spec)
import sys
sys.modules[spec.name] = apt_sources
spec.loader.exec_module(apt_sources)


@unittest.skipUnless(shutil.which("gpg"), "gpg is required to inspect OpenPGP keys")
class AptSourcesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="apt-source-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.updates = []

    def manager(self, distro=("debian", "13"), dry_run=False, arch="amd64"):
        return apt_sources.Manager(distro, root=self.root, dry_run=dry_run,
                                   update=lambda: self.updates.append("update"), arch=arch)

    def test_bundled_keys_have_the_pinned_primary_fingerprint(self):
        for name, source in apt_sources.SOURCES.items():
            with self.subTest(name=name):
                self.assertEqual(apt_sources.key_fingerprints(apt_sources.KEYS / source.key_file),
                                 {source.fingerprint})

    def test_install_verify_and_repeat_use_one_update(self):
        manager = self.manager()
        manager.install(["helm", "docker", "helm"])
        self.assertEqual(self.updates, ["update"])
        self.assertIn("Signed-By: /etc/apt/keyrings/dotfiles-helm.asc", manager.source_path("helm").read_text())
        self.assertEqual(manager.find("helm"), manager.source_path("helm"))
        self.assertEqual(manager.key_path("helm").stat().st_mode & 0o777, 0o644)
        manager.verify(["helm", "docker"])
        manager.install(["helm", "docker"])
        self.assertEqual(self.updates, ["update", "update"])

    def test_dry_run_creates_no_files_and_never_updates(self):
        manager = self.manager(dry_run=True)
        manager.install(["spotify"])
        self.assertFalse((self.root / "etc").exists())
        self.assertEqual(self.updates, [])

    def test_preserve_equivalent_existing_source_with_other_key_location(self):
        manager = self.manager()
        existing = manager.sources_dir / "helm-stable-debian.sources"
        key = self.root / "usr/share/keyrings/helm.asc"
        key.parent.mkdir(parents=True)
        shutil.copyfile(apt_sources.KEYS / "helm.asc", key)
        existing.parent.mkdir(parents=True)
        existing.write_text(manager.render("helm").replace(
            "/etc/apt/keyrings/dotfiles-helm.asc", "/usr/share/keyrings/helm.asc"))
        manager.install(["helm"])
        self.assertEqual(manager.find("helm"), existing)
        self.assertFalse(manager.source_path("helm").exists())
        self.assertFalse(manager.key_path("helm").exists())

    def test_preserve_equivalent_legacy_source_list_entry(self):
        manager = self.manager()
        key = self.root / "etc/apt/keyrings/helm.asc"
        key.parent.mkdir(parents=True)
        shutil.copyfile(apt_sources.KEYS / "helm.asc", key)
        legacy = self.root / "etc/apt/sources.list"
        legacy.write_text("deb [signed-by=/etc/apt/keyrings/helm.asc] "
                          "https://packages.buildkite.com/helm-linux/helm-debian/any/ any main\n")
        manager.install(["helm"])
        self.assertEqual(manager.find("helm"), legacy)
        self.assertFalse(manager.source_path("helm").exists())

    def test_conflict_prevents_all_writes_and_updates(self):
        manager = self.manager()
        existing = manager.sources_dir / "docker.sources"
        existing.parent.mkdir(parents=True)
        existing.write_text(manager.render("docker").replace("Suites: trixie", "Suites: bookworm"))
        with self.assertRaisesRegex(ValueError, "Conflicting APT entry"):
            manager.install(["helm", "docker"])
        self.assertFalse(manager.source_path("helm").exists())
        self.assertEqual(self.updates, [])

    def test_wrong_existing_key_and_symlinks_are_rejected(self):
        manager = self.manager()
        target = manager.key_path("helm")
        target.parent.mkdir(parents=True)
        shutil.copyfile(apt_sources.KEYS / "docker.gpg", target)
        with self.assertRaisesRegex(ValueError, "Conflicting signing key"):
            manager.install(["helm"])
        target.unlink()
        target.symlink_to(apt_sources.KEYS / "helm.asc")
        with self.assertRaisesRegex(ValueError, "symlink"):
            manager.install(["helm"])
        self.assertEqual(self.updates, [])

    def test_release_mapping_and_unsupported_combinations(self):
        for distro, suite in (("debian", "trixie"), ("ubuntu", "noble"), ("ubuntu", "resolute")):
            version = {"trixie": "13", "noble": "24.04", "resolute": "26.04"}[suite]
            manager = self.manager((distro, version))
            with self.subTest(distro=distro, suite=suite):
                self.assertIn(f"Suites: {suite}", manager.render("docker"))
                self.assertIn(f"/apt/{distro}", manager.render("mysql"))
                self.assertIn(f"/debian/{suite}", manager.render("zerotier"))
        with self.assertRaisesRegex(ValueError, "Debian 13"):
            self.manager(("ubuntu", "24.04")).install(["apm"])
        with self.assertRaisesRegex(ValueError, "Unsupported distribution"):
            self.manager(("ubuntu", "22.04")).install(["helm"])
        with self.assertRaisesRegex(ValueError, "requires amd64"):
            self.manager(arch="arm64").install(["google-chrome"])
        self.assertEqual(self.updates, [])

    def test_tampered_bundled_key_fails_before_changes(self):
        keydir = self.root / "tampered"
        keydir.mkdir()
        (keydir / "helm.asc").write_text("not a key")
        with patch.object(apt_sources, "KEYS", keydir):
            with self.assertRaises(ValueError):
                self.manager().install(["helm"])
        self.assertFalse((self.root / "etc").exists())
        self.assertEqual(self.updates, [])


if __name__ == "__main__":
    unittest.main()
