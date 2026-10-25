function [parameters, predictions, log] = apcControl(modelFile, problem, options)
%APCCONTROL Entry point for MATLAB Production Server compilation.
% modelFile: server-local MAT path, containing modelBundle.
% problem: names, bounds, current settings, goals and response constraints.
% options: search size, seed, time limit and extrapolation policy.
% parameters: one row in problem.InputNames order, or [] on failure.
% predictions: one row in problem.OutputNames order, or [] on failure.
% Apply a control command only when log.Success is true.
if nargin<3, options=struct; end
try
    loaded=load(modelFile,'modelBundle');
    if ~isfield(loaded,'modelBundle')
        error('APC:ModelFile','MAT file must contain modelBundle.');
    end
    [parameters,predictions,log]=apcRuntime(loaded.modelBundle,problem,options);
catch exception
    parameters=[]; predictions=[];
    log=struct('Success',false,'Status','error', ...
        'Message',sprintf('%s: %s',exception.identifier,exception.message));
end
end
