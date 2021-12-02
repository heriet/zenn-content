---
title: "GitLab Triageでプロジェクトの棚卸しを自動化する"
emoji: "📇"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["GitLab", "gitlab-triage"]
published: true
---

本記事は [富士通クラウドテクノロジーズ Advent Calendar 2021](https://qiita.com/advent-calendar/2021/fjct) の2日目の記事です。

1日目は[@ktakaaki](https://qiita.com/ktakaaki) の[TwilioとWindows PowerShellを使って連続で電話を掛けたい](https://qiita.com/ktakaaki/items/a6a3154c3600388f39ea)でした。Twilioはシステムから電話を掛ける際に非常に便利なサービスで、様々な場面でよく使われますが、PowerShellからでも簡単にコールできるんですね。

さて、富士通クラウドテクノロジーズ社では [全社員が利用するプロジェクト管理ツールとしてGitLabを採用](https://tech.fjct.fujitsu.com/entry/Story-of-introducing-GitLab-Enterprise-Edition-Premium) しています。各チームそれぞれがGitLabを活用しており、様々なGitLab活用ノウハウがあるのですが、今回は最近導入した GitLab Triage を紹介したいと思います。

## GitLab Triageとは

[GitLab Triage](https://gitlab.com/gitlab-org/gitlab-triage) はGitLabのプロジェクト上のIssue/Merge Request/Epicをトリアージするためのツールです。 **トリアージ(triage)** 自体は耳慣れない言葉だとおもいますが、ここではプロジェクト管理の文脈で「棚卸し」と捉えるとよいでしょう。たとえば、トリアージによってクローズし忘れのIssueをクローズしたり、マージ忘れていたMerge Requestをマージしたりといったことが自動で行われます。スクラムであればバックログリファインメントの中で似たようなことを手動で実施しているチームもあるでしょう。

GitLab Triage自体は[オープンソースのGitLab開発](https://gitlab.com/gitlab-org/gitlab/-/blob/master/doc/development/contributing/issue_workflow.md#issue-triaging)でも用いられており、GitLabの開発メンバーによってメンテナンスされているようです。

## GitLab Triageが必要な場面

プロジェクト管理でIssueなどを活用するのは一般的かと思いますが、何かしらの対策をしないと次のような状況がしばしば発生します。

* クローズし忘れのIssue/Merge Request/Epicが蓄積する
* 解決はしていないが、直近の状況が不明なIssue/Merge Request/Epicが蓄積する
* 担当者があいまいなIssueが残存し、Assigneeが設定されないまま放置される
* Merge RequestのReviewerを設定し忘れ、いつまでもレビューされない
* Issueに期限を設定したが、設定しただけで期限までに対応がされない
* Issueにプロジェクト運用上必要なラベルを付与するルールを定めたが、ラベルをつけ忘れる

これらはプロジェクト管理する上で避けるのは難しいことです。人間が操作・管理している以上、発生することを完全に防ぐのは現実的ではありません。そのため、発生することを前提として何かしらの対策が必要になります。

様々な対策があると思いますが、対策の一つはプロジェクトメンバーが定期的にチェックしたり気が付いたタイミングで、問題があれば一つ一つ手で修正するというナイーブな方法です。定期的にチェックされるよう、プロジェクトの棚卸ルールを定めているチームもあることでしょう。それで十分な場合もありますが、人間の目でチェックし続ける運用というのは問題を孕んでいます。

Issue/Merge Request/Epicを綺麗に保つことそのものはプロジェクトメンバーにとって本来の仕事でもありません。プロジェクトを成功に導くためには、Issue/Merge Request/Epicがある程度綺麗に管理されていることがもちろん望ましいのですが、綺麗に保つことに神経をとがらせるのも大変ですし、工数もかかってしまいます。また、Issue/Merge Request/Epicをどれだけ綺麗に保ちたいかは、プロジェクトメンバーの立場や性格にもよることでしょう。丁寧にIssue/Merge Request/Epicを保つのが得意で、綺麗な状態になっていないとかえって気に病んでしまう人もいれば、多少乱雑な状態が放置されていても別に大丈夫という人もいるはずです。

例えるなら、一つの家に同居している人たちのなかで、部屋の清潔さの許容範囲が異なる状況と言えるでしょう。同居人が2人で、部屋の清潔さの感覚が近いならおそらく問題にはならないでしょうが、それはレアケースです。たいていはどちらか片方がより清潔好きで、掃除が行き届いていなければ清潔好きな人にとって苦痛になりえますし、かといって清潔好きではない人にとって自分の許容範囲以上にこまめに掃除するのは負担になってしまいます。2人ならまだいいほうで、小さいプロジェクトでも大抵は3～5人は住んでいますし、大きなプロジェクトであれば何十人も関わることもあるわけで、そんな人たちの清潔さの感覚を合わせるのは人類には不可能なことです。なので、プロジェクトごとにどのような綺麗さを保つか **ポリシー（ルール）** を定めることが大事になってきます。当然、 **ポリシーに従わない人も出てくる** ので、ポリシーに従って清潔さが保たれるよう、トリアージが必要になってきます。

長々と書きましたが、要はたくさんの人が活動するプロジェクトは自然と汚れるものなので、綺麗にするポリシーの制定とトリアージが必要です。そのトリアージを行うためのツールがGitLab Triageです。


## GitLab Triageの導入

では、実際にGitLab Triageを使ってみましょう。GitLab Triage自体はシンプルなCLIツールで、[RubyGems.org](https://rubygems.org/gems/gitlab-triage/)で公開されています。

GitLab Triageを実行するには、トリアージのポリシーを定めるために YAMLファイルを作成する必要があります。デフォルトではこのYAMLファイルは `.triage-policies.yml` というファイル名で作成します。たとえば、「OpenなIssueのうち2週間更新がなければ、needs updateラベルを付与してAssigneeとIssue作成者にメンションする」というポリシーを定めてみましょう。

```yaml:.triage-policies.yml
resource_rules:
  issues:
    rules:
      - name: not updated for 2 weeks
        conditions:
          state: opened
          date:
            attribute: updated_at
            condition: older_than
            interval_type: weeks
            interval: 2
          forbidden_labels:
            - needs update
        actions:
          labels:
            - needs update
          comment: |
            {{assignee}} {{author}} 2週間更新されていません。状況を更新してください。
```

YAMLの正確な記法は [GitLab Triageの説明](https://gitlab.com/gitlab-org/gitlab-triage#defining-a-policy) を読んで欲しいのですが、記法を知らなくてもおおよそポリシーの内容が理解できるようなYAMLになっているかと思います。基本的に `conditions` で対象となるIssueを定義し、 `actions` で対象となったIssueに行いたい操作を定義します。 `forbidden_labels` は対象の除外条件として機能し、ここでは既に「needs update」ラベルが付与しているものを対象外にしています。何度もトリアージ操作を行ったときに、何度もメンションが飛ぶようなことを防ぐためです。なので、上記のポリシーはより正確に表現するなら「OpenなIssueのうち2週間更新がなくかつneeds updateラベルが設定されていなければ、needs updateラベルを付与してAssigneeとIssue作成者にメンションする」という意味になります。


GitLab TriageはRuby環境があればどこでも動きますが、プロジェクトで実際に使う場合はGitLabの標準機能である[GitLab CI/CD](https://docs.gitlab.com/ee/ci/)を使って動作させるのが一般的でしょう。たとえば、下記のような `.gitlab-ci.yml` をプロジェクト上に作成します。

```yaml:.gitlab-ci.yml
stages:
  - triage

triage:
  stage: triage
  image: 
    name: <GitLab Triageのコンテナイメージ>
    entrypoint: [""]
  script:
    - gitlab-triage --token $TRIAGE_GITLAB_API_TOKEN --source-id $CI_PROJECT_PATH --host-url $CI_SERVER_URL
  only:
    - schedules
```

`TRIAGE_GITLAB_API_TOKEN` は対象プロジェクトのGitLab APIが利用可能なトークンで、別途設定が必要になります。多くの場合は、[Project access tokens](https://docs.gitlab.com/ee/user/project/settings/project_access_tokens.html)を生成して、プロジェクトの [CI/CD variables](https://docs.gitlab.com/ee/ci/variables/index.html#add-a-cicd-variable-to-a-project) に設定すればよいでしょう。

GitLab Triageのコンテナイメージは各自で用意することが多いかと思います。私は下記のようなDockerfileでコンテナイメージを作っています。普段使っている [GitLab Container Registry](https://docs.gitlab.com/ee/user/packages/container_registry/) でコンテナイメージを登録しておくとよいでしょう。


```dockerfile:gitlab-triage.dockerfile
FROM ruby:3.0.2-slim

WORKDIR /app

COPY Gemfile /app/Gemfile
COPY Gemfile.lock /app/Gemfile.lock

RUN gem install bundler -v "2.2.31"
RUN bundle install

RUN gem install gitlab-triage

ENTRYPOINT ["gitlab-triage"]
```

今回は `.gitlab-ci.yml` で `schedules` としてのみ動作するようにしたので、[Pipeline schedules](https://docs.gitlab.com/ee/ci/pipelines/schedules.html) の設定も必要です。トリアージを実行したい頻度に合わせて設定すれば問題ありません。たとえば今回のケースなら毎朝8:00にPipeline schedules設定しておけば、毎朝8:00にGitLab Triageが実行され、 `.triage-policies.yml` に設定した通り「OpenなIssueのうち2週間更新がなくかつneeds updateラベルが設定されていなければ、needs updateラベルを付与してAssigneeとIssue作成者にメンションする」という動作をします。

今回は `schedules` で設定しましたが、これは `.gitlab-ci.yml` の設定次第で柔軟に変えられるので、目的に合わせて設定してください。たとえば、定期的な実行ではなく、Merge Request作成直後にMerge RequestのトリアージをするといったCI設定もできるでしょう。

基本的に `.triage-policies.yml` と `.gitlab-ci.yml` を適切に設定すれば、プロジェクトに必要なポリシーとトリアージを柔軟に設定できるようになります。設定の詳細については [GitLab Triage](https://gitlab.com/gitlab-org/gitlab-triage) 公式のドキュメントを読んでいただければと思います。

なお、今回は詳しく紹介しませんが、トリアージ対象となったIssueが存在するときに、対象IssueのまとめをSummary Issueとして作成するといった機能もあります。たとえば、プロジェクトのリーダーが状況を俯瞰したり、対処が不明瞭なものをまとめてリーダーが処理するといったケースに便利でしょう。そちらも公式ドキュメントに詳細が記載されています。

## GitLab Triageをさらに活用する

### triage-opsを参考にする

GitLab Triageを活用するうえで最も参考になるのは、GitLab開発でも実際に使われているポリシーで、[Issue Triage](https://about.gitlab.com/handbook/engineering/quality/issue-triage/) と [Triage Operations](https://about.gitlab.com/handbook/engineering/quality/triage-operations/) にその詳細が記載されています。実際に使われているポリシーも [GitLab.org / quality / triage-ops](https://gitlab.com/gitlab-org/quality/triage-ops/) に存在しているので、 `.triage-policies.yml` の書き方やポリシー設計の参考になります。

なお、GitLab開発でも自動化されているものはtriage-opsに設定がありますが、ポリシーのすべてがGitLab Triageで自動化されているわけではないようです。自動化可能なものはGitLab Triageで行い、一部どうしても人力で見ないといけないポリシーもあることが分かります。プロジェクトによって事情は変わると思いますが、自動化するものと、手動でみるものの切り分けの参考にもなるでしょう。

### タイミングによって GitLab Triageのポリシーを変える

GitLab Triageはスケジュール実行させることが多いと思いますが、プロジェクトの運用次第では、1時間毎に実行したいポリシー、毎日実行したいポリシー、週1で実行したいポリシーなど頻度ごとに実行したいポリシーを変えたいことがあるかもしれません。その場合、一つの解法としてポリシーファイルを複数用意してCIを設定すれば実現できます。下記のような `.gitlab-ci.yml` にします。

```yaml:.gitlab-ci.yml
stages:
  - triage

triage-hourly:
  stage: triage
  image: 
    name: <GitLab Triageのコンテナイメージ>
    entrypoint: [""]
  script:
    - gitlab-triage --token $TRIAGE_GITLAB_API_TOKEN --source-id $CI_PROJECT_PATH --host-url $CI_SERVER_URL --init .triage-policies-hourly.yml
  only:
    variables:
      - $TRIAGE_JOB_HOURLY

triage-daily:
  stage: triage
  image: 
    name: <GitLab Triageのコンテナイメージ>
    entrypoint: [""]
  script:
    - gitlab-triage --token $TRIAGE_GITLAB_API_TOKEN --source-id $CI_PROJECT_PATH --host-url $CI_SERVER_URL --init .triage-policies-daily.yml
  only:
    variables:
      - $TRIAGE_JOB_DAILY

triage-weekly:
  stage: triage
  image: 
    name: <GitLab Triageのコンテナイメージ>
    entrypoint: [""]
  script:
    - gitlab-triage --token $TRIAGE_GITLAB_API_TOKEN --source-id $CI_PROJECT_PATH --host-url $CI_SERVER_URL --init .triage-policies-weekly.yml
  only:
    variables:
      - $TRIAGE_JOB_WEEKLY
```

`--init` オプションで `.triage-policies` が指定できるので、頻度ごとに `.triage-policies.yml` 相当のYAMLファイルを用意する形になります。また、スケジュール実行で特定のスケジュールでのみジョブが実行されるようにしたいので、 `only:variables` を指定して、特定の環境変数が有効な場合のみ実行されるようにしています。頻度とジョブの対応がわかりやすい環境変数にするとよいでしょう。

頻度毎に全く違うポリシーが実行されるなら上記で十分かと思いますが、さらに頻度毎に同一のポリシーのトリアージを実行したい場合もあるかもしれません。その場合、ファイルごとに重複したポリシーを書くことになり、不都合なケースもあるでしょう。

より高度な設定方法として、ポリシーファイルを環境変数の設定に従ってジョブ内で自動生成するという方法も考えられます。たとえば [triage-opsでのポリシーの生成](https://gitlab.com/gitlab-org/quality/triage-ops/-/blob/master/lib/generate/group_policy.rb) の処理が参考になると思います。ただ、自動生成を絡ませるとYAMLファイルの管理が複雑になるデメリットもあるので、そこはトレードオフになるでしょう。

### より柔軟なconditionsの設定

GitLab Triageはconditionsで対象となる条件を記述できますが、プロジェクト運用によってはYAMLのconditionsでは単純に表現しきれないケースがでることもあります。たとえば、 [conditions:labels](https://gitlab.com/gitlab-org/gitlab-triage#labels-condition) では対象となるラベルの一覧は記述できますが、 「頭に `Priority::` と付くラベルがどれか付いている」といった指定は`conditions:labels`では実現できません。

そのようなケースでは、 [conditions:ruby](https://gitlab.com/gitlab-org/gitlab-triage#ruby-condition) でRubyコードを記載することで、柔軟なconditionsの設定が可能です。たとえば、 「頭に `Priority::` というラベルのいずれかが付与されている」ポリシーは下記のように書けます。

```yaml:.triage-policies.yml
resource_rules:
  issues:
    rules:
      - name: no priority label
        conditions:
          state: opened
          forbidden_labels:
            - needs priority label
          ruby: |
            return true if resource[:labels].nil?
            resource[:labels].find{|label| label.start_with?("Priority::")}.nil?
        actions:
          labels:
            - needs priority label
          comment: |
            <{{author}}> `Priority::*` ラベルをいずれか付与してください
```

`conditions:ruby` 内で利用可能な変数は公式ドキュメントを読んでいただければと思いますが、基本的に `resource` に対象リソースに関する情報は一通り入っているので、その中の情報を使って判定するコードを書けば大抵の条件は書けると思います。

YAML内にあまり複雑なRubyコードを入れたくない場合は、別途 [プラグインを用意](https://gitlab.com/gitlab-org/gitlab-triage#can-i-customize) する方法もあります。

## 独自ツールとGitLab Triage

GitLab Triageでは `conditions:ruby` 等も活用すればかなり柔軟にポリシーを規定できますが、おそらくプロジェクト運用上かゆいところに手が届かないというケースもあると思います。たとえば、 `actions` ではRubyコード実行する仕様は今のところないので、たとえばIssue上にコメントする代わりにWebhookを使ってSlackに通知を飛ばしたい、といったことはGitLab Triageではできません。

ただ、上記のようなGitLab Triageでは実現できないケースでも、独自のツールを作成すれば簡単に実現できます。ツールの作成方法はいくつかありますが、GitLab APIに対応したクライアント実装は既にたくさんあり、これらを使えば短いスクリプトで記述できます。実際、ポリシーによっては GitLab Triageの `.triage-policies.yml` を書くよりも短いコード量でかけるケースもあるでしょう。独自ツールで実現するのか、GitLab Triageを使うのかは下記の観点で比較するとよいでしょう。

- プロジェクトメンバーがプログラム理解できるか？
    - GitLab TriageはYAMLでポリシーが規定できるのが大きな差となります。プログラムが理解できないメンバーも大きく関わるのであれば、YAMLでポリシーを定義できるGitLab Triageは大きな優位があります
- 実現したいポリシーがGitLab Triageのポリシーで簡潔に書けそうか？
    - 実現できない場合は独自ツールしか選択肢がありません
    - 実現できたとしても、GitLab TriageのYAMLよりも独自ツールのほうが簡潔に記述できそうなら、独自ツールのほうがおそらくよいでしょう
        - YAML内のRubyコードが複雑になればなるほど、YAML管理は厳しくなるはずです

ちなみに、今回は詳しく説明しませんが、GitLab Triageとは違う視点で、コードレビューに関する処理を自動化する [Danger bot](https://docs.gitlab.com/ee/development/dangerbot.html) というものもあります。プロジェクト運用によっては、Dangerが適切な選択肢になることもあるでしょう。

## まとめ

[GitLab Triage](https://gitlab.com/gitlab-org/gitlab-triage) を使ってプロジェクトのトリアージ（棚卸し）を自動的に行う方法を紹介しました。適切なポリシーを設定して、面倒くさいトリアージ業務を自動化し、プロジェクトメンバーが本来行うべき業務により集中できるようになるでしょう。

ただ、GitLab Triageだけでプロジェクト管理の自動化が何でもできるわけでもありません。GitLab Triageが使いやすいケースではGitLab Triageを活用し、合わない場合は別のツールを使ったり人力で行うなどの使い分けもできると、より高度で柔軟なプロジェクト管理ができることでしょう。特に、GitLab TriageはYAMLでわかりやすくポリシーを定義できるという強みがあるので、エンジニア中心のプロジェクトはもちろんとして、プログラミング非経験者も関わるプロジェクト運用でも有効に働くはずです。

明日は[@hasunuma](https://qiita.com/hasunuma) が「社内slack botリプレースの話」の話を書いてくれるそうです。弊社ではSlackを活用したbotも様々なものが開発されており、その一端が垣間見れるのではないかと思います。
