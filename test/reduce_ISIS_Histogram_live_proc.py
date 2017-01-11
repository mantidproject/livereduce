from mantid.simpleapi import Rebin, SumSpectra

SumSpectra(InputWorkspace=input, OutputWorkspace=output)
Rebin(InputWorkspace=output, OutputWorkspace=output, Params='300,20,17000')
