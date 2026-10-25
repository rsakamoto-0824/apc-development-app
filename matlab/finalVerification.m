function folder = finalVerification()
%FINALVERIFICATION Check tests and run an export with the app source off path.
source=fileparts(mfilename('fullpath')); project=fileparts(source);
results=runTests;
output=fullfile(project,'test-results');
if ~isfolder(output), mkdir(output); end
reviewFile=fullfile(output,'synthetic_review.mat');
if ~isfile(reviewFile), createReviewArtifacts; end
records=table(results);
writetable(records(:,{'Name','Passed','Failed','Incomplete','Duration'}), ...
    fullfile(output,'test_results.csv'));
review=load(reviewFile,'summary');
previous=review.summary.ExportFolder;
if ~isfolder(previous)
    createReviewArtifacts;
    review=load(reviewFile,'summary'); previous=review.summary.ExportFolder;
end
model=load(fullfile(previous,'models.mat'),'modelBundle');
settings=load(fullfile(previous,'settings.mat'));
folder=apcExport(fullfile(project,'exports'),'optimizeAPC', ...
    model.modelBundle,settings.problem,settings.options);
addpath(folder); rmpath(source);
cleanup=onCleanup(@()restorePaths(source,folder));
[parameters,predictions,log]=optimizeAPC( ...
    fullfile(folder,'models.mat'),settings.problem,settings.options);
assert(log.Success,log.Message);
assert(max(abs(parameters-review.summary.Parameters))<1e-12,'Exported parameters differ.');
assert(max(abs(predictions-review.summary.Predictions))<1e-12,'Exported predictions differ.');
fprintf('ISOLATED_EXPORT_OK: %s\n',folder);
end

function restorePaths(source,folder)
addpath(source); rmpath(folder);
end
