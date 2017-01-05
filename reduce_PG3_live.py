from mantid import AlgorithmManager
from mantid.simpleapi import StartLiveData
import os
import sys
import time

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
    print "interupted StartLiveData"
    alg = AlgorithmManager.newestInstanceOf("StartLiveData")
    alg.cancel()
    while alg.isRunning():
        time.sleep(0.1)
    sys.exit(-1)

keep_running = True
while keep_running:
    try:
        time.sleep(2.0)
    except KeyboardInterrupt:
        print "interupted"
        keep_running = False

alg = AlgorithmManager.newestInstanceOf("MonitorLiveData")
if alg.isRunning():
    alg.cancel()
    while alg.isRunning():
        time.sleep(0.1)

sys.exit(0)
