# ce-morpheus

蓋を閉じても Mac をスリープさせない設定（`pmset -a disablesleep 1`）を、メニューバーから ON/OFF するだけの小さなアプリ。配布用のビルドは無いので、自分でビルドして使う。

- アイコン: ON = 薬液入りのアンプル、OFF = 斜線入りの空のアンプル、不明 = アンプルと「?」（Morpheus がモルヒネの語源であることから）
- 表示はアプリ内のフラグではなく `pmset -g` の `SleepDisabled` を読む（起動時・メニューを開く直前・切り替え直後・60 秒ごと）。
- アプリの終了時に設定を元に戻さない。終了後も ON のままになる（再起動後に残るかは未確認。「注意」を参照）。

## ビルドと起動

```sh
./build.sh                    # build/ce-morpheus.app を作り、ad-hoc 署名する
open build/ce-morpheus.app
```

必要なもの: Xcode（Swift 6）、macOS 14 以上。

## sudoers の設定（初回だけ）

`pmset -a disablesleep` は root が要る。アプリは `sudo -n`（パスワードを聞かない）で実行するので、この 2 コマンドだけをパスワードなしで許可する。

1. ユーザー名を確認する: `whoami`
2. `sudo visudo -f /etc/sudoers.d/ce-morpheus` で次の 1 行を書く（`<ユーザー名>` を 1 の値に置き換える）。

   ```
   <ユーザー名> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
   ```

3. 構文を確認する。断片だけでなく sudoers 全体も検査し、断片が読み込まれていることを確かめる。
   - `sudo visudo -cf /etc/sudoers.d/ce-morpheus`（`parsed OK` が出ればよい）
   - `sudo visudo -c`（すべて `parsed OK` で、その中に `sudoers.d/ce-morpheus` を含む行があればよい。無ければ `/etc/sudoers` が `sudoers.d` を読み込んでいない）
4. パスワードなしで通るか確認する。今の値を変えないよう、同じ値を指定する。
   1. `pmset -g; echo "exit=$?"` を実行する（`grep` にはつながない。つなぐと、読み取りの失敗と行が無い場合の区別がつかなくなる）。最後の行が `exit=0` でなければ、ここで中止する。
   2. 1 の出力から `SleepDisabled` の行を探す。値が `1` なら 1、`0` なら 0、行が無ければ 0 とする。それ以外の値なら、ここで中止する。
   3. `sudo -k -n /usr/bin/pmset -a disablesleep <2 で決めた値>` を実行する。`-k` で直前に入力したパスワードの認証キャッシュを無視させるので、上の構文確認（外側の手順 3）の直後でも、パスワードなしで許可されているときだけ成功する。
   4. エラーが出ずに終わればよい。`a password is required` が出たら、外側の手順 2〜3 を見直す。

注意: 同じユーザーで動くプロセスなら、どのアプリでもこの 2 コマンドを呼べる。`pmset` 全体を許可しないこと。

パスワードなしの実行が拒否された場合（sudoers が未設定など）、アプリでの切り替えは失敗し、「設定が必要」というアラートが出る。

## 手作業での ON/OFF と状態確認

```sh
sudo pmset -a disablesleep 1     # ON
sudo pmset -a disablesleep 0     # OFF
pmset -g | grep SleepDisabled    # 1 = ON、0 または行なし = OFF
```

## 注意

- ON のまま蓋を閉じた本体を、カバンや寝具の上など熱がこもる場所に置かない。
- ON はアプリを終了しても残る（再ログイン後も残るという報告あり。再起動後に残るかは未確認）。使い終わったら OFF に戻す。

## アンインストール

1. `pmset -g | grep SleepDisabled` が 1 なら `sudo pmset -a disablesleep 0` で戻す。
2. メニューの「終了」でアプリを閉じる。
3. sudoers の設定を消す: `sudo rm /etc/sudoers.d/ce-morpheus`
4. このフォルダ（`build/` と `.build/` を含む）を削除する。
