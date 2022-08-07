---
title: "ソフトウェアライセンスチェックツール hatto をつくった"
emoji: "🙅"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["license", "SBOM"]
published: true
---

[heriet/hatto](https://github.com/heriet/hatto) というソフトウェアライセンスの評価を行うCLIツールをつくったので、その紹介です。

## はじめに

近年、ソフトウェアサプライチェーンの議論が活発になっています。ソフトウェアサプライチェーンの話のひとつに、ソフトウェアライセンスのコンプライアンスチェックがあります。ソフトウェアの進化とともに、より多様なライセンスが生まれ、より複雑なソフトウェア依存関係を伴うようになってきました。1つのソフトウェアが依存するソフトウェアは、依存関係を深堀りすると数百を超えることも珍しくありません。

今や、多くの企業がソフトウェアを取り扱うようになりました。そのような何らかのソフトウェアを取り扱う組織にとって、ソフトウェアライセンスのコンプライアンスチェックは、無視できない課題です。近年、ソフトウェアを取り扱ううえで、SBOMの重要性も説かれるようになってきました。最近はSBOMを取り扱えるソフトウェアもどんどん増えてきています。

SBOMやソフトウェアコンプライアンス機能を持つ商用ツールも既に複数あります。また、OSSでも [oss-review-toolkit/ort](https://github.com/oss-review-toolkit/ort) や[pivotal/LicenseFinder](https://github.com/pivotal/LicenseFinder) あたりは特に高機能でCIでも使いやすく、様々な言語やパッケージマネージャーに対応しています。また、特定のパッケージマネージャーに特化した [EmbarkStudios/cargo-deny](https://github.com/EmbarkStudios/cargo-deny) や [google/go-licenses](https://github.com/google/go-licenses) などのツールもあります。これら既存のツールを組み合わせることで、CIでライセンスチェックすることは現状も可能です。

今回、 [heriet/hatto](https://github.com/heriet/hatto) を作ったのは、複数のチーム間で共通化したライセンスポリシーチェックをより簡単かつ柔軟に行いたいという思いがあります。いまどきは1つの組織のなかで開発するソフトウェアやプロジェクトは大量にあり、利用する言語も複数存在することも多くなりました。各プロジェクトごとにライセンスチェックを行っている場合もあるでしょう。

しかし、近年は前述のソフトウェアサプライチェーンの議論が活発になるにつれて、組織全体の横串で同じポリシーのライセンスチェックを求められることも増えてきたのではないかとおもいます。実際、ソフトウェアライセンスの問題は深堀りするとたいへん難しい問題で、組織の法務部門や品質管理部門のような専門家の考えを反映する必要性が出てきます。すべての開発者が著作権法や特許法を始めとする知財の知識を身につけるのが理想ですが、現実的には難しいでしょう。多くの場合、ソフトウェア開発者はソフトウェア開発の専門家であり、法律の専門家ではありません。そのため、法律の専門家のレビューを受けた組織のライセンスコンプライアンスチェックが必要になってきます。ただ、近年のソフトウェアの開発は固有の専門的な知識が必要で、法律の専門家にとって各ソフトウェア開発プロジェクトの多様な事情を汲み取ることも難しいのが実情です。

そのような情勢の中で、[heriet/hatto](https://github.com/heriet/hatto)は法律の専門知識を保有しライセンスコンプライアンスの責任者が定めるポリシーと、各ソフトウェア開発上の事情を汲み取り、協力してソフトウェアライセンスのコンプライアンスチェックができるようになることを目指しています。

現時点で [oss-review-toolkit/ort](https://github.com/oss-review-toolkit/ort) がその理想に近い位置にあると思いますが、ortは高機能ゆえに重いツールという側面もあります。[heriet/hatto](https://github.com/heriet/hatto)は柔軟性と取り扱いやすさ持ちつつ、ソフトウェアライセンスのコンプライアンスポリシー評価に特化し、各プロジェクトのCIに組み込みやすい軽いソフトウェアとなるように設計しました。

## 使い方

いろいろ書きましたが、hattoの仕組みそのものは単純で、SBOMまたはtsvでソフトウェアのライセンス情報を入力して、Pythonで記述したポリシー評価スクリプトを流すだけです。また、ライセンス情報をプロジェクト担当者の都合で補正する機能も備えています。

ライセンス情報の収集はhattoではない別のツールの責務として、任意の方法で生成してもらう前提です。入力のSBOMとしてSPDXまたはCycloneDXに対応しています。ライセンス情報を収集可能なツールも多数あり、近年のツールであればSBOM生成に対応しているはずです。ただ、ライセンス情報を収集できるツールすべてがSBOMの生成に対応していないのが現状で、SBOMの代わりにtsvでも入力できるようにしています。

たとえば、あるプロジェクトがfooとbarという2つのソフトウェアに依存していたとして、何らかの方法で下記のようなtsvを生成してもらいます。

```tsv:example.tsv
name	version	licenses	annotations
foo	1.0.1	MIT,Apache-2.0	usage=service
bar	1.1.2	UNKNOWN	
```

たとえば、LicenseFinderは上記に相当する情報をjson出力可能なので、jsonをjqなどで加工して上記のtsvの生成は簡単にできます。SPDXまたはCycloneDXで生成した場合でも、上記に相当する情報を抽出するようにしています。

次に、ポリシーを定義するための `policy.py` を用意します。ファイル名は何でもよいですが、Pythonで `def evaluate(material, result)` を実装する必要があります。

```python:policy.py
#!/usr/bin/python

allowed_licenses = [
    "Apache-2.0",
    "BSD-3-Clause",
    "MIT",
    "Unlicense",
]

def evaluate(material, result):
    for license in material.licenses:
        if license not in allowed_licenses:
           result.add_error(f"{license} is not allowed")
```

1つの依存関係（tsvの1行分）ごとにevaluateが実行されます。material引数にtsvで定義した情報が入っているので、policy.py内でライセンスコンプライアンス評価をします。評価上なにか問題があるときは、 `result.add_error` を呼ぶようにするだけです。上記のスクリプトであれば、 `Apache-2.0` `BSD-3-Clause` `MIT` `Unlicense` のみを許容します。

tsv（またはSBOM）とpolicy.pyを用意できたら、下記でhattoを実行します。

```sh
$ hatto evaluate --policy policy.py example.tsv
OK foo 1.0.1 licenses:["MIT", "Apache-2.0"] annotations:{"usage": "service"}
NG bar 1.1.2 licenses:["UNKNOWN"] annotations:{}
  ERROR UNKNOWN is not allowed
Failure: evaluate failed
```

barの情報としてライセンスが `UNKNOWN` になっており、これは `policy.py` で許容していないので、評価エラーとなります。

ちかごろのライセンス情報収集ツールはよくできているのですが、原理的にどうしてもライセンスを正しく判別できないことも稀にあります。プロジェクト担当者が詳しく調べてみると、barのライセンスは 三条項BSDライセンス（`BSD-3-Clause`） であることがわかったとします。入力ファイルを直接補正してもよいのですが、補正するための手段をhattoはcurationとして用意しています。

補正を行うために、下記のような `curation.py` を用意します。ファイル名は何でも良いですが、 `def curate_material(material)` をPythonで実装する必要があります。

```python:curation.py
#!/usr/bin/python

def curate_material(material):
    if material.name == "bar":
      material.licenses = ["BSD-3-Clause"]
```

上記のスクリプトにより、barのライセンスを `BSD-3-Clause` に補正しています。hattoの実行は下記のようになります。

```sh
$ hatto evaluate --policy policy.py --curation curation.py example.tsv
OK foo 1.0.1 licenses:["MIT", "Apache-2.0"] annotations:{"usage": "service"}
OK bar 1.1.2 licenses:["BSD-3-Clause"] annotations:{}
```

`curation.py` によってライセンス情報の補正が行われ、ポリシー評価がすべて成功するようになりました。

ライセンス評価ポリシーを定める `policy.py` は組織のライセンスコンプライアンス責任者のもとで作成し、 `curation.py` は各プロジェクト担当者がプロジェクトで依存するパッケージの事情を踏まえて作成されることを想定しています。

各スクリプトはただのPythonスクリプトなので、柔軟なポリシー設計や補正処理が行えます。必要であれば任意のPythonライブラリも使えますし、作ったスクリプトもPythonの流儀でテストもできます。

また、annotationを設定して、柔軟な評価ポリシーの実現も可能です。たとえば、なにかやむを得ない事情でライセンス評価は無視したいパッケージもあるかもしれません。

たとえば、下記のような `policy.py` を用意します。

```python:policy.py
def evaluate(material, result):
    if "ignore" in material.annotations:
        return

    # your policy check
```

上記によって、tsvやcuration.pyで `ignore` annotationが付与されている場合は、無視するような評価ができます。annotationは任意のkey/value文字列が設定できます。設定されたannotationをどう評価するかは `policy.py` 作成側に委ねられているので、組織の中で `policy.py` 作成側がannotationの仕様を定め、ドキュメントをプロジェクト担当者側に共有する必要があるでしょう。

これらを組み合わせれば、たとえば `AGPL-3.0` なソフトウェアをWebサービスで利用しているプロダクトで、ライセンスに従って正しくソース配布がなされているか、といったチェックも可能です。どのようなルールでチェックするのがよいかは、組織やプロダクトの性質によっても異なるので、hattoとしてはどのようなannotationを設定するべきかはあえて定めていません。法務上の事情が関わるライセンスコンプライアンス評価なので、各組織ごとにルールを決める必要があります。

上記で説明したとおり、hatto自体は簡単なPythonスクリプトを流す薄いCLIツールですが、組織の事情にあわせた柔軟なソフトウェアライセンスコンプライアンスのチェックを効率化できると考えています。

より細かい仕様などは [The hatto User Guide](https://heriet.github.io/hatto/) に書いたので、そちらを参照ください。

## 開発で検討したことメモ

以下はメモなので読み飛ばしてもらって良いです。

### なぜPythonスクリプトを採用したか

最初はyamlかtomlあたりでポリシーを定義して評価できるようなツールを考えたのですが、yamlなどの宣言的な記述では、ソフトウェアライセンス評価においては不十分という結論に至りました。ソフトウェアライセンスのルールは多様で、さらにそれを正しく準拠しているか評価するのはきめ細やかな制御が必要です。ライセンス条文は自然言語で記述されており、またこれを取り扱うのは法務上の見解を照らし合わせながら評価する必要があり、単純な宣言的定義では困難だと考えています。

あと、ポリシー評価言語として設計された [Rego](https://www.openpolicyagent.org/docs/latest/policy-language/)とか、独自DSLの実装なんかも面白いかなとはおもうのですが、いまの気分的にCLIそのものはRustで実装したかったこと、[PyO3/pyo3](https://github.com/PyO3/pyo3) というRustとPython連携ができる楽しいcrateがあったこと、Pythonであればソフトウェアの専門家ではない法務や品質管理部門でも読み書きしやすいのではないかというところを考慮して、今回はPython前提で実装しました。今回は採用しませんでしたが、同じようなことをRegoや独自DSLで実装するのもたぶん楽しいのではないかとおもいます。

### CLIもRustじゃなくてPythonで実装したほうがいいのでは？

それはそう。たぶん同じ仕様でPythonで書いたほうが早かったと思う。でもRustで作りたかったんや。誰か作りたかったらつくっていいよ。

### このぐらいならそもそも短いPythonスクリプト1個書けばいいのでは？

それもそうかもしれない。SBOMをパースして処理呼ぶだけだからね。そういうのつくってもいいと思うよ。

### project全体のレベルでcurationしたい気もした

評価対象のソフトウェアをprojectととらえ、project全体でannotationを持ったりcurationしたりは最初の頃はできるような設計にしていた（ `def curate_project` みたいなのを用意しようとおもった）のですが、最終的には消しました。プロジェクト全体のレベルでannotationつけたければ、 `project-` で始まるannotationを全部のmaterialにつけるポリシーにしてもらうでも実用上回るかなと思った感じです。hatto上でprojectの概念を導入するよりももっと仕様を薄くシンプルにしたかった感じです。

`curate_project` がないので、たとえばmaterialが不足していたら追加するとかもできないんですが、まあそれは入力側で頑張ってもらえばいいかなとも思っています。

### Permissive License以外があったらエラーにするぐらいでもいいのでは？

おそらく世の中のほとんどのソフトウェアはPermissive Licenseで99.99%は構成されているとおもう（要出典）ので、それだけCIでチェックしてエラーになった00.01%を目視でチェックするぐらいでも運用は回るんじゃないかと思います。hattoでもそういうポリシー設計にできますし、Rustであればcargo-denyあたりで簡単にチェックできます。

ただ、あなたの組織またはプロダクトがそう判断するかはわからないですし、将来の様々な未知のライセンスが生まれることも想定して、より柔軟なポリシー評価できる手段があるのも良いかなと思いました。

## おわりに

[heriet/hatto](https://github.com/heriet/hatto)の使い方と開発上で考えたことを整理して書きました。簡単なCLIツールなので、みなさんの組織でソフトウェアライセンスコンプライアンスの議論が出たときに、容易にCIに組み込むことが可能かとおもいます。もし皆さんの組織事情に合うようでしたら活用いただけると幸いです。

