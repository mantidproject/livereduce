from mantid import AlgorithmManager, ConfigService
from mantid.simpleapi import FakeISISHistoDAE
from threading import Thread

facility = ConfigService.getFacility().name()
ConfigService.setFacility('TEST_LIVE')

def startServer():
    FakeISISHistoDAE(NPeriods=5,NSpectra=10,NBins=100)


# This will generate 5 periods of histogram data, 10 spectra in each period,
# 100 bins in each spectrum
try:
    thread = Thread(target=startServer)
    thread.start()
    thread.join()
except Exception, e:
    print e
    alg = AlgorithmManager.newestInstanceOf('FakeISISHistoDAE')
    if alg.isRunning():
        alg.cancel()
finally:
    ConfigService.setFacility(facility)
