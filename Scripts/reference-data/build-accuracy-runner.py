#!/usr/bin/env python3
"""Build the isolated public-API evidence runner without changing frozen targets."""
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PACKAGE=ROOT/'.context/accuracy-qualification/runner-package'
BUILD=ROOT/'.context/accuracy-qualification/build-runner'
MANIFEST='''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AstronomyAccuracyEvidence",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "AccuracyQualificationRunner", targets: ["AccuracyQualificationRunner"])],
    targets: [
        .target(name: "CLibAstronomy", path: "Sources/CLibAstronomy", publicHeadersPath: "include", cSettings: [.headerSearchPath("include")]),
        .target(name: "AstronomyKit", dependencies: ["CLibAstronomy"], path: "Sources/AstronomyKit"),
        .executableTarget(name: "AccuracyQualificationRunner", dependencies: ["AstronomyKit"], path: "Sources/AccuracyQualificationRunner")
    ]
)
'''


def main():
    (PACKAGE/'Sources').mkdir(parents=True,exist_ok=True)
    for name,target in [('AstronomyKit',ROOT/'Sources/AstronomyKit'),('CLibAstronomy',ROOT/'Sources/CLibAstronomy'),('AccuracyQualificationRunner',ROOT/'Tools/Migration/AccuracyQualificationRunner')]:
        link=PACKAGE/'Sources'/name
        if link.is_symlink():
            if link.resolve()!=target.resolve(): raise ValueError('runner package symlink detached from workspace sources')
        elif link.exists(): raise ValueError('runner package source location unexpectedly occupied')
        else: link.symlink_to(target,target_is_directory=True)
    (PACKAGE/'Package.swift').write_text(MANIFEST)
    subprocess.run(['swift','build','--package-path',str(PACKAGE),'--scratch-path',str(BUILD),'--product','AccuracyQualificationRunner'],check=True,cwd=ROOT)

if __name__=='__main__': main()
