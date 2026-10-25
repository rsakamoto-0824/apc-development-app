function predicted = apcPredict(bundle, parameters)
%APCPREDICT Rows are conditions; columns follow bundle.InputNames.
apcValidateBundle(bundle);
if ~isnumeric(parameters) || ~isreal(parameters) || ...
        size(parameters,2)~=numel(bundle.InputNames) || any(~isfinite(parameters(:)))
    error('APC:PredictionInput','Prediction requires a finite numeric matrix in InputNames order.');
end
predicted = zeros(size(parameters,1),numel(bundle.Models));
for index = 1:numel(bundle.Models)
    model = bundle.Models{index};
    z = (parameters-reshape(model.Center,1,[]))./reshape(model.Scale,1,[]);
    if strcmp(model.Method,'gpr')
        predicted(:,index) = predict(model.Fit,z);
    else
        predicted(:,index) = apcFeatures(z,model.Method)*model.Beta(:);
    end
end
if ~isreal(predicted) || any(~isfinite(predicted(:)))
    error('APC:PredictionFailed','Model returned non-finite or complex predictions.');
end
end
