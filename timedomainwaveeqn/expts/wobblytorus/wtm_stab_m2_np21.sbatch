#!/bin/bash

#SBATCH -n 1
#SBATCH -p ccb
#SBATCH --constraint=broadwell
#SBATCH -t 1-00:00:00
#SBATCH -o wtm_stab_m2_np21.log

module load matlab/R2018a

cd ~/BIE3D/timedomainwaveeqn
matlab -nodesktop -nosplash < wtm_stab_m2_np21.m

# note don't need skylake, since np=21 fits on 130GB machine.
# broadwells seem to be 512GB if not the old ones.
