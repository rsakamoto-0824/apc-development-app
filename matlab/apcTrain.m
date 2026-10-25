function [bundle, diagnostic] = apcTrain(input, inputNames, outputNames, methods, settings)
%APCTRAIN Grouped out-of-fold evaluation followed by a full-data fit.
if nargin<5, settings=struct; end
settings = trainingSettings(settings);
inputNames = cellstr(string(inputNames(:)'));
outputNames = cellstr(string(outputNames(:)'));
methods = cellstr(lower(string(methods(:)')));
if isscalar(methods), methods=repmat(methods,1,numel(outputNames)); end
allNames = [inputNames,outputNames];
if ~istable(input) || isempty(inputNames) || isempty(outputNames) || ...
        numel(unique(allNames))~=numel(allNames) || ...
        ~all(ismember(allNames,input.Properties.VariableNames)) || ...
        numel(methods)~=numel(outputNames) || ...
        ~all(ismember(methods,{'linear','quadratic','ridge','gpr'}))
    error('APC:TrainingColumns','Choose distinct input/output columns and supported methods.');
end
for index=1:numel(allNames)
    column=input.(allNames{index});
    if ~isnumeric(column) || ~isreal(column) || size(column,2)~=1 || any(~isfinite(column))
        error('APC:TrainingData','Column %s must contain finite real numbers; missing rows are not removed automatically.',allNames{index});
    end
end
x=double(input{:,inputNames}); y=double(input{:,outputNames});
if height(input)<4
    error('APC:TrainingData','At least four rows are required.');
end
% Repeated conditions stay together, so validation does not reuse their labels.
[~,~,groups]=unique(x,'rows');
if ~isempty(settings.GroupColumn)
    if ~ismember(settings.GroupColumn,input.Properties.VariableNames)
        error('APC:GroupColumn','The validation group column does not exist.');
    end
    labels=string(input.(settings.GroupColumn));
    if any(ismissing(labels) | strlength(strtrim(labels))==0)
        error('APC:GroupColumn','Validation groups must not be missing.');
    end
    [~,~,groups]=unique(labels);
end
groupCount=max(groups); folds=min(settings.Folds,groupCount);
if folds<2, error('APC:TrainingData','At least two validation groups are required.'); end
stream=RandStream('mt19937ar','Seed',settings.Seed);
assignment=zeros(groupCount,1);
assignment(randperm(stream,groupCount))=mod(0:groupCount-1,folds)+1;
foldID=assignment(groups);
oof=nan(size(y)); training=nan(size(y)); models=cell(1,size(y,2));
for outputIndex=1:size(y,2)
    for fold=1:folds
        inTraining=foldID~=fold;
        fit=fitOne(x(inTraining,:),y(inTraining,outputIndex),methods{outputIndex},settings);
        temporary=makeBundle({fit},inputNames,outputNames(outputIndex),x);
        oof(~inTraining,outputIndex)=apcPredict(temporary,x(~inTraining,:));
    end
    models{outputIndex}=fitOne(x,y(:,outputIndex),methods{outputIndex},settings);
end
bundle=makeBundle(models,inputNames,outputNames,x);
bundle.CreatedUTC=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
bundle.MATLABRelease=version('-release');
bundle.TrainingSettings=settings;
training(:,:)=apcPredict(bundle,x);
residual=y-oof; total=sum((y-mean(y,1)).^2,1);
rSquared=1-sum(residual.^2,1)./total;
rSquared(total<=eps(max(1,max(abs(y),[],1))).^2*size(y,1))=NaN;
metrics=table(string(outputNames(:)),string(methods(:)), ...
    sqrt(mean(residual.^2,1))',mean(abs(residual),1)',rSquared', ...
    mean(residual,1)',sqrt(mean((y-training).^2,1))', ...
    'VariableNames',{'Response','Method','CV_RMSE','CV_MAE','CV_R2','CV_Bias','Train_RMSE'});
bundle.Metrics=metrics;
diagnostic=struct('Metrics',metrics,'Observed',y,'Predicted',oof, ...
    'Residual',residual,'FoldID',foldID,'Groups',groups,'Settings',settings);
end

function settings=trainingSettings(settings)
defaults=struct('Folds',5,'Seed',42,'RidgeLambda',1,'GroupColumn','', ...
    'Kernel','ardsquaredexponential');
if ~isstruct(settings) || ~isscalar(settings) || any(~ismember(fieldnames(settings),fieldnames(defaults)))
    error('APC:TrainingSettings','Unknown training setting.');
end
names=fieldnames(defaults);
for index=1:numel(names)
    if ~isfield(settings,names{index}), settings.(names{index})=defaults.(names{index}); end
end
validateattributes(settings.Folds,{'numeric'},{'scalar','integer','>=',2,'<=',50});
validateattributes(settings.Seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
validateattributes(settings.RidgeLambda,{'numeric'},{'scalar','real','finite','positive'});
settings.GroupColumn=char(settings.GroupColumn);
if ~ismember(settings.Kernel,{'squaredexponential','ardsquaredexponential','matern32', ...
        'ardmatern32','matern52','ardmatern52','rationalquadratic','ardrationalquadratic'})
    error('APC:TrainingSettings','Unsupported GPR kernel.');
end
end

function model=fitOne(x,y,method,settings)
model=struct('Method',method,'Center',mean(x,1),'Scale',std(x,0,1));
model.Scale(model.Scale<=eps(max(1,abs(model.Center))))=1;
z=(x-model.Center)./model.Scale;
if strcmp(method,'gpr')
    if exist('fitrgp','file')~=2
        error('APC:ToolboxRequired','GPR needs Statistics and Machine Learning Toolbox.');
    end
    model.Fit=compact(fitrgp(z,y,'KernelFunction',settings.Kernel, ...
        'Standardize',false,'FitMethod','exact','PredictMethod','exact'));
else
    features=apcFeatures(z,method);
    if strcmp(method,'ridge')
        penalty=eye(size(features,2)); penalty(1,1)=0;
        model.Beta=[features;sqrt(settings.RidgeLambda)*penalty]\[y;zeros(size(features,2),1)];
    else
        if size(features,1)<=size(features,2) || rank(features)<size(features,2) || cond(features)>1e10
            error('APC:InsufficientDesign', ...
                'Cannot fit %s, including validation folds. Add independent conditions or use fewer terms/ridge.',method);
        end
        model.Beta=features\y;
    end
end
end

function bundle=makeBundle(models,inputNames,outputNames,x)
bundle=struct('SchemaVersion',1,'ModelID','', ...
    'InputNames',{inputNames},'OutputNames',{outputNames},'Models',{models}, ...
    'TrainingMin',min(x,[],1),'TrainingMax',max(x,[],1));
% tempname provides an identifier without changing the caller's random stream.
[~,bundle.ModelID]=fileparts(tempname);
end
