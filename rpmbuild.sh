#!/bin/sh
rm -rf dist
pixi run build
cp dist/livereduce-*.tar.gz ~/rpmbuild/SOURCES/
rpmbuild -ba livereduce.spec
cp ~/rpmbuild/RPMS/noarch/python-livereduce-*-*.*.noarch.rpm dist/
cp ~/rpmbuild/SRPMS/python-livereduce-*-*.*.src.rpm dist/
