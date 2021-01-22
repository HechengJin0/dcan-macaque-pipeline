#!/bin/bash
#set -e

export PATH=`echo $PATH | sed 's|freesurfer/|freesurfer53/|g'`
export OMP_NUM_THREADS=1
echo "we are actually running this code" 
# Requirements for this script
#  installed versions of: FSL5.0.2 or higher , FreeSurfer (version 5 or higher) , gradunwarp (python code from MGH)
#  environment: use SetUpHCPPipeline.sh  (or individually set FSLDIR, FREESURFER_HOME, HCPPIPEDIR, PATH - for gradient_unwarp.py)

# make pipeline engine happy...
if [ $# -eq 1 ]
then
echo "Version unknown..."
exit 0
fi

########################################## PIPELINE OVERVIEW ##########################################

# TODO

########################################## OUTPUT DIRECTORIES ##########################################

# TODO

################################################ SUPPORT FUNCTIONS ##################################################

# function for parsing options
getopt1() {
	sopt="$1"
		shift 1
		for fn in $@ ; do
			if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
				echo $fn | sed "s/^${sopt}=//"
					return 0
					fi
					done
}

defaultopt() {
	echo $1
}

################################################## OPTION PARSING #####################################################
#set echo

# Just give usage if no arguments specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi

# parse arguments
Path=`getopt1 "--path" $@`  # "$1"
Subject=`getopt1 "--subject" $@`  # "$2"
NameOffMRI=`getopt1 "--fmriname" $@`  # "$6"
fMRITimeSeries=`getopt1 "--fmritcs" $@`  # "$3"
fMRIScout=`getopt1 "--fmriscout" $@`  # "$4"
SpinEchoPhaseEncodeNegative=`getopt1 "--SEPhaseNeg" $@`  # "$7"
SpinEchoPhaseEncodePositive=`getopt1 "--SEPhasePos" $@`  # "$5"
MagnitudeInputName=`getopt1 "--fmapmag" $@`  # "$8" #Expects 4D volume with two 3D timepoints
MagnitudeInputBrainName=`getopt1 "--fmapmagbrain" $@` # If you've already masked the magnitude.
PhaseInputName=`getopt1 "--fmapphase" $@`  # "$9"
DwellTime=`getopt1 "--echospacing" $@`  # "${11}"
deltaTE=`getopt1 "--echodiff" $@`  # "${12}"
UnwarpDir=`getopt1 "--unwarpdir" $@`  # "${13}"
FinalfMRIResolution=`getopt1 "--fmrires" $@`  # "${14}"
DistortionCorrection=`getopt1 "--dcmethod" $@`  # "${17}" #FIELDMAP or TOPUP
GradientDistortionCoeffs=`getopt1 "--gdcoeffs" $@`  # "${18}"
TopupConfig=`getopt1 "--topupconfig" $@`  # "${20}" #NONE if Topup is not being used
ContrastEnhanced=`getopt1 "--ce" $@`
RUN=`getopt1 "--printcom" $@`  # use ="echo" for just printing everything and not running the commands (default is to run)
useT2=`getopt1 "--useT2" $@`
useRevEpi=`getopt1 "--userevepi" $@` # true/false uses the scout brain and reverse se/reverse epi instead of a spin echo pair.
PreviousTask=`getopt1 "--previousregistration" $@`
if [ ! -z $PreviousTask ]; then
if [[ $PreviousTask =~ task-.* ]]; then
PreviousRegistration=true
else
echo "previousregistration $PreviousTask must start with a 'task-'"
fi
else
PreviousRegistration=false
fi

set -ex
# Setup PATHS
PipelineScripts=${HCPPIPEDIR_fMRIVol}
GlobalScripts=${HCPPIPEDIR_Global}
GlobalBinaries=${HCPPIPEDIR_Bin}

#Naming Conventions
T1wImage="T1w_acpc_dc"
T1wRestoreImage="T1w_acpc_dc_restore"
T1wRestoreImageBrain="T1w_acpc_dc_restore_brain"
T1wFolder="T1w" #Location of T1w images
AtlasSpaceFolder="MNINonLinear"
ResultsFolder="Results"
BiasField="BiasField_acpc_dc"
BiasFieldMNI="BiasField"
T1wAtlasName="T1w_restore"
MovementRegressor="Movement_Regressors" #No extension, .txt appended
MotionMatrixFolder="MotionMatrices"
MotionMatrixPrefix="MAT_"
FieldMapOutputName="FieldMap"
MagnitudeOutputName="Magnitude"
MagnitudeBrainOutputName="Magnitude_brain"
ScoutName="Scout"
OrigScoutName="${ScoutName}_orig"
OrigTCSName="${NameOffMRI}_orig"
FreeSurferBrainMask="brainmask_fs"
fMRI2strOutputTransform="${NameOffMRI}2str"
RegOutput="Scout2T1w"
AtlasTransform="acpc_dc2standard"
OutputfMRI2StandardTransform="${NameOffMRI}2standard"
Standard2OutputfMRITransform="standard2${NameOffMRI}"
QAImage="T1wMulEPI"
JacobianOut="Jacobian"
SubjectFolder="$Path"
########################################## DO WORK ##########################################
T1wFolder="$Path"/"$T1wFolder"
AtlasSpaceFolder="$Path"/"$AtlasSpaceFolder"
ResultsFolder="$AtlasSpaceFolder"/"$ResultsFolder"/"$NameOffMRI"

fMRIFolder="$Path"/"$NameOffMRI"
echo
if [ ! -e "$fMRIFolder" ] ; then
	mkdir "$fMRIFolder"
fi
cp "$fMRITimeSeries" "$fMRIFolder"/"$OrigTCSName".nii.gz

#Create fake "Scout" if it doesn't exist
if [ $fMRIScout = "NONE" ] ; then
	${RUN} ${FSLDIR}/bin/fslroi "$fMRIFolder"/"$OrigTCSName" "$fMRIFolder"/"$OrigScoutName" 0 1
	FakeScout="True"
else
	cp "$fMRIScout" "$fMRIFolder"/"$OrigScoutName".nii.gz
fi

#Gradient Distortion Correction of fMRI
if [ ! $GradientDistortionCoeffs = "NONE" ] ; then
	mkdir -p "$fMRIFolder"/GradientDistortionUnwarp
	${RUN} "$GlobalScripts"/GradientDistortionUnwarp.sh \
		--workingdir="$fMRIFolder"/GradientDistortionUnwarp \
		--coeffs="$GradientDistortionCoeffs" \
		--in="$fMRIFolder"/"$OrigTCSName" \
		--out="$fMRIFolder"/"$NameOffMRI"_gdc \
		--owarp="$fMRIFolder"/"$NameOffMRI"_gdc_warp

	mkdir -p "$fMRIFolder"/"$ScoutName"_GradientDistortionUnwarp
	${RUN} "$GlobalScripts"/GradientDistortionUnwarp.sh \
		--workingdir="$fMRIFolder"/"$ScoutName"_GradientDistortionUnwarp \
		--coeffs="$GradientDistortionCoeffs" \
		--in="$fMRIFolder"/"$OrigScoutName" \
		--out="$fMRIFolder"/"$ScoutName"_gdc \
		--owarp="$fMRIFolder"/"$ScoutName"_gdc_warp
else
	echo "NOT PERFORMING GRADIENT DISTORTION CORRECTION"
	${RUN} ${FSLDIR}/bin/imcp "$fMRIFolder"/"$OrigTCSName" "$fMRIFolder"/"$NameOffMRI"_gdc
	${RUN} ${FSLDIR}/bin/fslroi "$fMRIFolder"/"$NameOffMRI"_gdc "$fMRIFolder"/"$NameOffMRI"_gdc_warp 0 3
	${RUN} ${FSLDIR}/bin/fslmaths "$fMRIFolder"/"$NameOffMRI"_gdc_warp -mul 0 "$fMRIFolder"/"$NameOffMRI"_gdc_warp
	${RUN} ${FSLDIR}/bin/imcp "$fMRIFolder"/"$OrigScoutName" "$fMRIFolder"/"$ScoutName"_gdc
fi


echo "RUNNING MOTIONCORRECTION_FLIRTBASED"
mkdir -p "$fMRIFolder"/MotionCorrection_MCFLIRTbased
### ERIC'S DEBUGGING ECHO ###
${RUN} "$PipelineScripts"/MotionCorrection.sh \
	"$fMRIFolder"/MotionCorrection_MCFLIRTbased \
	"$fMRIFolder"/"$NameOffMRI"_gdc \
	"$fMRIFolder"/"$ScoutName"_gdc \
	"$fMRIFolder"/"$NameOffMRI"_mc \
	"$fMRIFolder"/"$MovementRegressor" \
	"$fMRIFolder"/"$MotionMatrixFolder" \
	"$MotionMatrixPrefix" \
	"MCFLIRT"

if [ ${FakeScout} = "True" ] ; then
	fslmaths "$fMRIFolder"/"$NameOffMRI"_mc -Tmean "$fMRIFolder"/"$ScoutName"_gdc
	invwarp -r "$fMRIFolder"/"$NameOffMRI"_gdc_warp -w "$fMRIFolder"/"$NameOffMRI"_gdc_warp -o "$fMRIFolder"/"$NameOffMRI"_gdc_invwarp
	applywarp --interp=spline -i "$fMRIFolder"/"$ScoutName"_gdc -r "$fMRIFolder"/"$ScoutName"_gdc -w "$fMRIFolder"/"$NameOffMRI"_gdc_invwarp -o "$fMRIFolder"/"$OrigScoutName"
fi


#EPI Distortion Correction and EPI to T1w Registration
if [ -e ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased ] ; then
	rm -r ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased
fi
mkdir -p ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased


if [ $DistortionCorrection = FIELDMAP ]; then 									
	### ERIC'S DEBUGGING ECHO ###
	# INSERTING MANUAL MASK IF IT IS FOUND IN PATH...
	if [ -e ${fMRIFolder}/../masks/${Subject}_${NameOffMRI}_mask.nii.gz ]; then 					
		echo "using manual mask for this subject..."
		InputMaskImage=${fMRIFolder}/../masks/${Subject}_${NameOffMRI}_mask.nii.gz
	fi

	${RUN} ${PipelineScripts}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased.sh \
		--workingdir=${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased \
		--scoutin=${fMRIFolder}/${ScoutName}_gdc \
		--t1=${T1wFolder}/${T1wImage} \
		--t1restore=${T1wFolder}/${T1wRestoreImage} \
		--t1brain=${T1wFolder}/${T1wRestoreImageBrain} \
		--fmapmag=${MagnitudeInputName} \
		--fmapphase=${PhaseInputName} \
		--echodiff=${deltaTE} \
		--SEPhaseNeg=${SpinEchoPhaseEncodeNegative} \
		--SEPhasePos=${SpinEchoPhaseEncodePositive} \
		--echospacing=${DwellTime} \
		--unwarpdir=${UnwarpDir} \
		--owarp=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
		--biasfield=${T1wFolder}/${BiasField} \
		--oregim=${fMRIFolder}/${RegOutput} \
		--freesurferfolder=${T1wFolder} \
		--freesurfersubjectid=${Subject} \
		--gdcoeffs=${GradientDistortionCoeffs} \
		--qaimage=${fMRIFolder}/${QAImage} \
		--method=${DistortionCorrection} \
		--topupconfig=${TopupConfig} \
		--ojacobian=${fMRIFolder}/${JacobianOut} \
		--ce=${ContrastEnhanced} \
		--inputmask=$InputMaskImage


elif [ $DistortionCorrection = TOPUP ]; then 
	echo "Running VOL with TOPUP"									
	if [ ! -e ${fMRIFolder}/FieldMap ]; then 								
		mkdir ${fMRIFolder}/FieldMap 2> /dev/null
	fi

	if ! ${PreviousRegistration:-false}; then 								
		if ${useRevEpi:-false}; then										
			SpinEchoPhaseEncodePositive=${fMRIFolder}/${ScoutName}_gdc
		fi
		echo  ${HCPPIPEDIR_Global}/TopupPreprocessingAll.sh \
			--workingdir=${fMRIFolder}/FieldMap \
			--phaseone=${SpinEchoPhaseEncodePositive} \
			--phasetwo=${SpinEchoPhaseEncodeNegative} \
			--scoutin=${fMRIFolder}/${ScoutName}_gdc \
			--echospacing=${DwellTime} \
			--unwarpdir=${SEUnwarpDir} \
			--ofmapmag=${fMRIFolder}/Magnitude \
			--ofmapmagbrain=${fMRIFolder}/Magnitude_brain \
			--ofmap=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
			--ojacobian=${fMRIFolder}/${JacobianOut} \
			--gdcoeffs=${GradientDistortionCoeffs} \
			--topupconfig=${TopupConfig}
		${HCPPIPEDIR_Global}/TopupPreprocessingAll.sh \
			--workingdir=${fMRIFolder}/FieldMap \
			--phaseone=${SpinEchoPhaseEncodeNegative} \
			--phasetwo=${SpinEchoPhaseEncodePositive} \
			--scoutin=${fMRIFolder}/${ScoutName}_gdc \
			--echospacing=${DwellTime} \
			--unwarpdir=${UnwarpDir} \
			--ofmapmag=${fMRIFolder}/Magnitude \
			--ofmapmagbrain=${fMRIFolder}/Magnitude_brain \
			--owarp=${fMRIFolder}/WarpField \
			--ojacobian=${fMRIFolder}/${JacobianOut} \
			--gdcoeffs=${GradientDistortionCoeffs} \
			--topupconfig=${TopupConfig}
			echo "this is another test"

		###########################################################################################################################################################################
		###########################################################################################################################################################################

		echo " this is T2 imaged restore ${T2wRestoreImage} "

		if [[ "TRUE"==${useT2^^} ]]; then							
			T2wRestoreImage=T2w_acpc_dc_restore
			T2wRestoreImageBrain=T2w_acpc_dc_restore_brain
		else											
			${FSLDIR}/bin/fslmaths ${T1wFolder}/${T1wRestoreImage} -mul -1 ${T1wFolder}/T2w_acpc_dc_restore.nii.gz
			${FSLDIR}/bin/fslmaths ${T1wFolder}/T2w_acpc_dc_restore.nii.gz -add 500 ${T1wFolder}/T2w_acpc_dc_restore.nii.gz
			${FSLDIR}/bin/fslmaths ${T1wFolder}/T2w_acpc_dc_restore.nii.gz -uthrp 95 ${T1wFolder}/T2w_acpc_dc_restore.nii.gz
			${FSLDIR}/bin/fslmaths ${T1wFolder}/T2w_acpc_dc_restore.nii.gz -mas ${T1wFolder}/T1w_acpc_brain_mask.nii.gz ${T1wFolder}/T2w_acpc_dc_restore_brain.nii.gz
			T2wRestoreImage=T2w_acpc_dc_restore
			T2wRestoreImageBrain=T2w_acpc_dc_restore_brain
			#T1wImage=T1w_acpc_dc_restore ##not sure where this comes from, so this could be a different image. 
		fi


		echo "this is name of MRI ${NameOffMRI}"
		echo `ls /opt/anatsesh/${NameOffMRI}`
		if [ -e /opt/anatsesh/${NameOffMRI} ]; then						
			echo "session specific anat has been input, will use this to register func 2 T1 brain"
			echo "this is the session we are currently running ${NameOffMRI}"
			seshT1=($(ls /opt/anatsesh/${NameOffMRI}/*T1w.nii.gz))
			cp ${seshT1} ${fMRIFolder}/T1sesh_head.nii.gz
			#Start with the regular steps of the pipeline to get the func mask using the baseline T2 head
			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${fMRIFolder}/${ScoutName}_gdc -w ${fMRIFolder}/WarpField.nii.gz -o ${fMRIFolder}/${ScoutName}_gdc_undistorted
			# apply Jacobian correction to scout image (optional)
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted -mul ${fMRIFolder}/FieldMap/Jacobian ${fMRIFolder}/${ScoutName}_gdc_undistorted
			# register undistorted scout image to T2w head
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/${ScoutName}_gdc_undistorted -ref ${T1wFolder}/${T2wRestoreImage} -omat "$fMRIFolder"/Scout2T2w.mat -out ${fMRIFolder}/Scout2T2w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo
			${FSLDIR}/bin/convert_xfm -omat "$fMRIFolder"/T2w2Scout.mat -inverse "$fMRIFolder"/Scout2T2w.mat
			${FSLDIR}/bin/applywarp --interp=nn -i ${T1wFolder}/${T2wRestoreImageBrain} -r ${fMRIFolder}/${ScoutName}_gdc_undistorted --premat="$fMRIFolder"/T2w2Scout.mat -o ${fMRIFolder}/Scout_brain_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/Scout_brain_mask.nii.gz -bin ${fMRIFolder}/Scout_brain_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted -mas ${fMRIFolder}/Scout_brain_mask.nii.gz ${fMRIFolder}/Scout_brain_dc.nii.gz

			#NameOffMRI=ses-combined_task-MOVIEacq20181030_run-1
			if [ -e /opt/anatsesh/${NameOffMRI}/*_brain.nii.gz ]; then											
				seshT1_brain=($(ls /opt/anatsesh/${NameOffMRI}/*_brain.nii.gz))
				cp ${seshT1_brain} ${fMRIFolder}/T1sesh_brain.nii.gz
			else																		
				#denoise this image
				${ANTSPATH}${ANTSPATH:+/}DenoiseImage -d 3 -n Rician -i ${fMRIFolder}/T1sesh_head.nii.gz -v -o ${fMRIFolder}/T1sesh_head.nii.gz
				#and bias field correct it
				${ANTSPATH}${ANTSPATH:+/}N4BiasFieldCorrection -v -r -d 3 -c [50x50x50x300] -i ${fMRIFolder}/T1sesh_head.nii.gz -v -o ${fMRIFolder}/T1sesh_head.nii.gz

				#then use UNet to create a mask of the brain
				${HCPPIPEDIR_masking}/runUNet.sh ${fMRIFolder}/T1sesh_head.nii.gz ${fMRIFolder}/
				#dialate mask with fslmaths because we don't have AFNI installed in this docker

				${FSLDIR}/bin/fslmaths ${fMRIFolder}/T1sesh_head_pre_mask.nii.gz -kernel boxv 5 -dilD ${fMRIFolder}/T1sesh_head_pre_mask_filled.nii.gz
				#and apply that mask to the head to get the session T1 brain
				${FSLDIR}/bin/fslmaths ${fMRIFolder}/T1sesh_head.nii.gz -mas ${fMRIFolder}/T1sesh_head_pre_mask_filled.nii.gz ${fMRIFolder}/T1sesh_brain.nii.gz
			fi
			#now flirt Register this brain to the baseline brain 
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/T1sesh_brain.nii.gz -ref ${T1wFolder}/${T1wRestoreImageBrain} -omat "$fMRIFolder"/T1sesh2T1base.mat -out ${fMRIFolder}/T1sesh2T1base -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo
			#invert this registration to then apply to the brain in a second
			${FSLDIR}/bin/convert_xfm -omat "$fMRIFolder"/T1base2T1sesh.mat -inverse "$fMRIFolder"/T1sesh2T1base.mat
			#apply inverted transform to baseline brain to get it to session space for later masking
			${FSLDIR}/bin/applywarp --interp=nn -i ${T1wFolder}/${T1wRestoreImageBrain} -r ${fMRIFolder}/T1sesh_brain.nii.gz --premat="$fMRIFolder"/T1base2T1sesh.mat -o ${fMRIFolder}/T1sesh_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/T1sesh_mask.nii.gz -bin ${fMRIFolder}/T1sesh_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/T1sesh_head.nii.gz -mas ${fMRIFolder}/T1sesh_mask.nii.gz ${fMRIFolder}/T1sesh_brain.nii.gz

			#after making new brain, register to baseline again and then use this transform to concat later
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/T1sesh_brain.nii.gz -ref ${T1wFolder}/${T1wRestoreImageBrain} -omat "$fMRIFolder"/T1sesh2T1base2.mat -out ${fMRIFolder}/T1sesh2T1base2 -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo

			## and now register scout brain made in the first section to this session T1 brain   
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/Scout_brain_dc.nii.gz -ref ${fMRIFolder}/T1sesh_brain.nii.gz -omat "$fMRIFolder"/${ScoutName}_gdc_undistorted2sessionT1w_init.mat -out ${fMRIFolder}/${ScoutName}_gdc_undistorted2sessionT1w_brain_init -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo

			#concatonate the t1 sesh to baseline and the func brain to t1 brain  
			convert_xfm -omat ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -concat "$fMRIFolder"/T1sesh2T1base2.mat "$fMRIFolder"/${ScoutName}_gdc_undistorted2sessionT1w_init.mat

			#  generate combined warpfields and spline interpolated images + apply bias field correction
			${FSLDIR}/bin/convertwarp --relout --rel -r ${T1wFolder}/${T2wRestoreImage} --warp1=${fMRIFolder}/WarpField --postmat=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp




			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/Jacobian.nii.gz -r ${T1wFolder}/${T1wRestoreImage} --premat=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -o ${fMRIFolder}/Jacobian2T1w.nii.gz 
			#applywarp that is a combination of the Warpfiled and func brain to T1 brain to scout gdc
			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${T1wFolder}/${T1wRestoreImage} -w ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp -o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init ##This is the warp that will be copied to T1w/xfms later. 

			# apply Jacobian correction to scout image (optional)
			#  
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init -div ${T1wFolder}/${BiasField} -mul ${fMRIFolder}/Jacobian2T1w.nii.gz ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.nii.gz
			SUBJECTS_DIR=${T1wFolder}


		else																	

			# This is what it runs if there is no anatsesh folder, so it runs this one under TOPUP
			echo "now its trying the else statement"
			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${fMRIFolder}/${ScoutName}_gdc -w ${fMRIFolder}/WarpField.nii.gz -o ${fMRIFolder}/${ScoutName}_gdc_undistorted
			# apply Jacobian correction to scout image (optional)
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted -mul ${fMRIFolder}/FieldMap/Jacobian ${fMRIFolder}/${ScoutName}_gdc_undistorted
			# register undistorted scout image to T2w head
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/${ScoutName}_gdc_undistorted -ref ${T1wFolder}/${T2wRestoreImage} -omat "$fMRIFolder"/Scout2T2w.mat -out ${fMRIFolder}/Scout2T2w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo
			${FSLDIR}/bin/convert_xfm -omat "$fMRIFolder"/T2w2Scout.mat -inverse "$fMRIFolder"/Scout2T2w.mat
			${FSLDIR}/bin/applywarp --interp=nn -i ${T1wFolder}/${T2wRestoreImageBrain} -r ${fMRIFolder}/${ScoutName}_gdc_undistorted --premat="$fMRIFolder"/T2w2Scout.mat -o ${fMRIFolder}/Scout_brain_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/Scout_brain_mask.nii.gz -bin ${fMRIFolder}/Scout_brain_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted -mas ${fMRIFolder}/Scout_brain_mask.nii.gz ${fMRIFolder}/Scout_brain_dc.nii.gz
			## re-registering the maked brain to the T1 brain:  
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/Scout_brain_dc.nii.gz -ref ${T1wFolder}/${T1wRestoreImageBrain} -omat "$fMRIFolder"/${ScoutName}_gdc_undistorted2T1w_init.mat -out ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_brain_init -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo

			#  generate combined warpfields and spline interpolated images + apply bias field correction
			${FSLDIR}/bin/convertwarp --relout --rel -r ${T1wFolder}/${T2wRestoreImage} --warp1=${fMRIFolder}/WarpField --postmat=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp

			#applywarp of func brain to T1 brain to the jacobian
			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/Jacobian.nii.gz -r ${T1wFolder}/${T2wRestoreImage} --premat=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -o ${fMRIFolder}/Jacobian2T1w.nii.gz 
		#applywarp that is a combination of the Warpfiled and func brain to T1 brain to scout gdc
			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${T1wFolder}/${T2wRestoreImage} -w ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp -o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init ##This is the warp that will be copied to T1w/xfms later. 

		# apply Jacobian correction to scout image (optional)
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init -div ${T1wFolder}/${BiasField} -mul ${fMRIFolder}/Jacobian2T1w.nii.gz ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.nii.gz
			SUBJECTS_DIR=${T1wFolder}
		fi

		###########################################################################################################################################################################
		###########################################################################################################################################################################


		#@TODO re-evaluate: this xfm may be lackluster compared to a proper bbr.  We could try the resolved bbr from WashU's pipe.
		cp ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp.nii.gz ${T1wFolder}/xfms/${fMRI2strOutputTransform}.nii.gz
		imcp ${fMRIFolder}/Jacobian2T1w.nii.gz ${fMRIFolder}/$JacobianOut #  this is the proper "JacobianOut" for input into OneStepResampling.

	elif ${PreviousRegistration}; then							
		#  take bold results, as they tend to be more accurate transforms until we can improve them.  Combine rigid ferumox -> bold
		echo "using ${PreviousTask} to calculate ${NameOffMRI} registration to anatomical"
		PrevTaskFolder="$Path"/${PreviousTask}
		Lin2PrevTask="${fMRIFolder}"/${PreviousTask}_2_${NameOffMRI}.mat
		flirt -in "${fMRIFolder}"/Scout_orig.nii.gz -cost mutualinfo -dof 6 -ref "${PrevTaskFolder}"/Scout_orig.nii.gz -omat ${Lin2PrevTask}
		PrevTaskTransform=${PreviousTask}2str
		imcp "$PrevTaskFolder"/"$JacobianOut" "$fMRIFolder"/"$JacobianOut"
		convertwarp --rel --relout --out=${T1wFolder}/xfms/${fMRI2strOutputTransform}.nii.gz --warp1=${T1wFolder}/xfms/${PrevTaskTransform}.nii.gz --premat=${Lin2PrevTask} --ref=${T1wFolder}/${T1wImage}
	fi
	#####################################################################################################################################################################
	####Starting Bene's work around if no fieldmaps exist. 
elif [ $DistortionCorrection = NONE ]; then	
	echo "Running VOL and distortion Correction is NONE" 					
	if [ ! -e ${fMRIFolder}/FieldMap ]; then						
		mkdir ${fMRIFolder}/FieldMap 2> /dev/null
	fi

	if ! ${PreviousRegistration:-false}; then						
		#if ${useRevEpi:-false}; then								
			#SpinEchoPhaseEncodePositive=${fMRIFolder}/${ScoutName}_gdc
		#fi
		if [[ "TRUE"==${useT2^^} ]]; then							
			T2wRestoreImage=T2w_acpc_dc_restore
			T2wRestoreImageBrain=T2w_acpc_dc_restore_brain
		else											
			${FSLDIR}/bin/fslmaths ${T1wFolder}/${T1wRestoreImage} -mul -1 ${T1wFolder}/T2w_acpc_dc_restore.nii.gz
			${FSLDIR}/bin/fslmaths ${T1wFolder}/T2w_acpc_dc_restore.nii.gz -add 500 ${T1wFolder}/T2w_acpc_dc_restore.nii.gz
			${FSLDIR}/bin/fslmaths ${T1wFolder}/T2w_acpc_dc_restore.nii.gz -uthrp 95 ${T1wFolder}/T2w_acpc_dc_restore.nii.gz
			${FSLDIR}/bin/fslmaths ${T1wFolder}/T2w_acpc_dc_restore.nii.gz -mas ${T1wFolder}/T1w_acpc_brain_mask.nii.gz ${T1wFolder}/T2w_acpc_dc_restore_brain.nii.gz
			T2wRestoreImage=T2w_acpc_dc_restore
			T2wRestoreImageBrain=T2w_acpc_dc_restore_brain
		fi
		##Added from HCP pipline to fake jacobians
		#${RUN} ${FSLDIR}/bin/imcp "$fMRIFolder"/"$OrigTCSName" "$fMRIFolder"/"$NameOffMRI"_gdc
		#${RUN} ${FSLDIR}/bin/fslroi "$fMRIFolder"/"$NameOffMRI"_gdc "$fMRIFolder"/"$NameOffMRI"_gdc_warp 0 3
		#${RUN} ${FSLDIR}/bin/fslmaths "$fMRIFolder"/"$NameOffMRI"_gdc_warp -mul 0 "$fMRIFolder"/"$NameOffMRI"_gdc_warp
		#${RUN} ${FSLDIR}/bin/imcp "$fMRIFolder"/"$OrigScoutName" "$fMRIFolder"/"$ScoutName"_gdc

		#make fake jacobians of all 1s, for completeness
		#${RUN} ${FSLDIR}/bin/fslmaths "$fMRIFolder"/"$OrigScoutName" -mul 0 -add 1 "$fMRIFolder"/"$ScoutName"_gdc_warp_jacobian
		#${RUN} ${FSLDIR}/bin/fslroi "$fMRIFolder"/"$NameOffMRI"_gdc_warp "$fMRIFolder"/"$NameOffMRI"_gdc_warp_jacobian 0 1
		#${RUN} ${FSLDIR}/bin/fslmaths "$fMRIFolder"/"$NameOffMRI"_gdc_warp_jacobian -mul 0 -add 1 "$fMRIFolder"/"$NameOffMRI"_gdc_warp_jacobian

		#T1wImage=T1w_acpc_dc_restore ##not sure where this comes from, so this could be a different image. 

		echo "this is name of MRI ${NameOffMRI}"
		echo `ls /opt/anatsesh/${NameOffMRI}`

		if [ -e /opt/anatsesh/${NameOffMRI} ]; then						
			echo "session specific anat has been input, will use this to register func 2 T1 brain"
			echo "this is the session we are currently running ${NameOffMRI}"
			seshT1=($(ls /opt/anatsesh/${NameOffMRI}/*T1w.nii.gz))
			cp ${seshT1} ${fMRIFolder}/T1sesh_head.nii.gz
			#Start with the regular steps of the pipeline to get the func mask using the baseline T2 head #TODO Figure out what to do with WarpField 
			#cp ${fMRIFolder}/${ScoutName}_gdc ${fMRIFolder}/${ScoutName}_gdc_undistorted
			#${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${fMRIFolder}/${ScoutName}_gdc -w ${fMRIFolder}/WarpField.nii.gz -o ${fMRIFolder}/${ScoutName}_gdc_undistorted
			# apply Jacobian correction to scout image (optional)
			#${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted -mul ${fMRIFolder}/FieldMap/Jacobian ${fMRIFolder}/${ScoutName}_gdc_undistorted
			# register undistorted scout image to T2w head
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/${ScoutName}_gdc -ref ${T1wFolder}/${T2wRestoreImage} -omat "$fMRIFolder"/Scout2T2w.mat -out ${fMRIFolder}/Scout2T2w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo
			${FSLDIR}/bin/convert_xfm -omat "$fMRIFolder"/T2w2Scout.mat -inverse "$fMRIFolder"/Scout2T2w.mat
			${FSLDIR}/bin/applywarp --interp=nn -i ${T1wFolder}/${T2wRestoreImageBrain} -r ${fMRIFolder}/${ScoutName}_gdc --premat="$fMRIFolder"/T2w2Scout.mat -o ${fMRIFolder}/Scout_brain_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/Scout_brain_mask.nii.gz -bin ${fMRIFolder}/Scout_brain_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc -mas ${fMRIFolder}/Scout_brain_mask.nii.gz ${fMRIFolder}/Scout_brain_dc.nii.gz
			##then mess with the session T1 to get the session specific registration. 
			#get the first T1 of the session specific 
			#NameOffMRI=ses-combined_task-MOVIEacq20181030_run-1
			if [ -e /opt/anatsesh/${NameOffMRI}/*_brain.nii.gz ]; then											
				seshT1_brain=($(ls /opt/anatsesh/${NameOffMRI}/*_brain.nii.gz))
				cp ${seshT1_brain} ${fMRIFolder}/T1sesh_brain.nii.gz
			else																		
				#denoise this image
				${ANTSPATH}${ANTSPATH:+/}DenoiseImage -d 3 -n Rician -i ${fMRIFolder}/T1sesh_head.nii.gz -v -o ${fMRIFolder}/T1sesh_head.nii.gz
				#and bias field correct it
				${ANTSPATH}${ANTSPATH:+/}N4BiasFieldCorrection -v -r -d 3 -c [50x50x50x300] -i ${fMRIFolder}/T1sesh_head.nii.gz -v -o ${fMRIFolder}/T1sesh_head.nii.gz

				#then use UNet to create a mask of the brain
				${HCPPIPEDIR_masking}/runUNet.sh ${fMRIFolder}/T1sesh_head.nii.gz ${fMRIFolder}/
				#dialate mask with fslmaths because we don't have AFNI installed in this docker

				${FSLDIR}/bin/fslmaths ${fMRIFolder}/T1sesh_head_pre_mask.nii.gz -kernel boxv 5 -dilD ${fMRIFolder}/T1sesh_head_pre_mask_filled.nii.gz
				#and apply that mask to the head to get the session T1 brain
				${FSLDIR}/bin/fslmaths ${fMRIFolder}/T1sesh_head.nii.gz -mas ${fMRIFolder}/T1sesh_head_pre_mask_filled.nii.gz ${fMRIFolder}/T1sesh_brain.nii.gz
			fi
			#now flirt Register this brain to the baseline brain 
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/T1sesh_brain.nii.gz -ref ${T1wFolder}/${T1wRestoreImageBrain} -omat "$fMRIFolder"/T1sesh2T1base.mat -out ${fMRIFolder}/T1sesh2T1base -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo
			#invert this registration to then apply to the brain in a second
			${FSLDIR}/bin/convert_xfm -omat "$fMRIFolder"/T1base2T1sesh.mat -inverse "$fMRIFolder"/T1sesh2T1base.mat
			#apply inverted transform to baseline brain to get it to session space for later masking
			${FSLDIR}/bin/applywarp --interp=nn -i ${T1wFolder}/${T1wRestoreImageBrain} -r ${fMRIFolder}/T1sesh_brain.nii.gz --premat="$fMRIFolder"/T1base2T1sesh.mat -o ${fMRIFolder}/T1sesh_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/T1sesh_mask.nii.gz -bin ${fMRIFolder}/T1sesh_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/T1sesh_head.nii.gz -mas ${fMRIFolder}/T1sesh_mask.nii.gz ${fMRIFolder}/T1sesh_brain.nii.gz

			#after making new brain, register to baseline again and then use this transform to concat later
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/T1sesh_brain.nii.gz -ref ${T1wFolder}/${T1wRestoreImageBrain} -omat "$fMRIFolder"/T1sesh2T1base2.mat -out ${fMRIFolder}/T1sesh2T1base2 -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo

			## and now register scout brain made in the first section to this session T1 brain   
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/Scout_brain_dc.nii.gz -ref ${fMRIFolder}/T1sesh_brain.nii.gz -omat "$fMRIFolder"/${ScoutName}_gdc2sessionT1w_init.mat -out ${fMRIFolder}/${ScoutName}_gdc2sessionT1w_brain_init -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo

			#concatonate the t1 sesh to baseline and the func brain to t1 brain  
			convert_xfm -omat ${fMRIFolder}/${ScoutName}_gdc2T1w_init.mat -concat "$fMRIFolder"/T1sesh2T1base2.mat "$fMRIFolder"/${ScoutName}_gdc2sessionT1w_init.mat

			#  generate combined warpfields and spline interpolated images + apply bias field correction
			#${FSLDIR}/bin/convertwarp --relout --rel -r ${T1wFolder}/${T2wRestoreImage} --warp1=${fMRIFolder}/WarpField --postmat=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp
			#taking out warpfield as it is not being made without a fieldmap. 
			${FSLDIR}/bin/convertwarp --relout --rel -r ${T1wFolder}/${T2wRestoreImage} --postmat=${fMRIFolder}/${ScoutName}_gdc2T1w_init.mat -o ${fMRIFolder}/${ScoutName}_gdc2T1w_init_warp


			#added from else statement#TODO
			${FSLDIR}/bin/fslmaths ${T1wFolder}/${T1wImage} -abs -add 1 -bin ${fMRIFolder}/${JacobianOut}
			${FSLDIR}/bin/fslmaths ${T1wFolder}/${T1wImage} -abs -add 1 -bin ${fMRIFolder}/Jacobian.nii.gz

			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/Jacobian.nii.gz -r ${T1wFolder}/${T1wRestoreImage} --premat=${fMRIFolder}/${ScoutName}_gdc2T1w_init.mat -o ${fMRIFolder}/Jacobian2T1w.nii.gz 
			#applywarp that is a combination of the Warpfiled and func brain to T1 brain to scout gdc
			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${T1wFolder}/${T1wRestoreImage} -w ${fMRIFolder}/${ScoutName}_gdc2T1w_init_warp -o ${fMRIFolder}/${ScoutName}_gdc2T1w_init ##This is the warp that will be copied to T1w/xfms later. 

			# apply Jacobian correction to scout image (optional)
			#  
			#${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc2T1w_init -div ${T1wFolder}/${BiasField} -mul ${fMRIFolder}/Jacobian2T1w.nii.gz ${fMRIFolder}/${ScoutName}_gdc2T1w_init.nii.gz
			SUBJECTS_DIR=${T1wFolder}	
	#@TODO SEE WHERE THIS BELONGS @TODO re-evaluate: this xfm may be lackluster compared to a proper bbr.  We could try the resolved bbr from WashU's pipe.
			cp ${fMRIFolder}/${ScoutName}_gdc2T1w_init_warp.nii.gz ${T1wFolder}/xfms/${fMRI2strOutputTransform}.nii.gz
			imcp ${fMRIFolder}/Jacobian2T1w.nii.gz ${fMRIFolder}/$JacobianOut #  this is the proper "JacobianOut" for input into OneStepResampling.


		else																	

			echo "now its trying the else statement from Anatsesh fix"
			#making a copy just in case I missed something that is looking for this file, even though they should be the same. 
			#cp ${fMRIFolder}/${ScoutName}_gdc ${fMRIFolder}/${ScoutName}_gdc_undistorted
			#${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${fMRIFolder}/${ScoutName}_gdc -w ${fMRIFolder}/WarpField.nii.gz -o ${fMRIFolder}/${ScoutName}_gdc_undistorted
			# apply Jacobian correction to scout image (optional)
			#${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted -mul ${fMRIFolder}/FieldMap/Jacobian ${fMRIFolder}/${ScoutName}_gdc_undistorted
			# register undistorted scout image to T2w head
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/${ScoutName}_gdc -ref ${T1wFolder}/${T2wRestoreImage} -omat "$fMRIFolder"/Scout2T2w.mat -out ${fMRIFolder}/Scout2T2w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo
			${FSLDIR}/bin/convert_xfm -omat "$fMRIFolder"/T2w2Scout.mat -inverse "$fMRIFolder"/Scout2T2w.mat
			${FSLDIR}/bin/applywarp --interp=nn -i ${T1wFolder}/${T2wRestoreImageBrain} -r ${fMRIFolder}/${ScoutName}_gdc --premat="$fMRIFolder"/T2w2Scout.mat -o ${fMRIFolder}/Scout_brain_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/Scout_brain_mask.nii.gz -bin ${fMRIFolder}/Scout_brain_mask.nii.gz
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc -mas ${fMRIFolder}/Scout_brain_mask.nii.gz ${fMRIFolder}/Scout_brain_dc.nii.gz
			###### #TODO make sure transition is right
			## re-registering the maked brain to the T1 brain:  
			${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/Scout_brain_dc.nii.gz -ref ${T1wFolder}/${T1wRestoreImageBrain} -omat "$fMRIFolder"/${ScoutName}_gdc2T1w_init.mat -out ${fMRIFolder}/${ScoutName}_gdc2T1w_brain_init -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo
			#  generate combined warpfields and spline interpolated images + apply bias field correction
			#${FSLDIR}/bin/convertwarp --relout --rel -r ${T1wFolder}/${T2wRestoreImage} --warp1=${fMRIFolder}/WarpField --postmat=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp
			#taking out warpfield as it is not being made without a fieldmap. 
			${FSLDIR}/bin/convertwarp --relout --rel -r ${T1wFolder}/${T2wRestoreImage} --postmat=${fMRIFolder}/${ScoutName}_gdc2T1w_init.mat -o ${fMRIFolder}/${ScoutName}_gdc2T1w_init_warp

			#added from else statement#TODO
			${FSLDIR}/bin/fslmaths ${T1wFolder}/${T1wImage} -abs -add 1 -bin ${fMRIFolder}/${JacobianOut}
			${FSLDIR}/bin/fslmaths ${T1wFolder}/${T1wImage} -abs -add 1 -bin ${fMRIFolder}/Jacobian.nii.gz

			#applywarp of func brain to T1 brain to the jacobian
			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/Jacobian.nii.gz -r ${T1wFolder}/${T2wRestoreImage} --premat=${fMRIFolder}/${ScoutName}_gdc2T1w_init.mat -o ${fMRIFolder}/Jacobian2T1w.nii.gz 
			#applywarp that is a combination of the Warpfiled and func brain to T1 brain to scout gdc
			${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${T1wFolder}/${T2wRestoreImage} -w ${fMRIFolder}/${ScoutName}_gdc2T1w_init_warp -o ${fMRIFolder}/${ScoutName}_gdc2T1w_init ##This is the warp that will be copied to T1w/xfms later. 

			# apply Jacobian correction to scout image (optional)
			${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc2T1w_init -div ${T1wFolder}/${BiasField} -mul ${fMRIFolder}/Jacobian2T1w.nii.gz ${fMRIFolder}/${ScoutName}_gdc2T1w_init.nii.gz
			SUBJECTS_DIR=${T1wFolder}
			cp ${fMRIFolder}/${ScoutName}_gdc2T1w_init_warp.nii.gz ${T1wFolder}/xfms/${fMRI2strOutputTransform}.nii.gz
			imcp ${fMRIFolder}/Jacobian2T1w.nii.gz ${fMRIFolder}/$JacobianOut #  this is the proper "JacobianOut" for input into OneStepResampling.

		fi
##OREV REGISTRATION AFTER ANATSESH IF STATMENT 
	elif ${PreviousRegistration}; then							
		#  take bold results, as they tend to be more accurate transforms until we can improve them.  Combine rigid ferumox -> bold
		echo "using ${PreviousTask} to calculate ${NameOffMRI} registration to anatomical"
		PrevTaskFolder="$Path"/${PreviousTask}
		Lin2PrevTask="${fMRIFolder}"/${PreviousTask}_2_${NameOffMRI}.mat
		flirt -in "${fMRIFolder}"/Scout_orig.nii.gz -cost mutualinfo -dof 6 -ref "${PrevTaskFolder}"/Scout_orig.nii.gz -omat ${Lin2PrevTask}
		PrevTaskTransform=${PreviousTask}2str
		imcp "$PrevTaskFolder"/"$JacobianOut" "$fMRIFolder"/"$JacobianOut"
		convertwarp --rel --relout --out=${T1wFolder}/xfms/${fMRI2strOutputTransform}.nii.gz --warp1=${T1wFolder}/xfms/${PrevTaskTransform}.nii.gz --premat=${Lin2PrevTask} --ref=${T1wFolder}/${T1wImage}
	fi

		###finished with Bene's work around if no fieldmaps exist 3-19-2020

else
	# fake jacobian out
	# DFM is still being applied from CYA, will put DFM procedure here later.
	fslmaths ${T1wFolder}/${T1wImage} -abs -add 1 -bin ${fMRIFolder}/${JacobianOut}
fi
#### DOne with IF Statment detwrmining the distortion correction 1 #TODO

echo "RUNNING ONE STEP RESAMPLING"
#One Step Resampling
mkdir -p ${fMRIFolder}/OneStepResampling
echo ${RUN} ${PipelineScripts}/OneStepResampling.sh \
	--workingdir=${fMRIFolder}/OneStepResampling \
	--infmri=${fMRIFolder}/${OrigTCSName}.nii.gz \
	--t1=${AtlasSpaceFolder}/${T1wAtlasName} \
	--fmriresout=${FinalfMRIResolution} \
	--fmrifolder=${fMRIFolder} \
	--fmri2structin=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
	--struct2std=${AtlasSpaceFolder}/xfms/${AtlasTransform} \
	--owarp=${AtlasSpaceFolder}/xfms/${OutputfMRI2StandardTransform} \
	--oiwarp=${AtlasSpaceFolder}/xfms/${Standard2OutputfMRITransform} \
	--motionmatdir=${fMRIFolder}/${MotionMatrixFolder} \
	--motionmatprefix=${MotionMatrixPrefix} \
	--ofmri=${fMRIFolder}/${NameOffMRI}_nonlin \
	--freesurferbrainmask=${AtlasSpaceFolder}/${FreeSurferBrainMask} \
	--biasfield=${AtlasSpaceFolder}/${BiasFieldMNI} \
	--gdfield=${fMRIFolder}/${NameOffMRI}_gdc_warp \
	--scoutin=${fMRIFolder}/${OrigScoutName} \
	--scoutgdcin=${fMRIFolder}/${ScoutName}_gdc \
	--oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
	--jacobianin=${fMRIFolder}/${JacobianOut} \
	--ojacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution}

${RUN} ${PipelineScripts}/OneStepResampling.sh \
	--workingdir=${fMRIFolder}/OneStepResampling \
	--infmri=${fMRIFolder}/${OrigTCSName}.nii.gz \
	--t1=${AtlasSpaceFolder}/${T1wAtlasName} \
	--fmriresout=${FinalfMRIResolution} \
	--fmrifolder=${fMRIFolder} \
	--fmri2structin=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
	--struct2std=${AtlasSpaceFolder}/xfms/${AtlasTransform} \
	--owarp=${AtlasSpaceFolder}/xfms/${OutputfMRI2StandardTransform} \
	--oiwarp=${AtlasSpaceFolder}/xfms/${Standard2OutputfMRITransform} \
	--motionmatdir=${fMRIFolder}/${MotionMatrixFolder} \
	--motionmatprefix=${MotionMatrixPrefix} \
	--ofmri=${fMRIFolder}/${NameOffMRI}_nonlin \
	--freesurferbrainmask=${AtlasSpaceFolder}/${FreeSurferBrainMask} \
	--biasfield=${AtlasSpaceFolder}/${BiasFieldMNI} \
	--gdfield=${fMRIFolder}/${NameOffMRI}_gdc_warp \
	--scoutin=${fMRIFolder}/${OrigScoutName} \
	--scoutgdcin=${fMRIFolder}/${ScoutName}_gdc \
	--oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
	--jacobianin=${fMRIFolder}/${JacobianOut} \
	--ojacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution}


echo "RUNNING INTENSITY NORMALIZATION & BIAS REMOVAL"
#Intensity Normalization and Bias Removal
### ERIC'S DEBUGGING ECHO ###
echo ${RUN} ${PipelineScripts}/IntensityNormalization.sh \
	--infmri=${fMRIFolder}/${NameOffMRI}_nonlin \
	--biasfield=${fMRIFolder}/${BiasFieldMNI}.${FinalfMRIResolution} \
	--jacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution} \
	--brainmask=${fMRIFolder}/${FreeSurferBrainMask}.${FinalfMRIResolution} \
	--ofmri=${fMRIFolder}/${NameOffMRI}_nonlin_norm \
	--inscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
	--oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin_norm \
	--usejacobian=false
${RUN} ${PipelineScripts}/IntensityNormalization.sh \
	--infmri=${fMRIFolder}/${NameOffMRI}_nonlin \
	--biasfield=${fMRIFolder}/${BiasFieldMNI}.${FinalfMRIResolution} \
	--jacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution} \
	--brainmask=${fMRIFolder}/${FreeSurferBrainMask}.${FinalfMRIResolution} \
	--ofmri=${fMRIFolder}/${NameOffMRI}_nonlin_norm \
	--inscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
	--oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin_norm \
	--usejacobian=false

mkdir -p ${ResultsFolder}
# MJ QUERY: WHY THE -r OPTIONS BELOW?
${RUN} cp -r ${fMRIFolder}/${NameOffMRI}_nonlin_norm.nii.gz ${ResultsFolder}/${NameOffMRI}.nii.gz
${RUN} cp -r ${fMRIFolder}/${MovementRegressor}.txt ${ResultsFolder}/${MovementRegressor}.txt
${RUN} cp -r ${fMRIFolder}/${MovementRegressor}_dt.txt ${ResultsFolder}/${MovementRegressor}_dt.txt
${RUN} cp -r ${fMRIFolder}/${NameOffMRI}_SBRef_nonlin_norm.nii.gz ${ResultsFolder}/${NameOffMRI}_SBRef.nii.gz
${RUN} cp -r ${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution}.nii.gz ${ResultsFolder}/${NameOffMRI}_${JacobianOut}.nii.gz
###Add stuff for RMS###
${RUN} cp -r ${fMRIFolder}/Movement_RelativeRMS.txt ${ResultsFolder}/Movement_RelativeRMS.txt
${RUN} cp -r ${fMRIFolder}/Movement_AbsoluteRMS.txt ${ResultsFolder}/Movement_AbsoluteRMS.txt
${RUN} cp -r ${fMRIFolder}/Movement_RelativeRMS_mean.txt ${ResultsFolder}/Movement_RelativeRMS_mean.txt
${RUN} cp -r ${fMRIFolder}/Movement_AbsoluteRMS_mean.txt ${ResultsFolder}/Movement_AbsoluteRMS_mean.txt
###Add stuff for RMS###

echo "-------------------------------"
echo "END OF fMRI-VOLUME-PROCESSING.sh SCRIPT"
echo "Please Verify Clean Error File"
