from __future__ import (absolute_import, division, print_function)
import os
import signal
import time

####################
# register a signal handler so we can exit gracefully if someone kills us
####################
keep_running = True
def sigterm_handler(sig_received, frame):
    sig_name = {signal.SIGINT:'SIGINT',
                signal.SIGQUIT:'SIGQUIT',
                signal.SIGTERM:'SIGTERM'}

    msg = 'received %s(%d)' % (sig_name[sig_received], sig_received)
    #logger.debug( "SIGTERM received")
    print(msg)
    shutdown_mantid()
    if  sig_received == signal.SIGINT:
        raise KeyboardInterrupt(msg)
    else:
        raise RuntimeError(msg)

# signal.SIGHUP - hangup does nothing
# signal.SIGSTOP - doesn't want to register
# signal.SIGKILL - doesn't want to register
for signal_event in [signal.SIGINT, signal.SIGQUIT, signal.SIGTERM]:
    #print('registering ', str(signal_event))
    signal.signal(signal_event, sigterm_handler)
####################
# end of signal handling
####################

def shutdown_mantid():
    '''Determine if mantid is running and shuts it down'''
    keep_running = False

    if 'AlgorithmManager' in locals() or 'AlgorithmManager' in globals():
        print('shutting down mantid')
        AlgorithmManager.cancelAll()


from mantid import AlgorithmManager # required for clean shutdown to work
from mantid.simpleapi import StartLiveData

direc = '/SNS/PG3/shared/livereduce'
direc = '/home/pf9/Dropbox/projects'
procScript = os.path.join(direc, 'reduce_PG3_live_proc.py')
postProcScript = os.path.join(direc, 'reduce_PG3_live_post_proc.py')

if not os.path.exists(procScript):
    raise RuntimeError('ProcessingScriptFilename \'%s\' does not exist' %
                       procScript)
if not os.path.exists(postProcScript):
    raise RuntimeError('PostProcessingScriptFilename \'%s\' does not exist' %
                       procScript)

# need handle to the `MonitorLiveData` algorithm or it only runs once
try:
    StartLiveData(Instrument='POWGEN',
                  ProcessingScriptFilename=procScript,
                  PostProcessingScriptFilename=postProcScript,
                  FromNow=False,
                  FromStartOfRun=True,
                  UpdateEvery=30,
                  PreserveEvents=True,
                  AccumulationWorkspace='accum',
                  OutputWorkspace='result')
except KeyboardInterrupt:
    print("interupted StartLiveData")
    shutdown_mantid()
    sys.exit(-1)

# need to keep the process going otherwise script will end after one chunk
while keep_running:
    time.sleep(2.0)

# cleanup in the off chance that the script gets here
shutdown_mantid()
sys.exit(0)
