function planC = importNiftiSegToPlanC(planC,structFileName,scanNum)
% function planC = importNiftiSegToPlanC(planC,structFileName,scanNum)
% 
% Script to load segmentation mask from nifti file and add to CERR planC
%
% Example usage:
%
% Import PET and CT DICOM to planC and proceed with the following.
% global planC % access planC via from Viewer or load from file
% scanNum = 2; % (optional) to assign segmentation on scan at index 2.
% structFileName = 'path:\to\niifile\pt1_mask.nii';
% planC = importNiftiSegToPlanC(planC,structFileName,scanNum);
%
% APA, 6/19/2020

%indexS = planC{end};

strName = 'ROI';
isUniform = 0;

if ~exist('scanNum', 'var')
    scanNum = 1; % assuming PET scan is at index 1
end

% Read NIfTI file

gzFlag = 0;

% check if files gzipped
fileparts = strsplit(structFileName,'.');
if strcmpi(fileparts{end},'gz') && any(strcmpi(fileparts{end - 1},{'img','hdr','nii'}))
    gzFlag = 1;    
    tmpDirPath = fullfile(getCERRPath, 'ImageRegistration', 'tmpFiles');
    if strcmpi(fileparts{end - 1},'nii')
        filegz = structFileName;
        ungzfile = gunzip(filegz,tmpDirPath);
        structFileName = ungzfile{1};
    end
    if any(strcmp(fileparts{end - 1},{'hdr','img'}))
        filebase = structFileName(1:end - 7);
        for ext = {'hdr','img'}
            filegz = [filebase '.hdr.gz'];
            ungzfile = gunzip(filegz, tmpDirPath);
        end
        structFileName = ungzfile{1};
    end
end

[vol,info] = nifti_read_volume(structFileName);
mask3M = permute(vol,[2,1,3]);

% Add mask to CERR structure
structsV = unique(mask3M(:));
structsV(structsV==0) = [];
for strNum = 1:numel(structsV)
    planC = maskToCERRStructure(mask3M==structsV(strNum), isUniform, scanNum, ...
        [strName,'_',num2str(structsV(strNum))], planC);
end
planC = maskToCERRStructure(mask3M>0, isUniform, scanNum, 'All lesions', planC);

%remove temp unzipped files
if gzFlag
    filebase = structFileName(1:end-4);
    delete([filebase, filesep, '*']);
end