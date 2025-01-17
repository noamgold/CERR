function planC = openPlanCFromFile(file)
%function planC = openPlanCFromFile(file)
%
%This function loads planC from the specified file
%
%APA, 10/18/2010


[pathstr, name, ext] = fileparts(file);

%Get temporary directory to extract uncompress
pathStr = getCERRPath;
optName = [pathStr 'CERROptions.json'];
optS = opts4Exe(optName);

if isempty(optS.tmpDecompressDir)
    tmpExtractDir = tempdir;
elseif isdir(optS.tmpDecompressDir)
    tmpExtractDir = optS.tmpDecompressDir;
elseif ~isdir(optS.tmpDecompressDir)
    error('Please specify a valid directory within CERROptions.m for optS.tmpDecompressDir')
end

%untar if it is a .tar file
tarFile = 0;
if strcmpi(ext, '.tar')
    if ispc
        untar(file,tmpExtractDir)
        fileToUnzip = fullfile(tmpExtractDir, name);
    else
        untar(file,pathstr)
        fileToUnzip = fullfile(pathstr, name);
    end
    file = fileToUnzip;
    [pathstr, name, ext] = fileparts(fullfile(pathstr, name));
    tarFile = 1;
end

if strcmpi(ext, '.bz2')
    zipFile = 1;
    CERRStatusString(['Decompressing ' name ext '...']);
    outstr = gnuCERRCompression(file, 'uncompress',tmpExtractDir);
    if ispc
        loadfile = fullfile(tmpExtractDir, name);
    else
        loadfile = fullfile(pathstr, name);
    end
    [pathstr, name, ext] = fileparts(fullfile(pathstr, name));
elseif strcmpi(ext, '.zip')
    zipFile = 1;
    if ispc
        unzip(file,tmpExtractDir)
        loadfile = fullfile(tmpExtractDir, name);
    else
        unzip(file,pathstr)
        loadfile = fullfile(pathstr, name);
    end
    [pathstr, name, ext] = fileparts(fullfile(pathstr, name));
else
    zipFile = 0;
    loadfile = file;
end

CERRStatusString(['Loading ' name ext '...']);

planC           = load(loadfile,'planC');
try
    if zipFile
        delete(loadfile);
    end
    if tarFile
        delete(fileToUnzip);
    end
catch
end
planC           = planC.planC; %Conversion from struct created by load
