A `Makefile` project for building CHIRP flatpak.

Requirements:
-------------

* curl
* envsubst 
* flatpak
* flatpak-builder 
* gh
* git 
* gpg 
* make
* python3 
* sed 
  
Usage:
------

```bash
Usage:
  make setup       Gather needed files and runtimes
  make generate    Generate flatpak manifest
  make build       Create flatpak. Requires env: GPG_SIGNING_KEY
  make install     Install flatpak locally
  make bundle      Create flatpak bundle from build
  make archive     Create repo tarball from build
  make release     Upload bundle and repo archive to GitHub Releases. Requires env: GH_TOKEN
  make trigger     Trigger import on remote repository. Requires env: GH_TOKEN
  make clean       Clean the installation
```
