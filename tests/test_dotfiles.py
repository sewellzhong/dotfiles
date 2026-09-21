#!/usr/bin/env python3
"""Offline regression tests. All mutations use disposable HOME/repository fixtures."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import fcntl
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DotfilesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / 'home with spaces'
        self.home.mkdir()
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith(('DOTFILES_', 'XDG_')) or key.endswith('_VERSION'):
                self.env.pop(key, None)
        self.env.update(HOME=str(self.home), PATH='/usr/bin:/bin', TERM='screen-256color',
                        GIT_CONFIG_NOSYSTEM='1', PYTHONDONTWRITEBYTECODE='1', XDG_CONFIG_HOME=str(self.home/'.config'),
                        XDG_DATA_HOME=str(self.home/'.local/share'), XDG_CACHE_HOME=str(self.home/'.cache'),
                        XDG_STATE_HOME=str(self.home/'.local/state'), NVIM_LOG_FILE=str(self.base/'nvim.log'))
        self.repo = self.base / 'repository with spaces'
        (self.repo/'demo/.config/demo').mkdir(parents=True)
        (self.repo/'demo/.config/demo/settings').write_text('new configuration\n')

    def run_command(self, args, expected=0, **kwargs):
        result = subprocess.run(args, env=self.env, cwd=self.base, text=True,
                                capture_output=True, timeout=40, **kwargs)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def transaction(self, action, *args, expected=0):
        return self.run_command(['python3', str(ROOT/'lib/transaction.py'), action,
                                '--repo', str(self.repo), '--home', str(self.home), *args,
                                '--', 'demo'], expected)

    def stub(self, name, body):
        bindir = self.base/'bin'; bindir.mkdir(exist_ok=True)
        path = bindir/name
        path.write_text('#!/bin/bash\n'+body+'\n'); path.chmod(0o755)
        self.env['PATH'] = str(bindir)+':/usr/bin:/bin'

    def batch(self):
        return next((self.home/'.dotfiles_backup').glob('*/journal.json')).parent

    def target(self):
        return self.home/'.config/demo/settings'

    def original(self, value='old configuration\n'):
        self.target().parent.mkdir(parents=True, exist_ok=True)
        self.target().write_text(value)

    def copy_repo(self):
        shutil.copytree(ROOT, self.repo, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('.git', '.agents', '.codex', '__pycache__', '.nvimlog'))

    def test_first_link_repeat_and_restore(self):
        self.original()
        self.transaction('link', '--yes')
        self.assertTrue(self.target().is_symlink())
        batch = self.batch()
        self.transaction('link', '--yes')
        self.assertEqual(len(list((self.home/'.dotfiles_backup').glob('*/journal.json'))), 1)
        self.transaction('restore', '--batch', batch.name, '--dry-run')
        self.assertTrue(self.target().is_symlink())
        self.transaction('restore', '--batch', batch.name, '--yes')
        self.assertEqual(self.target().read_text(), 'old configuration\n')
        self.transaction('restore', '--batch', batch.name, '--yes')

    def test_empty_home_rollback_removes_new_files_and_dirs(self):
        self.transaction('link', '--yes')
        self.transaction('restore', '--batch', self.batch().name, '--yes')
        self.assertFalse((self.home/'.config').exists())

    def test_dry_run_has_no_writes(self):
        self.original()
        self.transaction('link', '--dry-run')
        self.assertFalse((self.home/'.dotfiles_backup').exists())
        self.assertFalse(self.target().is_symlink())

    def test_broken_link_roundtrip(self):
        self.target().parent.mkdir(parents=True)
        self.target().symlink_to('missing-original')
        self.transaction('link', '--yes')
        self.transaction('restore', '--batch', self.batch().name, '--yes')
        self.assertEqual(os.readlink(self.target()), 'missing-original')

    def test_shape_conflict_precedes_backup(self):
        self.target().mkdir(parents=True)
        self.transaction('link', '--yes', expected=1)
        self.assertFalse(any((self.home/'.dotfiles_backup').glob('*/journal.json')))

    def test_symlink_parent_rejected(self):
        other = self.base/'other'; other.mkdir()
        (self.home/'.config').symlink_to(other)
        self.transaction('link', '--yes', expected=1)
        self.assertEqual(list(other.iterdir()), [])

    def test_stow_failure_restores_files(self):
        self.original()
        self.stub('stow', 'if [ "$1" = -n ]; then exit 0; fi\nexit 23')
        self.transaction('link', '--yes', expected=1)
        self.assertEqual(self.target().read_text(), 'old configuration\n')
        self.assertEqual(json.loads((self.batch()/'journal.json').read_text())['status'], 'restored')

    def test_partial_stow_failure_restores_files(self):
        self.original()
        self.stub('stow', 'if [ "$1" = -n ]; then exit 0; fi\n/bin/ln -s "$TEST_SOURCE" "$HOME/.config/demo/settings"\nexit 23')
        self.env['TEST_SOURCE'] = str(self.repo/'demo/.config/demo/settings')
        self.transaction('link', '--yes', expected=1)
        self.assertFalse(self.target().is_symlink())
        self.assertEqual(self.target().read_text(), 'old configuration\n')

    def test_later_modifications_protected(self):
        self.original()
        self.transaction('link', '--yes')
        self.target().unlink(); self.target().write_text('later changes')
        self.transaction('restore', '--batch', self.batch().name, '--yes', expected=1)
        self.assertEqual(self.target().read_text(), 'later changes')

    def test_changes_through_symlink_protected(self):
        self.original(); self.transaction('link', '--yes')
        self.target().write_text('edited through link')
        self.transaction('restore', '--batch', self.batch().name, '--yes', expected=1)

    def test_backup_only_roundtrip(self):
        self.original(); self.transaction('backup', '--yes')
        self.assertFalse(self.target().exists())
        self.transaction('restore', '--batch', self.batch().name, '--yes')
        self.assertEqual(self.target().read_text(), 'old configuration\n')

    def test_stow_success_without_expected_links_rolls_back(self):
        self.original()
        self.stub('stow', 'exit 0')
        self.transaction('link', '--yes', expected=1)
        self.assertEqual(self.target().read_text(), 'old configuration\n')

    def test_missing_build_tool_does_not_delete_build_directory(self):
        self.env['TEST_REPO']=str(ROOT)
        result=self.run_command(['bash','-c','''source "$TEST_REPO/bin/.local/bin/update-beauty"
require_command() { [ "$1" != meson ]; }
run() { echo "MUTATION: $*"; }
main --yes rofi
'''],1)
        self.assertNotIn('MUTATION:',result.stdout)

    def test_private_files_not_stowed(self):
        (self.repo/'demo/.config/demo/settings.local').write_text('private')
        self.transaction('link', '--yes')
        self.assertFalse((self.home/'.config/demo/settings.local').exists())

    def test_multi_module_conflict(self):
        (self.repo/'other/.config/demo').mkdir(parents=True)
        (self.repo/'other/.config/demo/settings').write_text('other')
        self.run_command(['python3',str(ROOT/'lib/transaction.py'),'check','--repo',str(self.repo),
                          '--home',str(self.home),'--','demo','other'],1)

    def test_static_verify_from_other_cwd(self):
        self.run_command(['bash',str(ROOT/'dotfiles.sh'),'verify','--static'])

    def test_verify_missing_dependencies_fails(self):
        result = self.run_command(['bash',str(ROOT/'dotfiles.sh'),'verify'],1)
        self.assertIn('Missing dependency',result.stderr)

    def test_syntax_error_in_later_script_fails(self):
        self.copy_repo()
        (self.repo/'bin/.local/bin/sizeof').write_text('#!/bin/bash\nif then\n')
        self.run_command(['bash',str(self.repo/'dotfiles.sh'),'verify','--static'],1)

    def test_missing_lock_entry_fails(self):
        self.copy_repo()
        (self.repo/'dotfiles.lock').write_text('# incomplete\n')
        self.run_command(['bash',str(self.repo/'dotfiles.sh'),'verify','--static'],1)

    def test_failed_lock_generation_preserves_file(self):
        self.env['DOTFILES_LOCK_FILE']=str(self.base/'lock')
        Path(self.env['DOTFILES_LOCK_FILE']).write_text('original lock')
        self.run_command(['bash',str(ROOT/'dotfiles.sh'),'lock'],1)
        self.assertEqual(Path(self.env['DOTFILES_LOCK_FILE']).read_text(),'original lock')

    def test_build_failure_never_installs(self):
        script = '''source "$TEST_REPO/bin/.local/bin/update-beauty"
preflight_component() { :; }
use_latest_release() { :; }
cd() { :; }
run() { printf '%s\\n' "$*"; [ "$1" != meson ]; }
main --install --yes rofi
'''
        self.env['TEST_REPO']=str(ROOT)
        result=self.run_command(['bash','-c',script],1)
        self.assertNotIn('sudo install',result.stdout)
        self.assertNotIn('ninja -C',result.stdout)

    def test_checkout_failure_propagates(self):
        self.env['TEST_REPO']=str(ROOT)
        result=self.run_command(['bash','-c','''source "$TEST_REPO/bin/.local/bin/update-beauty"
preflight_source_repo() { :; }
confirm_git_clean() { :; }
run() { printf '%s\\n' "$*"; [ "$2" != checkout ]; }
DOTFILES_UPDATE_BEAUTY_REF=missing
if use_latest_release; then exit 0; else exit 1; fi
'''],1)
        self.assertNotIn('rev-parse',result.stdout)

    def test_cache_allowlist_and_dry_run(self):
        cache=self.home/'.cache'; cache.mkdir()
        for name in ['nvim','zsh','unknown']:
            (cache/name).mkdir(); (cache/name/'keep').write_text('data')
        outside=self.base/'outside'; outside.mkdir(); (outside/'keep').write_text('data')
        (cache/'fzf').symlink_to(outside)
        self.run_command(['bash',str(ROOT/'bin/.local/bin/cleaner'),'--cache','--dry-run'])
        self.assertTrue((cache/'nvim/keep').exists())
        self.run_command(['bash',str(ROOT/'bin/.local/bin/cleaner'),'--cache'])
        self.assertFalse((cache/'nvim').exists())
        self.assertTrue((cache/'unknown/keep').exists()); self.assertTrue((outside/'keep').exists())

    def test_term_and_portable_stow(self):
        self.copy_repo()
        (self.home/'.config/common').mkdir(parents=True)
        (self.home/'.config/common/.aliases').symlink_to(self.repo/'common/.config/common/.aliases')
        self.env['TEST_REPO']=str(self.repo)
        for shell in ['bash','zsh']:
            result=self.run_command([shell,'-c','''source "$TEST_REPO/common/.config/common/.exports"
source "$HOME/.config/common/.aliases"
printf 'TERM=%s\\n' "$TERM"
stow -n --no-folding -t "$HOME" vim
'''])
            self.assertIn('TERM=screen-256color',result.stdout)

    def test_search_defaults_and_explicit_deep_search(self):
        project=self.base/'project'; project.mkdir()
        (project/'.git').mkdir(); (project/'.gitignore').write_text('ignored\n')
        (project/'ignored').write_text('needle'); (project/'.hidden').write_text('needle')
        (project/'visible').write_text('needle')
        self.env['RIPGREP_CONFIG_PATH']=str(ROOT/'ripgrep/.config/ripgrep/config')
        normal=self.run_command(['rg','-l','needle',str(project)]).stdout
        self.assertIn('visible',normal); self.assertNotIn('ignored',normal); self.assertNotIn('.hidden',normal)
        deep=self.run_command(['rg','--hidden','--follow','--no-ignore','-l','needle',str(project)]).stdout
        self.assertIn('ignored',deep); self.assertIn('.hidden',deep)

    def test_ssh_local_override(self):
        folder=self.home/'.ssh'; folder.mkdir()
        (folder/'config.local').write_text('Host pve\n User override\n Port 2222\nHost other\n User other\n')
        (folder/'config.sewellzhong').write_text((ROOT/'ssh/.ssh/config.sewellzhong').read_text())
        config=folder/'config'
        config.write_text((ROOT/'ssh/.ssh/config').read_text().replace('~/.ssh/',str(folder)+'/'))
        result=self.run_command(['ssh','-G','-F',str(config),'pve'])
        self.assertIn('user override\n',result.stdout); self.assertIn('port 2222\n',result.stdout)

    def test_interrupt_recovers_partial_batch(self):
        self.original()
        self.stub('stow', 'if [ "$1" = -n ]; then exit 0; fi\nkill -TERM "$PPID"\nsleep 0.1\nexit 1')
        self.transaction('link', '--yes', expected=1)
        self.assertEqual(self.target().read_text(), 'old configuration\n')
        self.assertEqual(json.loads((self.batch()/'journal.json').read_text())['status'], 'restored')

    def test_backup_failure_restores_already_moved_files(self):
        self.original()
        (self.repo/'demo/.config/demo/second').write_text('second source')
        (self.home/'.config/demo/second').write_text('second original')
        script = r'''import importlib.util, sys
from pathlib import Path
from unittest.mock import patch
spec = importlib.util.spec_from_file_location("transaction", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
sys.argv = [sys.argv[1], "link", "--repo", sys.argv[2], "--home", sys.argv[3], "--yes", "--", "demo"]
original = Path.rename
count = 0
def rename(path, target):
    global count
    if "/files/" in str(target):
        count += 1
        if count == 2: raise OSError("injected move failure")
    return original(path, target)
with patch.object(Path, "rename", rename):
    m.main()
'''
        self.run_command(['python3','-c',script,str(ROOT/'lib/transaction.py'),str(self.repo),str(self.home)],1)
        self.assertEqual(self.target().read_text(), 'old configuration\n')
        self.assertEqual((self.home/'.config/demo/second').read_text(), 'second original')

    def test_configuration_operations_wait_for_home_lock(self):
        root=self.home/'.dotfiles_backup'; root.mkdir()
        with (root/'.lock').open('w') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            command=['python3',str(ROOT/'lib/transaction.py'),'link','--repo',str(self.repo),
                     '--home',str(self.home),'--yes','--','demo']
            process=subprocess.Popen(command,env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                time.sleep(0.15)
                self.assertIsNone(process.poll())
                self.assertFalse(self.target().exists())
                fcntl.flock(lock,fcntl.LOCK_UN)
                out,err=process.communicate(timeout=10)
                self.assertEqual(process.returncode,0,out+err)
            finally:
                if process.poll() is None: process.kill(); process.communicate()

    def test_nvim_initialization_error_is_nonzero(self):
        self.copy_repo()
        (self.repo/'nvim/.config/nvim/lua/dotfiles/options.lua').write_text('error("injected startup error")')
        self.env['DOTFILES_VERIFY']='1'
        result=self.run_command(['nvim','--headless','--clean','-u',str(self.repo/'nvim/.config/nvim/init.lua'),'+qa'],1)
        self.assertIn('injected startup error',result.stderr)

    def test_duplicate_lock_records_rejected(self):
        self.copy_repo(); lock=self.repo/'dotfiles.lock'
        lock.write_text(lock.read_text()+lock.read_text().splitlines()[1]+'\n')
        self.run_command(['bash',str(self.repo/'dotfiles.sh'),'verify','--static'],1)

    def test_restore_rejects_path_traversal(self):
        self.transaction('restore','--batch','../outside','--yes',expected=1)

    def test_all_components_report_failure_but_continue(self):
        self.env['TEST_REPO']=str(ROOT)
        result=self.run_command(['bash','-c','''source "$TEST_REPO/bin/.local/bin/update-beauty"
preflight_component() { :; }
update_rofi() { echo failed-rofi; return 12; }
update_picom() { echo built-picom; }
main --yes rofi picom
'''],1)
        self.assertIn('built-picom',result.stdout)
        self.assertIn('Failed: update_rofi',result.stderr)

    def test_lock_atomic_replace_failure_keeps_previous_lock(self):
        lock=self.base/'dependency.lock'; lock.write_text('original lock')
        script = """import sys
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, sys.argv[1])
from dependencies import publish
path=Path(sys.argv[2])
with patch('dependencies.os.replace', side_effect=OSError('injected-final-rename-failure')):
    publish(path, b'new lock', {path: path.read_bytes()})
"""
        result=self.run_command(['python3','-c',script,str(ROOT/'lib'),str(lock)],1)
        self.assertIn('injected-final-rename-failure',result.stderr)
        self.assertEqual(lock.read_text(),'original lock')
        self.assertEqual(list(self.base.glob('.dotfiles-lock.*')),[])

    def test_first_full_install_and_repeat_offline(self):
        self.stub('sudo','echo unexpected sudo >&2; exit 90')
        self.stub('dpkg-query',"printf 'install ok installed'")
        self.stub('git','''case "$1" in
clone) mkdir -p "$3/.git"; printf '%s' "$2" > "$3/.git/origin"; exit 0 ;;
-C)
 case "$3" in
  config) cat "$2/.git/origin" ;;
  status|fetch|checkout|ls-files) exit 0 ;;
  rev-parse) printf "%s\\n" "$2" ;;
  *) echo "unexpected git: $*" >&2; exit 91 ;;
 esac ;;
*) exit 92 ;;
esac''')
        self.stub('nvim','if [ \"$1\" = --version ]; then echo \"NVIM v0.10.4\"; else echo simulated locked Neovim restore; fi')
        self.stub('node',':'); self.stub('npm',':')
        self.env['TEST_REPO']=str(ROOT)
        self.run_command(['bash','-c','source "$TEST_REPO/dotfiles.sh"; install_neovim_plugins() { :; }; main --yes'])
        self.assertTrue((self.home/'.zshrc').is_symlink())
        self.assertTrue((self.home/'.vimrc').is_symlink())
        self.env['TEST_REPO']=str(ROOT)
        self.run_command(['bash','-c','source "$TEST_REPO/dotfiles.sh"; install_neovim_plugins() { :; }; main --yes'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
