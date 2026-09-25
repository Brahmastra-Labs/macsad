"""Read-only consistency checks for local candidate build evidence.

Never imports or executes candidate.py. This is not release admission, a signed
attestation, a hermetic dependency audit, or independent build reproduction.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tomllib

SCHEMA = 'macsad-logos-built-candidate/1'
MODE = 'development-built-candidate'
SKIP = {'target', '.git', '.lake', 'node_modules', '__pycache__', '.DS_Store'}
ROOT_INPUTS = ['Cargo.toml','Cargo.lock','README.md','LICENSE.md','AGENTS.md','CLAUDE.md',
               'LOGOS_QUICKGUIDE.md','docs','.cargo/config.toml','.config/nextest.toml',
               'scripts/lean-demo.sh','scripts/lean-contract-fixtures.sh',
               'reference-kernels/lean4export','work/alejandro/contract']
MAX_FILES = 100000
MAX_BYTES = 1_000_000_000


def pin(value):
    if not isinstance(value,str) or re.fullmatch('[0-9a-f]{64}',value) is None:
        raise ValueError('invalid candidate SHA-256 pin')
    return value


def confined(root, path):
    path=Path(os.path.abspath(path))
    if not path.is_relative_to(root):
        raise ValueError('candidate input escapes source root')
    for current in [path,*path.parents]:
        if current == root.parent:
            break
        if current.is_symlink():
            raise ValueError('candidate symlink is not allowed')
    return path


def regular(path, executable=False):
    data=path.lstat()
    if not stat.S_ISREG(data.st_mode) or data.st_nlink != 1:
        raise ValueError('candidate input must be an independent regular file')
    if executable and not os.access(path,os.X_OK):
        raise ValueError('candidate binary is not executable')
    return data


def digest(path):
    before=regular(path)
    result=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):
            result.update(chunk)
    after=regular(path)
    fields=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_mode,s.st_nlink)
    if fields(before)!=fields(after):
        raise ValueError('candidate input changed while hashing')
    return result.hexdigest()


def unique(pairs):
    value={}
    for key,item in pairs:
        if key in value:
            raise ValueError('duplicate candidate evidence field')
        value[key]=item
    return value


def read_json(path, limit=65536):
    if regular(path).st_size>limit:
        raise ValueError('candidate evidence exceeds size limit')
    return json.loads(path.read_text(),object_pairs_hook=unique,
                      parse_constant=lambda _:(_ for _ in ()).throw(ValueError('nonfinite evidence number')))


def keys(value, expected):
    if not isinstance(value,dict) or set(value)!=set(expected.split()):
        raise ValueError('unexpected candidate evidence fields')


def timestamp(value):
    if not isinstance(value,str):
        raise ValueError('invalid candidate evidence timestamp')
    result=datetime.datetime.fromisoformat(value)
    if result.tzinfo is None:
        raise ValueError('candidate timestamps require a timezone')
    return result


def read_text(path):
    if regular(path).st_size>16*1024*1024:
        raise ValueError('candidate source parser limit exceeded')
    return path.read_text()


def files_below(root, path):
    path=confined(root,path)
    if path.is_file():
        regular(path)
        yield path
        return
    if not path.is_dir():
        raise ValueError('required candidate source input missing')
    entries=0
    for directory,dirs,files in os.walk(path,followlinks=False):
        dirs[:]=sorted(d for d in dirs if d not in SKIP and not d.startswith('target-'))
        entries+=len(dirs)+len(files)
        if entries>MAX_FILES or len(Path(directory).relative_to(root).parts)>64:
            raise ValueError('candidate source inventory limit exceeded')
        for name in dirs:
            confined(root,Path(directory)/name)
        for name in sorted(files):
            if name in SKIP:
                continue
            item=confined(root,Path(directory)/name)
            regular(item)
            yield item


def selection(root):
    workspace=tomllib.loads(read_text(confined(root,root/'Cargo.toml')))
    patterns=workspace['workspace']['members']
    if not isinstance(patterns,list) or not patterns or len(patterns)>MAX_FILES:
        raise ValueError('invalid candidate workspace members')
    members=set()
    for pattern in patterns:
        if not isinstance(pattern,str) or Path(pattern).is_absolute() or '..' in Path(pattern).parts:
            raise ValueError('invalid candidate member pattern')
        matches=[confined(root,p) for p in root.glob(pattern) if (p/'Cargo.toml').is_file()]
        if not matches:
            raise ValueError('candidate workspace member unresolved')
        members.update(matches)
    pending=list(members)+[root];visited=set()
    while pending:
        member=pending.pop()
        if member in visited:
            continue
        visited.add(member)
        if len(visited)>MAX_FILES:
            raise ValueError('candidate manifest limit exceeded')
        data=tomllib.loads(read_text(confined(root,member/'Cargo.toml')))
        def dependency_paths(value):
            if isinstance(value,dict):
                if isinstance(value.get('path'),str):
                    yield value['path']
                for item in value.values():
                    yield from dependency_paths(item)
            elif isinstance(value,list):
                for item in value:
                    yield from dependency_paths(item)
        for relative in dependency_paths(data):
            dependency=Path(os.path.abspath(member/relative))
            if (dependency/'Cargo.toml').is_file():
                dependency=confined(root,dependency)
                if dependency not in members and dependency!=root:
                    members.add(dependency);pending.append(dependency)
    chosen=set()
    for member in sorted(members):
        chosen.update(files_below(root,member))
    for relative in ROOT_INPUTS:
        chosen.update(files_below(root,root/relative))
    for relative in ['rust-toolchain','rust-toolchain.toml','.cargo/config']:
        if (root/relative).exists() or (root/relative).is_symlink():
            chosen.update(files_below(root,root/relative))
    pending=list(chosen);scanned=set()
    while pending:
        path=pending.pop()
        if path in scanned or path.suffix!='.rs':
            continue
        scanned.add(path)
        if 'src' not in path.parts and path.name!='build.rs':
            continue
        source='\n'.join(line for line in read_text(path).splitlines() if not line.lstrip().startswith('//'))
        for match in re.finditer(r'include_(?:str|bytes)!\(\s*"([^"\n]+)"\s*\)',source):
            target=confined(root,path.parent/match.group(1));regular(target)
            if target not in chosen:
                chosen.add(target);pending.append(target)
        if len(chosen)>MAX_FILES:
            raise ValueError('candidate selected source limit exceeded')
    return {p.relative_to(root).as_posix() for p in chosen},sorted(p.relative_to(root).as_posix() for p in members)


def verify(candidate, binary_pin, inventory_pin):
    """Validate the exact bounded candidate.py copy/build schema, without running it."""
    try:
        return _verify(candidate,pin(binary_pin),pin(inventory_pin))
    except (OSError,TypeError,KeyError,UnicodeError,tomllib.TOMLDecodeError,RecursionError) as error:
        raise ValueError('invalid or unavailable local candidate evidence/source') from error


def _verify(candidate,binary_pin,inventory_pin):
    if candidate.is_symlink():
        raise ValueError('candidate root must be a real directory')
    candidate=candidate.resolve(strict=True)
    source=confined(candidate,candidate/'repo');evidence=confined(candidate,candidate/'evidence')
    if not source.is_dir() or not evidence.is_dir() or (source/'.git').exists() or (source/'.git').is_symlink():
        raise ValueError('candidate must be an independent source copy without .git')
    paths={name:confined(candidate,evidence/name) for name in ['copy.json','binary.json','source-inputs.json','largo-build.command.json']}
    for name,path in paths.items():
        if regular(path).st_size>(8*1024*1024 if name=='source-inputs.json' else 65536):
            raise ValueError('candidate evidence exceeds size limit')
    evidence_hashes={name:digest(path) for name,path in paths.items()}
    if evidence_hashes['source-inputs.json']!=inventory_pin:
        raise ValueError('candidate source inventory pin mismatch')
    copy=read_json(paths['copy.json']);binary=read_json(paths['binary.json']);command=read_json(paths['largo-build.command.json'])
    inventory=read_json(paths['source-inputs.json'],8*1024*1024)
    keys(copy,'schema completed_utc source repo members files bytes source_inventory_sha256 hardlinks symlinks shared_dependencies')
    keys(binary,'path sha256 bytes source_inventory_sha256 built_from')
    keys(command,'argv cwd environment_overrides exit_code started_utc finished_utc')
    if (copy['schema']!='logos-demo-copy/1' or copy['repo']!=str(source) or copy['hardlinks'] is not False
        or copy['symlinks'] is not False or copy['source_inventory_sha256']!=inventory_pin
        or binary['built_from']!=str(source) or binary['sha256']!=binary_pin
        or binary['source_inventory_sha256']!=inventory_pin):
        raise ValueError('candidate evidence cross-link mismatch')
    argv=command['argv'];environment=command['environment_overrides']
    keys(environment,'CARGO_TARGET_DIR CARGO_BUILD_JOBS ELAN_TOOLCHAIN PATH')
    if (not isinstance(argv,list) or len(argv)!=9 or not all(isinstance(a,str) for a in argv)
        or Path(argv[0]).name!='cargo' or argv[1:]!=['build','--offline','--locked','--release','-p','logicaffeine-cli','--bin','largo']
        or command['cwd']!=str(source) or type(command['exit_code']) is not int or command['exit_code']!=0
        or environment['CARGO_TARGET_DIR']!=str(candidate/'build')
        or not all(isinstance(v,str) and v for v in environment.values())
        or not timestamp(copy['completed_utc'])<=timestamp(command['started_utc'])<=timestamp(command['finished_utc'])):
        raise ValueError('candidate does not record the expected successful independent build')
    if not isinstance(inventory,dict) or not 1<=len(inventory)<=MAX_FILES:
        raise ValueError('invalid candidate inventory')
    total=0
    for relative,record in inventory.items():
        relative_path=PurePosixPath(relative)
        if (not relative or relative_path.is_absolute() or '..' in relative_path.parts or '\\' in relative
            or relative_path.as_posix()!=relative or relative=='.'):
            raise ValueError('invalid candidate inventory path')
        keys(record,'sha256 bytes mode');pin(record['sha256'])
        if type(record['bytes']) is not int or record['bytes']<0 or type(record['mode']) is not int or not 0<=record['mode']<=0o7777:
            raise ValueError('invalid candidate inventory metadata')
        total+=record['bytes']
        if total>MAX_BYTES:
            raise ValueError('candidate source byte limit exceeded')
        path=confined(source,source/relative);data=regular(path)
        if data.st_size!=record['bytes'] or stat.S_IMODE(data.st_mode)!=record['mode'] or digest(path)!=record['sha256']:
            raise ValueError('candidate source bytes or metadata changed: '+relative)
    names,members=selection(source)
    if names!=set(inventory) or members!=copy['members'] or type(copy['files']) is not int or copy['files']!=len(inventory) or type(copy['bytes']) is not int or copy['bytes']!=total:
        raise ValueError('candidate source/member inventory changed')
    frozen=confined(candidate,evidence/('largo-'+binary_pin));binary_data=regular(frozen,executable=True)
    if binary_data.st_size>512*1024*1024 or binary['path']!=str(frozen) or type(binary['bytes']) is not int or binary_data.st_size!=binary['bytes'] or digest(frozen)!=binary_pin:
        raise ValueError('candidate frozen binary mismatch')
    # Also detect metadata replacement during the source walk/hash pass.
    if any(digest(paths[name])!=value for name,value in evidence_hashes.items()):
        raise ValueError('candidate evidence changed during verification')
    return {'candidate':str(candidate),'workspace':str(source),'binary':str(frozen),
            'binary_sha256':binary_pin,'source_inventory_sha256':inventory_pin,
            'evidence_sha256':evidence_hashes,
            'source':{'files':len(inventory),'bytes':total,'members':members,'source_inventory_sha256':inventory_pin}}
