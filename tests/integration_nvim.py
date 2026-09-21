#!/usr/bin/env python3
"""Real pinned lazy.nvim, local fixture remotes, no network during tests."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PIN = json.loads((ROOT/'nvim/.config/nvim/lazy-lock.json').read_text())['lazy.nvim']['commit']
SEED = Path(os.environ.get('DOTFILES_LAZY_SEED', '/nonexistent'))


class EditorIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('nvim'):
            raise RuntimeError('Neovim >= 0.10.4 is required (integration tests cannot skip it)')
        subprocess.run(['nvim','--headless','--clean','-u','NONE',
                        '+lua if vim.fn.has("nvim-0.10.4")==0 then vim.cmd("cquit 1") end','+qa'],check=True)
        if not (SEED/'.git').exists():
            raise RuntimeError('Set DOTFILES_LAZY_SEED to a prepared git checkout of the pinned lazy.nvim')
        actual=subprocess.check_output(['git','-C',str(SEED),'rev-parse','HEAD'],text=True).strip()
        if actual != PIN:
            raise RuntimeError(f'lazy seed HEAD must be {PIN}, got {actual}')
        if subprocess.check_output(['git','-C',str(SEED),'status','--porcelain','--untracked-files=no'],text=True).strip():
            raise RuntimeError('lazy seed contains tracked changes')

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='dotfiles-editor-integration-')
        self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name); self.home=self.base/'home with spaces'; self.home.mkdir()
        self.repo=self.base/'repo with spaces'
        shutil.copytree(ROOT,self.repo,ignore=shutil.ignore_patterns('.git','.agents','.codex','__pycache__','.nvimlog','.dotfiles-dependencies.lock'))
        self.config=self.repo/'nvim/.config/nvim'
        self.data=self.home/'.local/share'; self.plugins=self.data/'nvim/lazy'
        self.env={k:v for k,v in os.environ.items() if not k.startswith(('DOTFILES_','XDG_','GIT_CONFIG_'))}
        self.env.update(HOME=str(self.home),XDG_DATA_HOME=str(self.data),XDG_CONFIG_HOME=str(self.home/'.config'),
                        XDG_CACHE_HOME=str(self.home/'.cache'),XDG_STATE_HOME=str(self.home/'.local/state'),
                        NVIM_LOG_FILE=str(self.base/'nvim.log'),GIT_CONFIG_NOSYSTEM='1',GIT_ALLOW_PROTOCOL='file',
                        GIT_TERMINAL_PROMPT='0',PYTHONDONTWRITEBYTECODE='1')
        self.remote=self.base/'remotes'; self.remote.mkdir()
        self.commits={}
        for name in ('alpha','beta'):
            source=self.remote/name; source.mkdir()
            self.git(source,'init','-b','main'); self.git(source,'config','user.name','Fixture')
            self.git(source,'config','user.email','fixture@example.invalid')
            (source/'lua').mkdir(); (source/f'lua/{name}.lua').write_text('return { value = 1 }')
            self.git(source,'add','.'); self.git(source,'commit','-m','first')
            first=self.git(source,'rev-parse','HEAD')
            (source/f'lua/{name}.lua').write_text('return { value = 2 }')
            self.git(source,'commit','-am','second')
            self.commits[name]=(first,self.git(source,'rev-parse','HEAD'))
            self.git(self.home,'config','--global',f'url.{source.as_uri()}.insteadOf',f'https://github.com/fixture/{name}.git')
        self.git(self.home,'config','--global',f'url.{SEED.resolve().as_uri()}.insteadOf','https://github.com/folke/lazy.nvim.git')
        manager=self.plugins/'lazy.nvim'; manager.parent.mkdir(parents=True)
        self.cmd(['git','clone','--quiet','--no-local',str(SEED),str(manager)])
        self.git(manager,'checkout','-B','main',PIN)
        self.git(manager,'remote','set-url','origin','https://github.com/folke/lazy.nvim.git')
        self.write_specs()
        self.expected={'lazy.nvim':{'branch':'main','commit':PIN}}
        self.expected.update({name:{'branch':'main','commit':commits[0]} for name,commits in self.commits.items()})
        self.lock=self.config/'lazy-lock.json'; self.write_lock()
        # Minimal fixture API assertions, using the production config startup and update pipeline.
        (self.repo/'lib/nvim-check.lua').write_text('''local ok,e=xpcall(function()
local config=require('lazy.core.config')
local names=vim.tbl_keys(config.plugins)
require('lazy').load({plugins=names})
assert(#(_G.dotfiles_errors or {})==0,table.concat(_G.dotfiles_errors or {},'\\n'))
for _,name in ipairs(names) do assert(config.plugins[name]._.loaded, name) end
assert(require('alpha').value and require('beta').value)
end,debug.traceback)
if not ok then vim.api.nvim_err_writeln(e); vim.cmd('cquit 1') end
vim.cmd('qa')
''')

    def cmd(self,args,expected=0,env=None):
        result=subprocess.run(args,env=env or self.env,cwd=self.base,text=True,capture_output=True,timeout=90)
        self.assertEqual(result.returncode,expected,result.stdout+result.stderr)
        return result

    def git(self,directory,*args):
        return self.cmd(['git','-C',str(directory),*args]).stdout.strip()

    def write_specs(self,extra=''):
        (self.config/'lua/dotfiles/plugins.lua').write_text('''return {
{'folke/lazy.nvim', pin=true, branch='main'},
{'fixture/alpha', branch='main', lazy=true, %s},
{'fixture/beta', branch='main', lazy=true},
}
''' % extra)

    def write_lock(self):
        self.lock.write_text(json.dumps(self.expected,indent=2)+'\n')

    def install(self,expected=0):
        env=dict(self.env,TEST_REPO=str(self.repo))
        return self.cmd(['bash','-c','source "$TEST_REPO/dotfiles.sh"; install_neovim_plugins'],expected,env)

    def update(self,expected=0):
        return self.cmd(['bash',str(self.repo/'bin/.local/bin/update'),'--yes','--nvim'],expected)

    def assert_heads(self,expected):
        for name,entry in expected.items():
            self.assertEqual(self.git(self.plugins/name,'rev-parse','HEAD'),entry['commit'])

    def test_fresh_repeat_rollback_upgrade_downgrade_mixed_missing(self):
        path=self.config/'lua/dotfiles/plugins.lua'
        path.write_text(path.read_text().replace("lazy=true", "lazy=false"))
        before=self.lock.read_bytes()
        self.install(); self.assert_heads(self.expected)
        self.install(); self.assert_heads(self.expected)
        for name in ('alpha','beta'):
            self.git(self.plugins/name,'checkout',self.commits[name][1])
        self.install(); self.assert_heads(self.expected)
        self.assertEqual(self.lock.read_bytes(),before)
        self.expected['alpha']['commit']=self.commits['alpha'][1]; self.write_lock()
        shutil.rmtree(self.plugins/'beta')
        self.install(); self.assert_heads(self.expected)
        self.expected['alpha']['commit']=self.commits['alpha'][0]; self.write_lock()
        self.install(); self.assert_heads(self.expected)

    def test_update_publishes_lock_keeps_manager_and_other_records(self):
        self.install(); dependency_lock=(self.repo/'dotfiles.lock').read_bytes()
        self.update()
        updated=json.loads(self.lock.read_text())
        self.assertEqual(updated['lazy.nvim']['commit'],PIN)
        for name in ('alpha','beta'):
            self.assertEqual(updated[name]['commit'],self.commits[name][1])
        self.assert_heads(updated)
        self.assertEqual((self.repo/'dotfiles.lock').read_bytes(),dependency_lock)

    def test_failed_build_keeps_original_lock(self):
        self.install(); before=self.lock.read_bytes()
        self.write_specs('build=function() error("injected build failure") end')
        result=self.update(1)
        self.assertIn('injected build failure',result.stderr)
        self.assertEqual(self.lock.read_bytes(),before)

    def test_failed_configuration_keeps_original_lock(self):
        self.install(); before=self.lock.read_bytes()
        self.write_specs('config=function() error("injected config failure") end')
        self.update(1)
        self.assertEqual(self.lock.read_bytes(),before)

    def test_failed_clone_restore_and_startup_are_nonzero(self):
        before=self.lock.read_bytes()
        self.git(self.home,'config','--global','--unset-all',f'url.{(self.remote/"alpha").as_uri()}.insteadOf')
        self.git(self.home,'config','--global',f'url.{(self.base/"absent").as_uri()}.insteadOf','https://github.com/fixture/alpha.git')
        self.install(1); self.assertEqual(self.lock.read_bytes(),before)
        self.git(self.home,'config','--global','--unset-all',f'url.{(self.base/"absent").as_uri()}.insteadOf')
        self.git(self.home,'config','--global',f'url.{(self.remote/"alpha").as_uri()}.insteadOf','https://github.com/fixture/alpha.git')
        self.expected['alpha']['commit']='0'*40; self.write_lock()
        invalid=self.lock.read_bytes(); self.install(1)
        self.assertEqual(self.lock.read_bytes(),invalid)
        (self.config/'lua/dotfiles/options.lua').write_text('error("injected init failure")')
        self.install(1)

    def test_update_fetch_failure_keeps_original_lock(self):
        self.install(); before=self.lock.read_bytes()
        shutil.rmtree(self.remote/'alpha')
        self.update(1); self.assertEqual(self.lock.read_bytes(),before)

    def test_equivalent_ssh_origin_does_not_reclone_or_remove_untracked_files(self):
        self.install()
        alpha=self.plugins/'alpha'
        self.git(alpha,'remote','set-url','origin','git@github.com:fixture/alpha.git')
        self.git(self.home,'config','--global','--add',f'url.{(self.remote/"alpha").as_uri()}.insteadOf',
                 'git@github.com:fixture/alpha.git')
        (alpha/'user-file').write_text('preserve me')
        self.update()
        self.assertEqual((alpha/'user-file').read_text(),'preserve me')
        self.assertEqual(self.git(alpha,'config','--get','remote.origin.url'),'git@github.com:fixture/alpha.git')

    def test_build_error_output_without_exception_is_nonzero(self):
        self.install(); before=self.lock.read_bytes()
        self.write_specs('build=function() vim.api.nvim_err_writeln("injected parser failure") end')
        result=self.update(1)
        self.assertIn('injected parser failure',result.stderr)
        self.assertEqual(self.lock.read_bytes(),before)

    def test_silent_build_failure_is_nonzero(self):
        self.install(); before=self.lock.read_bytes()
        self.write_specs('build="false"')
        self.update(1)
        self.assertEqual(self.lock.read_bytes(),before)

    def test_concurrent_lock_edit_is_not_overwritten(self):
        self.install()
        dependency_lock=self.repo/'dotfiles.lock'
        before=self.lock.read_bytes(); original=dependency_lock.read_text()
        self.write_specs('build=function() local f=assert(io.open(' + json.dumps(str(dependency_lock)) +
                         ',"a")); f:write("\\n# concurrent edit\\n"); f:close() end')
        result=self.update(1)
        self.assertIn('changed concurrently',result.stderr)
        self.assertEqual(self.lock.read_bytes(),before)
        self.assertTrue(dependency_lock.read_text().startswith(original))
        self.assertIn('# concurrent edit',dependency_lock.read_text())

    def test_final_publication_failure_preserves_locks(self):
        self.install(); before=self.lock.read_bytes()
        script = """import sys,runpy
from unittest.mock import patch
sys.path.insert(0,sys.argv[1]+'/lib')
repo=sys.argv[1]
sys.argv=[repo+'/lib/update-dependencies.py','nvim','--repo',repo]
with patch('dependencies.os.replace',side_effect=OSError('injected publish failure')):
    runpy.run_path(sys.argv[0],run_name='__main__')
"""
        result=self.cmd(['python3','-c',script,str(self.repo)],1)
        self.assertIn('injected publish failure',result.stderr)
        self.assertEqual(self.lock.read_bytes(),before)
        self.assertEqual(list(self.config.glob('.dotfiles-lock.*')),[])

    def test_missing_manager_and_mismatched_locks_fail(self):
        before=self.lock.read_bytes()
        shutil.rmtree(self.plugins/'lazy.nvim')
        self.update(1); self.assertEqual(self.lock.read_bytes(),before)
        self.expected['lazy.nvim']['commit']='0'*40; self.write_lock()
        result=self.update(1)
        self.assertIn('differ between dependency locks',result.stderr)

    def test_dirty_and_origin_mismatch_fail_before_modification(self):
        self.install(); before=self.lock.read_bytes()
        (self.plugins/'alpha/lua/alpha.lua').write_text('local change')
        self.update(1); self.install(1)
        self.assertEqual((self.plugins/'alpha/lua/alpha.lua').read_text(),'local change')
        self.git(self.plugins/'alpha','checkout','--','lua/alpha.lua')
        self.git(self.plugins/'alpha','remote','set-url','origin','https://evil.invalid/github.com/fixture/alpha.git')
        self.update(1); self.install(1)
        self.assertEqual(self.lock.read_bytes(),before)


if __name__ == '__main__':
    unittest.main(verbosity=2)
