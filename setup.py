from setuptools import setup, find_packages
import os
import sys

setup(name="livereduce",
      version="1.6",
      description = "Need a description",
      author = "Pete Peterson",
      author_email = "petersonpf@ornl.gov",
      url = "https://github.com/mantidproject/livereduce",
      long_description = """Daemon for running live data reduction with systemd""",
      license = "The MIT License (MIT)",
      scripts=["scripts/livereduce.py"],
      packages=find_packages(),
      package_dir={},
      install_requires=['pyinotify'],
      setup_requires=[],
      data_files=[('/usr/lib/systemd/system/', ['livereduce.service'])]
)
