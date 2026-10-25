classdef APCDevelopmentApp < handle
    %APCDEVELOPMENTAPP Excel -> regression -> Pareto evaluation -> MPS source.
    properties
        Figure
        UI=struct
        Data=table
        Bundle=[]
        Diagnostic=[]
        Result=[]
        Workbook=''
    end
    methods
        function app=APCDevelopmentApp(visible)
            if nargin<1, visible='on'; end
            assert(~verLessThan('matlab','9.11'),'MATLAB R2021b or later is required.');
            app.buildUI(visible);
            app.loadExample;
        end

        function delete(app)
            if ~isempty(app.Figure) && isvalid(app.Figure), delete(app.Figure); end
        end

        function loadExample(app)
            stream=RandStream('mt19937ar','Seed',7);
            temperature=380+40*rand(stream,100,1);
            pressure=2+2*rand(stream,100,1);
            flow=80+40*rand(stream,100,1);
            thickness=100+0.12*(temperature-400)+1.5*(pressure-3) ...
                +0.02*(flow-100).^2+0.05*randn(stream,100,1);
            uniformity=1+0.002*(temperature-395).^2+0.3*(pressure-2.7).^2 ...
                +0.001*(flow-95).^2+0.01*randn(stream,100,1);
            app.Workbook='';
            app.Data=table(temperature,pressure,flow,thickness,uniformity, ...
                'VariableNames',{'Temperature','Pressure','Flow','Thickness','Uniformity'});
            app.UI.File.Value='架空のサンプルデータ（実プロセスを表しません）';
            app.UI.Sheet.Items={'サンプル'}; app.UI.Sheet.Value='サンプル';
            app.refreshData;
            app.setStatus('架空サンプルを表示中。Excelを読み込むか、このままモデルを作成できます。');
        end

        function importWorkbook(app,file,sheet)
            imported=readtable(file,'Sheet',sheet,'VariableNamingRule','preserve');
            if isempty(imported), error('APC:Excel','The selected sheet contains no data.'); end
            app.Data=imported; app.Workbook=file;
            app.UI.File.Value=file;
            app.refreshData;
            app.setStatus(sprintf('Excel読込: %d行 × %d列。説明変数と予測項目を選択してください。',height(imported),width(imported)));
        end

        function train(app)
            app.setStatus('回帰モデルを作成し、交差検証しています…'); drawnow;
            settings=struct('Folds',app.UI.Folds.Value,'Seed',app.UI.Seed.Value, ...
                'RidgeLambda',app.UI.Lambda.Value,'GroupColumn','', ...
                'Kernel',app.UI.Kernel.Value);
            if ~strcmp(app.UI.Group.Value,'(同じ入力条件でまとめる)')
                settings.GroupColumn=app.UI.Group.Value;
            end
            methodData=app.UI.Methods.Data;
            app.invalidateTraining;
            [bundle,diagnostic]=apcTrain(app.Data,app.UI.Inputs.Value, ...
                app.UI.Outputs.Value,methodData(:,2),settings);
            app.applyBundle(bundle);
            app.Diagnostic=diagnostic;
            app.UI.Metrics.Data=diagnostic.Metrics;
            app.drawDiagnostics;
            app.setStatus(sprintf('学習完了: %dモデル。交差検証の誤差を確認してください。',numel(bundle.Models)));
        end

        function [problem,options]=readProblem(app)
            app.requireModel;
            [problem,options]=apcDefaultProblem(app.Bundle);
            factors=app.UI.Factors.Data; responses=app.UI.Responses.Data;
            problem.LowerBounds=cell2mat(factors(:,2))';
            problem.UpperBounds=cell2mat(factors(:,3))';
            problem.CurrentPoint=cell2mat(factors(:,4))';
            problem.MaxMove=cell2mat(factors(:,5))';
            problem.Step=cell2mat(factors(:,6))';
            problem.Goals=responses(:,2)';
            problem.Targets=cell2mat(responses(:,3))';
            problem.Scales=cell2mat(responses(:,4))';
            problem.Weights=cell2mat(responses(:,5))';
            problem.ResponseLower=cell2mat(responses(:,6))';
            problem.ResponseUpper=cell2mat(responses(:,7))';
            options.PopulationSize=app.UI.Population.Value;
            options.Generations=app.UI.Generations.Value;
            options.Seed=app.UI.SearchSeed.Value;
            options.MaxSeconds=app.UI.MaxSeconds.Value;
            options.AllowExtrapolation=app.UI.Extrapolate.Value;
        end

        function optimize(app)
            [problem,options]=app.readProblem;
            app.clearResult;
            app.setStatus('多目的探索を実行しています…'); drawnow;
            [parameters,predictions,log]=apcRuntime(app.Bundle,problem,options);
            app.Result=struct('Parameters',parameters,'Predictions',predictions,'Log',log);
            app.UI.Log.Value=splitlines(string(jsonencode(log)));
            if strcmp(log.Status,'error'), error('APC:Optimization','%s',log.Message); end
            if ~log.Success
                app.setStatus('条件を満たす候補が見つかりません。制約や探索量を確認してください。'); return;
            end
            names=["X: "+string(app.Bundle.InputNames),"Y: "+string(app.Bundle.OutputNames)];
            app.UI.Candidates.ColumnName=cellstr(names);
            app.UI.Candidates.Data=[log.ParetoParameters,log.ParetoPredictions];
            app.drawPareto;
            app.showCandidate(log.SelectedIndex);
            app.setStatus(sprintf('候補 %d件、予測評価 %d件。選択行と予測制約を確認してください。', ...
                size(log.ParetoParameters,1),log.Evaluations));
        end

        function folder=export(app,parent,name)
            [problem,options]=app.readProblem;
            folder=apcExport(parent,name,app.Bundle,problem,options);
            app.setStatus(['関数・モデル・設定を出力: ',folder]);
        end
    end

    methods (Access=private)
        function buildUI(app,visible)
            app.Figure=uifigure('Name','APC開発アプリ','Position',[80,80,1280,850], ...
                'Visible',visible,'Color',[0.96,0.97,0.98]);
            layout=uigridlayout(app.Figure,[3,1]);
            layout.RowHeight={48,'1x',30}; layout.Padding=[16,10,16,10];
            header=uigridlayout(layout,[1,3]); header.ColumnWidth={'1x',155,155}; header.Padding=[0,0,0,0];
            uilabel(header,'Text','APC  |  モデル開発・多目的最適化','FontSize',22,'FontWeight','bold');
            uibutton(header,'Text','モデルMATを開く','ButtonPushedFcn',@(~,~)app.safe(@()app.openModel));
            uibutton(header,'Text','モデルMATを保存','ButtonPushedFcn',@(~,~)app.safe(@()app.saveModel));
            tabs=uitabgroup(layout); app.UI.Tabs=tabs;
            dataTab=uitab(tabs,'Title','1  Excel・モデル設定');
            validationTab=uitab(tabs,'Title','2  回帰モデルの評価');
            searchTab=uitab(tabs,'Title','3  多目的最適化');
            exportTab=uitab(tabs,'Title','4  MPS向け関数出力');
            app.UI.Status=uilabel(layout,'Text','','FontColor',[0.15,0.25,0.35]);
            app.buildDataTab(dataTab); app.buildValidationTab(validationTab);
            app.buildSearchTab(searchTab); app.buildExportTab(exportTab);
        end

        function buildDataTab(app,tab)
            grid=uigridlayout(tab,[5,1]); grid.RowHeight={34,160,205,80,'1x'};
            top=uigridlayout(grid,[1,5]); top.ColumnWidth={115,100,'1x',65,150}; top.Padding=[0,0,0,0];
            uibutton(top,'Text','Excelを開く','ButtonPushedFcn',@(~,~)app.safe(@()app.chooseExcel));
            uibutton(top,'Text','架空サンプル','ButtonPushedFcn',@(~,~)app.loadExample);
            app.UI.File=uieditfield(top,'text','Editable','off');
            uilabel(top,'Text','シート');
            app.UI.Sheet=uidropdown(top,'Items',{'未選択'},'ValueChangedFcn',@(~,~)app.safe(@()app.changeSheet));
            app.UI.Preview=uitable(grid);
            selection=uigridlayout(grid,[1,3]); selection.ColumnWidth={'1x','1x','1.5x'};
            left=uigridlayout(selection,[2,1]); left.RowHeight={23,'1x'};
            uilabel(left,'Text','説明変数（複数選択可）','FontWeight','bold');
            app.UI.Inputs=uilistbox(left,'Multiselect','on','ValueChangedFcn',@(~,~)app.invalidateTraining);
            middle=uigridlayout(selection,[2,1]); middle.RowHeight={23,'1x'};
            uilabel(middle,'Text','予測する項目（複数選択可）','FontWeight','bold');
            app.UI.Outputs=uilistbox(middle,'Multiselect','on','ValueChangedFcn',@(~,~)app.outputsChanged);
            right=uigridlayout(selection,[2,1]); right.RowHeight={23,'1x'};
            uilabel(right,'Text','項目ごとの回帰モデル','FontWeight','bold');
            app.UI.Methods=uitable(right,'ColumnName',{'予測項目','モデル'}, ...
                'ColumnEditable',[false,true],'ColumnFormat',{[],{'linear','quadratic','ridge','gpr'}}, ...
                'CellEditCallback',@(~,~)app.invalidateTraining);
            controls=uigridlayout(grid,[2,8]);
            controls.ColumnWidth={65,75,55,85,85,85,75,'1x'};
            controls.RowHeight={26,26};
            uilabel(controls,'Text','CV分割'); app.UI.Folds=uieditfield(controls,'numeric','Value',5,'Limits',[2,50],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidateTraining);
            uilabel(controls,'Text','Seed'); app.UI.Seed=uieditfield(controls,'numeric','Value',42,'Limits',[0,2^32-1],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidateTraining);
            uilabel(controls,'Text','Ridge λ'); app.UI.Lambda=uieditfield(controls,'numeric','Value',1,'Limits',[eps,Inf],'ValueChangedFcn',@(~,~)app.invalidateTraining);
            uilabel(controls,'Text','GPR核'); app.UI.Kernel=uidropdown(controls,'Items',{'ardsquaredexponential','squaredexponential','ardmatern32','matern32','ardmatern52','matern52','ardrationalquadratic','rationalquadratic'},'ValueChangedFcn',@(~,~)app.invalidateTraining);
            uilabel(controls,'Text','CVグループ');
            app.UI.Group=uidropdown(controls,'Items',{'(同じ入力条件でまとめる)'},'ValueChangedFcn',@(~,~)app.invalidateTraining);
            app.UI.Group.Layout.Column=[2,6];
            button=uibutton(controls,'Text','モデル作成・評価','ButtonPushedFcn',@(~,~)app.safe(@()app.train));
            button.Layout.Column=[7,8];
            uilabel(grid,'Text',{'Excelは先頭行を列名、1行を1条件とします。欠損値・文字列の列は学習に使えません。', ...
                'linear: 線形 / quadratic: 2次・交互作用 / ridge: 線形＋正則化 / gpr: ガウス過程', ...
                '繰返し条件は同じ検証グループへ割り当てます。ロット単位で分割する場合はCVグループ列を指定します。'},'VerticalAlignment','top');
        end

        function buildValidationTab(app,tab)
            grid=uigridlayout(tab,[3,1]); grid.RowHeight={170,34,'1x'};
            app.UI.Metrics=uitable(grid);
            controls=uigridlayout(grid,[1,4]); controls.ColumnWidth={80,220,170,'1x'}; controls.Padding=[0,0,0,0];
            uilabel(controls,'Text','予測項目');
            app.UI.DiagnosticOutput=uidropdown(controls,'Items',{'未学習'},'ValueChangedFcn',@(~,~)app.drawDiagnostics);
            uibutton(controls,'Text','評価値をCSV保存','ButtonPushedFcn',@(~,~)app.safe(@()app.saveMetrics));
            uilabel(controls,'Text','CVは未学習の行に対する予測。R²<0は平均予測より悪い場合を示します。');
            plots=uigridlayout(grid,[1,2]);
            app.UI.ObservedAxes=uiaxes(plots); app.UI.ResidualAxes=uiaxes(plots);
            title(app.UI.ObservedAxes,'実測と交差検証予測'); title(app.UI.ResidualAxes,'交差検証の残差');
        end

        function buildSearchTab(app,tab)
            grid=uigridlayout(tab,[5,1]); grid.RowHeight={185,65,35,'1x',44};
            definitions=uigridlayout(grid,[1,2]);
            app.UI.Factors=uitable(definitions,'ColumnName',{'入力','下限','上限','現在値','最大変更量','刻み'}, ...
                'ColumnEditable',[false,true,true,true,true,true], ...
                'CellEditCallback',@(~,~)app.clearResult);
            app.UI.Responses=uitable(definitions,'ColumnName',{'予測項目','目的','目標値','尺度','重み','許容下限','許容上限'}, ...
                'ColumnEditable',[false,true,true,true,true,true,true], ...
                'ColumnFormat',{[],{'min','max','target'},'numeric','numeric','numeric','numeric','numeric'}, ...
                'CellEditCallback',@(~,~)app.clearResult);
            controls=uigridlayout(grid,[2,10]); controls.RowHeight={25,25};
            controls.ColumnWidth={60,75,60,75,60,75,80,75,130,'1x'};
            uilabel(controls,'Text','探索数'); app.UI.Population=uieditfield(controls,'numeric','Value',64,'Limits',[8,2000],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.clearResult);
            uilabel(controls,'Text','世代数'); app.UI.Generations=uieditfield(controls,'numeric','Value',25,'Limits',[0,1000],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.clearResult);
            uilabel(controls,'Text','Seed'); app.UI.SearchSeed=uieditfield(controls,'numeric','Value',42,'Limits',[0,2^32-1],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.clearResult);
            uilabel(controls,'Text','上限秒数'); app.UI.MaxSeconds=uieditfield(controls,'numeric','Value',15,'Limits',[0.01,Inf],'ValueChangedFcn',@(~,~)app.clearResult);
            app.UI.Extrapolate=uicheckbox(controls,'Text','外挿を許可','Value',false,'ValueChangedFcn',@(~,~)app.clearResult);
            uibutton(controls,'Text','多目的探索','ButtonPushedFcn',@(~,~)app.safe(@()app.optimize));
            note=uilabel(controls,'Text','固定する入力は下限＝上限、刻み0は連続値。刻みの原点は下限。最大変更量Infは変更量の制限なし。');
            note.Layout.Column=[1,10];
            selectors=uigridlayout(grid,[1,5]); selectors.ColumnWidth={65,190,65,190,'1x'}; selectors.Padding=[0,0,0,0];
            uilabel(selectors,'Text','横軸'); app.UI.ParetoX=uidropdown(selectors,'Items',{'未学習'},'ValueChangedFcn',@(~,~)app.drawPareto);
            uilabel(selectors,'Text','縦軸'); app.UI.ParetoY=uidropdown(selectors,'Items',{'未学習'},'ValueChangedFcn',@(~,~)app.drawPareto);
            uilabel(selectors,'Text','候補表の行を選択すると、その条件と予測値を下に表示します。');
            results=uigridlayout(grid,[1,2]); results.ColumnWidth={'1.2x','1x'};
            app.UI.Candidates=uitable(results,'CellSelectionCallback',@(~,event)app.candidateSelected(event));
            app.UI.ParetoAxes=uiaxes(results);
            app.UI.Selected=uilabel(grid,'Text','モデルを作成して条件を設定してください。','WordWrap','on');
        end

        function buildExportTab(app,tab)
            grid=uigridlayout(tab,[4,1]); grid.RowHeight={120,40,45,'1x'};
            uilabel(grid,'Text',{'MPS向けの入口関数と補助関数、学習済みモデルMAT、設定MAT、呼び出し例を出力します。', ...
                '[parameters, predictions, log] = optimizeAPC(modelFile, problem, options)', ...
                '入口関数は短く保ち、数値処理はprivateフォルダへ分けます。CTF化は別環境で実施してください。', ...
                'log.Success=trueの場合だけ制御へ使用します。候補なし・入力不正・モデル不正は空配列を返します。'},'FontSize',14);
            controls=uigridlayout(grid,[1,4]); controls.ColumnWidth={90,220,230,'1x'}; controls.Padding=[0,0,0,0];
            uilabel(controls,'Text','関数名'); app.UI.FunctionName=uieditfield(controls,'text','Value','optimizeAPC');
            uibutton(controls,'Text','関数一式をフォルダへ出力','ButtonPushedFcn',@(~,~)app.safe(@()app.chooseExport));
            uibutton(controls,'Text','探索ログをMAT保存','ButtonPushedFcn',@(~,~)app.safe(@()app.saveLog));
            uilabel(grid,'Text','数値結果は予測に基づきます。近似Pareto集合であり、大域最適性や実プロセスの改善を保証しません。','WordWrap','on');
            app.UI.Log=uitextarea(grid,'Editable','off','Value',{'探索後のログが表示されます。'});
        end

        function refreshData(app)
            app.invalidateTraining;
            app.UI.Preview.Data=app.Data(1:min(12,height(app.Data)),:);
            names=app.Data.Properties.VariableNames;
            numeric=cellfun(@(name)isnumeric(app.Data.(name)) && size(app.Data.(name),2)==1,names);
            candidates=names(numeric);
            if numel(candidates)<2
                error('APC:Excel','At least two numeric columns are required.');
            end
            app.UI.Inputs.Items=candidates; app.UI.Outputs.Items=candidates;
            outputCount=min(2,numel(candidates)-1);
            app.UI.Inputs.Value=candidates(1:end-outputCount);
            app.UI.Outputs.Value=candidates(end-outputCount+1:end);
            app.UI.Group.Items=[{'(同じ入力条件でまとめる)'},names];
            app.UI.Group.Value='(同じ入力条件でまとめる)';
            app.outputsChanged;
        end

        function outputsChanged(app)
            app.invalidateTraining;
            names=cellstr(string(app.UI.Outputs.Value(:)));
            app.UI.Methods.Data=[names,repmat({'quadratic'},numel(names),1)];
        end

        function invalidateTraining(app)
            app.Bundle=[]; app.Diagnostic=[];
            app.UI.Metrics.Data=[]; app.UI.Factors.Data=[]; app.UI.Responses.Data=[];
            cla(app.UI.ObservedAxes); cla(app.UI.ResidualAxes);
            app.clearResult;
        end

        function clearResult(app)
            app.Result=[]; app.UI.Candidates.Data=[];
            cla(app.UI.ParetoAxes);
            app.UI.Selected.Text='現在の条件で探索を実行してください。';
            app.UI.Log.Value={'現在の設定に対応した探索結果はありません。'};
        end

        function applyBundle(app,bundle)
            apcValidateBundle(bundle); app.Bundle=bundle; app.Diagnostic=[];
            app.clearResult;
            [problem,~]=apcDefaultProblem(bundle);
            app.UI.Factors.Data=[bundle.InputNames(:),num2cell([problem.LowerBounds(:), ...
                problem.UpperBounds(:),problem.CurrentPoint(:),problem.MaxMove(:),problem.Step(:)])];
            baseline=apcPredict(bundle,problem.CurrentPoint);
            scales=max(abs(baseline),1);
            if isfield(bundle,'Metrics'), app.UI.Metrics.Data=bundle.Metrics; end
            app.UI.Responses.Data=[bundle.OutputNames(:),problem.Goals(:), ...
                num2cell([baseline(:),scales(:),problem.Weights(:), ...
                problem.ResponseLower(:),problem.ResponseUpper(:)])];
            outputs=bundle.OutputNames;
            app.UI.DiagnosticOutput.Items=outputs; app.UI.DiagnosticOutput.Value=outputs{1};
            app.UI.ParetoX.Items=outputs; app.UI.ParetoX.Value=outputs{1};
            app.UI.ParetoY.Items=outputs; app.UI.ParetoY.Value=outputs{min(2,numel(outputs))};
        end

        function drawDiagnostics(app)
            if isempty(app.Diagnostic), return; end
            index=find(strcmp(app.UI.DiagnosticOutput.Value,app.Bundle.OutputNames),1);
            observed=app.Diagnostic.Observed(:,index); predicted=app.Diagnostic.Predicted(:,index);
            scatter(app.UI.ObservedAxes,observed,predicted,28,'filled'); hold(app.UI.ObservedAxes,'on');
            limits=[min([observed;predicted]),max([observed;predicted])];
            plot(app.UI.ObservedAxes,limits,limits,'k--'); hold(app.UI.ObservedAxes,'off');
            xlabel(app.UI.ObservedAxes,'実測値'); ylabel(app.UI.ObservedAxes,'CV予測値'); grid(app.UI.ObservedAxes,'on');
            scatter(app.UI.ResidualAxes,predicted,observed-predicted,28,'filled');
            yline(app.UI.ResidualAxes,0,'k--');
            xlabel(app.UI.ResidualAxes,'CV予測値'); ylabel(app.UI.ResidualAxes,'実測 − 予測'); grid(app.UI.ResidualAxes,'on');
        end

        function drawPareto(app)
            if isempty(app.Result) || ~app.Result.Log.Success, return; end
            first=find(strcmp(app.UI.ParetoX.Value,app.Bundle.OutputNames),1);
            second=find(strcmp(app.UI.ParetoY.Value,app.Bundle.OutputNames),1);
            y=app.Result.Log.ParetoPredictions;
            scatter(app.UI.ParetoAxes,y(:,first),y(:,second),32,'filled');
            xlabel(app.UI.ParetoAxes,app.Bundle.OutputNames{first},'Interpreter','none');
            ylabel(app.UI.ParetoAxes,app.Bundle.OutputNames{second},'Interpreter','none');
            title(app.UI.ParetoAxes,'予測値のPareto候補'); grid(app.UI.ParetoAxes,'on');
        end

        function candidateSelected(app,event)
            if isempty(event.Indices) || isempty(app.Result) || ~app.Result.Log.Success, return; end
            app.showCandidate(event.Indices(1,1));
        end

        function showCandidate(app,index)
            values=[app.Result.Log.ParetoParameters(index,:),app.Result.Log.ParetoPredictions(index,:)];
            names=[app.Bundle.InputNames,app.Bundle.OutputNames];
            text=strjoin(compose('%s = %.6g',string(names(:)),values(:)),' / ');
            app.UI.Selected.Text=sprintf('表示候補 %d  |  %s （MPSの自動選択は重みに基づきます）',index,text);
        end

        function chooseExcel(app)
            [name,folder]=uigetfile({'*.xlsx;*.xls','Excel (*.xlsx, *.xls)'});
            if isequal(name,0), return; end
            file=fullfile(folder,name); sheets=sheetnames(file);
            if isempty(sheets), error('APC:Excel','No Excel sheets found.'); end
            app.importWorkbook(file,sheets(1));
            app.UI.Sheet.Items=cellstr(sheets); app.UI.Sheet.Value=char(sheets(1));
        end

        function changeSheet(app)
            if ~isempty(app.Workbook), app.importWorkbook(app.Workbook,app.UI.Sheet.Value); end
        end

        function openModel(app)
            [name,folder]=uigetfile('*.mat','学習済みモデルを開く');
            if isequal(name,0), return; end
            loaded=load(fullfile(folder,name),'modelBundle');
            if ~isfield(loaded,'modelBundle'), error('APC:ModelFile','MATにmodelBundleがありません。'); end
            apcValidateBundle(loaded.modelBundle);
            app.invalidateTraining; app.applyBundle(loaded.modelBundle);
            app.setStatus('学習済みモデルを読込みました。診断の散布図には元の検証データが必要です。');
        end

        function saveModel(app)
            app.requireModel;
            [name,folder]=uiputfile('*.mat','モデルを保存','apc_models.mat');
            if ~isequal(name,0), apcSaveModel(fullfile(folder,name),app.Bundle); app.setStatus('モデルMATを保存しました。'); end
        end

        function saveMetrics(app)
            app.requireModel;
            [name,folder]=uiputfile('*.csv','評価指標を保存','cv_metrics.csv');
            if ~isequal(name,0), writetable(app.Bundle.Metrics,fullfile(folder,name)); end
        end

        function chooseExport(app)
            app.requireModel;
            parent=uigetdir(pwd,'関数の出力先');
            if isequal(parent,0), return; end
            app.export(parent,app.UI.FunctionName.Value);
        end

        function saveLog(app)
            if isempty(app.Result), error('APC:NoResult','探索を先に実行してください。'); end
            [name,folder]=uiputfile('*.mat','探索ログを保存','apc_result.mat');
            if ~isequal(name,0), result=app.Result; save(fullfile(folder,name),'result','-v7'); end
        end

        function requireModel(app)
            if isempty(app.Bundle), error('APC:NoModel','モデルを作成または読み込んでください。'); end
        end

        function setStatus(app,message)
            app.UI.Status.Text=message;
        end

        function safe(app,action)
            app.Figure.Pointer='watch'; cleanup=onCleanup(@()app.restorePointer);
            try
                action();
            catch exception
                app.setStatus(['エラー: ',exception.message]);
                uialert(app.Figure,exception.message,'処理を確認してください');
            end
        end

        function restorePointer(app)
            if isvalid(app.Figure), app.Figure.Pointer='arrow'; end
        end
    end
end
