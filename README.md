# lightstream (Godot 4)

Wii の「lightstream」のような、光の筋の隣を走ってゲージを溜め、ギアを上げていくスコアアタック型のドライブゲーム。
HTML5 のたたき台 (`game/index.html`) の動きとパラメータをそのまま Godot 4 へ移植したもの。

- エンジン: Godot 4.7.2 (GDScript)
- 描画: 本物の 3D (Camera3D がオーバルのコースに沿って走り、道路の縁・光の筋・自機を 3D 空間の光の帯として描く)
- レンダラー: Compatibility (Web 書き出しに必要)
- 画面: 1280×720 (16:9)。ウィンドウの大きさに合わせて拡大縮小し、比率は保つ
- 実装範囲: 見た目は「standard」、線の速さは「standard」のみ

## 遊び方 (Godot エディタで確認)

1. Godot 4.7.2 で `project.godot` を開く
2. F5 (メインシーンを実行) でデスクトップのウィンドウで遊べる
3. ブラウザで確認するときは、エディタ右上の「リモートデバッグ」のとなりにある **ブラウザで実行** (HTML5 アイコン) を押す
   - 初回は Web の書き出しテンプレートが必要 (エディタ > 書き出しテンプレートの管理 > ダウンロード)

## Web 書き出し

- エディタ: プロジェクト > エクスポート > 「Web」プリセット > プロジェクトのエクスポート (`build/web/index.html`)
- コマンド: `godot --headless --path . --export-release "Web" build/web/index.html`
- スレッドなしの書き出し (`variant/thread_support=false`) にしてあるので、特別なサーバー設定 (COOP/COEP) なしで普通の Web サーバーに置けば動く
- 書き出したファイルはブラウザで直接開けないので、Web サーバー経由で開く (例: `cd build/web && python3 -m http.server` → http://localhost:8000)
- GitHub Actions (`.github/workflows/web.yml`) が push ごとに Web 書き出しを行い、成果物 `web` (zip) を保存する。main ブランチでは GitHub Pages へ公開する (リポジトリの Settings > Pages で Source を「GitHub Actions」にしたとき)

テスト用: Web 版は URL に `?time=60`、デスクトップ版は `-- --time=60` を付けると制限時間を変えられる。

## 操作

| 動作 | キーボード | ゲームパッド |
|---|---|---|
| 車線移動 (押しっぱなしで連続) | ← → (A / D) | 十字キー左右 / 左スティック |
| シフトアップ (Wii リモコンの 2) | ↑ / X | A / RB |
| シフトダウン (Wii リモコンの 1) | ↓ / Z | X / LB |
| ポーズ (もう一度押すと再開) | Esc / P | Start |
| ポーズ中: resume (再開) / quit (終了してリザルトへ) | ↑ ↓ / Enter・Space・X | 十字キー上下・左スティック / A |
| 音のオン・オフ | M | - |
| メニュー選択・決定 | ↑ ↓ / Enter・Space・X | 十字キー上下・左スティック / A・Start |

入力はすべて InputMap のアクション (`lane_left`, `lane_right`, `shift_up`, `shift_down`, `pause`, `sound_toggle`, `menu_up`, `menu_down`, `menu_accept`) で受けている。
割り当てはエディタの プロジェクト設定 > インプットマップ で変えられる。`tools/setup_input.gd` は既定の割り当てを作り直すスクリプト。

## ファイル構成

| ファイル | 内容 |
|---|---|
| `scenes/main.tscn` | メインシーン (3D 表示、HUD、音) |
| `scripts/params.gd` | 調整用パラメータ (たたき台の `P` オブジェクトと同じ値) |
| `scripts/track.gd` | コース (オーバル + ゆるい起伏) と、コース上の位置 → 3D 座標 |
| `scripts/race.gd` | 1 プレイ分のルール: 光の筋の生成と移動、車線の排他、ゲージ、ギア、追い抜きボーナス、衝突・割り込みのペナルティ、無敵時間 |
| `scripts/world_view.gd` | 3D 表示: カメラと、光の帯のメッシュ |
| `scripts/hud.gd` | HUD・タイトル・リザルト・演出 (オレンジの弧、ready / go、time up) |
| `scripts/sound.gd` | 効果音とテクノ系 BGM (たたき台の WebAudio 合成と同じ音色を起動時に合成) |
| `scripts/main.gd` | 画面の流れ (タイトル → プレイ → time up → リザルト)、入力、保存 (自己ベスト・累計距離) |
| `tools/` | 開発用スクリプト (書き出しには含めない)。`sim_test.gd` は画面なしでロジックを動かす確認 |
| `assets/fonts/` | Quicksand, Exo 2 (SIL Open Font License) |

仕様: プロジェクトの `spec/game-spec-from-video.md`。
