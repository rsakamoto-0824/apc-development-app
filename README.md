# APC開発アプリ

Excelのデータから複数の回帰モデルを作り、予測に基づく多目的最適化を評価するローカルアプリです。MATLAB R2021b以降を対象としています。

- Excelのシート、説明変数、予測項目を選択。
- 項目ごとに線形・2次多項式・リッジ回帰・GPRを選択。
- 交差検証のRMSE、MAE、R²、バイアス、実測対予測・残差を表示。
- 学習済みモデルをMATへ保存・再読込。
- 予測項目ごとの最小化・最大化・目標合わせ、入力上下限・刻み・変更量、予測上下限を設定。
- Pareto候補とその予測値を比較。
- MPS用の短い入口関数、補助関数、モデルMAT、設定例を出力。

アプリ内でCTF化はしません。Windows配布用のビルドスクリプトを含みます。この端末にはMATLAB Compilerがないため、exeのビルドとRuntimeでの動作確認は未実施です。

## 起動

MATLABで `matlab` フォルダを開きます。

```matlab
addpath(pwd)
app = launchAPC;
```

MATLABとStatistics and Machine Learning Toolboxを使用します。GPR以外の回帰・多目的探索はMATLABのみで動きます。Optimization Toolbox、Global Optimization Toolbox、ネット接続、APIキー、環境変数は不要です。

## 基本操作

1. 「1 Excel・モデル設定」でExcelを開き、シートを選びます。
2. 説明変数と予測項目を複数選択します。同じ列を両方に含めないでください。
3. 予測項目ごとに回帰モデルを選び、「モデル作成・評価」を押します。
4. 「2 回帰モデルの評価」でCV誤差と残差を確認します。
5. 「3 多目的最適化」で入力の範囲、現在値、各応答の目的・尺度・制約を設定します。
6. 「多目的探索」を押し、表の行を選んで条件と予測値を比較します。
7. モデルをMATに保存します。「4 MPS向け関数出力」で関数一式を出力します。

起動時は100行の架空サンプルを表示します。サンプルの式・値・範囲はソフトウェア確認用であり、製造プロセスの推奨条件ではありません。

`createReviewArtifacts` を実行すると、`examples/APC_sample.xlsx`、画面確認画像、サンプル関数出力を再作成できます。

## Excelの形式

`.xlsx` / `.xls` の先頭行を列名、1行を1つの測定条件とします。列数・列名は固定しません。日本語の列名も保持します。学習に指定する列は有限の実数にしてください。空欄や文字列を自動補完・削除しません。1セルに配列を入れる形式、カテゴリ説明変数、時系列の自動補正は対象外です。

|Temperature|Pressure|Flow|Thickness|Uniformity|
|---:|---:|---:|---:|---:|
|400|3.0|100|100.2|1.4|
|390|2.5|95|98.7|1.2|

この2行だけではモデルを学習できません。2次多項式は入力数pに対して `1 + 2p + p(p-1)/2` 項を使います。交差検証の各学習部分で、項数より多い行数と独立した条件が必要です。ランク不足を自動的な正則化で隠しません。

通常は同じ入力条件の行をまとめてCV分割します。ロットなどの列を「CVグループ」に指定すると、その単位で分割します。これはランダムなグループ分割であり、時間順の将来予測評価ではありません。平均・標準偏差は各CV学習部分だけで求めます。CVを使って方式や設定を選んだ場合は、別のデータで最終確認してください。

## 回帰モデル

|名前|内容|
|---|---|
|linear|切片と全説明変数の主効果|
|quadratic|linear＋二乗項＋2因子交互作用|
|ridge|線形回帰にL2正則化。切片には罰則なし。λを画面で設定|
|gpr|ガウス過程回帰。二乗指数・Matérn 3/2・Matérn 5/2・有理二次と各ARD版|

全モデルで同じ説明変数を使い、予測項目ごとに方式を変更できます。GPRのハイパーパラメータは学習部分のデータから推定します。CV_R2は定数応答でNaNです。モデルMATは係数またはCompactRegressionGP、前処理、学習範囲、指標、設定を保存します。元の入力テーブルやCV予測行を別変数として保存しませんが、GPRには予測に必要な学習点が含まれます。モデルMATは学習データと同じ範囲で管理し、信頼できる出所のファイルを使用してください。

## 最適化と選択

入力下限・上限と `現在値 ± 最大変更量` の共通範囲で探索します。刻み0は連続値、正の刻みは入力下限を原点とする格子です。整数条件は下限を整数・刻みを1にします。固定入力は下限＝上限にします。既定では学習データの列ごとの最小〜最大の外へ出る条件を拒否します。この範囲内でも疎な領域では予測が不確かになります。

応答の損失を次で定義し、全損失を最小化方向に揃えます。

```text
min:    (予測値 − 目標値) / 尺度
max:    (目標値 − 予測値) / 尺度
target: abs(予測値 − 目標値) / 尺度
```

min/maxの目標値は損失の原点であり、最適候補の優越関係に影響しません。尺度は正数です。応答の許容下限・上限は予測平均に適用します。許容誤差は尺度で正規化して既定 `1e-8`。予測区間や実測値に対する保証ではありません。

一様乱数による全体探索と、候補周辺の局所探索を繰り返し、実行可能な非劣候補を保持します。候補上限は既定300で、混雑距離を使って分布と端点を残します。近似Pareto探索であり、最適解・全候補の網羅は保証しません。「候補なし」は実行不可能の数学的証明ではありません。

自動選択は、探索後の候補内で損失を0〜1に正規化し、理想点までの距離の二乗を重み付けして最小の1行を返します。重みはすべて正数です。重みはPareto集合の探索には使いません。画面で選択した行は比較表示用であり、MPSでの自動選択はこの規則に従います。

Seedと探索量を固定すると同じ候補を再現できます。ただし上限時間に達して途中終了した場合は、環境の速度によって到達世代が変わります。時間は世代境界で確認するため、厳密な実行期限ではありません。各要求に専用の乱数ストリームを使用し、呼出側の乱数状態を変えません。

## MPS向けの出力

出力フォルダは毎回新規作成します。

```text
optimizeAPC_日時/
  optimizeAPC.m       短い入口関数
  private/           予測・入力検査・探索の4つの補助関数
  models.mat         modelBundle
  settings.mat       problem, options
  exampleCall.m      MATLABからの呼び出し例
  README.md
```

出力したフォルダで `exampleCall` を実行すると、アプリと同じ処理を検証できます。入口は短く保ち、補助関数の依存を静的に解決できる構成です。学習処理と画面は依存に含みません。

```matlab
settings = load('settings.mat');
[parameters, predictions, log] = optimizeAPC( ...
    'models.mat', settings.problem, settings.options);
if log.Success
    disp(parameters)
    disp(predictions)
else
    disp(log.Message)
end
```

`modelFile` はMPSサーバー内のMATファイルのパスです。クライアントPCのパスではありません。`models.mat` の差替え時は、モデルID、列順、学習範囲、MATLABリリースを確認してください。モデルは呼び出しごとに読み込み、永続キャッシュは使用しません。GPRのシリアライズ互換性を含め、学習・CTF作成・Runtimeは同じリリースで検証してください。

MATLAB Compiler SDKを使う別の環境で、入口関数をMPS用CTFへコンパイルしてください。`private/` 内の補助関数が依存として含まれていること、サーバーからモデルを読めること、MPSの数値配列・構造体の受渡しを実システムで確認してください。アプリからMPSへの接続や制御指令の送信は行いません。

### 引数・返却値

|引数|内容|
|---|---|
|problem.InputNames / OutputNames|モデルと一致する名前・列順|
|LowerBounds / UpperBounds / CurrentPoint|入力ごとの範囲・現在値|
|MaxMove / Step|入力ごとの最大変更量（Inf可）・刻み（0は連続）|
|Goals / Targets / Scales / Weights|応答ごとの目的・目標値・尺度・選択重み|
|ResponseLower / ResponseUpper|応答ごとの予測上下限（無制限は±Inf）|
|options|PopulationSize、Generations、Seed、MaxSeconds、Tolerance、AllowExtrapolation、ArchiveLimit|
|parameters|InputNames順の数値1行。失敗時は空配列|
|predictions|OutputNames順の数値1行。失敗時は空配列|
|log|成否、理由、モデルID、条件、探索履歴、Pareto候補と予測値、選択番号|

JSONでInfを直接送れない接続方式では、構造体の無制限値を運用上の十分な有限値へ置き換えてください。MPSの使用APIに合わせた変換は呼出側で行います。

`log.Success` がtrueのときだけ制御に使います。入力不正、ファイル不正、候補なしでは空配列です。`log.History` の列は世代番号・累積予測評価件数・保持候補数・発見した最小制約違反。`log.ParetoParameters / ParetoPredictions / ParetoLosses` に候補集合、`log.BaselinePredictions` に現在値の予測を保存します。ログの時間や件数は実行時に算出します。

## Windowsスタンドアローン版

WindowsのMATLAB R2021b以降で、MATLAB CompilerとStatistics and Machine Learning Toolboxを利用して実行します。

```matlab
addpath(pwd)
result = buildStandalone;
```

`build/windows` に生成します。配布先へ、ビルドしたMATLABリリースに対応するMATLAB Runtimeをインストールしてください。開発用MATLABを入れずに使用できます。MacからWindowsのexeを生成する方式ではありません。

ビルド時に出力用のソースを `.txt` 資産として同梱します。配布後も読みやすい `.m` を書き出せるようにするためです。Windows上で、Excel読込・GPR学習・モデル保存・ソース出力・出力関数再実行まで確認してください。

## 検証

```matlab
runTests
```

検証状況は `verification.md`、残課題は `issues.md` を参照してください。

## 公式仕様

- [MATLAB Compilerのスタンドアローンアプリ](https://www.mathworks.com/help/compiler/standalone-applications.html)
- [MPS用アーカイブの作成](https://www.mathworks.com/help/compiler_sdk/mps_dev_test/compiler.build.productionserverarchive.html)
- [MATLAB Compilerの制約](https://www.mathworks.com/help/compiler/limitations-about-what-may-be-compiled.html)
- [GPRモデル](https://www.mathworks.com/help/stats/regressiongp.html)
