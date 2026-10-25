function apcValidateBundle(bundle)
%APCVALIDATEBUNDLE Validate a versioned model contract before inference.
required = {'SchemaVersion','ModelID','InputNames','OutputNames','Models', ...
    'TrainingMin','TrainingMax'};
if ~isstruct(bundle) || ~isscalar(bundle) || ~all(isfield(bundle,required))
    error('APC:InvalidModel','The model bundle is incomplete.');
end
if ~isequal(bundle.SchemaVersion,1)
    error('APC:ModelVersion','Unsupported model schema version.');
end
inputNames = cellstr(string(bundle.InputNames));
outputNames = cellstr(string(bundle.OutputNames));
inputCount = numel(inputNames);
if inputCount<1 || isempty(outputNames) || ...
        numel(unique(inputNames))~=inputCount || ...
        numel(unique(outputNames))~=numel(outputNames) || ...
        any(strlength(string([inputNames(:);outputNames(:)]))==0) || ...
        ~iscell(bundle.Models) || numel(bundle.Models)~=numel(outputNames)
    error('APC:InvalidModel','Model names or model count are invalid.');
end
if ~isnumeric(bundle.TrainingMin) || ~isnumeric(bundle.TrainingMax) || ...
        ~isreal(bundle.TrainingMin) || ~isreal(bundle.TrainingMax) || ...
        numel(bundle.TrainingMin)~=inputCount || numel(bundle.TrainingMax)~=inputCount || ...
        any(~isfinite([bundle.TrainingMin(:);bundle.TrainingMax(:)])) || ...
        any(bundle.TrainingMin(:)>bundle.TrainingMax(:))
    error('APC:InvalidModel','Training ranges are invalid.');
end
for index = 1:numel(bundle.Models)
    model = bundle.Models{index};
    if ~isstruct(model) || ~all(isfield(model,{'Method','Center','Scale'})) || ...
            numel(model.Center)~=inputCount || numel(model.Scale)~=inputCount || ...
            ~isreal(model.Center) || ~isreal(model.Scale) || ...
            any(~isfinite([model.Center(:);model.Scale(:)])) || any(model.Scale<=0)
        error('APC:InvalidModel','Invalid model preprocessing.');
    end
    if ismember(model.Method,{'linear','quadratic','ridge'})
        termCount = inputCount+1;
        if strcmp(model.Method,'quadratic')
            termCount = 1+2*inputCount+inputCount*(inputCount-1)/2;
        end
        if ~isfield(model,'Beta') || ~isnumeric(model.Beta) || ~isreal(model.Beta) || ...
                numel(model.Beta)~=termCount || any(~isfinite(model.Beta(:)))
            error('APC:InvalidModel','Invalid regression coefficients.');
        end
    elseif strcmp(model.Method,'gpr')
        if ~isfield(model,'Fit') || ~isobject(model.Fit)
            error('APC:InvalidModel','Invalid Gaussian process model.');
        end
    else
        error('APC:ModelMethod','Unsupported regression method.');
    end
end
end
