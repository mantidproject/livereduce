from __future__ import (absolute_import, division, print_function)
import json
import logging
import os
import signal
import sys
import time

keep_running = True  # file-global variable to keep the interpreter running


####################
# configure logging
####################
LOG_NAME='livereduce'  # constant for logging
LOG_FILE='/var/log/SNS_applications/livereduce.log'
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# create a file handler
if os.environ['USER'] == 'snsdata':
    handler = logging.FileHandler(LOG_FILE)
else:
    handler = logging.FileHandler('livereduce.log')
handler.setLevel(logging.INFO)

# create a logging format
format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
handler.setFormatter(logging.Formatter(format))

# add the handlers to the logger
logger.addHandler(handler)

logger.info('logging started')
####################
# end of logging configuration
####################



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
    logger.info(msg)
    shutdown_mantid()
    if sig_received == signal.SIGINT:
        raise KeyboardInterrupt(msg)
    else:
        raise RuntimeError(msg)

for signal_event in sig_name.keys():
    logger.debug('registering '+str(signal_event))
    signal.signal(signal_event, sigterm_handler)
####################
# end of signal handling
####################


def shutdown_mantid():
    '''Determine if mantid is running and shuts it down'''
    keep_running = False

    if 'AlgorithmManager' in locals() or 'AlgorithmManager' in globals():
        logger.info('shutting down mantid')
        AlgorithmManager.cancelAll()


class Config(object):
    '''
    Configuration storred in json format. The keys are:
    * 'instrument' - default from ~/.mantid/Mantid.user.properties
    * 'mantid_loc' - if not specified, goes to environment variable
      ${MANTIDPATH} then defaults to '/opt/Mantid/bin/'
    * 'script_dir' - default value is '/SNS/{instrument}/shared/livereduce'
    '''

    def __init__(self, filename):
        '''Optional arguemnt is the json formatted config file'''
        self.logger = logger or logging.getLogger(self.__class__.__name__)

        # read file from json into a dict
        if filename is not None and os.path.exists(filename):
            self.logger.info('Loading configuration from \'%s\'' % filename)
            with open(filename, 'r') as handle:
                json_doc = json.load(handle)
        else:
            self.logger.info('Using default configuration')
            json_doc = dict()

        # get mantid location and add to the python path
        self.mantid_loc = json_doc.get('mantid_loc')
        if self.mantid_loc is None:
            self.mantid_loc = os.environ.get('MANTIDPATH')
            if self.mantid_loc is None:
                self.mantid_loc = '/opt/Mantid/bin/'
        sys.path.append(self.mantid_loc)

        self.instrument = self.__getInstrument(json_doc.get('instrument'))
        self.updateEvery = json_doc.get('update_every', 30) # in seconds
        self.preserveEvents = json_doc.get('preserve_events', True)

        # location of the scripts
        self.script_dir = json_doc.get('script_dir')
        if self.script_dir is None:
            self.script_dir = '/SNS/%s/shared/livereduce' % \
                              self.instrument.shortName()
        self.script_dir = str(self.script_dir)

        self.__determineScriptNames(json_doc.get('post_process', True))

    def __getInstrument(self, instrument):
        try:
            from mantid import ConfigService
            if instrument is None:
                self.logger.info('Using default instrument')
                return ConfigService.getInstrument()
            else:
                return ConfigService.getInstrument(str(instrument))
        except ImportError, e:
            self.logger.error('Failed to import mantid', exc_info=True)
            raise

    def __determineScriptNames(self, tryPostProcess):
        filenameStart = 'reduce_%s_live' % str(self.instrument.shortName())

        # script for processing each chunk
        self.procScript = filenameStart + '_proc.py'
        self.procScript = os.path.join(self.script_dir, self.procScript)
        if not os.path.exists(self.procScript):
            msg = 'ProcessingScriptFilename \'%s\' does not exist' % \
                  self.procScript
            raise RuntimeError(msg)

        # script for processing accumulation
        self.postProcScript = None  # signifies nothing to be done in post-processing
        if tryPostProcess:
            self.postProcScript = filenameStart + '_post_proc.py'
            self.postProcScript = os.path.join(self.script_dir,
                                               self.postProcScript)
            if not os.path.exists(self.postProcScript):
                self.postProcScript = None
                msg = 'PostProcessingScriptFilename \'%s\' does not exist' % \
                      self.postProcScript
                self.logger.info(msg, 'not running post-proccessing')

    def toStartLiveArgs(self):

        args = dict(Instrument=self.instrument.name(),
                    UpdateEvery=self.updateEvery,
                    PreserveEvents=self.preserveEvents,
                    ProcessingScriptFilename=self.procScript,
                    OutputWorkspace='result')


        # these must be in agreement with each other
        args['FromNow'] = False
        args['FromStartOfRun'] = True

        if self.postProcScript is not None:
            args['AccumulationWorkspace'] = 'accumulation'
            args['PostProcessingScriptFilename'] = self.postProcScript

        return args

    def toJson(self, **kwargs):
        values = dict(instrument=self.instrument.shortName(),
                      mantid_loc=self.mantid_loc,
                      script_dir=self.script_dir,
                      update_every=self.updateEvery,
                      preserve_events=self.preserveEvents,
                      post_process=(self.postProcScript is not None))

        return json.dumps(values, **kwargs)

# determine the configuration file
config = ['/etc/livereduce.conf']
if len(sys.argv) > 1:
    config.insert(0, sys.argv[1])
config = [filename for filename in config
          if os.path.exists(filename)]
if len(config) > 0:
    config = config[0]
else:
    config = None

# convert configuration from filename to object and print it out
config = Config(config)
logger.info('Configuration options: '
            + config.toJson(sort_keys=True, indent=2))

# needs to happen after configuration is loaded
from mantid import AlgorithmManager  # required for clean shutdown to work
from mantid.simpleapi import StartLiveData

# need handle to the `MonitorLiveData` algorithm or it only runs once
liveArgs = config.toStartLiveArgs()
logger.info('StartLiveData(' + json.dumps(liveArgs, sort_keys=True, indent=2)
            + ')')

try:
    StartLiveData(**liveArgs)
except KeyboardInterrupt:
    logger.info("interupted StartLiveData")
    shutdown_mantid()
    sys.exit(-1)

# need to keep the process going otherwise script will end after one chunk
while keep_running:
    time.sleep(2.0)

# cleanup in the off chance that the script gets here
shutdown_mantid()
sys.exit(0)
