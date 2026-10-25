function summary = createReviewArtifacts()
%CREATEREVIEWARTIFACTS Reproduce the synthetic workbook and UI review outputs.
source=fileparts(mfilename('fullpath')); project=fileparts(source); addpath(source);
output=fullfile(project,'test-results'); examples=fullfile(project,'examples');
exports=fullfile(project,'exports');
folders={output,examples,exports};
for index=1:numel(folders)
    if ~isfolder(folders{index}), mkdir(folders{index}); end
end
app=APCDevelopmentApp('on'); cleanup=onCleanup(@()delete(app));
workbook=fullfile(examples,'APC_sample.xlsx');
writetable(app.Data,workbook,'Sheet','SyntheticProcess');
drawnow; exportapp(app.Figure,fullfile(output,'01_excel.png'));
app.train;
app.UI.Tabs.SelectedTab=app.UI.Tabs.Children(2);
drawnow; exportapp(app.Figure,fullfile(output,'02_validation.png'));
responses=app.UI.Responses.Data;
responses(1,3:4)={100,1}; responses(2,2:4)={'min',0,1};
app.UI.Responses.Data=responses;
app.optimize;
app.UI.Tabs.SelectedTab=app.UI.Tabs.Children(3);
drawnow; exportapp(app.Figure,fullfile(output,'03_optimization.png'));
folder=app.export(exports,'optimizeAPC');
summary=struct('Workbook',workbook,'ExportFolder',folder, ...
    'Metrics',table2struct(app.Bundle.Metrics),'Success',app.Result.Log.Success, ...
    'Parameters',app.Result.Parameters,'Predictions',app.Result.Predictions, ...
    'ParetoCount',size(app.Result.Log.ParetoParameters,1), ...
    'Evaluations',app.Result.Log.Evaluations);
save(fullfile(output,'synthetic_review.mat'),'summary','-v7');
disp(summary);
files=dir(fullfile(source,'*.m'));
for index=1:numel(files)
    messages=checkcode(fullfile(source,files(index).name),'-id');
    for message=1:numel(messages)
        fprintf('%s:%d %s %s\n',files(index).name,messages(message).line, ...
            messages(message).id,messages(message).message);
    end
end
end
