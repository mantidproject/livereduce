import mantid
from mantid import simpleapi

simpleapi.CompressEvents(InputWorkspace=input, OutputWorkspace=output)
if simpleapi.mtd[str(input)].run().getProtonCharge() > 0.:
    simpleapi.NormaliseByCurrent(InputWorkspace=input, OutputWorkspace=output)

simpleapi.PDDetermineCharacterizations(InputWorkspace=output,
                                       Characterizations='characterizations',
                                       ReductionProperties='__pd_reduction_properties')
manager = mantid.PropertyManagerDataService.retrieve('__pd_reduction_properties')

def getRunId(manager, key):
    value = manager[key].value[0]
    if value == 0:
        return None
    else:
        return 'PG3_'+str(value)

def smooth(wksp):
    simpleapi.ConvertUnits(InputWorkspace=wksp, OutputWorkspace=wksp,
                           Target='TOF', EMode='Elastic')
    simpleapi.FFTSmooth(InputWorkspace=wksp,
                        OutputWorkspace=wksp,
                        Filter="Butterworth",
                        Params='20,2',
                        IgnoreXBins=True,
                        AllSpectra=True)
    simpleapi.ConvertUnits(InputWorkspace=wksp, OutputWorkspace=wksp,
                           Target='dSpacing', EMode='Elastic')


processingParams = {'CalibrationWorkspace':'PG3_cal',
                    'GroupingWorkspace':'PG3_group',
                    'MaskWorkspace':'PG3_mask',
                    'Params':-0.0008,
                    'RemovePromptPulseWidth':0, # should be 50
                    'ReductionProperties':'__pd_reduction_properties'}

can = getRunId(manager, 'container')
if can is not None and not simpleapi.mtd.doesExist(can):
    mantid.logger.information("processing container '%s'" % can)
    simpleapi.LoadEventNexus(Filename=can, OutputWorkspace=can)
    simpleapi.AlignAndFocusPowder(InputWorkspace=can, OutputWorkspace=can,
                                  **processingParams)
    simpleapi.ConvertUnits(InputWorkspace=can, OutputWorkspace=can,
                           Target='dSpacing', EMode='Elastic')
    simpleapi.NormaliseByCurrent(InputWorkspace=can, OutputWorkspace=can)
    #smooth(can)

if can is not None:
    simpleapi.Minus(LHSWorkspace=output, RHSWorkspace=can, OutputWorkspace=output)

van = getRunId(manager, 'vanadium')
if van is not None and not simpleapi.mtd.doesExist(van):
    mantid.logger.information("processing vanadium '%s'" % van)
    simpleapi.LoadEventNexus(Filename=van, OutputWorkspace=van)
    simpleapi.AlignAndFocusPowder(InputWorkspace=van, OutputWorkspace=van,
                                  **processingParams)
    simpleapi.NormaliseByCurrent(InputWorkspace=van, OutputWorkspace=van)

    vanback = getRunId(manager, 'vanadium_background')
    if vanback is not None:
        mantid.logger.information("processing vanadium background '%s'" % vanback)
        simpleapi.LoadEventNexus(Filename=vanback, OutputWorkspace='__vanback')
        vanback = '__vanback'
        simpleapi.AlignAndFocusPowder(InputWorkspace=vanback, OutputWorkspace=vanback,
                                      **processingParams)
        simpleapi.NormaliseByCurrent(InputWorkspace=vanback, OutputWorkspace=vanback)

        mantid.logger.information("subtracting vanadium background")
        simpleapi.Minus(LHSWorkspace=van, RHSWorkspace=vanback, OutputWorkspace=van,
                        ClearRHSWorkspace=True)
        simpleapi.DeleteWorkspace(Workspace=vanback)
        simpleapi.CompressEvents(InputWorkspace=van, OutputWorkspace=van)


    simpleapi.ConvertUnits(InputWorkspace=van, OutputWorkspace=van,
                            Target='dSpacing', EMode='Elastic')
    simpleapi.StripVanadiumPeaks(InputWorkspace=van, OutputWorkspace=van,
                                  BackgroundType='Quadratic', PeakPositionTolerance=.05)
    smooth(van)


if van is not None:
    simpleapi.Divide(LHSWorkspace=output, RHSWorkspace=van, OutputWorkspace=output)

##### generate plot and post
div = simpleapi.SavePlot1D(InputWorkspace=output, OutputType='plotly')

try:
    runNumber = simpleapi.mtd[output].run().get('run_number').value
except:
    runNumber = simpleapi.mtd[str(input)].run().get('run_number').value

mantid.logger.information('Posting plot of PG3_%s' % runNumber)
try: # version on autoreduce
    from postprocessing.publish_plot import publish_plot
except ImportError: # version on instrument computers
    from finddata import publish_plot
request = publish_plot('PG3', runNumber, files={'file':div})
mantid.logger.information("post returned %d" % request.status_code)
mantid.logger.information("resulting document:")
mantid.logger.information(str(request.text))
