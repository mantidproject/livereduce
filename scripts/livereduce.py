from __future__ import (absolute_import, division, print_function)
import json
import logging
import os
import signal
import sys
import time

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
class LiveDataManager(object):
    '''class for handling ``StartLiveData`` and ``MonitorLiveData``'''
    logger = logger or logging.getLogger(self.__class__.__name__)

    def __init__(self, config):
        self.config = config

    def start(self):
        liveArgs = self.config.toStartLiveArgs()
        self.logger.info('StartLiveData('
                         + json.dumps(liveArgs, sort_keys=True, indent=2)
                         + ')')
        try:
            mantid.simpleapi.StartLiveData(**liveArgs)
        except KeyboardInterrupt:
            self.logger.info("interupted StartLiveData")
            self.stop()
            sys.exit(-1)

    @classmethod
    def stop(cls):
        '''Determine if mantid is running and shuts it down'''
        if 'mantid' in locals() or 'mantid' in globals():
            cls.logger.info('stopping live data processing')
            mantid.AlgorithmManager.cancelAll()
        else:
            cls.logger.info('mantid not initialized - nothing to cleanup')


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
    LiveDataManager.stop()
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


####################
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
        self.configfile = None
        if filename is not None and os.path.exists(filename):
            self.configfile = filename
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
        self.accumMethod = str(json_doc.get('accum_method', 'Add'))
        self.periods= json_doc.get('periods', None)
        self.spectra = json_doc.get('spectra', None)

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
                instrument = ConfigService.getInstrument(str(instrument))
                facility = instrument.facility().name()
                # set the facility if it isn't the default
                if facility != ConfigService.getFacility().name():
                    ConfigService.setFacility(facility)
                return instrument
        except ImportError, e:
            self.logger.error('Failed to import mantid', exc_info=True)
            raise

    def __validateStartLvieDataProps(self):
        alg = mantid.AlgorithmManager.createUnmanaged('StartLiveData')
        alg.initialize()

        allowed = alg.getProperty('AccumulationMethod').allowedValues
        if not self.accumMethod in allowed:
            msg = 'accumulation method \'%s\' is not allowed ' \
                  % self.accumMethod
            msg += str(allowed)
            raise RuntimeError(msg)


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
        self.__validateStartLvieDataProps()

        args = dict(Instrument=self.instrument.name(),
                    UpdateEvery=self.updateEvery,
                    PreserveEvents=self.preserveEvents,
                    ProcessingScriptFilename=self.procScript,
                    AccumulationMethod=self.accumMethod,
                    OutputWorkspace='result')


        # these must be in agreement with each other
        args['FromNow'] = False
        args['FromStartOfRun'] = True

        if self.postProcScript is not None:
            args['AccumulationWorkspace'] = 'accumulation'
            args['PostProcessingScriptFilename'] = self.postProcScript

        if self.periods is not None:
            args['PeriodList'] = self.periods

        if self.spectra is not None:
            args['spectra'] = self.spectra

        return args

    def toJson(self, **kwargs):
        values = dict(instrument=self.instrument.shortName(),
                      mantid_loc=self.mantid_loc,
                      script_dir=self.script_dir,
                      update_every=self.updateEvery,
                      preserve_events=self.preserveEvents,
                      post_process=(self.postProcScript is not None),
                      accum_method=self.accumMethod)

        if self.periods is not None:
            values['periods'] = self.periods

        if self.spectra is not None:
            values['spectra'] = self.spectra

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
import mantid

# start up the live data
liveDataMgr = LiveDataManager(config)
liveDataMgr.start()

# need to keep the process going otherwise script will end after one chunk
while True:
    time.sleep(2.0)

# cleanup in the off chance that the script gets here
liveDataMgr.stop()
sys.exit(0)
