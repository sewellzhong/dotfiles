#!/usr/bin/env python3
"""Offline identity, publishing, apt and Stow regression coverage."""
import importlib.util
import fcntl
import time
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch
import test_dotfiles as fixtures
ROOT = fixtures.ROOT

sys.path.insert(0, str(ROOT / 'lib'))
from dependencies import normalize, publish, validate
from nvim_installed import clone_view


def load_file(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DependencyTests(unittest.TestCase):
    setUp = fixtures.DotfilesTests.setUp
    run_command = fixtures.DotfilesTests.run_command
    stub = fixtures.DotfilesTests.stub
    copy_repo = fixtures.DotfilesTests.copy_repo
    transaction = fixtures.DotfilesTests.transaction

    def git(self, directory, *args):
        return self.run_command(['git', '-C', str(directory), *args]).stdout.strip()

    def fixture(self, directory):
        directory.mkdir(parents=True, exist_ok=True)
        self.git(directory, 'init', '-b', 'main')
        self.git(directory, 'config', 'user.name', 'Test')
        self.git(directory, 'config', 'user.email', 'test@example.invalid')
        (directory/'tracked').write_text('original')
        self.git(directory, 'add', '.')
        self.git(directory, 'commit', '-m', 'original')
        self.git(directory, 'remote', 'add', 'origin', 'https://github.com/example/project.git')
        return self.git(directory, 'rev-parse', 'HEAD')

    def prepare_zsh(self):
        self.copy_repo()
        self.env['GIT_ALLOW_PROTOCOL']='file'
        self.env['GIT_CONFIG_GLOBAL']=str(self.home/'.gitconfig')
        registry_output=self.run_command(['python3',str(ROOT/'lib/dependencies.py'),'registry']).stdout
        self.zsh_rows=[line.split('\t') for line in registry_output.splitlines()][1:5]
        self.zsh_commits={}
        for index,(origin,directory,_) in enumerate(self.zsh_rows):
            source=self.base/f'remote-{index}'
            first=self.fixture(source)
            (source/'tracked').write_text('updated')
            self.git(source,'commit','-am','updated')
            last=self.git(source,'rev-parse','HEAD')
            Path(directory).parent.mkdir(parents=True,exist_ok=True)
            self.run_command(['git','clone','--quiet',str(source),directory])
            self.git(directory,'remote','set-url','origin',origin)
            self.git(directory,'checkout','--detach',first)
            self.git(self.home,'config','--global',f'url.{source.as_uri()}.insteadOf',origin)
            self.zsh_commits[normalize(origin)]=(first,last)
        lock=self.repo/'dotfiles.lock'
        lines=[]
        for line in lock.read_text().splitlines():
            key=line.split('\t')[0]
            lines.append(key+'\t'+self.zsh_commits[key][0] if key in self.zsh_commits else line)
        lock.write_text('\n'.join(lines)+'\n')
        return lock

    def update_zsh(self,expected=0,dry=False):
        return self.run_command(['bash',str(self.repo/'bin/.local/bin/update-beauty'),
                                 '--yes',*(['--dry-run'] if dry else []),'oh-my-zsh'],expected)

    def test_zsh_detached_update_only_changes_registered_lock_records(self):
        lock=self.prepare_zsh(); before=lock.read_text()
        archive=self.home/'.oh-my-zsh/custom/plugins/archive'; archive.mkdir()
        (archive/'local').write_text('user archive')
        unmanaged=self.home/'.oh-my-zsh/custom/plugins/unmanaged'; unmanaged.mkdir()
        (unmanaged/'local').write_text('user plugin')
        self.update_zsh()
        lines=dict(line.split('\t') for line in lock.read_text().splitlines() if line and not line.startswith('#'))
        for origin,directory,_ in self.zsh_rows:
            pin=self.zsh_commits[normalize(origin)][1]
            self.assertEqual(self.git(directory,'rev-parse','HEAD'),pin)
            self.assertEqual(lines[normalize(origin)],pin)
        for line in before.splitlines():
            if line.split('\t')[0] not in self.zsh_commits:
                self.assertIn(line,lock.read_text())
        self.assertEqual((archive/'local').read_text(),'user archive')
        self.assertEqual((unmanaged/'local').read_text(),'user plugin')

    def test_zsh_dry_run_and_dirty_precheck_preserve_every_head(self):
        lock=self.prepare_zsh(); before=lock.read_bytes()
        self.update_zsh(dry=True)
        directory=Path(self.zsh_rows[-1][1]); (directory/'tracked').write_text('local change')
        self.update_zsh(1)
        for origin,directory,_ in self.zsh_rows:
            self.assertEqual(self.git(directory,'rev-parse','HEAD'),self.zsh_commits[normalize(origin)][0])
        self.assertEqual(lock.read_bytes(),before)

    def test_zsh_partial_checkout_failure_keeps_lock_and_reports_changes(self):
        lock=self.prepare_zsh(); before=lock.read_bytes()
        failed_directory=self.zsh_rows[-1][1]
        self.env['FAIL_CHECKOUT_DIR']=failed_directory
        self.stub('git', 'if [ "$2" = "$FAIL_CHECKOUT_DIR" ] && [ "$3" = checkout ]; then exit 25; fi\nexec /usr/bin/git "$@"')
        result=self.update_zsh(1)
        self.assertIn('Worktrees may have changed',result.stderr)
        self.assertEqual(lock.read_bytes(),before)
        self.assertEqual(self.git(self.zsh_rows[0][1],'rev-parse','HEAD'),self.zsh_commits[normalize(self.zsh_rows[0][0])][1])

    def test_dependency_updates_wait_for_operation_lock(self):
        lockfile=self.prepare_zsh(); before=lockfile.read_bytes()
        with (self.repo/'.dotfiles-dependencies.lock').open('w') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            command=['python3',str(self.repo/'lib/update-dependencies.py'),'zsh','--repo',str(self.repo)]
            process=subprocess.Popen(command,env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                time.sleep(0.15)
                self.assertIsNone(process.poll())
                self.assertEqual(lockfile.read_bytes(),before)
                for origin,directory,_ in self.zsh_rows:
                    self.assertEqual(self.git(directory,'rev-parse','HEAD'),self.zsh_commits[normalize(origin)][0])
                fcntl.flock(lock,fcntl.LOCK_UN)
                out,err=process.communicate(timeout=15)
                self.assertEqual(process.returncode,0,out+err)
            finally:
                if process.poll() is None: process.kill(); process.communicate()

    def test_identity_valid_forms_and_spoof_rejection(self):
        for url in ('https://github.com/owner/repo.git', 'ssh://git@github.com/owner/repo.git',
                    'git@github.com:owner/repo.git', 'github.com/owner/repo'):
            self.assertEqual(normalize(url), 'github.com/owner/repo')
        self.assertEqual(normalize('ssh://git@gitlab.com/group/sub/repo.git'), 'gitlab.com/group/sub/repo')
        for url in ('https://evil.invalid/github.com/owner/repo.git', 'https://github.com.evil/owner/repo',
                    'https://github.com@evil.invalid/owner/repo', 'https://github.com/owner/repo?ref=x',
                    'https://github.com/owner/../repo', 'https://github.com/owner/%2e%2e/repo',
                    'https://github.com:443/owner/repo', 'http://github.com/owner/repo',
                    'git@evil:github.com/owner/repo', 'https://github.com/owner/repo#x'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                normalize(url)

    def test_worktree_origin_root_commit_and_dirty_checks(self):
        directory=self.base/'dependency'; commit=self.fixture(directory)
        origin='https://github.com/example/project.git'
        self.assertEqual(validate(directory, origin, commit), commit)
        (directory/'untracked').write_text('not guaranteed')
        validate(directory, origin, commit)
        for target, url, pin in ((directory, 'https://github.com/other/project', None),
                                 (directory, origin, '0'*40), (directory/'.git', origin, None)):
            with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                validate(target, url, pin)
        (directory/'tracked').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'Tracked changes'):
            validate(directory, origin)

    def test_independent_validation_checkout(self):
        source=self.base/'plugins/example'; commit=self.fixture(source)
        clone_view({'example': {'branch':'main','commit':commit}}, source.parent, self.base/'view')
        clone=self.base/'view/example'
        self.assertFalse((clone/'.git/objects/info/alternates').exists())
        self.assertNotEqual((clone/'tracked').stat().st_ino, (source/'tracked').stat().st_ino)
        (clone/'tracked').write_text('validation callback changed this')
        self.assertEqual((source/'tracked').read_text(), 'original')
        self.assertEqual(self.git(source, 'rev-parse', 'HEAD'), commit)
        self.assertEqual(self.git(source, 'status', '--porcelain'), '')

    def test_concurrent_lock_change_refuses_publication(self):
        lock=self.base/'lock'; lock.write_bytes(b'original')
        before={lock:lock.read_bytes()}; lock.write_bytes(b'another writer')
        with self.assertRaisesRegex(ValueError, 'concurrently'):
            publish(lock,b'ours',before)
        self.assertEqual(lock.read_bytes(), b'another writer')

    def test_apt_groups_validated_before_any_mutation(self):
        self.env.update(DOTFILES_APT_GROUPS='base typo', TEST_REPO=str(ROOT))
        self.stub('sudo','echo MUTATION; exit 99')
        result=self.run_command(['bash','-c','source "$TEST_REPO/dotfiles.sh"; install_apt_package_groups'],1)
        self.assertNotIn('MUTATION',result.stdout)

    def test_apt_missing_packages_batched_and_deduplicated(self):
        log=self.base/'apt.log'; self.env.update(TEST_REPO=str(ROOT),APT_LOG=str(log),DOTFILES_APT_GROUPS='base base server')
        self.stub('dpkg-query','exit 1')
        self.stub('sudo','printf "%s\\n" "$*" >> "$APT_LOG"')
        self.run_command(['bash','-c','source "$TEST_REPO/dotfiles.sh"; install_apt_package_groups'])
        commands=log.read_text().splitlines()
        self.assertEqual(len(commands),2)
        self.assertEqual(commands[0],'apt-get update')
        packages=commands[1].split()[3:]
        self.assertEqual(len(packages),len(set(packages)))
        self.assertIn('openssh-server',packages)

    def test_apt_shadowing_old_editor_fails_before_changes(self):
        self.stub('nvim','echo "NVIM v0.9.5"')
        self.run_command(['python3',str(ROOT/'lib/apt-preflight.py')],1)

    def apt_candidate(self, candidate, dry=False, current=None, installed=False):
        module=load_file('apt_preflight',ROOT/'lib/apt-preflight.py')
        def command(args, **kwargs):
            return subprocess.CompletedProcess(args,0,stdout=(f'NVIM v{current}' if args[0]=='/usr/bin/nvim'
                                                            else f'  Candidate: {candidate}\n'),stderr='')
        arguments=['apt-preflight']+(['--dry-run'] if dry else [])+(['--installed'] if installed else [])
        with patch.object(sys,'argv',arguments), patch.object(module.shutil,'which',return_value='/usr/bin/nvim' if current else None), patch.object(module.subprocess,'run',side_effect=command):
            module.main()

    def test_apt_candidate_and_postinstall_version_guards(self):
        self.apt_candidate('0.10.4-8')
        self.apt_candidate('1:0.10.4-8',current='0.9.5')
        with self.assertRaises(ValueError): self.apt_candidate('0.9.5-1')
        with self.assertRaises(ValueError): self.apt_candidate('(none)')
        self.apt_candidate('(none)',dry=True)
        with self.assertRaises(ValueError): self.apt_candidate('0.10.4-8',current='0.9.5',installed=True)

    def test_apt_dry_run_does_not_call_sudo(self):
        self.env.update(TEST_REPO=str(ROOT))
        self.stub('dpkg-query','exit 1'); self.stub('sudo','echo MUTATION; exit 99')
        result=self.run_command(['bash','-c','source "$TEST_REPO/dotfiles.sh"; DRY_RUN=true; install_apt_package_groups'])
        self.assertNotIn('MUTATION',result.stdout)
        self.assertIn('+ sudo apt-get install',result.stdout)

    def test_stow_local_and_global_ignore_precedence(self):
        folder=self.repo/'demo/.config/demo'
        for name in ('from-global','from-local','another-local','keep.local','README'):
            (folder/name).write_text(name)
        (self.home/'.stow-global-ignore').write_text('from-global\n')
        (self.repo/'demo/.stow-local-ignore').write_text('# custom patterns\n\nfrom-local\nanother-local\n')
        self.transaction('link','--yes')
        target=self.home/'.config/demo'
        self.assertTrue((target/'from-global').is_symlink())
        self.assertTrue((target/'README').is_symlink())  # local list replaces built-in list
        self.assertFalse((target/'from-local').exists())
        self.assertFalse((target/'another-local').exists())
        self.assertFalse((target/'keep.local').exists())

    def test_stow_global_path_patterns_and_local_bin(self):
        folder=self.repo/'demo/.config/demo'
        (folder/'skip').mkdir(); (folder/'skip/data').write_text('ignored')
        (self.home/'.stow-global-ignore').write_text('^/\\.config/demo/skip\n')
        (self.repo/'demo/.local/bin').mkdir(parents=True)
        (self.repo/'demo/.local/bin/command').write_text('hello')
        self.transaction('link','--yes')
        self.assertTrue((self.home/'.local/bin/command').is_symlink())
        self.assertFalse((self.home/'.config/demo/skip').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
