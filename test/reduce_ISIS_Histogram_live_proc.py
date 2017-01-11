#StartLiveData(Instrument='ISIS_Histogram',  #done
#              OutputWorkspace='wsOut',      #done
#              UpdateEvery=1,                #done
#              AccumulationMethod='Replace', #done
#              PeriodList=[1,3],             #TODO
#              SpectraList=[2,4,6])          #TODO

#print 'number events', input.getNumberEvents()

from mantid.simpleapi import Rebin, SumSpectra

SumSpectra(InputWorkspace=input, OutputWorkspace=output)
Rebin(InputWorkspace=output, OutputWorkspace=output, Params='300,20,17000')
