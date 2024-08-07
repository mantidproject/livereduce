import json
import logging
import os
import signal
import sys
import time
from hashlib import md5

import mantid  # for clearer error message
import pyinotify
from mantid.simpleapi import StartLiveData
from mantid.utils.logging import log_to_python as mtd_log_to_python
from packaging.version import parse as parse_version

# ##################
# configure logging
# ##################
LOG_NAME = "livereduce"  # constant for logging
LOG_FILE = "/var/log/SNS_applications/livereduce.log"

# mantid should let python logging do the work
mtd_log_to_python("information")
logging.getLogger("Mantid").setLevel(logging.INFO)

# create a file handler
if os.environ["USER"] == "snsdata":
    fileHandler = logging.FileHandler(LOG_FILE)
else:
    fileHandler = logging.FileHandler("livereduce.log")
fileHandler.setLevel(logging.INFO)
# set the logging format
logformat = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
fileHandler.setFormatter(logging.Formatter(logformat))

# create a stream handler
streamHandler = logging.StreamHandler()
streamHandler.setLevel(logging.INFO)
streamHandler.addFilter(logging.Filter("Mantid"))

# add the handlers to the root logger
logging.getLogger().addHandler(fileHandler)
logging.getLogger().addHandler(streamHandler)


logging.getLogger(LOG_NAME).setLevel(logging.INFO)
logger = logging.getLogger(LOG_NAME)

logger.info("logging started by user '" + os.environ["USER"] + "'")
logger.info(f"using python interpreter {sys.executable}")


# ##################
class LiveDataManager:
    """class for handling ``StartLiveData`` and ``MonitorLiveData``"""

    logger = logging.getLogger(LOG_NAME + ".LiveDataManager")

    def __init__(self, config):
        self.config = config

    def start(self):
        mtd_log_to_python("information")

        liveArgs = self.config.toStartLiveArgs()
        self.logger.info("StartLiveData(" + json.dumps(liveArgs, sort_keys=True, indent=2) + ")")
        try:
            StartLiveData(**liveArgs)
        except KeyboardInterrupt:
            self.logger.info("interrupted StartLiveData")
            self.stop()
            sys.exit(-1)

    @classmethod
    def stop(cls):
        """Determine if mantid is running and shuts it down"""
        if "mantid" in locals() or "mantid" in globals():
            cls.logger.info("stopping live data processing")
            mantid.AlgorithmManager.cancelAll()
        else:
            cls.logger.info("mantid not initialized - nothing to cleanup")


# ##################
# register a signal handler so we can exit gracefully if someone kills us
# ##################
# signal.SIGHUP - hangup does nothing
# signal.SIGSTOP - doesn't want to register
# signal.SIGKILL - doesn't want to register
sig_name = {signal.SIGINT: "SIGINT", signal.SIGQUIT: "SIGQUIT", signal.SIGTERM: "SIGTERM"}


def sigterm_handler(sig_received, frame):  # noqa: ARG001
    msg = "received %s(%d)" % (sig_name[sig_received], sig_received)
    # logger.debug( "SIGTERM received")
    logger.info(msg)
    LiveDataManager.stop()
    if sig_received == signal.SIGINT:
        raise KeyboardInterrupt(msg)
    elif sig_received == signal.SIGTERM:
        sys.exit(0)
    else:
        raise RuntimeError(msg)


for signal_event in sig_name.keys():
    logger.debug("registering " + str(signal_event))
    signal.signal(signal_event, sigterm_handler)
####################
# end of signal handling
####################


####################
class Config:
    r"""
    Configuration stored in json format. The keys are:
    * 'instrument' - default from ~/.mantid/Mantid.user.properties
    * 'CONDA_ENV' - if not specified, defaults to 'mantid-dev'
    * 'script_dir' - default value is '/SNS/{instrument}/shared/livereduce'
    """

    def __init__(self, filename):
        r"""Optional argument is the json formatted config file"""
        self.logger = logging.getLogger(LOG_NAME + ".Config")

        # read file from json into a dict
        self.filename = None
        if filename is not None and os.path.exists(filename) and os.path.getsize(filename) > 0:
            self.filename = os.path.abspath(filename)
            self.logger.info(f"Loading configuration from '{filename}'")
            with open(filename) as handle:
                json_doc = json.load(handle)
            logger.debug(json.dumps(json_doc))
        else:
            self.logger.info("Using default configuration")
            json_doc = dict()
        self.logger.info("Finished parsing configuration")

        # log the conda environment and mantid's location
        self.conda_env = json_doc.get("CONDA_ENV", "mantid-dev")
        self.logger.info(f"CONDA_ENV = {self.conda_env}")
        self.logger.info(f'mantid_loc="{os.path.dirname(mantid.__file__)}"')

        try:
            from mantid.kernel import UsageService

            # to differentiate from other apps
            UsageService.setApplicationName("livereduce")
        except Exception:
            self.logger.error("General error while importing " "mantid.kernel.ConfigService:", exc_info=True)
            raise

        self.instrument = self.__getInstrument(json_doc.get("instrument"))
        self.logger.info(f'self.instrument="{self.instrument}"')
        self.updateEvery = int(json_doc.get("update_every", 30))  # in seconds
        self.preserveEvents = json_doc.get("preserve_events", True)
        self.accumMethod = str(json_doc.get("accum_method", "Add"))
        self.periods = json_doc.get("periods", None)
        self.spectra = json_doc.get("spectra", None)

        # location of the scripts
        self.script_dir = json_doc.get("script_dir")
        if self.script_dir is None:
            self.script_dir = f"/SNS/{self.instrument.shortName()!s}/shared/livereduce"
        else:
            self.script_dir = os.path.abspath(self.script_dir)

        self.script_dir = str(self.script_dir)

        self.__determineScriptNames()
        self.logger.info(f"bottom of Config.__init__({filename})")

    def __getInstrument(self, instrument):
        try:
            from mantid.kernel import ConfigService

            if instrument is None:
                self.logger.info("Using default instrument")
                return ConfigService.getInstrument()
            else:
                self.logger.info("Converting instrument using ConfigService")
                instrument = ConfigService.getInstrument(str(instrument))
                facility = instrument.facility().name()
                # set the facility if it isn't the default
                if facility != ConfigService.getFacility().name():
                    ConfigService.setFacility(facility)
                return instrument
        except ImportError:
            self.logger.error("Failed to import mantid.ConfigService", exc_info=True)
            raise
        except:
            self.logger.error("General error while getting instrument", exc_info=True)
            raise

    def __validateStartLiveDataProps(self):
        alg = mantid.AlgorithmManager.createUnmanaged("StartLiveData")
        alg.initialize()

        allowed = alg.getProperty("AccumulationMethod").allowedValues
        if self.accumMethod not in allowed:
            msg = f"accumulation method '{self.accumMethod}' is not allowed "
            msg += str(allowed)
            raise ValueError(msg)

    def __determineScriptNames(self):
        filenameStart = f"reduce_{self.instrument.shortName()!s}_live"

        # script for processing each chunk
        self.procScript = filenameStart + "_proc.py"
        self.procScript = os.path.join(self.script_dir, self.procScript)
        if not os.path.exists(self.procScript):
            msg = f"ProcessingScriptFilename '{self.procScript}' does not exist"
            raise RuntimeError(msg)

        if os.path.getsize(self.procScript) <= 0:
            msg = f"ProcessingScriptFilename '{self.procScript}' is empty"
            raise RuntimeError(msg)

        # script for processing accumulation
        self.postProcScript = filenameStart + "_post_proc.py"
        self.postProcScript = os.path.join(self.script_dir, self.postProcScript)

    def toStartLiveArgs(self):
        self.__validateStartLiveDataProps()

        args = dict(
            Instrument=self.instrument.name(),
            UpdateEvery=self.updateEvery,
            PreserveEvents=self.preserveEvents,
            ProcessingScriptFilename=self.procScript,
            AccumulationMethod=self.accumMethod,
            OutputWorkspace="result",
        )

        # these must be in agreement with each other
        args["FromNow"] = False
        args["FromStartOfRun"] = True

        if os.path.exists(self.postProcScript) and os.path.getsize(self.postProcScript) > 0:
            args["AccumulationWorkspace"] = "accumulation"
            args["PostProcessingScriptFilename"] = self.postProcScript

        if self.periods is not None:
            args["PeriodList"] = self.periods

        if self.spectra is not None:
            args["spectra"] = self.spectra

        return args

    def toJson(self, **kwargs):
        args = dict(
            instrument=self.instrument.shortName(),
            CONDA_ENV=self.conda_env,
            script_dir=self.script_dir,
            update_every=self.updateEvery,
            preserve_events=self.preserveEvents,
            accum_method=self.accumMethod,
        )

        if self.periods is not None:
            args["periods"] = self.periods

        if self.spectra is not None:
            args["spectra"] = self.spectra

        return json.dumps(args, **kwargs)


####################
class EventHandler(pyinotify.ProcessEvent):
    logger = logging.getLogger(LOG_NAME + ".EventHandler")

    def __init__(self, config, livemanager):
        # files that we actually care about
        self.configfile = config.filename
        self.scriptdir = config.script_dir

        # key=filename
        # value=md5sum of contents to track if file actually changed
        self.scriptfiles = {
            config.procScript: self._md5(config.procScript),
            config.postProcScript: self._md5(config.postProcScript),
        }

        # thing controlling the actual work
        self.livemanager = livemanager

    def _md5(self, filename):
        if filename and os.path.exists(filename):
            # starting in python 3.9 one can point out md5 is not used in security context
            if parse_version(f"{sys.version_info.major}.{sys.version_info.minor}") < parse_version("3.9"):
                md5sum = md5(open(filename, "rb").read())  # noqa: S324
            else:
                md5sum = md5(open(filename, "rb").read(), usedforsecurity=False)
            return md5sum.hexdigest()
        else:
            return ""

    def filestowatch(self):
        if self.configfile:
            return [self.scriptdir, self.configfile]
        else:
            return self.scriptdir

    def process_default(self, event):
        # changing the config file means just restart
        if event.pathname == self.configfile:
            self.logger.warning("Modifying configuration file is not supported" + "- shutting down")
            self.livemanager.stop()
            raise KeyboardInterrupt("stop inotify")

        # changing the (post) processing script means restart LiveDataManager
        # with new scripts
        if event.pathname in self.scriptfiles.keys():
            newmd5 = self._md5(event.pathname)
            if newmd5 == self.scriptfiles[event.pathname]:
                self.logger.info(f'Processing script "{event.pathname}" has not changed md5' "sum - continuing")
            else:
                # update the md5 sum associated with the file
                self.scriptfiles[event.pathname] = newmd5
                # restart the service
                self.logger.info(f'Processing script "{event.pathname}" changed - restarting ' '"StartLiveData"')
                self.livemanager.stop()
                time.sleep(1.0)  # seconds
                self.livemanager.start()


# determine the configuration file
config = ["/etc/livereduce.conf"]
if len(sys.argv) > 1:
    config.insert(0, sys.argv[1])
config = [filename for filename in config if os.path.exists(filename) and os.path.getsize(filename) > 0]
if len(config) > 0:
    config = config[0]
else:
    config = None

# convert configuration from filename to object and print it out
config = Config(config)
logger.info("Configuration options: " + config.toJson(sort_keys=True, indent=2))

# for passing into the eventhandler for inotify
liveDataMgr = LiveDataManager(config)

handler = EventHandler(config, liveDataMgr)
wm = pyinotify.WatchManager()
notifier = pyinotify.Notifier(wm, handler)

# watched events
mask = pyinotify.IN_DELETE | pyinotify.IN_MODIFY | pyinotify.IN_CREATE
logger.info(f"WATCHING:{handler.filestowatch()}")
wm.add_watch(handler.filestowatch(), mask)

# start up the live data
liveDataMgr.start()

# inotify will keep the program running
notifier.loop()

# cleanup in the off chance that the script gets here
liveDataMgr.stop()
sys.exit(0)
