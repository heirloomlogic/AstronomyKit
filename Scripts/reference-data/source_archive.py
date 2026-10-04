"""Read byte-pinned historical inputs without substituting live production code."""
import hashlib
import json
import os
import contextlib
import subprocess
import sys
import tempfile
from pathlib import Path

ARCHIVE = Path('Scripts/reference-data/sources/production-baseline')
MANIFEST_SHA256 = '94914af0b0665173e067cdd75432174117eca979356a67c5926678bc51a4c7a5'


def manifest(root):
    data = (Path(root) / ARCHIVE / 'manifest.json').read_bytes()
    if hashlib.sha256(data).hexdigest() != MANIFEST_SHA256:
        raise ValueError('historical source archive manifest hash mismatch')
    return json.loads(data)


def read_bytes(root, path):
    """Archive only explicitly catalogued historical inputs; all others remain live."""
    root, path = Path(root), Path(path)
    name = path.relative_to(root).as_posix()
    archive = root / ARCHIVE
    catalog = manifest(root)
    if name not in catalog['filesSHA256']:
        return path.read_bytes()
    data = Path(str(archive / name) + '.archive').read_bytes()
    if hashlib.sha256(data).hexdigest() != catalog['filesSHA256'][name]:
        raise ValueError('historical source archive hash mismatch: ' + name)
    return data


def sha256(root, path):
    return hashlib.sha256(read_bytes(root, path)).hexdigest()


@contextlib.contextmanager
def baseline_tree(root):
    """Materialize original C/script inputs; keep the retained references read-only by linkage."""
    root = Path(root)
    catalog = manifest(root)
    for name, expected in catalog['liveAssetsSHA256'].items():
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
            raise ValueError('historical source asset hash mismatch: ' + name)
    with tempfile.TemporaryDirectory(prefix='astronomykit-historical-replay-') as temporary:
        baseline = Path(temporary).resolve()
        def link_with_overrides(name):
            source, target = root / name, baseline / name
            if name in catalog['filesSHA256']:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(read_bytes(root, source))
            elif any(path.startswith(name + '/') for path in catalog['filesSHA256']):
                target.mkdir(parents=True, exist_ok=True)
                for child in source.iterdir():
                    link_with_overrides(name + '/' + child.name)
            else:
                target.symlink_to(source, target_is_directory=source.is_dir())
        for name in ['Documentation', 'Tests', 'Tools', '.context']:
            if (root / name).exists():
                link_with_overrides(name)
        (baseline / 'Scripts/reference-data').mkdir(parents=True)
        for child in (root / 'Scripts').iterdir():
            if child.name != 'reference-data':
                (baseline / 'Scripts' / child.name).symlink_to(child, target_is_directory=child.is_dir())
        archived_script_names = {Path(name).name for name in catalog['filesSHA256'] if name.startswith('Scripts/reference-data/')}
        for child in (root / 'Scripts/reference-data').iterdir():
            if child.name not in archived_script_names:
                (baseline / 'Scripts/reference-data' / child.name).symlink_to(child, target_is_directory=child.is_dir())
        for name in catalog['filesSHA256']:
            target = baseline / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(read_bytes(root, root / name))
        for name in catalog['liveAssetsSHA256']:
            target = baseline / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(root / name)
        migration_source_hashes(root, {})
        for child in (root / 'Sources').iterdir():
            if child.name == 'AstronomyKit':
                destination = baseline / 'Sources/AstronomyKit'
                destination.mkdir()
                for source in child.iterdir():
                    target = destination / source.name
                    if source.name in MIGRATION_RATE_SOURCES:
                        target.write_bytes((root / 'Scripts/reference-data/sources/migration-rate-contract' / (source.name + '.archive')).read_bytes())
                    else:
                        target.symlink_to(source, target_is_directory=source.is_dir())
            elif child.name != 'CLibAstronomy':
                (baseline / 'Sources' / child.name).symlink_to(child, target_is_directory=child.is_dir())
        yield baseline


def replay(root, script, arguments):
    """Run an archived script version; public/current probes continue using the live tree."""
    root = Path(root)
    relative = Path(script).relative_to(root)
    if relative.as_posix() not in manifest(root)['filesSHA256']:
        raise ValueError('uncatalogued historical replay script')
    with baseline_tree(root) as baseline:
        environment = os.environ.copy()
        if (root / '.git').exists():
            environment['GIT_DIR'] = subprocess.check_output(['git', 'rev-parse', '--absolute-git-dir'], cwd=root, text=True).strip()
            environment['GIT_WORK_TREE'] = str(root)
        subprocess.run([sys.executable, str(baseline / relative), *arguments], cwd=baseline, env=environment, check=True)


MIGRATION_RATE_SOURCES = {
    'Position.swift': 'b540d9fe19a55cb6c2a201d6832879a070076a133947181b1da0c5f614edee7e',
    'MoonPhase.swift': '59bee7833b966dd9039e4168a8b498c41c1c9b9e7716fa69d8e6b15caf77db2d',
    'Coordinates.swift': 'b5fe4378043d41a8ac25da5d30c9225d861c3e81d3270d5072c140eeed5d0e38',
}


def migration_source_hashes(root, current):
    """Validate frozen Swift inputs and permit only API-comment changes in live sources."""
    root = Path(root)
    result = dict(current)
    def without_api_comments(data):
        return b'\n'.join(line for line in data.splitlines() if not line.lstrip().startswith(b'///'))
    for name, expected in MIGRATION_RATE_SOURCES.items():
        historical = (root / 'Scripts/reference-data/sources/migration-rate-contract' / (name + '.archive')).read_bytes()
        if hashlib.sha256(historical).hexdigest() != expected:
            raise ValueError('historical migration Swift source hash mismatch: ' + name)
        path = 'Sources/AstronomyKit/' + name
        if without_api_comments((root / path).read_bytes()) != without_api_comments(historical):
            raise ValueError('live migration Swift code differs from historical input: ' + name)
        result[path] = expected
    return result
