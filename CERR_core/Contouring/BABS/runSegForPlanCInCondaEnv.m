function planC = runSegForPlanCInCondaEnv(planC,sessionPath,algorithm,...
    condaEnvList,wrapperFunctionList,batchSize)
% function planC = runSegForPlanCInCondaEnv(planC,sessionPath,algorithm,...
%     condaEnvList,wrapperFunctionList,batchSize)
%
% This function is a wrapper to run DL-segmentation models in Conda environments.
% -------------------------------------------------------------------------------
% INPUTS:
% planC
% sessionPath  -  Directory for writitng temporary segmentation metadata.
% algorithm    -  Algorthim name. For full list, see:
%                   https://github.com/cerr/CERR/wiki/Auto-Segmentation-models.
%                 Pass caret-delimited list to chain multilple algorithms, e.g:
%                   algorithm = ['CT_ChewingStructures_DeepLabV3^',...
%                   'CT_Larynx_DeepLabV3^CT_PharyngealConstrictor_DeepLabV3'];
% condaEnvList -  String containing caret-separated names of conda env.
%                 It can also be a cell-array of conda environment names.
%                 It is obtained from getSegWrapperFunc if not specified or empty
%                 Specify absolute paths of Conda environmnents. If names are specified,
%                 the location of conda installation must be defined in CERROptions.json.
%                 "condaPath" : "C:/Miniconda3/"
%                 The environment muust contain subdirectory 'condabin', "activate" script
%                 and subdirectory 'envs'.
% wrapperFunctionList (optionsl)
%              - String containing caret-separated absolute paths of wrapper functions.
%                It can also be a cell-array of strings. 
%                If not specified or empty, the names of wrapper functions
%                are obtained from getSegWrapperFunc.m.
% batchSize (optional)
%              -  Batch size for inference
%
%
%--------------------------------------------------------------------------------
% EXAMPLE:
% To run segmentation, open a CERR-format file using the GUI or command-line, followed by:
%
%   global planC % to access metadata from CERR Viewer
%   sessionPath = '/path/to/session/dir';
%   algorithm = 'CT_Heart_DeepLab';
%   condaEnvName = '/path/to/condaEnv/testEnv';
%   wrapperFunctionList = '/path/to/wrapperFunction/testWrapper.py';
%   batchSize = 1;
%   planC = runSegForPlanCInCondaEnv(planC,sessionPath,algorithm,condaEnvName,wrapperFunctionList,batchSize);
%--------------------------------------------------------------------------------
%
% AI, 09/21/2020

global stateS

%% Create session directory to write segmentation metadata
indexS = planC{end};
% Create temp. dir labelled by series UID, local time and date
if isfield(planC{indexS.scan}(1).scanInfo(1),'seriesInstanceUID') && ...
        ~isempty(planC{indexS.scan}(1).scanInfo(1).seriesInstanceUID)
    folderNam = planC{indexS.scan}(1).scanInfo(1).seriesInstanceUID;
else
    %folderNam = dicomuid;
    orgRoot = '1.3.6.1.4.1.9590.100.1.2';
    folderNamJava = javaMethod('createUID','org.dcm4che3.util.UIDUtils',orgRoot);    
    folderNam = folderNamJava.toCharArray';
end
dateTimeV = clock;
randNum = 1000.*rand;
sessionDir = ['session',folderNam,num2str(dateTimeV(4)), num2str(dateTimeV(5)),...
    num2str(dateTimeV(6)), num2str(randNum)];
fullSessionPath = fullfile(sessionPath,sessionDir);


%% Create sub-directories 
%-For CERR files
mkdir(fullSessionPath)
cerrPath = fullfile(fullSessionPath,'dataCERR');
mkdir(cerrPath)
outputCERRPath = fullfile(fullSessionPath,'segmentedOrigCERR');
mkdir(outputCERRPath)
segResultCERRPath = fullfile(fullSessionPath,'segResultCERR');
mkdir(segResultCERRPath)
%-For H5 files
outputH5Path = fullfile(fullSessionPath,'outputH5');
mkdir(outputH5Path);
inputH5Path = fullfile(fullSessionPath,'inputH5');
mkdir(inputH5Path);
testFlag = true;
%-For structname-to-label map
labelPath = fullfile(fullSessionPath,'outputLabelMap');
mkdir(labelPath);


%% Get conda installation path
optS = opts4Exe([getCERRPath,'CERROptions.json']);
condaPath = optS.condaPath;

%% Parse algorithm & functionName and convert to cell arrray
if iscell(algorithm)
    algorithmC = algorithm;
else
    algorithmC = strsplit(algorithm,'^');
end

numAlgorithms = numel(algorithmC);
%functionNameC = strsplit(functionName,'^');
% numWrapperFunctions = numel(functionNameC);
% if numAlgorithms ~= numWrapperFunctions
%     error('Mismatch between no. specified algorithms and wrapper functions')
% end

%condaEnvList = varargin{1};
if iscell(condaEnvList)
    condaEnvListC = condaEnvList;
else
    condaEnvListC = strsplit(condaEnvList,'^');
end
numContainers = numel(condaEnvListC);
if numAlgorithms > 1 && numContainers == 1
    condaEnvListC = repmat(condaEnvListC,numAlgorithms,1);
elseif numAlgorithms ~= numContainers
    error('Mismatch between no. specified algorithms and conda envs.')
end

% Get wrapper function names for algorithm/condaEnvs
if ~exist('wrapperFunctionList','var') || isempty(wrapperFunctionList)
    functionNameC = getSegWrapperFunc(condaEnvListC,algorithmC);
elseif iscell(wrapperFunctionList)
    functionNameC = wrapperFunctionList;
else
    functionNameC = strsplit(wrapperFunctionList,'^');
end
numContainers = numel(functionNameC);
if numAlgorithms > 1 && numContainers == 1
    functionNameC = repmat(functionNameC,numAlgorithms,1);
elseif numAlgorithms ~= numContainers
    error('Mismatch between no. specified algorithms and wrapper functions')
end


% Loop over algorithms
for k=1:length(algorithmC)
    
    %Clear previous contents of session dir
    inputH5Path = fullfile(fullSessionPath,'inputH5');
    outputH5Path = fullfile(fullSessionPath,'outputH5');
    if exist(inputH5Path, 'dir')
        rmdir(inputH5Path, 's')
        mkdir(inputH5Path);
    end
    if exist(outputH5Path, 'dir')
        rmdir(outputH5Path, 's')
        mkdir(outputH5Path);
    end
    
    % Get config file path
    configFilePath = fullfile(getCERRPath,'ModelImplementationLibrary',...
        'SegmentationModels', 'ModelConfigurations',...
        [algorithmC{k}, '_config.json']);
    
    % Pre-process and export data to HDF5 format
    userOptS = readDLConfigFile(configFilePath);
    if ~exist('batchSize','var') || isempty(batchSize)
        batchSize = userOptS.batchSize;
    end
    [scanC, maskC, scanNumV, userOptS, planC] = ...
        extractAndPreprocessDataForDL(userOptS,planC,testFlag);
    %Note: mask3M is empty for testing
    
    %Export to H5 format
    tic
    fprintf('\nWriting to H5 format...\n');
    filePrefixForHDF5 = 'cerrFile';
    passedScanDim = userOptS.passedScanDim;
    scanOptS = userOptS.scan;
    %Loop over scan types
    for n = 1:size(scanC,1)
        %Append identifiers to o/p name
        if length(scanOptS)>1
            idS = scanOptS(n).identifier;
            idListC = cellfun(@(x)(idS.(x)),fieldnames(idS),'un',0);
            appendStr = strjoin(idListC,'_');
            idOut = [filePrefixForHDF5,'_',appendStr];
        else
            idOut = filePrefixForHDF5;
        end
        %Get o/p dirs & dim
        outDirC = getOutputH5Dir(inputH5Path,scanOptS(n),'');
        %Write to HDF5
        writeHDF5ForDL(scanC{n},maskC{n},passedScanDim,outDirC,idOut,testFlag);
    end
    
    % Call python wrapper and execute model
    pth = getenv('PATH');
    condaBinPath = fullfile(condaPath,'condabin;');
    %condaScriptsPath = fullfile(condaPath,'Scripts;');
    if ~isempty(strfind(condaEnvListC{k},filesep))        
        condaEnvPath = condaEnvListC{k};
        condaBinPath = fullfile(condaEnvPath,'Scripts;');
    else
        condaEnvPath = fullfile(condaPath,'envs',condaEnvListC{k});
    end
    %if isempty(strfind(pth,condaBinPath))
    %    newPth = [condaBinPath,pth];
    %    setenv('PATH',newPth)
    %end
    newPth = [condaBinPath,pth];
    setenv('PATH',newPth)
    wrapperFunc = functionNameC{k};
    if ispc
        command = sprintf('call activate %s && python %s %s %s %s',...
            condaEnvPath, wrapperFunc, inputH5Path, outputH5Path,...
            num2str(batchSize));
    else
        condaSrc = fullfile(condaEnvPath,'/bin/activate');
        command = sprintf('source %s && python %s %s %s %s',...
            condaSrc, wrapperFunc, inputH5Path, outputH5Path,...
            num2str(batchSize));
    end
    % Resolve error by setting KMP_DUPLICATE_LIB_OK' to 'TRUE'
    % OMP: Error #15: Initializing libiomp5md.dll, but found libiomp5md.dll already initialized.
    % https://community.intel.com/t5/Intel-Integrated-Performance/Solution-to-Error-15-Initializing-libiomp5md-dll-but-found/td-p/800649
    setenv('KMP_DUPLICATE_LIB_OK','TRUE')
    disp(command)
    tic
    status = system(command);
    toc
    
    % Set Environment variables to default
    setenv('PATH',pth)
    
    % Read structure masks
    outC = stackHDF5Files(fullSessionPath,userOptS.passedScanDim); %Updated
    
    % Import to planC
    tic
    identifierS = userOptS.structAssocScan.identifier;
    if ~isempty(fieldnames(userOptS.structAssocScan.identifier))
        origScanNum = getScanNumFromIdentifiers(identifierS,planC);
    else
        origScanNum = 1; %Assoc with first scan by default
    end
    outScanNum = scanNumV(origScanNum);
    userOptS(outScanNum).scan = userOptS(origScanNum).scan;
    userOptS(outScanNum).scan.origScan = origScanNum;
    planC  = joinH5planC(outScanNum,outC{1},labelPath,userOptS,planC); % only 1 file
    toc
    
    % Post-process segmentation
    planC = postProcStruct(planC,userOptS);
    
    %Delete intermediate (resampled) scans if any
    scanListC = arrayfun(@(x)x.scanType, planC{indexS.scan},'un',0);
    resampScanName = ['Resamp_scan',num2str(origScanNum)];
    matchIdxV = ismember(scanListC,resampScanName);
    if any(matchIdxV)
        deleteScanNum = find(matchIdxV);
        planC = deleteScan(planC,deleteScanNum);
    end
    
end

% Remove session directory
rmdir(fullSessionPath, 's')

% Refresh Viewer
if ~isempty(stateS) && (isfield(stateS,'handle') && ishandle(stateS.handle.CERRSliceViewer))
    stateS.structsChanged = 1;
    CERRRefresh
end

end
