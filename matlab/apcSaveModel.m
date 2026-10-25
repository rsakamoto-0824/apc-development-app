function apcSaveModel(file, modelBundle)
%APCSAVEMODEL Save models and metadata without a separate source table.
% GPR retains the training points required for prediction inside its model.
apcValidateBundle(modelBundle);
save(file,'modelBundle','-v7');
end
