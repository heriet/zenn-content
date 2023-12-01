---
title: "smithy-rsでニフクラのRust SDKを生成を試す"
emoji: "🐙"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["smithy", "Rust"]
published: true
---

本記事は[富士通クラウドテクノロジーズ Advent Calendar 2023](https://qiita.com/advent-calendar/2023/fjct)の2日目の記事です。

1日目は @tunakyonn の [ニフクラに IaC スキャンしてみた](https://tech.fjct.fujitsu.com/entry/advent-calendar-2023-iacscan) でした。Trivyは私もよく使う機会がありますが、こういったIaC用のファイルを静的解析してくれるツールも最近は増えてきたので、大変助かりますね。KICSも取り入れてみたいところです。

さて、今年を振り返ってみると、Rustに関する話題を、以前にも増してよく見かけたようになったと感じます。個人的にもRustは好きな言語です。

普段はニフクラに関する業務をしているため、ニフクラを操作するプログラムを書くことも多いです。が、残念ながらニフクラはRust対応のSDKは今のところありません。そのため、ニフクラの操作が必要な場合は、SDK対応している言語の中で慣れているGolangやPythonを選ぶことも多いです。GolangやPythonも嫌いではありませんが、やはり最近はRustで書けるなら、なるべくそうしたいという気持ちが強いです。

というわけで、今回はsmithy-rsを使ってRust SDK生成ができないか試してみようと思います。

## smithy-rsとは

[smithy-lang/smithy-rs](https://github.com/smithy-lang/smithy-rs) は主にAWSで使われているRust用SDK生成ツールです。AWSのRust SDKである [awslabs/aws-sdk-rust](https://github.com/awslabs/aws-sdk-rust) も smithy-rsで生成されています。

SmithyはAmazonが開発したインターフェース定義言語であり、AWSの多様なSDK生成にも活用されています。たとえば、 [aws/aws-sdk-go-v2](https://github.com/aws/aws-sdk-go-v2) もSmithy言語で定義されたモデルからAWSのGolang SDKが生成されています。Smithy自体は、ある程度AWSの事情を想定して組まれてはいるものの、汎用的なWebサービスのSDKコード生成に活用できるよう設計されているようです。たとえば [smithy-rs の examples](https://github.com/smithy-lang/smithy-rs/tree/main/examples)にはAWSとは関係なく一般的なWebサービスをSmithyで定義し、そのSDKを生成する例が示されています。

ニフクラのGolang SDKである [nifcloud/nifcloud-sdk-go](https://github.com/nifcloud/nifcloud-sdk-go) もSmithyでモデルを定義し、SDKを生成しています。すでにニフクラ用のSmithyファイルはあるので、これを活用すれば、ニフクラのRust用SDKも生成できそうです。

以前、弊社のエンジニアが書いた[SmithyでAPIリファレンス作成してみよう](https://zenn.dev/seumo/articles/d33581c111a6d7)でもSmithyモデルについて解説されているので、参考になるでしょう。

## smithy-rsを使わない実装

smithy-rsでSDKを生成する前に、まずはSDKを使わずにリクエストするコードを書いてみます。

簡単に実装するため、 リクエスト用に[reqwest](https://crates.io/crates/reqwest) とシグネチャ計算に [aws-sign-v4](https://crates.io/crates/aws-sign-v4) を使います。リクエスト先は、ニフクラのオブジェクトストレージサービスのAPIにします。

ニフクラのAPI認証を通すためには、アクセスキーとシークレットキーを使ってシグネチャ計算を行い、仕様に従ってHTTPヘッダーの設定が必要です。

ざっと下記のようになります。

```rust
#[tokio::main]
async fn main() -> Result<(), reqwest::Error> {
    let access_key_id = std::env::var("NIFCLOUD_ACCESS_KEY_ID").expect("NIFCLOUD_ACCESS_KEY_ID is not defined");
    let secret_access_key = std::env::var("NIFCLOUD_SECRET_ACCESS_KEY").expect("NIFCLOUD_SECRET_ACCESS_KEY is not defined");

    let region = "jp-east-1";
    let host = format!("{}.storage.api.nifcloud.com", region);
    let url = format!("https://{}/?x-id=GetService", host); // ?x-id=GetService はなくても良い

    let mut headers = reqwest::header::HeaderMap::new();

    let datetime = chrono::Utc::now();
    let x_amz_date = datetime.format("%Y%m%dT%H%M%SZ").to_string();
    headers.insert(
        "x-amz-date",
        x_amz_date.parse().unwrap(),
    );

    let body = "";
    let x_amz_content_sha256 = sha256::digest(body);
    headers.insert(
        "x-amz-content-sha256",
        x_amz_content_sha256.parse().unwrap(),
    );
    headers.insert("host", host.parse().unwrap());

    let aws_sign = aws_sign_v4::AwsSign::new(
        "GET",
        url.as_str(),
        &datetime,
        &headers,
        region,
        &access_key_id,
        &secret_access_key,
        "s3",
        body,
    );
    let signature = aws_sign.sign();
    headers.insert(reqwest::header::AUTHORIZATION, signature.parse().unwrap());

    let client = reqwest::Client::new();
    let req = client
        .get(url)
        .headers(headers.to_owned())
        .body(body);

    let res = req
        .send()
        .await?;

    let res_body = res.text().await?;
    println!("Body:\n\n{}", res_body);

    Ok(())}
```

上記は動作しますが、レスポンスボディのパースはできておらず、レスポンスボディ全体を文字列としてしか取り扱えていません。プログラム上で取り扱う上では不便ですね。

やはり、SDK経由でリクエストを行い、厳格なリクエストパラメーターの設定からレスポンスのパースまでやって欲しいところです。


## smithy-rsを使って最低限のSDKを生成してみる

それでは、ニフクラのSmithyファイルから簡単にできる範囲でSDK生成を試してみます。

お試しで作ったソースコード全体は [heriet/nifcloud-sdk-rust](https://github.com/heriet/nifcloud-sdk-rust) を参照ください。

Smithyは主にJava Gradle環境が必要になります。また、smithy-rsでは当然ながらRust環境も必要です。他にも色々と依存するものがあり、0から環境を作るのは大変です。幸い、[CI用のDockerfile](https://github.com/smithy-lang/smithy-rs/tree/main/tools/ci-build) があるので、こちらを使うのが楽です。

以後、生成には CI用に用意された `smithy-rs-build-image:latest` イメージを使って作業していきます。今回は、下記のようなcompose.ymlを用意しました。 `${REPO_SMITHY_RS}` は smithy-rsをcloneしたディレクトリです。

```yaml
services:
  smithy-rs:
    image: smithy-rs-build-image:latest
    container_name: nifcloud-sdk-rust-dev
    working_dir: /work
    volumes:
      - ./:/work
      - ./codegen/gradle:/home/build/.gradle
      - ./maven_repository:/root/.m2/repository
      - ${REPO_SMITHY_RS}:/smithy-rs
```

SDK生成に必要なsmithy-rs内のいくつかのプロジェクトは、 Maven Central には登録されていません。直接参照させても良いですが、自分でビルドして、Mavenのローカルリポジトリに登録するのが楽そうでした。ビルドついでに、まずはAWSのRust SDKがどのように生成されるのかも試してみましょう。例えば下記のようにします。

```sh
cd /smithy-rs
./gradlew :aws:sdk:assemble
./gradlew publishToMavenLocal
```

これでMavenのローカルリポジトリに必要なライブラリが登録されるので、これらを使ってニフクラ用のSDK生成をしていきます。[例となるbuild.gradle.kts](https://github.com/crisidev/smithy-rs-pokemon-service/blob/main/model/build.gradle.kts) などを参考に下記のような `build.gradle.kts` を書きます。

```gradle
plugins {
    id("software.amazon.smithy").version("0.6.0")
}

val smithyVersion: String by project

dependencies {
    implementation("software.amazon.smithy.rust.codegen:codegen-client:0.1.0")

    implementation("software.amazon.smithy:smithy-aws-traits:$smithyVersion")
    implementation("software.amazon.smithy:smithy-model:$smithyVersion")
    implementation("software.amazon.smithy:smithy-validation-model:$smithyVersion")
}
```

また、smityのビルドには `smithy-build.json` というファイルが必要になります。今回は smithy-rs内の `rust-client-codegen` を使ってRust SDKを生成したいので、下記のようなjsonを用意します。

```json
{
    "version": "1.0",
    "projections": {
        "storage": {
            "imports": ["./nifcloud-models/storage.smithy"],

            "plugins": {
                "rust-client-codegen": {
                    "service": "com.nifcloud.api.storage#ObjectStorageService",
                    "module": "storage",
                    "moduleVersion": "0.0.0-local",
                    "moduleAuthors": ["heriet <heriet@heriet.info>"],
                    "moduleDescription": "NIFCLOUD SDK for Object Storage Service",
                    "license": "Apache-2.0",
                    "runtimeConfig": {
                        "version": "DEFAULT"
                    }
                }
            }
        }
    }
}
```

`./nifcloud-models/storage.smithy` は [nifcloud-sdk-go の storage.smithy](https://github.com/nifcloud/nifcloud-sdk-go/blob/main/codegen/sdk-codegen/nifcloud-models/storage.smithy) です。ニフクラのオブジェクトストレージサービス用のSmithyファイルとして作られているものです。

その他、ディレクトリ構成を整えたり一般的なgradleビルドに必要ないくつかファイルを配置したら、準備は完了です。最終的な構成は [heriet/nifcloud-sdk-rust](https://github.com/heriet/nifcloud-sdk-rust) を参照ください。これをビルドしてみます。

```sh
cd /work/codegen
./gradlew :nifcloud:sdk:assemble
```

ビルドが成功すると、ビルドディレクトリの中にRustのcrateが生成されます。やりましたね。

本来はより複雑な設定値やコード生成時のデコレーターなどなどが必要だったりはするのですが、今回は省いています。

## 生成したSDKを使う

上に挙げた方法で生成すると `Cargo.toml` は下記のようになっていました。

```toml
# Code generated by software.amazon.smithy.rust.codegen.smithy-rs. DO NOT EDIT.
[package]
name = "storage"
version = "0.0.0-local"
authors = ["heriet <heriet@heriet.info>"]
description = "NIFCLOUD SDK for Object Storage Service"
edition = "2021"
license = "Apache-2.0"
repository = "https://github.com/heriet/nifcloud-sdk-rust"

[package.metadata.smithy]
codegen-version = "null-404f402e59456c222d9c51b6d978ee04e1499778"
[dependencies.aws-smithy-async]
version = "null"
[dependencies.aws-smithy-http]
version = "null"
[dependencies.aws-smithy-runtime]
version = "null"
features = ["client"]
[dependencies.aws-smithy-runtime-api]
version = "null"
features = ["client", "http-02x"]
[dependencies.aws-smithy-types]
version = "null"
[dependencies.aws-smithy-xml]
version = "null"
[dependencies.http]
version = "0.2.9"
[features]
rt-tokio = ["aws-smithy-async/rt-tokio", "aws-smithy-types/rt-tokio"]
test-util = ["aws-smithy-runtime/test-util"]
behavior-version-latest = []
rustls = ["aws-smithy-runtime/tls-rustls"]
default = ["rt-tokio", "rustls"]
```

`version = "null"` となっていると `Cargo.toml` としては不正なので、今回はこれは手で補正します。本来は別途補正する処理を流すようです（今回はお試しなのでそこまでgradleの処理を組んでない）。

この生成された `storage` crateを使ったRustコードを書いてみます。今回は、 `smithy-rsを使わない実装` と同様にオブジェクトストレージサービスの [GetService](https://docs.nifcloud.com/object-storage-service/api/GetService.htm) を叩いてみることにします。SDKとして生成されている `client.rs` のコメントにもSDKの叩き方が出力されるので、それらも参考にクライアントコードを書いてみます。

```rust
use storage::{Client, Config, Error};

#[tokio::main]
async fn main() -> Result<(), Error> {
    let config = Config::builder()
        .endpoint_url("https://jp-east-1.storage.api.nifcloud.com/")
        .build();
    let client = Client::from_conf(config);

    let response = client
        .get_service()
        .send()
        .await
        .expect("operation failed");

    println!("{:#?}", response);

    Ok(())
}
```

ぱっとみ良さそうにも見えすが、実はこれはまだ動きません。下記が不足しているためです。

- (1) TLSの設定
- (2) ニフクラの認証の設定

ニフクラの各エンドポイントは、当然ながらHTTPSになっていますが、クライアント側のTLS関係の設定が必要になります。これは [examplesのclient-connector](https://github.com/smithy-lang/smithy-rs/blob/main/examples/pokemon-service-client-usage/examples/client-connector.rs) あたりの実装をみると参考になります。

また、ニフクラの認証は認証仕様に従ってHTTPヘッダーを付与する必要があります。本来、これは生成されるSDKの仕事なのですが、今回は簡単にSDKを生成したので認証処理の実装が生成されていません。おそらく AWSでの[SigV4AuthDecorator](https://github.com/smithy-lang/smithy-rs/blob/main/aws/sdk-codegen/src/main/kotlin/software/amazon/smithy/rustsdk/SigV4AuthDecorator.kt) あたりを参考にSDKの生成コードにデコレートして生成コードを変更するようなのですが、この実装は少し大変そうです。今回は、一旦動作させたいだけなので、暫定処置としてクライアント側で認証用のヘッダーを付与することにします。

上記の (1) (2) に対応すると、雑ですが最終的には下記のようになります。

```rust
use storage::{Client, Config, Error};
use aws_smithy_runtime::client::http::hyper_014::HyperClientBuilder;
use hyper::header::{HeaderMap, HeaderName, HeaderValue};

#[tokio::main]
async fn main() -> Result<(), Error> {
    let access_key_id = std::env::var("NIFCLOUD_ACCESS_KEY_ID").expect("NIFCLOUD_ACCESS_KEY_ID is not defined");
    let secret_access_key = std::env::var("NIFCLOUD_SECRET_ACCESS_KEY").expect("NIFCLOUD_SECRET_ACCESS_KEY is not defined");

    let region = "jp-east-1";
    let host = format!("{}.storage.api.nifcloud.com", region);
    let url = format!("https://{}/?x-id=GetService", host); // GetService

    let https_connector = hyper_rustls::HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_only()
        .enable_http1()
        .build();
    let hyper_client = HyperClientBuilder::new().build(https_connector);

    let config = Config::builder()
        .endpoint_url(url.as_str())
        .http_client(hyper_client)
        .build();
    let client = Client::from_conf(config);

    let response = client
        .get_service()
        .customize()
        .mutate_request(move |req| {
            let headers = req.headers_mut();

            let datetime = chrono::Utc::now();
            let x_amz_date = datetime.format("%Y%m%dT%H%M%SZ").to_string();
            headers.insert(
                HeaderName::from_static("x-amz-date"),
                HeaderValue::from_str(x_amz_date.as_str()).unwrap(),
            );

            let body = "";
            let x_amz_content_sha256 = sha256::digest(body);
            headers.insert(
                HeaderName::from_static("x-amz-content-sha256"),
                HeaderValue::from_str(&x_amz_content_sha256).unwrap(),
            );

            let header_map = HeaderMap::from_iter([
                (
                    HeaderName::from_static("x-amz-date"),
                    HeaderValue::from_str(x_amz_date.as_str()).unwrap(),
                ),
                (
                    HeaderName::from_static("x-amz-content-sha256"),
                    HeaderValue::from_str(&x_amz_content_sha256).unwrap(),
                ),
            ]);

            let aws_sign = aws_sign_v4::AwsSign::new(
                "GET",
                url.as_str(),
                &datetime,
                &header_map,
                region,
                &access_key_id,
                &secret_access_key,
                "s3",
                body,
            );
            let signature = aws_sign.sign();

            headers.insert(
                hyper::header::AUTHORIZATION,
                HeaderValue::from_str(&signature).unwrap(),
            );
        })
        .send()
        .await
        .expect("operation failed");

    println!("{:#?}", response);

    Ok(())
}
```

主に認証周りのせいでSDKの割に長いコードになってしまっていますが、今回はSDK生成を簡単にやっているのでしかたないですね。

修正後のコードを実行してみると、リクエストは成功します。が、まだ少し問題があります。下記のような出力が得られます。

```sh
$ cargo run
（中略）
operation failed: ServiceError(ServiceError { source: Unhandled(Unhandled { source: XmlDecodeError { kind: Custom("encountered invalid XML root: expected GetServiceResult but got StartEl { name: Name { prefix: \"\", local: \"ListAllMyBucketsResult\" }, attributes: [Attr { name: Name { prefix: \"\", local: \"xmlns\" }, 
（略） 
Response { status: StatusCode(200), ...（略）
body: SdkBody { inner: Once(Some(b"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ListAllMyBucketsResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"><Owner>（略）</Owner><Buckets><Bucket>（（略））</Bucket></Buckets></ListAllMyBucketsResult>")), retryable: true }, extensions: Extensions } })
```

出力を見ると、HTTPステータスコードは200でリクエストは返っており、レスポンスも通っているようですが、XMLのパース時にエラーが出ています。つまり、クライアント側のパースの問題です。どうやら、SDKが認識しているXML要素名と乖離があるようです。

`storage.smithy` の該当部分を確認すると、下記のように定義されています。

```sh
structure GetServiceResult {
    @xmlName("Buckets")
    Buckets: ListOfBuckets,
    @xmlName("Owner")
    Owner: Owner,
}
```

これはGolang用SDK向けの定義としては問題ないようなのですが、Rust用SDKの実装では定義が不足しているようです。`ListAllMyBucketsResult` という要素に関する定義がありません。

最終的には、 Smithy 2.0形式に変換の上、 `ListAllMyBucketsResult` 要素の情報を追加する必要があるようでした。

```json
        "com.nifcloud.api.storage#GetServiceResult": {
            "type": "structure",
            "members": {
                "Buckets": {
                    "target": "com.nifcloud.api.storage#ListOfBuckets",
                    "traits": {
                        "smithy.api#xmlName": "Buckets"
                    }
                },
                "Owner": {
                    "target": "com.nifcloud.api.storage#Owner",
                    "traits": {
                        "smithy.api#xmlName": "Owner"
                    }
                }
            },
            "traits": {
                "smithy.api#output": {},
                "smithy.api#xmlName": "ListAllMyBucketsResult"
            }
        },
```

`storage.smithy` を元に修正した `storage.json` から `./gradlew :nifcloud:sdk:assemble` を再度実行すると、生成されるSDKのコードが修正されました。再度生成されたSDKを使ったクライアントコードを実行してみます。

```sh
$ cargo run
（略）
GetServiceOutput {
    buckets: Some(
        [
            Buckets {
                creation_date: Some(
                    DateTime {
                        seconds: xxxxxx,
                        subsecond_nanos: xxxxx,
                    },
                ),
                name: Some(
                    "xxxxxx-xxxxxxx",
                ),
            },
        ],
    ),
    owner: Some(
        Owner {
            display_name: Some(
                "xxxxxxxxxx",
            ),
            id: Some(
                "xxxxxxxxxx",
            ),
        },
    ),
}
```

`GetService` のレスポンスが、Smithyで定義した構造で正しくパースされ、プログラム上で取り扱いやすい状態にできています。

これで `smithy-rs` を使ってSmithyファイルから一旦動くRust SDKが生成できることが確認できました。必要最低限の状態でコード生成しているので、開発の実用にはまだ遠いのですが、今回の結果をベースに必要な処理を追加していけば、ニフクラのRust SDKが作れそうなことがわかります。

## まとめ

smithy-rsでSmithyファイルからRust SDKが生成できる事がわかりました。

課題として、TLS対応やエンドポイント、認証処理など、使いやすいSDKにするための生成コード補正が対応できていないので、現状は使いにくい状態です。とはいえ、結局のところRustのソースコードを生成しているわけで、生成コード補正の実装さえ頑張れば対応は技術的には可能なはずです。

個人的には `smithy-rs` の挙動をおおよそ確認できたので、一旦は満足です。今回調べたことで、ニフクラのRust SDK生成までの道のりもだいぶ短くなったはずです。将来的には、公式にRust SDKが対応できると大変うれしいですね。

明日は [@e10persona](https://qiita.com/e10persona) の「Chromeに保存したパスワード取得を検証してみた」です。ブラウザのパスワードマネージャーからパスワードが流出する話もよく聞くので、どのぐらい簡単にパスワードが取得できてしまうのか気になりますね。