---
title: "trivy+conftestで柔軟にライセンスポリシーをチェックする"
emoji: "🐦"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["license", "SBOM", "trivy", "conftest"]
published: true
---

本記事は[富士通クラウドテクノロジーズ Advent Calendar 2022](https://qiita.com/advent-calendar/2022/fjct)の6日目の記事です。昨日は `@sameshima_alt` の[ITエンジニアっぽい手法で作曲を自動化してみた](https://sameshima-fjct.hatenablog.com/entry/2022/12/05/ai_trackmaking) でした。テキストベースの音楽シーケンサ自体は昔からありますが、今は音楽も自動生成できる時代なので、シーケンサ用テキストを自動生成してくれるみたいなものも出てきたら面白いかもしれませんね。

## はじめに

少し前に [ソフトウェアライセンスチェックツール hatto をつくった
](https://zenn.dev/heriet/articles/hatto-license-policy-check-tool) という記事を書いていて、このツールは今も活用しています。hattoはSBOMに対してpythonスクリプトを書いてポリシーチェックできるツールでした。いったんこのとき作った[hatto](https://github.com/heriet/hatto)で直近の課題は解決できているのですが、さらによりよい方法はあるだろうなと考えています。2022年はSBOM関連の処理ができるツールがかなり増えましたし、ソフトウェアサプライチェーンへの注目も拡大しているので、まだその勢いは止まらないでしょう。

今回は、[trivy](https://github.com/aquasecurity/trivy) でSBOMを出力し、[conftest](https://github.com/open-policy-agent/conftest)でそのSBOMをチェックすることを考えてみます。

## trivyでライセンスポリシーチェック

[trivy](https://github.com/aquasecurity/trivy) はソフトウェアのセキュリティに関する問題を検出するツールです。脆弱性のスキャンだけではなく、設定ファイルのミスや機密情報の埋め込み、ソフトウェアライセンスのチェックなどさまざまな機能を持っています。最近はとても開発が活発で、新しい機能もどしどし追加されています。また、trivyを内部的に利用して同様の機能を実現するソフトウェアも増えているようです。

ライセンスチェックの機能が入ったのも今年で、[v0.30 (2022/7/15)](https://github.com/aquasecurity/trivy/releases/tag/v0.30.0)にて実装されています。trivy単体でも一定のライセンスポリシーチェックは実現可能です。

公式ドキュメントに同様の説明がありますが、trivyで `alpine:3.15` に対してライセンスポリシーチェックをかけると下記のようになります。

```sh
$ trivy image --security-checks license --severity HIGH alpine:3.15
2022-12-04T14:16:50.229Z        INFO    License scanning is enabled

OS Packages (license)
=====================
Total: 6 (HIGH: 6, CRITICAL: 0)

┌───────────────────┬─────────┬────────────────┬──────────┐
│      Package      │ License │ Classification │ Severity │
├───────────────────┼─────────┼────────────────┼──────────┤
│ alpine-baselayout │ GPL-2.0 │ restricted     │ HIGH     │
├───────────────────┤         │                │          │
│ apk-tools         │         │                │          │
├───────────────────┤         │                │          │
│ busybox           │         │                │          │
├───────────────────┤         │                │          │
│ musl-utils        │         │                │          │
├───────────────────┤         │                │          │
│ scanelf           │         │                │          │
├───────────────────┤         │                │          │
│ ssl_client        │         │                │          │
└───────────────────┴─────────┴────────────────┴──────────┘
```

trivyのデフォルトの動作として、[Google License Classification](https://opensource.google/documentation/reference/thirdparty/licenses)にある分類に従ってチェックが行われます。 `alpine:3.15` には `GPL-2.0` のパッケージが含まれており、これはGoogle License Classificationにおいてrestrictedの扱いになります。GPL-2.0のソフトウェアを利用し頒布する場合、ソフトウェアのソースコード公開が必要となり、ビジネスによってはこれは問題になることがあります。ソースコード公開を避けたい場合、GPL-2.0のソフトウェアを利用していないことのチェックが必要であり、trivyでもチェックができるということです。

trivy実行時のオプションに `--ignored-licenses` で特定のライセンスは無視したり、 `trivy.yaml` で独自のClassificationを定義することも可能です。

```sh
$ trivy image --security-checks license --ignored-licenses GPL-2.0 --severity HIGH alpine:3.15
2022-12-04T14:31:11.422Z        INFO    License scanning is enabled
# 結果なし
```

```sh
$ cat trivy.yaml
severity:
  - HIGH
scan:
  security-checks:
    - license
license:
  restricted:
    - MIT

$ trivy image alpine:3.15
2022-12-04T14:35:04.118Z        INFO    Loaded trivy.yaml
2022-12-04T14:35:04.127Z        INFO    License scanning is enabled

OS Packages (license)
=====================
Total: 2 (HIGH: 2)

┌────────────────────────┬─────────┬────────────────┬──────────┐
│        Package         │ License │ Classification │ Severity │
├────────────────────────┼─────────┼────────────────┼──────────┤
│ ca-certificates-bundle │ MIT     │ restricted     │ HIGH     │
├────────────────────────┤         │                │          │
│ musl                   │         │                │          │
└────────────────────────┴─────────┴────────────────┴──────────┘
```

上記を活用することで、ほとんど多くのケースでは、trivyによるライセンスポリシーチェックで十分かもしれません。ただ、みなさんが所属する組織によっては、より複雑なライセンスチェックの仕組みが必要かもしれません。組織やプロダクトの性質によって、 `GPL-2.0` が問題になるケースもあればならない場合もあります。プロジェクトごとに法務的な観点で利用可能なライセンス一覧や無視可能なライセンスを洗い出すのは現実的ではないかもしれません。

また、trivyではいまのところライセンスポリシーチェックとSBOMの生成は分離不可のようです（v0.35時点では、SBOMに対しては脆弱性スキャンのみが可能）。できれば、SBOMの生成と、SBOMに対するライセンスポリシーチェックは別で行いたいです。trivyは多くのパッケージマネージャーに対応してくれてはいますが、trivyでは対応しない言語が今後あるかもしれません。その場合、SBOMの生成は別ツールで行う必要がありますが、ライセンスポリシーチェックの処理は組織全体でなるべく共通の物を使いたいはずです。チェックの処理がtrivyに依存しているとライセンスポリシーチェックができなくなってしまいます。

## trivy+conftestでライセンスポリシーチェック

trivy単体ではライセンスポリシーチェックできないケースを想定して、trivyではSBOM生成までを行い、別のツールでライセンスポリシーチェックすることを考えてみます。もちろんhattoを使ってもいいのですが、今回は[conftest](https://github.com/open-policy-agent/conftest)を使うことを考えます。

conftestは様々な構造化データに対してポリシー記述言語である[Rego](https://www.openpolicyagent.org/docs/latest/policy-language/)で柔軟なチェックが行えるツールです。Rego言語でデータチェックするという観点では[opa](https://www.openpolicyagent.org/docs/latest/cli/)を使ってもいいのですが、conftestは特定のフォーマットに対するパーサーが実装されていて、対応しているフォーマットであればopaよりも使いやすいでしょう。conftestはSBOMの主流フォーマットであるCycloneDXやSPDXに対応しています。

### 簡単なポリシー

まずはtrivyでSBOM出力のみしておきます。今回はCycloneDXで出力します。

```sh
$ trivy image --format cyclonedx --output alpine.cdx alpine:3.15

$ head -n 3 alpine.cdx
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
```

この出力された `alpine.cdx` にたいしてconftestでライセンスポリシーチェックしてみましょう。

conftestはデフォルトではpolicyディレクトリ配下のRegoファイルを見るようになっています。まずconftestの動作を確認するために、簡単なポリシーを書いてみます。

```sh
$ mkdir policy
$ vim policy/bom_format.rego
```

```rego:policy/bom_format.rego
package main

deny[msg] {
	input.bomFormat != "CycloneDX"
    msg = "bomFormat must be set CycloneDX"
}
```

上記は、CycloneDXの必須要素であるbomFormatが `CycloneDX` ではないとき、ポリシー違反とするものです。上記を用意して、conftestを流してみます。

```sh
$ conftest test --parser cyclonedx alpine.cdx

1 test, 1 passed, 0 warnings, 0 failures, 0 exceptions
```

conftestによるポリシーチェックが成功していることがわかります。

エラーになったときも確認してみましょう。

```sh
$ sed -e "s/CycloneDX/CycloneDXX/g" alpine.cdx > invalid_alpine.cdx

$ conftest test --parser cyclonedx invalid_alpine.cdx
FAIL - invalid_alpine.cdx - main - bomFormat must be set CycloneDX

1 test, 0 passed, 0 warnings, 1 failure, 0 exceptions
```

想定通り、 `bomFormat must be set CycloneDX` というメッセージが出力され、ポリシーチェックに失敗することがわかります。regoで自組織のポリシーを表現すれば、conftestでポリシーチェックできそうなことがわかりますね。

### CycloneDXのパースモジュールを作る

さて、regoでかけばポリシーは実現できそうということはわかりました。さらに具体的に考えてみましょう。

[CycloneDXの仕様](https://cyclonedx.org/docs/1.4/json/)をみていただくとわかるのですが、ライセンスの情報を埋め込めるフィールドはたくさんあります。問題の単純化のため、今回は[components.licenses](https://cyclonedx.org/docs/1.4/json/#components_items_licenses) のみをチェックすることを考えます。CycloneDXを出力する側の問題で、licenses以下にどのように値が入ってくるかは未知です。`license.id` にきっちりSPDX identifierが入っているかもしれませんし、`expression` に `Apache-2.0 AND (MIT OR GPL-2.0-only)` のような文字列が入っているかもしれません。世の中にはSPDX identifierがふられていない未知のライセンスも存在するので、 `license.name` にライセンスを同定する情報が入っている場合もありえます。

う、うーん。なんか急にややこしくなってきたな？~~現状のSBOMって情報出すところだけ頑張ってて、読み取って処理する側の苦労をまだフォローできてない感じがあるよね~~。まあ一旦頑張ってみましょう。要はやりたいことは下記です。

- それぞれのポリシーとして何らかの判定したいライセンスの一覧がある
- `components.licenses` 以下にある情報でライセンスの一覧と合致するものがあったとき、特定のルールに従ってポリシーチェックをする
- `components.licenses` 以下にある情報でライセンスの一覧と合致するものは下記の条件
    - `license.id` に完全一致する
    - `license.name` に部分一致する
    - `expression` に部分一致する

たとえば、redis系っぽいライセンス（SPDX identifierには規定されていないライセンス）があったら `license.name` に redisっていうキーワードが入ってないかチェックしたりとか、 `Apache-2.0 AND GPL-2.0-only` という　`expression` になっていたら `GPL-2.0-only` でチェックしてくれたりするとかそういうのをしたいわけですね。もちろん皆さんの組織のポリシーによってもっと別のケースもあるかもしれませんが。

複数あるであろうポリシーで上記の判定を個別に記述するのは冗長なので、モジュール化することを考えます。

```rego:policy/cyclonedx.rego
package cyclonedx

find_components_contains_licenses(components, licenses) := x {
    x := [components[c] | contains_licenses(components[c], licenses)]
}

# contains_license returns true if has_license_id OR contains_license_name OR contains_expression
contains_licenses(components, licenses) {
    equals_licenses_id(components, licenses)
}

contains_licenses(components, licenses) {
    contains_licenses_name(components, licenses)
}

contains_licenses(components, licenses) {
    contains_licenses_expression(components, licenses)
}


equals_licenses_id(components, licenses) {
    c := [ x | equals_license_id(components, licenses[x])]
    count(c) > 0
}

contains_licenses_name(components, licenses) {
    c := [ x | contains_license_name(components, licenses[x])]
    count(c) > 0
}

contains_licenses_expression(components, licenses) {
    c := [ x | contains_license_expression(components, licenses[x])]
    count(c) > 0
}


equals_license_id(components, license) {
    components.licenses[_].license.id == license
}

contains_license_name(components, license) {
    contains(components.licenses[_].license.name, license)
}

contains_license_expression(components, license) {
    contains(components.licenses[_].expression, license)
}
```

```rego:policy/gpl.rego
package main

import data.cyclonedx

deny[msg] {
    gpl_licenses := ["GPL-1.0", "GPL-2.0", "GPL-3.0"]
	components := cyclonedx.find_components_contains_licenses(input.components, gpl_licenses)
    count(components) > 0

    component_names := cyclonedx.concat_components_names(components)
    msg := sprintf("GPL software must not contain / %s", [component_names])
}
```

はい。一気に長くなってしまいましたが、長いのはモジュールとして共通化して使う `cyclonedx.rego` の処理だけです。個別のポリシー規定側としては、 `cyclonedx.find_components_contains_licenses` を使うだけですね。

上記の例では、GPLライセンスに関するチェックをするポリシーを規定しています。（※ SPDX identifierとしては GPL-1.0などはDeprecatedな表記ですが、ここは本質ではないのでわかりやすい表記を使っています）。

Rego言語自体が従来の手続き型プログラミング言語と思想が違うので、少し複雑なことをしようとすると難解にはなってしまいます。が、ポリシーだけ見ればまあRego言語を知らなくても意図は伝わる気はします。なお、OK/NGだけの判定ならもっとシンプルに書けるのですが、出力結果に違反となったcomponent名の一覧を出したかった（componentの一覧を返す必要がある）ので、少し複雑度が上がっています。わたし自身Rego言語習熟度は低いのでもっと良い書き方もあるかもしれません。

これで一旦流してみます。

```sh
conftest test --parser cyclonedx alpine.cdx
FAIL - alpine.cdx - main - GPL software must not contain / alpine-baselayout, apk-tools, busybox, musl-utils, scanelf, ssl_client

2 tests, 1 passed, 0 warnings, 1 failure, 0 exceptions
```

GPLライセンスのソフトウェアが存在するので、ポリシーチェックに失敗することがわかります。


### 外部のデータファイルを使って判定する

さて、ポリシーの判定をする上で、別のデータファイルの情報を使ってチェックしたいケースがありえます。たとえば、ポリシーとしては組織全体で同一のものを使うが、プロジェクト固有のなにか事情があって、特定のプロジェクトではあるポリシーを無効化したいので、プロジェクトに関する情報を個別に持ちたいなどが考えられます。

conftestでは別のdataを読み込んでポリシーの条件内で使うこともできます。プロジェクトの情報を持つ設定ファイルを規定してみましょう

```yaml:project.yaml
---

project:
  name: my-project
  ignores:
    - rule: gpl-must-not-contain
      component: alpine-baselayout
    - rule: gpl-must-not-contain
      component: busybox
```

スキーマは組織の都合に合わせて様々なものがありえるとおもいますが、上記では `alpine-baselayout` `busybox` に対しては `gpl-must-not-contain` のルールは無視するように明示しました（この2つを選んだのはこの記事用の実行サンプルとしての意味であり、特に実用的な意味はありません）。これをregoで認識できるようにしてみましょう。

```rego:policy/cyclonedx.rego
package cyclonedx

import data.project

（中略）

filter_ignore(rule_id, components) := x {
    x := [ components[c] | not is_ignore_component(rule_id, components[c])]
}

is_ignore_component(rule_id, component) {
    project.ignores[i].rule == rule_id
    project.ignores[i].component == component.name
}
```

```rego:policy/gpl.rego
package main

import data.cyclonedx

deny[msg] {
    gpl_licenses := ["GPL-1.0", "GPL-2.0", "GPL-3.0"]
	components := cyclonedx.find_components_contains_licenses(input.components, gpl_licenses)
    filterd_components := cyclonedx.filter_ignore("gpl-must-not-contain", components)
    count(filterd_components) > 0

    component_names := cyclonedx.concat_components_names(filterd_components)
    msg := sprintf("GPL software must not contain / %s", [component_names])
}
```

`policy/cyclonedx.rego` に ignoreするための処理として `filter_ignore` を追加しました。`conftest` 実行時に `--data` で `project.yaml` を渡すと、`import data.project` によってyamlの情報が参照できるようになります。

```sh
$ conftest test --parser cyclonedx --data project.yaml alpine.cdx
FAIL - alpine.cdx - main - GPL software must not contain / apk-tools, musl-utils, scanelf, ssl_client

2 tests, 1 passed, 0 warnings, 1 failure, 0 exceptions
```

`alpine-baselayout` と `busybox` が除外されていることがわかります。

今回あげた事例ではシンプルな条件付けをしただけですが、任意のデータ構造やより複雑なポリシーを定めてチェックすることも可能そうですね。

## まとめ

今回はtrivyでSBOMを生成し、conftestでSBOMをRegoでチェックする例を示しました。もちろん、SBOM生成の部分をtrivy以外の別のツールでやってもよいですし、conftest以外の方法でSBOMをチェックしても良いでしょう。SBOM関連のツールやプラットフォームは今後も出てくると思われるので、処理ごとに方法は容易に切替可能にしておくのがよいと考えます。

ポリシー記述言語であるRegoを活用することで、より汎用的で流用も容易なポリシーを定めることができそうです。今回紹介しませんでしたが、ポリシーに対してテストを描くこともできます。ただ、現時点ではポリシー記述言語の表記になれた人は少ないので、プロジェクトで使っていけるかどうかは要検討とはおもいます。今回のように適度にモジュール化することで、本質的なポリシーの記述の可読性を上げることはできるでしょう。

現時点の難点の一つとして、SBOMを表現する方法はCycloneDXだけではないのですが、今回挙げたconftestとRegoの方法ではCycloneDXに依存しすぎています。なにか組織の方針が変わって、CycloneDXではないSBOMで管理しようとなったとき、ここで作ったポリシーは修正が必要になります。SBOM間の変換などもできるので何かしら対処のしようはあると思いますが、ポリシー表現が特定のフォーマットに依存しすぎるのもあまり良くない気はします。今後、SBOMを取り扱う技術が発展すれば、SBOMを処理する側の問題に対する解がなにか出てくるかもしれません。

明日は [@yusayoshi](https://qiita.com/yusayoshi) が「playwrightとgitlabCIでE2Eテストを自動化した話を書きます」とのことです。[playwright](https://github.com/microsoft/playwright)といえばMicrosoftのツールですが、私も昔まったく別の用途で[playwright](https://github.com/heriet/playwright)という名前のpipライブラリを公開していたことがありました、Microsoftの方からpip上でplaywrightという名前で登録したいとお声がかかって、お譲りした覚えがあります（私が作ったのは放置プロジェクトだったので快く譲りました）。そんなplaywrightをどのように活用されているのか気になりますね。
