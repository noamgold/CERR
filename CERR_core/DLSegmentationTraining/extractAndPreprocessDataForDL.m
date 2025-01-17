function [scanOutC, maskOutC, scanNumV, optS, planC] = ...
    extractAndPreprocessDataForDL(optS,planC,testFlag,scanNumV)
%
% Script to extract scan and mask and perform user-defined pre-processing.
%
% -------------------------------------------------------------------------
% INPUTS:
% optS          :  Dictionary of preprocessing options.
% planC         :  CERR archive
%
% --Optional--
% testFlag      : Set flag to true for test dataset. Default:true. Assumes testing dataset if not specified
% -------------------------------------------------------------------------
% AI 9/18/19
% AI 9/18/20  Extended to handle multiple scans

%% Get processing directives from optS
regS = optS.register;
scanOptS = optS.scan;
resampleS = [scanOptS.resample];
resizeS = [scanOptS.resize];

if isfield(optS,'structList')
    strListC = optS.structList;
else
    strListC = {};
end

if ~exist('testFlag','var')
    testFlag = true;
end

%% Identify available structures in planC
indexS = planC{end};
allStrC = {planC{indexS.structures}.structureName};
strNotAvailableV = ~ismember(lower(strListC),lower(allStrC)); %Case-insensitive
labelV = 1:length(strListC);
if any(strNotAvailableV) && ~testFlag
    scanOutC = {};
    maskOutC = {};
    warning(['Skipping pt. Missing structures: ',strjoin(strListC(strNotAvailableV),',')]);
    return
end
exportStrC = strListC(~strNotAvailableV);

if ~isempty(exportStrC) || testFlag
    
    exportLabelV = labelV(~strNotAvailableV);
    
    %Get structure ID and assoc scan
    strIdxC = cell(length(exportStrC),1);
    for strNum = 1:length(exportStrC)
        
        currentLabelName = exportStrC{strNum};
        strIdxC{strNum} = getMatchingIndex(currentLabelName,allStrC,'exact');
        
    end
end

%% Register scans (in progress)
if ~isempty(fieldnames(regS))
    identifierS = regS.baseScan.identifier;
    scanNumV(1) = getScanNumFromIdentifiers(identifierS,planC);
    identifierS = regS.movingScan.identifier;
    movScanV = getScanNumFromIdentifiers(identifierS,planC);
    scanNumV(2:length(movScanV)+1) = movScanV;
    if strcmp(regS.method,'none')
        %For pre-registered scans
        if isfield(regS,'copyStr')
            copyStrsC = {regS.copyStr};
            for nStr = 1:length(copyStrsC)
                cpyStrV = getMatchingIndex(copyStrsC{nStr},allStrC,'exact');
                assocScanV = getStructureAssociatedScan(cpyStrV,planC);
                cpyStr = cpyStrV(assocScanV==scanNumV(1));
                planC = copyStrToScan(cpyStr,movScanV,planC);
            end
        end
    else
        %--TBD
        % [outScanV, planC]  = registerScans(regS, planC);
        % Update scanNumV with warped scan IDs (outScanV)
        %---
    end
else
    %Get scan no. matching identifiers
    if ~exist('scanNumV','var')
        scanNumV = nan(1,length(scanOptS));
        for n = 1:length(scanOptS)
            identifierS = scanOptS(n).identifier;
            scanNumV(n) = getScanNumFromIdentifiers(identifierS,planC);
        end
    end
end
% Ignore missing inputs if marked optional
optFlagV = strcmpi({scanOptS.required},'no');
ignoreIdxV = optFlagV & isnan(scanNumV);
scanNumV(ignoreIdxV) = [];

%% Extract & preprocess data
numScans = length(scanNumV);
scanC = cell(numScans,1);
scanOutC = cell(numScans,1);
maskC = cell(numScans,1);
maskOutC = cell(numScans,1);

UIDc = {planC{indexS.structures}.assocScanUID};
%resM = nan(length(scanNumV),3);

%-Loop over scans
for scanIdx = 1:numScans
    
    %Extract scan array from planC
    scan3M = double(getScanArray(scanNumV(scanIdx),planC));
    CTOffset = double(planC{indexS.scan}(scanNumV(scanIdx)).scanInfo(1).CTOffset);
    scan3M = scan3M - CTOffset;
    
    %Extract masks from planC
    strC = {planC{indexS.structures}.structureName};
    if isempty(exportStrC) && testFlag
        mask3M = [];
        validStrIdxV = [];
    else
        mask3M = zeros(size(scan3M));
        assocStrIdxV = strcmpi(planC{indexS.scan}(scanNumV(scanIdx)).scanUID,UIDc);
        strIdxV = [strIdxC{:}];
        strIdxV = reshape(strIdxV,1,[]);
        validStrIdxV = ismember(strIdxV,find(assocStrIdxV));
        validStrIdxV = strIdxV(validStrIdxV);
        keepLabelIdxV = assocStrIdxV(validStrIdxV);
        validExportLabelV = exportLabelV(keepLabelIdxV);
    end
    
    for strNum = 1:length(validStrIdxV)
        
        strIdx = validStrIdxV(strNum);
        
        %Update labels
        tempMask3M = false(size(mask3M));
        [rasterSegM, planC] = getRasterSegments(strIdx,planC);
        [maskSlicesM, uniqueSlices] = rasterToMask(rasterSegM, scanNumV(scanIdx), planC);
        tempMask3M(:,:,uniqueSlices) = maskSlicesM;
        mask3M(tempMask3M) = validExportLabelV(strNum);
        
    end
    
    %Set scan-specific parameters: channels, view orientation, background adjustment, aspect ratio
    channelParS = scanOptS(scanIdx).channels;
    numChannels = length(channelParS);
    
    viewC = scanOptS(scanIdx).view;
    if ~iscell(viewC)
        viewC = {viewC};
    end
    
    if ~isequal(viewC,{'axial'})
        transformViewFlag = 1;
    else
        transformViewFlag = 0;
    end
    
    filterTypeC = {channelParS.imageType};
    structIdxC = cellfun(@isstruct,filterTypeC,'un',0);
    if any([structIdxC{:}])
     filterTypeC = arrayfun(@(x)fieldnames(x.imageType),channelParS,'un',0);
     if any(ismember([filterTypeC{:}],'assignBkgIntensity'))
         adjustBackgroundVoxFlag = 1;
     else
         adjustBackgroundVoxFlag = 0;
     end
    else
        adjustBackgroundVoxFlag = 0;
    end
    
    if strcmp(resizeS(scanIdx).preserveAspectRatio,'Yes')
        preserveAspectFlag = 1;
    else
        preserveAspectFlag = 0;
    end
    
    %% Pre-processing
    cropS = scanOptS(scanIdx).crop;
    
    %1. Resample to (resolutionXCm,resolutionYCm,resolutionZCm) voxel size
    if ~strcmpi(resampleS(scanIdx).method,'none')
        
        fprintf('\n Resampling data...\n');
        tic
        % Get the new x,y,z grid
        [xValsV, yValsV, zValsV] = getScanXYZVals(planC{indexS.scan}(scanNumV(scanIdx)));
        if yValsV(1) > yValsV(2)
            yValsV = fliplr(yValsV);
        end
        
        %Get input resolution
        dx = median(diff(xValsV));
        dy = median(diff(yValsV));
        dz = median(diff(zValsV));
        inputResV = [dx,dy,dz];
        outResV = inputResV;
        resListC = {'resolutionXCm','resolutionYCm','resolutionZCm'};
        for nDim = 1:length(resListC)
            if isfield(resampleS(scanIdx),resListC{nDim})
                outResV(nDim) = resampleS(scanIdx).(resListC{nDim});
            else
                outResV(nDim) = nan;
            end
        end
        resampleMethod = resampleS(scanIdx).method;
        
        %Resample scan
        gridResampleMethod = 'center';
        %volumeInterpMethod = resampleS.method;
        [xResampleV,yResampleV,zResampleV] = ...
            getResampledGrid(outResV,xValsV,yValsV,zValsV,gridResampleMethod);
        scan3M = imgResample3d(double(scan3M), ...
            xValsV,yValsV,zValsV,...
            xResampleV,yResampleV,zResampleV,...
            resampleMethod);
        %[scan3M,xResampleV,yResampleV,zResampleV] = ...
        %   imgResample3d(scan3M,inputResV,xValsV,yValsV,zValsV,...
        %   outResV,resampleMethod);
        
        %Store to planC
        scanInfoS.horizontalGridInterval = outResV(1);
        scanInfoS.verticalGridInterval = outResV(2);
        scanInfoS.coord1OFFirstPoint = xResampleV(1);
        scanInfoS.coord2OFFirstPoint = yResampleV(1);
        scanInfoS.zValues = zResampleV;
        sliceThicknessV = diff(zResampleV);
        scanInfoS.sliceThickness = [sliceThicknessV,sliceThicknessV(end)];
        planC = scan2CERR(scan3M,['Resamp_scan',num2str(scanNumV(scanIdx))],...
            '',scanInfoS,'',planC);
        scanNumV(scanIdx) = length(planC{indexS.scan});
        toc
        
        % Resample structures required for training
        
        %Resample reqd structures
        % TBD: add structures reqd for training        
        if ~(length(cropS) == 1 && strcmpi(cropS(1).method,'none'))
            cropStrListC = arrayfun(@(x)x.params.structureName,cropS,'un',0);
            cropParS = [cropS.params];
            if ~isempty(cropStrListC)
                for n = 1:length(cropStrListC)
                    strIdx = getMatchingIndex(cropStrListC{n},strC,'EXACT');
                    if ~isempty(strIdx)
                        str3M = double(getStrMask(strIdx,planC));
                        outStr3M = imgResample3d(str3M,inputResV,xValsV,...
                            yValsV,zValsV,outResV,resampleMethod,0) >= 0.5;
                        outStrName = [cropParS(n).structureName,'_resamp'];
                        cropParS(n).structureName = outStrName;
                        planC = maskToCERRStructure(outStr3M,0,scanNumV(scanIdx),...
                            outStrName,planC);
                    end
                end
                cropS.params = cropParS;
            end
        end
    end
    
    %2. Crop around the region of interest
    limitsM = [];
    if ~(length(cropS) == 1 && strcmpi(cropS(1).method,'none'))
        fprintf('\nCropping to region of interest...\n');
        tic
        [minr, maxr, minc, maxc, slcV, cropStr3M, planC] = ...
            getCropLimits(planC,mask3M,scanNumV(scanIdx),cropS);
        %- Crop scan
        if ~isempty(scan3M) && numel(minr)==1
            scan3M = scan3M(minr:maxr,minc:maxc,slcV);
            limitsM = [minr, maxr, minc, maxc];
        else
            scan3M = scan3M(:,:,slcV);
            limitsM = [minr, maxr, minc, maxc];
        end
        
        %- Crop mask
        if numel(minr)==1
            cropStr3M = cropStr3M(minr:maxr,minc:maxc,slcV);
            if ~isempty(mask3M)
                mask3M = mask3M(minr:maxr,minc:maxc,slcV);
            end
        else
            cropStr3M = cropStr3M(:,:,slcV);
            if ~isempty(mask3M)
                mask3M = mask3M(:,:,slcV);
            end
        end
        toc
    end
    scanOptS(scanIdx).crop = cropS;
    
    %3. Resize
    if ~strcmpi(resizeS(scanIdx).method,'none')
        fprintf('\nResizing data...\n');
        tic
        resizeMethod = resizeS(scanIdx).method;
        outSizeV = resizeS(scanIdx).size;
        [scan3M, mask3M] = resizeScanAndMask(scan3M,mask3M,outSizeV,...
            resizeMethod,limitsM,preserveAspectFlag);
        % obtain patient outline in view if background adjustment is needed
        if adjustBackgroundVoxFlag || transformViewFlag
            [~, cropStr3M] = resizeScanAndMask([],cropStr3M,outSizeV,...
                resizeMethod,limitsM,preserveAspectFlag);
        else
            cropStr3M = [];
        end
        toc
    else
        cropStr3M = [];
    end
    
    scanC{scanIdx} = scan3M;
    maskC{scanIdx} = mask3M;
    
    
    %4. Transform view
    if transformViewFlag
        tic
        %     if ~isequal(viewC,{'axial'})
        fprintf('\nTransforming orientation...\n');
        %     end
        [viewOutC,maskOutC{scanIdx}] = transformView(scanC{scanIdx},...
            maskC{scanIdx},viewC);
        [~,cropStrC] = transformView([],cropStr3M,viewC);
        toc
    else % case: 1 view, 'axial'
        viewOutC = {scanC{scanIdx}};
        maskOutC{scanIdx} = {maskC(scanIdx)};
        cropStrC = {cropStr3M};
    end
    
    %5. Filter images as required
    tic
    procScanC = cell(numChannels,1);
    
    for i = 1:length(viewC)
        
        scanView3M = viewOutC{i};
        maskView3M = logical(cropStrC{i});
        
        for c = 1:numChannels
            
            %             mask3M = true(size(scanView3M));
            
            if strcmpi(filterTypeC{c},'original')
                %Use original image
                procScanC{c} = scanView3M;
                
            else
                imType = filterTypeC{c};
                imType = imType{1};
                if strcmpi(imType,'original')
                    procScanC{c} = scanView3M;
                else
                    fprintf('\nApplying %s filter...\n',imType);
                    paramS = channelParS(c);
                    filterParS = paramS.imageType.(imType);
                    outS = processImage(imType, scanView3M, maskView3M, filterParS);
                    fieldName = fieldnames(outS);
                    fieldName = fieldName{1};
                    procScanC{c} = outS.(fieldName);
                end
            end
        end
        viewOutC{i} = procScanC;
    end
    toc
    
    %6. Populate channels
    
    if numChannels > 1
        tic
        channelOutC = populateChannels(viewOutC,channelParS);
        fprintf('\nPopulating channels...\n');
        toc
    else
        channelOutC = viewOutC;
    end
    
    scanOutC{scanIdx} = channelOutC;
    
end
optS.scan = scanOptS;

%Get scan metadata
%uniformScanInfoS = planC{indexS.scan}(scanNumV(scanIdx)).uniformScanInfo;
%resM(scanIdx,:) = [uniformScanInfoS.grid2Units, uniformScanInfoS.grid1Units, uniformScanInfoS.sliceThickness];

end
