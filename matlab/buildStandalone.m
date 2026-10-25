function result = buildStandalone()
%BUILDSTANDALONE Build the Windows desktop app; does not compile MPS code.
assert(~verLessThan('matlab','9.11'),'MATLAB R2021b or later is required.');
assert(ispc,'Build the Windows application on Windows MATLAB.');
assert(license('test','Compiler'),'MATLAB Compiler is required.');
assert(license('test','Statistics_Toolbox'),'Statistics and Machine Learning Toolbox is required for GPR.');
source=fileparts(mfilename('fullpath'));
output=fullfile(fileparts(source),'build','windows');
addpath(source);
% Text assets remain readable after compilation, allowing source export.
assets={'apcControl.m','apcRuntime.m','apcPredict.m','apcFeatures.m','apcValidateBundle.m'};
templates=fullfile(fileparts(source),'build','export_templates');
if ~isfolder(templates), mkdir(templates); end
for index=1:numel(assets)
    copyfile(fullfile(source,assets{index}),fullfile(templates,[assets{index},'.txt']));
end
assets={templates,fullfile(fileparts(source),'README.md')};
result=compiler.build.standaloneApplication(fullfile(source,'launchAPC.m'), ...
    'ExecutableName','APCDevelopmentApp','OutputDir',output,'AdditionalFiles',assets);
fprintf('Build: %s\nInstall the matching MATLAB Runtime on the target computer.\n',output);
end
