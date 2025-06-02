This should be a fully working example. Create a conda
environment `livereduce` with the required dependencies (specially package `mantid`).
Please note that the server and client need to be started separately in corresponding terminals,
and are configured to be executed with the `livereduction` conda environment activated.


Start Live Data Server
----------------------

From the root of the repository, on a terminal run:
```
(livereduction)$ mantidpython --classic test/fake_server.py
```
if you did not install mantid's `workbench` (no `mantidpython` command) but just the mantid backend, run:
```
(livereduction)$ python test/fake_server.py
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
(livereduction)$ python scripts/livereduce.py test/fake.conf --test
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
