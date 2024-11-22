This should be a fully working example. All that you need is to add a
working version of mantid. Please note that the server and client need
to be started separately and are configured to be executed with the
conda environment activated

Start Live Data Server
----------------------

This is done by running
```
$ mantidpython --classic test/fake_server.py
```
Unfortunately, there is not currently a clean way to shutdown the
process. `kill -9 <pid>` is the current suggestion.

Start Live Processing
---------------------

Similarly to the server
```
$ PATH=$PATH:/path/with/nsd-app-wrap scripts/livereduce.sh test/fake.conf
```
Once the first chunk of live data is processed, `ctrl-C` will
interrupt the process and it will close cleanly.

In testing mode, the logging will go to `${PWD}/livereduce.log` and can be watched with `tail -F livereduce.log`


Example using event data, to test memory monitoring
----------------------------------------------------

This test case will continuously accumulate events until it fails.

Start the server using `test/fake_event_server.py` and use the configuration `test/fake_event.conf`.
