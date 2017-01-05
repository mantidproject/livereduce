import mantid
from mantid import simpleapi
import os

cal_dir = '/SNS/PG3/shared/CALIBRATION/2016_2_11A_CAL/'
cal_file  = os.path.join(cal_dir, "PG3_PAC_d29581_2016_08_29.h5")
char_file = os.path.join(cal_dir, "PG3_char_2016_08_01-HR.txt") \
            + ',' + os.path.join(cal_dir, "PG3_char_2016_11_22-HR-PAC.txt")

mantid.logger.information('Number events = %d' % input.getNumberEvents())

simpleapi.PDLoadCharacterizations(Filename=char_file,
                                  OutputWorkspace='characterizations')
simpleapi.PDDetermineCharacterizations(InputWorkspace=input,
                                       Characterizations='characterizations',
                                       ReductionProperties='__pd_reduction_properties')
manager = mantid.PropertyManagerDataService.retrieve('__pd_reduction_properties')
simpleapi.Rebin(InputWorkspace=input, OutputWorkspace=input,
                Params=(manager['tof_min'].value,100,manager['tof_max'].value))


if True: #input.getNumberEvents() > 0:
    simpleapi.AlignAndFocusPowder(InputWorkspace=input, OutputWorkspace=output,
                                  CalFilename=cal_file,
                                  Params=-0.0008,
                                  RemovePromptPulseWidth=0, # should be 50
                                  ReductionProperties='__pd_reduction_properties')
    simpleapi.ConvertUnits(InputWorkspace=output, OutputWorkspace=output,
                           Target='dSpacing', EMode='Elastic')
