from threading import Thread

from mantid import AlgorithmManager, ConfigService
from mantid.simpleapi import FakeISISEventDAE

facility = ConfigService.getFacility().name()
ConfigService.setFacility("TEST_LIVE")


def startServer():
    FakeISISEventDAE(NEvents=1000000)


try:
    thread = Thread(target=startServer)
    thread.start()
    thread.join()
except Exception as e:  # noqa: BLE001
    print(e)
    alg = AlgorithmManager.newestInstanceOf("FakeISISEventDAE")
    if alg.isRunning():
        alg.cancel()
finally:
    ConfigService.setFacility(facility)
