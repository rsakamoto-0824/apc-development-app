function [parameters, predictions, log] = apcRuntime(bundle, problem, options)
%APCRUNTIME Bounded Pareto search without UI or Optimization Toolbox.
% Empty numeric outputs always mean that no control command may be applied.
parameters=[]; predictions=[]; started=tic;
log=struct('Success',false,'Status','error','Message','', ...
    'ModelID','','InputNames',{{}},'OutputNames',{{}},'Seed',[], ...
    'ElapsedSeconds',0,'Evaluations',0,'CompletedGenerations',0, ...
    'StopReason','','History',[],'ParetoParameters',[], ...
    'ParetoPredictions',[],'ParetoLosses',[],'SelectedIndex',[], ...
    'SelectedLosses',[],'BaselinePredictions',[],'Problem',struct,'Options',struct);
try
    apcValidateBundle(bundle);
    [problem,options,lower,upper]=checkRequest(bundle,problem,options);
    log.ModelID=bundle.ModelID; log.InputNames=bundle.InputNames;
    log.OutputNames=bundle.OutputNames; log.Seed=options.Seed;
    log.Problem=problem; log.Options=options;
    log.BaselinePredictions=apcPredict(bundle,problem.CurrentPoint);
    stream=RandStream('mt19937ar','Seed',options.Seed);
    inputCount=numel(lower); populationSize=options.PopulationSize;
    candidates=lower+rand(stream,populationSize,inputCount).*(upper-lower);
    candidates(1,:)=min(upper,max(lower,problem.CurrentPoint));
    candidates=projectGrid(candidates,problem,lower,upper);
    archiveX=[]; archiveY=[]; archiveLoss=[];
    history=zeros(options.Generations+1,4);
    bestViolation=Inf;
    for generation=0:options.Generations
        [y,loss,violation]=evaluateCandidates(bundle,candidates,problem,options.Tolerance);
        log.Evaluations=log.Evaluations+size(candidates,1);
        bestViolation=min(bestViolation,min(violation));
        feasible=violation<=options.Tolerance;
        archiveX=[archiveX;candidates(feasible,:)]; %#ok<AGROW>
        archiveY=[archiveY;y(feasible,:)]; %#ok<AGROW>
        archiveLoss=[archiveLoss;loss(feasible,:)]; %#ok<AGROW>
        [archiveX,archiveY,archiveLoss]=paretoArchive( ...
            archiveX,archiveY,archiveLoss,options.ArchiveLimit);
        history(generation+1,:)=[generation,log.Evaluations,size(archiveX,1),bestViolation];
        log.CompletedGenerations=generation;
        if toc(started)>=options.MaxSeconds
            log.StopReason='time_limit'; break;
        end
        if generation==options.Generations
            log.StopReason='generation_limit'; break;
        end
        % Global samples retain coverage; local samples refine Pareto candidates.
        if isempty(archiveX)
            [~,order]=sort(violation);
            parents=candidates(order(1:min(10,numel(order))),:);
        else
            parents=archiveX;
        end
        parentIndex=randi(stream,size(parents,1),populationSize,1);
        radius=0.25*(1-generation/max(1,options.Generations))+0.01;
        candidates=parents(parentIndex,:)+radius*randn(stream,populationSize,inputCount).*(upper-lower);
        globalCount=max(1,ceil(populationSize/4));
        candidates(1:globalCount,:)=lower+rand(stream,globalCount,inputCount).*(upper-lower);
        candidates=projectGrid(candidates,problem,lower,upper);
    end
    log.History=history(1:log.CompletedGenerations+1,:);
    log.ParetoParameters=archiveX; log.ParetoPredictions=archiveY; log.ParetoLosses=archiveLoss;
    if isempty(archiveX)
        log.Status='no_feasible_candidate';
        log.Message='No feasible candidate was found. This does not prove infeasibility.';
    else
        % Weights choose one candidate only after the Pareto set is constructed.
        lossRange=max(archiveLoss,[],1)-min(archiveLoss,[],1);
        lossRange(lossRange==0)=1;
        distance=(archiveLoss-min(archiveLoss,[],1))./lossRange;
        score=(distance.^2)*(problem.Weights(:)/sum(problem.Weights));
        [~,selected]=min(score);
        parameters=archiveX(selected,:); predictions=archiveY(selected,:);
        log.SelectedIndex=selected; log.SelectedLosses=archiveLoss(selected,:);
        log.Success=true; log.Status='ok';
        log.Message='Approximate Pareto candidate selected; global optimality is not guaranteed.';
    end
catch exception
    parameters=[]; predictions=[];
    log.Success=false; log.Status='error';
    log.Message=sprintf('%s: %s',exception.identifier,exception.message);
end
log.ElapsedSeconds=toc(started);
end

function [problem,options,lower,upper]=checkRequest(bundle,problem,options)
required={'InputNames','OutputNames','LowerBounds','UpperBounds','CurrentPoint', ...
    'MaxMove','Step','Goals','Targets','Scales','Weights','ResponseLower','ResponseUpper'};
if ~isstruct(problem) || ~isscalar(problem) || ~all(isfield(problem,required)) || ...
        any(~ismember(fieldnames(problem),required))
    error('APC:Problem','Problem fields are missing or unknown.');
end
if ~isequal(string(problem.InputNames(:)),string(bundle.InputNames(:))) || ...
        ~isequal(string(problem.OutputNames(:)),string(bundle.OutputNames(:)))
    error('APC:ColumnOrder','InputNames and OutputNames must match the model order exactly.');
end
inputCount=numel(bundle.InputNames); outputCount=numel(bundle.OutputNames);
inputFields={'LowerBounds','UpperBounds','CurrentPoint','MaxMove','Step'};
outputFields={'Targets','Scales','Weights','ResponseLower','ResponseUpper'};
for index=1:numel(inputFields)
    name=inputFields{index};
    problem.(name)=numericRow(problem.(name),inputCount,name);
end
for index=1:numel(outputFields)
    name=outputFields{index};
    problem.(name)=numericRow(problem.(name),outputCount,name);
end
finiteValues=[problem.LowerBounds,problem.UpperBounds,problem.CurrentPoint, ...
    problem.Step,problem.Targets,problem.Scales,problem.Weights];
if any(~isfinite(finiteValues)) || any(problem.LowerBounds>problem.UpperBounds) || ...
        any(problem.MaxMove<0) || any(problem.Step<0) || ...
        any(problem.Scales<=0) || any(problem.Weights<=0) || ...
        any(problem.ResponseLower>problem.ResponseUpper) || ...
        any(problem.ResponseLower==Inf) || any(problem.ResponseUpper==-Inf)
    error('APC:Problem','Bounds, steps, scales, weights or response constraints are invalid.');
end
problem.Goals=cellstr(lowerCaseGoals(problem.Goals,outputCount));
defaults=struct('PopulationSize',64,'Generations',25,'Seed',42, ...
    'MaxSeconds',15,'Tolerance',1e-8,'AllowExtrapolation',false,'ArchiveLimit',300);
if ~isstruct(options) || ~isscalar(options) || any(~ismember(fieldnames(options),fieldnames(defaults)))
    error('APC:Options','Unknown optimizer option.');
end
names=fieldnames(defaults);
for index=1:numel(names)
    if ~isfield(options,names{index}), options.(names{index})=defaults.(names{index}); end
end
validateattributes(options.PopulationSize,{'numeric'},{'scalar','integer','>=',8,'<=',2000});
validateattributes(options.Generations,{'numeric'},{'scalar','integer','>=',0,'<=',1000});
validateattributes(options.ArchiveLimit,{'numeric'},{'scalar','integer','>=',2,'<=',2000});
validateattributes(options.Seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
validateattributes(options.MaxSeconds,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(options.Tolerance,{'numeric'},{'scalar','real','finite','>=',0,'<=',1e-3});
validateattributes(options.AllowExtrapolation,{'logical'},{'scalar'});
if ~options.AllowExtrapolation && ...
        (any(problem.LowerBounds<reshape(bundle.TrainingMin,1,[])) || ...
        any(problem.UpperBounds>reshape(bundle.TrainingMax,1,[])) || ...
        any(problem.CurrentPoint<reshape(bundle.TrainingMin,1,[])) || ...
        any(problem.CurrentPoint>reshape(bundle.TrainingMax,1,[])))
    error('APC:Extrapolation','Requested bounds/current point exceed the observed training range.');
end
lower=max(problem.LowerBounds,problem.CurrentPoint-problem.MaxMove);
upper=min(problem.UpperBounds,problem.CurrentPoint+problem.MaxMove);
if any(lower>upper)
    error('APC:MoveLimit','Bounds and maximum moves do not intersect.');
end
% Step is anchored at LowerBounds, even when move limits narrow the interval.
discrete=problem.Step>0;
lower(discrete)=problem.LowerBounds(discrete)+ceil( ...
    (lower(discrete)-problem.LowerBounds(discrete))./problem.Step(discrete)-1e-12).*problem.Step(discrete);
upper(discrete)=problem.LowerBounds(discrete)+floor( ...
    (upper(discrete)-problem.LowerBounds(discrete))./problem.Step(discrete)+1e-12).*problem.Step(discrete);
if any(lower>upper)
    error('APC:Grid','No allowed discrete setting is inside the move/bound limits.');
end
end

function row=numericRow(value,count,name)
if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || ...
        numel(value)~=count || any(isnan(value(:)))
    error('APC:Problem','%s must be a real numeric vector of length %d.',name,count);
end
row=reshape(double(value),1,[]);
end

function goals=lowerCaseGoals(value,count)
goals=lower(string(value(:)'));
if numel(goals)~=count || any(~ismember(goals,["min","max","target"]))
    error('APC:Goals','Each output goal must be min, max or target.');
end
end

function x=projectGrid(x,problem,lower,upper)
x=min(upper,max(lower,x));
discrete=problem.Step>0;
x(:,discrete)=problem.LowerBounds(discrete)+round( ...
    (x(:,discrete)-problem.LowerBounds(discrete))./problem.Step(discrete)).*problem.Step(discrete);
x=min(upper,max(lower,x));
x=unique(x,'rows','stable');
end

function [predicted,loss,violation]=evaluateCandidates(bundle,x,problem,tolerance)
predicted=apcPredict(bundle,x);
loss=zeros(size(predicted));
for index=1:numel(problem.Goals)
    difference=(predicted(:,index)-problem.Targets(index))/problem.Scales(index);
    switch problem.Goals{index}
        case 'min', loss(:,index)=difference;
        case 'max', loss(:,index)=-difference;
        case 'target', loss(:,index)=abs(difference);
    end
end
if any(~isfinite(loss(:)))
    error('APC:LossOverflow','Objective losses overflowed. Review response scales and targets.');
end
% Feasibility tolerance is dimensionless, normalized by each response scale.
below=max(0,(problem.ResponseLower-predicted)./problem.Scales);
above=max(0,(predicted-problem.ResponseUpper)./problem.Scales);
violation=max(below+above,[],2);
violation(violation<=tolerance)=0;
end

function [x,y,loss]=paretoArchive(x,y,loss,limit)
if isempty(x), return; end
[x,indices]=unique(x,'rows','stable'); y=y(indices,:); loss=loss(indices,:);
keep=true(size(x,1),1);
for index=1:size(loss,1)
    keep(index)=~any(all(loss<=loss(index,:),2) & any(loss<loss(index,:),2));
end
x=x(keep,:); y=y(keep,:); loss=loss(keep,:);
if size(x,1)<=limit, return; end
% Preserve extremes and diverse points when the archive must be bounded.
distance=zeros(size(x,1),1);
for objective=1:size(loss,2)
    [values,order]=sort(loss(:,objective));
    span=values(end)-values(1);
    if span==0, continue; end
    distance(order([1,end]))=Inf;
    distance(order(2:end-1))=distance(order(2:end-1))+(values(3:end)-values(1:end-2))/span;
end
[~,order]=sort(distance,'descend'); order=order(1:limit);
x=x(order,:); y=y(order,:); loss=loss(order,:);
end
