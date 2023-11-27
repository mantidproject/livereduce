#!/bin/sh
rm -rf dist livereduce.egg-info
python -m build --sdist --no-isolation
cp dist/livereduce-*.tar.gz ~/rpmbuild/SOURCES/
rpmbuild -ba livereduce.spec
cp ~/rpmbuild/RPMS/noarch/python-livereduce-*-*.*.noarch.rpm dist/
cp ~/rpmbuild/SRPMS/python-livereduce-*-*.*.src.rpm dist/
