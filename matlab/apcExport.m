function folder = apcExport(parentFolder, functionName, bundle, problem, options)
%APCEXPORT Export a readable entry point and its static private dependencies.
if ~ischar(functionName) || ~isvarname(functionName) || ...
        ~isempty(which(functionName)) || ~isempty(regexp(functionName,'^apc','once'))
    error('APC:ExportName','Use a new MATLAB function name that does not start with apc.');
end
apcValidateBundle(bundle);
% A validation error must be resolved before a deployment package is written.
probe=options; probe.Generations=0; probe.PopulationSize=8;
[~,~,validation]=apcRuntime(bundle,problem,probe);
if strcmp(validation.Status,'error')
    error('APC:ExportProblem','%s',validation.Message);
end
if ~isfolder(parentFolder), error('APC:ExportFolder','Parent folder does not exist.'); end
stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
folder=fullfile(parentFolder,[functionName,'_',stamp]);
if isfolder(folder), error('APC:ExportFolder','Export folder already exists.'); end
mkdir(folder); mkdir(fullfile(folder,'private'));
entry=readTemplate('apcControl.m');
entry=strrep(entry,'= apcControl(',['= ',functionName,'(']);
writeText(fullfile(folder,[functionName,'.m']),entry);
helpers={'apcRuntime.m','apcPredict.m','apcFeatures.m','apcValidateBundle.m'};
for index=1:numel(helpers)
    writeText(fullfile(folder,'private',helpers{index}),readTemplate(helpers{index}));
end
apcSaveModel(fullfile(folder,'models.mat'),bundle);
save(fullfile(folder,'settings.mat'),'problem','options','-v7');
example=sprintf([ ...
    '%% Run from this export folder in MATLAB before compiling for MPS.\n' ...
    'folder = fileparts(mfilename(''fullpath''));\n' ...
    'addpath(folder);\n' ...
    'settings = load(fullfile(folder,''settings.mat''));\n' ...
    '[parameters, predictions, log] = %s( ...\n' ...
    '    fullfile(folder,''models.mat''), settings.problem, settings.options);\n' ...
    'disp(parameters); disp(predictions); disp(log);\n'],functionName);
writeText(fullfile(folder,'exampleCall.m'),example);
readme=sprintf([ ...
    '# MPS向けAPC関数\n\n' ...
    '入口: `%s.m`。補助処理は `private/` に分離しています。CTF化は別環境で実施してください。\n\n' ...
    '1. `exampleCall` で数値とログを確認します。\n' ...
    '2. MATLAB Compiler SDKのProduction Server Compilerで入口関数を指定します。\n' ...
    '3. private内の4ファイルが依存関数に含まれることを確認します。\n' ...
    '4. models.matはサーバー側に置き、そのローカルパスを第1引数へ渡します。\n' ...
    '5. problemとoptionsはsettings.matの構造体を基に呼出側から渡します。\n\n' ...
    'log.Success=trueの場合だけparametersを制御へ使用してください。失敗時は出力が空です。\n' ...
    'log.ParetoParameters/Predictions/Lossesは候補集合です。最適解の保証はありません。\n' ...
    'log.Historyの列は世代、予測評価件数、候補数、最小制約違反です。\n' ...
    'MaxSecondsは世代境界で判定するため、厳密な応答期限を保証しません。\n' ...
    '学習したリリースに対応したRuntimeで検証し、特にGPRのMAT互換性を確認してください。\n'],functionName);
writeText(fullfile(folder,'README.md'),readme);
end

function content=readTemplate(name)
if isdeployed
    file=fullfile(ctfroot,'export_templates',[name,'.txt']);
else
    file=fullfile(fileparts(mfilename('fullpath')),name);
end
content=fileread(file);
end

function writeText(file,content)
[handle,message]=fopen(file,'w','n','UTF-8');
if handle<0, error('APC:ExportWrite','%s',message); end
cleanup=onCleanup(@()fclose(handle));
fprintf(handle,'%s',content);
end
