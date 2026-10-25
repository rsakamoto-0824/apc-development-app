classdef TestAPC < matlab.unittest.TestCase
    methods (Test)
        function linearValidationAndRoundTrip(test)
            [data,inputs,outputs]=test.fixture;
            [bundle,diagnostic]=apcTrain(data,inputs,outputs,'linear');
            test.verifyLessThan(max(diagnostic.Metrics.CV_RMSE),1e-10);
            test.verifySize(diagnostic.Predicted,[80,2]);
            folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
            file=fullfile(folder,'models.mat'); apcSaveModel(file,bundle);
            loaded=load(file);
            test.verifyFalse(isfield(loaded.modelBundle,'Data'));
            test.verifyEqual(apcPredict(bundle,[0.2,0.4]),apcPredict(loaded.modelBundle,[0.2,0.4]),'AbsTol',1e-14);
        end

        function quadraticTerms(test)
            [data,inputs,outputs]=test.fixture;
            data.Y1=data.A.^2+2*data.A.*data.B+data.B.^2;
            [bundle,diagnostic]=apcTrain(data,inputs,outputs,{'quadratic','linear'});
            test.verifyLessThan(max(diagnostic.Metrics.CV_RMSE),1e-10);
            test.verifyEqual(apcPredict(bundle,[0.2,0.4]),[0.36,1.4],'AbsTol',1e-12);
        end

        function repeatedConditionsStayInSameFold(test)
            [data,inputs,outputs]=test.fixture;
            data=[data;data(1:10,:)];
            [~,diagnostic]=apcTrain(data,inputs,outputs,'linear');
            test.verifyEqual(diagnostic.FoldID(1:10),diagnostic.FoldID(81:90));
        end

        function explicitGroups(test)
            [data,inputs,outputs]=test.fixture;
            data.Lot=repelem((1:8)',10);
            [~,diagnostic]=apcTrain(data,inputs,outputs,'linear',struct('GroupColumn','Lot'));
            for group=1:8
                test.verifyEqual(numel(unique(diagnostic.FoldID(data.Lot==group))),1);
            end
        end

        function trainingRejectsInvalidValues(test)
            [data,inputs,outputs]=test.fixture; data.A(1)=NaN;
            test.verifyError(@()apcTrain(data,inputs,outputs,'linear'),'APC:TrainingData');
            data.A(1)=0;
            test.verifyError(@()apcTrain(data,{'A'},{'A'},'linear'),'APC:TrainingColumns');
        end

        function rankDeficiencyAndRidge(test)
            [data,inputs,outputs]=test.fixture; data.B=data.A;
            test.verifyError(@()apcTrain(data,inputs,outputs,'quadratic'),'APC:InsufficientDesign');
            bundle=apcTrain(data,inputs,outputs,'ridge');
            test.verifyTrue(all(isfinite(apcPredict(bundle,[0,0]))));
        end

        function preprocessingUsesOnlyTrainingFold(test)
            [data,inputs,outputs]=test.fixture;
            [~,diagnostic]=apcTrain(data,inputs,outputs,'ridge',struct('Folds',4));
            fold=diagnostic.FoldID(1); training=data(diagnostic.FoldID~=fold,:);
            bundle=apcTrain(training,inputs,outputs,'ridge',struct('Folds',2));
            expected=apcPredict(bundle,data{diagnostic.FoldID==fold,inputs});
            test.verifyEqual(diagnostic.Predicted(diagnostic.FoldID==fold,:),expected,'AbsTol',1e-12);
        end

        function constantOutputHasUndefinedR2(test)
            [data,inputs,outputs]=test.fixture; data.Y1(:)=2;
            [~,diagnostic]=apcTrain(data,inputs,outputs,'linear');
            test.verifyTrue(isnan(diagnostic.Metrics.CV_R2(1)));
        end

        function deterministicSearchAndGlobalRng(test)
            [bundle,problem,options]=test.problemFixture;
            state=rng;
            [first,predicted,log]=apcRuntime(bundle,problem,options);
            [second,secondPrediction,again]=apcRuntime(bundle,problem,options);
            test.verifyTrue(log.Success,log.Message);
            test.verifyEqual(first,second); test.verifyEqual(predicted,secondPrediction);
            test.verifyEqual(log.ParetoLosses,again.ParetoLosses);
            test.verifyEqual(rng,state);
            for index=1:size(log.ParetoLosses,1)
                dominated=all(log.ParetoLosses<=log.ParetoLosses(index,:),2) & ...
                    any(log.ParetoLosses<log.ParetoLosses(index,:),2);
                test.verifyFalse(any(dominated));
            end
        end

        function boundsMovesStepsAndFixedInputs(test)
            [bundle,problem,options]=test.problemFixture;
            problem.LowerBounds=[-0.5,0.2]; problem.UpperBounds=[0.5,0.2];
            problem.CurrentPoint=[0,0.2]; problem.MaxMove=[0.2,0]; problem.Step=[0.1,0];
            [parameters,~,log]=apcRuntime(bundle,problem,options);
            test.verifyTrue(log.Success,log.Message);
            test.verifyLessThanOrEqual(max(abs(log.ParetoParameters(:,1))),0.2+1e-12);
            test.verifyEqual(parameters(2),0.2,'AbsTol',1e-14);
            gridIndex=(log.ParetoParameters(:,1)+0.5)/0.1;
            test.verifyEqual(gridIndex,round(gridIndex),'AbsTol',1e-12);
        end

        function responseConstraintsAndInfeasibility(test)
            [bundle,problem,options]=test.problemFixture;
            problem.ResponseLower=[-Inf,-Inf]; problem.ResponseUpper=[0.6,1.7];
            [~,~,log]=apcRuntime(bundle,problem,options);
            test.verifyTrue(log.Success,log.Message);
            test.verifyTrue(all(all(log.ParetoPredictions<=problem.ResponseUpper+1e-8)));
            problem.ResponseUpper=[-100,-100];
            [parameters,predictions,log]=apcRuntime(bundle,problem,options);
            test.verifyFalse(log.Success); test.verifyEmpty(parameters); test.verifyEmpty(predictions);
            test.verifyEqual(log.Status,'no_feasible_candidate');
        end

        function invalidOrderExtrapolationAndNoGrid(test)
            [bundle,problem,options]=test.problemFixture;
            problem.InputNames=fliplr(problem.InputNames);
            [x,~,log]=apcRuntime(bundle,problem,options);
            test.verifyEmpty(x); test.verifySubstring(log.Message,'APC:ColumnOrder');
            problem.InputNames=bundle.InputNames; problem.LowerBounds(1)=-20;
            [~,~,log]=apcRuntime(bundle,problem,options);
            test.verifyFalse(log.Success); test.verifySubstring(log.Message,'APC:Extrapolation');
            [problem,~]=apcDefaultProblem(bundle);
            problem.LowerBounds=[0,0]; problem.UpperBounds=[0.5,0.5];
            problem.CurrentPoint=[0.2,0.2]; problem.MaxMove=[0,0]; problem.Step=[0.5,0.5];
            [~,~,log]=apcRuntime(bundle,problem,options);
            test.verifyFalse(log.Success); test.verifySubstring(log.Message,'APC:Grid');
        end

        function timeLimitIsLogged(test)
            [bundle,problem,options]=test.problemFixture;
            options.MaxSeconds=1e-9;
            [~,~,log]=apcRuntime(bundle,problem,options);
            test.verifyEqual(log.StopReason,'time_limit');
            test.verifyEqual(log.CompletedGenerations,0);
        end

        function exportedFunctionIsIndependentAndEquivalent(test)
            [bundle,problem,options]=test.problemFixture;
            parent=tempname; mkdir(parent);
            folder=apcExport(parent,'controlForTest',bundle,problem,options);
            addpath(folder);
            cleanup=onCleanup(@()test.removeExport(folder,parent)); %#ok<NASGU>
            [expected,predicted,expectedLog]=apcRuntime(bundle,problem,options);
            [actual,actualPrediction,log]=controlForTest(fullfile(folder,'models.mat'),problem,options);
            test.verifyEqual(actual,expected); test.verifyEqual(actualPrediction,predicted);
            test.verifyEqual(log.ParetoLosses,expectedLog.ParetoLosses);
            test.verifyLessThan(numel(splitlines(string(fileread(fullfile(folder,'controlForTest.m'))))),40);
            [x,y,log]=controlForTest(fullfile(folder,'missing.mat'),problem,options);
            test.verifyEmpty(x); test.verifyEmpty(y); test.verifyFalse(log.Success);
        end

        function gaussianProcess(test)
            [data,inputs,outputs]=test.fixture;
            bundle=apcTrain(data,inputs,outputs,{'gpr','linear'},struct('Folds',2));
            test.verifyTrue(all(isfinite(apcPredict(bundle,[0.1,0.2]))));
            parent=tempname; mkdir(parent); cleanup=onCleanup(@()rmdir(parent,'s')); %#ok<NASGU>
            file=fullfile(parent,'gpr.mat'); apcSaveModel(file,bundle); loaded=load(file);
            test.verifyEqual(apcPredict(bundle,[0.1,0.2]),apcPredict(loaded.modelBundle,[0.1,0.2]),'AbsTol',1e-12);
        end

        function excelAndAppWorkflow(test)
            [data,~,~]=test.fixture;
            parent=tempname; mkdir(parent); cleanup=onCleanup(@()rmdir(parent,'s')); %#ok<NASGU>
            workbook=fullfile(parent,'input.xlsx'); writetable(data,workbook,'Sheet','Process');
            app=APCDevelopmentApp('off'); appCleanup=onCleanup(@()delete(app)); %#ok<NASGU>
            app.importWorkbook(workbook,'Process');
            test.verifyEqual(height(app.Data),height(data));
            app.train; app.optimize;
            test.verifyTrue(app.Result.Log.Success,app.Result.Log.Message);
            folder=app.export(parent,'uiControlForTest');
            test.verifyTrue(isfile(fullfile(folder,'uiControlForTest.m')));
        end
    end
    methods (Static,Access=private)
        function [data,inputs,outputs]=fixture
            stream=RandStream('mt19937ar','Seed',19);
            a=2*rand(stream,80,1)-1; b=2*rand(stream,80,1)-1;
            data=table(a,b,a+2*b,2-a-b,'VariableNames',{'A','B','Y1','Y2'});
            inputs={'A','B'}; outputs={'Y1','Y2'};
        end

        function [bundle,problem,options]=problemFixture
            [data,inputs,outputs]=TestAPC.fixture;
            bundle=apcTrain(data,inputs,outputs,'linear');
            [problem,options]=apcDefaultProblem(bundle);
            problem.Goals={'min','min'};
            options.Generations=5; options.PopulationSize=32; options.MaxSeconds=120;
        end

        function removeExport(folder,parent)
            rmpath(folder); rmdir(parent,'s');
        end
    end
end
