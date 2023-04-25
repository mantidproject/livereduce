from mantid.simpleapi import Rebin, SumSpectra

SumSpectra(InputWorkspace=input, OutputWorkspace=output)  # noqa: F821
Rebin(InputWorkspace=output, OutputWorkspace=output, Params="300,20,17000")  # noqa: F821
