This should be a fully working example. Create a pixi
environment `livereduce` with the required dependencies (specially package `mantid`).
This can be done by `pixi install` then `pixi shell` to activate.
Please note that the server and client need to be started separately in corresponding terminals,
and are configured to be executed with the `livereduce` pixi environment activated.


Start Live Data Server
----------------------

From the root of the repository, on a terminal run:
```
(livereduction)$ pixi run python test/fake_server.py
```
Unfortunately, there is not currently a clean way to shutdown the
process. `kill -9 <pid>` is the current suggestion.

Start Live Processing
---------------------

Similarly to the server, on a different terminal run:
```
(livereduction)$ PATH=$PATH:/path/with/nsd-app-wrap scripts/livereduce.sh test/fake.conf
```
If you don't have access to nsd-app-wrap, run instead:
```
(livereduction)$ pixi run python scripts/livereduce.py test/fake.conf
```

Once the first chunk of live data is processed, `ctrl-C` will
interrupt the process and it will close cleanly.

In testing mode, the logging will go to `${PWD}/livereduce.log` and can be watched with `tail -F livereduce.log`


Testing with post processing script
----------------------------------

An example using only a post-processing script can be tested using the `test/postprocessing/fake.conf`.


Example using event data, to test memory monitoring
----------------------------------------------------

This test case will continuously accumulate events until it fails.

Start the server using `test/fake_event_server.py` and use the configuration `test/fake_event.conf`.


Testing the file watcher
------------------------

`test/test_filewatch.sh` runs `scripts/livereduce_filewatch.sh` on its own, with a stand-in
livereduce.py that records the signals it receives, and a json written the way `livereduce.py`
writes it. It checks which changes send `SIGTERM` and which are ignored, that a stale pid isn't
signalled, that edits made while livereduce restarts are
ignored until the json is republished, saves made of several steps, changes made before the watcher
started, and that the watcher exits when the published paths change.
Only `inotify-tools`, `jq` and python are needed.

```
$ pixi run test-filewatch
```

Testing the file watcher under systemd
--------------------------------------

`test/systemd/` runs `livereduce.service` and `livereduce_filewatch.service` in a container with
systemd as PID 1. It checks that editing a processing script or the configuration restarts livereduce
(`SIGTERM` to the pid it published, then `Restart=always`), and that the watcher also restarts when the script paths
livereduce publishes change.
Mantid and nsd-app-wrap aren't needed: `fake_livereduce.py` and `nsd-app-wrap.sh` stand in for them.

```
$ pixi run test-systemd
```

This needs Docker and runs the container with `--privileged` so that systemd can start.
