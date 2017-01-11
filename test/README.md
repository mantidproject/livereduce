This should be a fully working example. All that you need is to add a
working version of mantid. Please note that the server and client need
to be started separately.

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
$ mantidpython --classic scripts/livereduce.py test/fake.conf
```
Once the first chunk of live data is processed, `ctrl-C` will
interrupt the process and it will close cleanly.
