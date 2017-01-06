from __future__ import (absolute_import, division, print_function)
import json
import os
import signal
import sys
import time

keep_running = True  # file-global variable to keep the interpreter running

####################
# register a signal handler so we can exit gracefully if someone kills us
####################
# signal.SIGHUP - hangup does nothing
# signal.SIGSTOP - doesn't want to register
# signal.SIGKILL - doesn't want to register
sig_name = {signal.SIGINT: 'SIGINT',
            signal.SIGQUIT: 'SIGQUIT',
            signal.SIGTERM: 'SIGTERM'}


def sigterm_handler(sig_received, frame):
    msg = 'received %s(%d)' % (sig_name[sig_received], sig_received)
    # logger.debug( "SIGTERM received")
    print(msg)
    shutdown_mantid()
    if sig_received == signal.SIGINT:
        raise KeyboardInterrupt(msg)
    else:
        raise RuntimeError(msg)

for signal_event in sig_name.keys():
    # print('registering ', str(signal_event))
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


class Config(object):
    '''
    Configuration storred in json format. The keys are:
    * 'instrument' - missing generates an error
    * 'mantid_loc' - if not specified, goes to environment variable
      ${MANTIDPATH} then defaults to '/opt/Mantid/bin/'
    * 'script_dir' - default value is '/SNS/{instrument}/shared/livereduce'
    '''

    def __init__(self, filename='/etc/liveprocessing.conf'):
        '''Optional arguemnt is the json formatted config file'''
        # read file from json into a dict
        with open(filename, 'r') as handle:
            json_doc = json.load(handle)

        # get mantid location and add to the python path
        self.mantid_loc = json_doc.get('mantid_loc')
        if self.mantid_loc is None:
            self.mantid_loc = os.environ.get('MANTIDPATH')
            if self.mantid_loc is None:
                self.mantid_loc = '/opt/Mantid/bin/'
        sys.path.append(self.mantid_loc)

        # instrument is critical
        self.instrument = self.__getInstrument(json_doc.get('instrument'))

        # location of the scripts
        self.script_dir = json_doc.get('script_dir')
        if self.script_dir is None:
            self.script_dir = '/SNS/%s/shared/livereduce' % \
                              self.instrument.shortName()
        self.script_dir = str(self.script_dir)

        self.__determineScriptNames()

    def __getInstrument(self, instrument):
        from mantid import ConfigService
        if instrument is None:
            print('Using default instrument')
            return ConfigService.getInstrument()
        else:
            return ConfigService.getInstrument(str(instrument))

    def __determineScriptNames(self):
        filenameStart = 'reduce_%s_live' % str(self.instrument.shortName())

        # script for processing each chunk
        self.procScript = filenameStart + '_proc.py'
        self.procScript = os.path.join(self.script_dir, self.procScript)
        if not os.path.exists(self.procScript):
            msg = 'ProcessingScriptFilename \'%s\' does not exist' % \
                  self.procScript
            raise RuntimeError(msg)

        # script for processing accumulation
        self.postProcScript = filenameStart + '_post_proc.py'
        self.postProcScript = os.path.join(self.script_dir,
                                           self.postProcScript)
        if not os.path.exists(self.postProcScript):
            msg = 'PostProcessingScriptFilename \'%s\' does not exist' % \
                  self.postProcScript
            raise RuntimeError(msg)

    def toJson(self):
        values = dict(instrument=self.instrument.shortName(),
                      mantid_loc=self.mantid_loc,
                      script_dir=self.script_dir)
        return json.dumps(values)

config = Config('liveprocessing.conf')
print(config.toJson())

# needs to happen after configuration is loaded
from mantid import AlgorithmManager  # required for clean shutdown to work
from mantid.simpleapi import StartLiveData

# need handle to the `MonitorLiveData` algorithm or it only runs once
try:
    StartLiveData(Instrument=config.instrument.name(),
                  ProcessingScriptFilename=config.procScript,
                  PostProcessingScriptFilename=config.postProcScript,
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
