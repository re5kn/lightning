class_name Params
## 調整用パラメータ。HTML5 たたき台 (game/index.html) の P オブジェクトをそのまま移植した値。
## 線の速さは「standard」のみ (バリエーションは後で追加)。見た目の種類は world_view.gd

const LANES := 7                 # 車線数
const LANE_W := 2.0              # 車線幅 (ワールド単位)
const CAM_H := 10.0              # カメラの高さ
const CAM_BACK := 32.0           # カメラから自機の先端までの距離
const PLAYER_LEN := 18.0         # 自機の線の長さ (判定用)
const VIEW := 520.0              # 描画距離
const NEAR := 0.8
const HORIZON_Y := 0.30          # 地平線の高さ (画面の上から、画面の高さに対する割合)
const FOCAL := 0.95              # 焦点距離 (画面の高さに対する割合)
const BASE_V := 20.0             # LO の速度 (ワールド単位/秒)
const RATIO := [1.0, 1.4, 1.9, 2.9, 4.3, 6.3]          # ギアごとの速度比
const GAUGE_RATE := [12.0, 12.0, 12.0, 12.0, 12.0, 0.0] # ゲージ増加 %/秒。上げられるギアの上限ごと (同じ速さの線が片側の隣にあるとき)
const ADJ_SPEED_MUL := Vector2(0.4, 2.0)                # 隣の線の速さによる倍率の下限・上限 (隣の速さ ÷ 上限ギアの速さ)
const TIME_LIMIT := 300.0        # 初期 5:00
const TIME_BONUS := 10.0         # 虹色の線で +10 秒
const STREAM_COUNT := 11         # 同時に出ている光の筋の目安
const RAINBOW_CHANCE := 0.07
const LANE_RUN := 6.0            # 自機が1車線横へ動く間に進む距離 (斜めの軌跡の傾き)
const DST_UNIT := 57.0           # ワールド単位 → DST 表示 (LO で約 0.35/秒)
const SCORE_PER_UNIT := 0.15     # 走行距離あたりのスコア
const INVULN_TIME := 1.5         # 接触後の無敵時間 (秒)。この間は自機の線が点滅し、ペナルティを受けない

# 線の速さのパターン「standard」(たたき台の LINE_SETS.standard)
const LINES_PLAYER := 1.0                   # 自機の速さの倍率
const LINES_BEHIND := Vector2(1.2, 1.55)    # 後ろから来る線 (自機を抜いていく側)
const LINES_START := Vector2(0.8, 1.15)     # 開始時に並んでいる線 (LO の速さに対する倍率)
# 前方に出てくる線は 12 〜 自機の 0.8 倍 (最低でも 24 まで)

const GEARS := ["LO", "2nd", "3rd", "4th", "5th", "TOP"]
const TOP := 5
const ROAD_HALF := LANES * LANE_W / 2.0 + 1.5
const PALETTE := [Color("#ff3b3b"), Color("#ff9a2e"), Color("#ffe23b"), Color("#44e05a"), Color("#3fe0ff"), Color("#3f6bff"), Color("#b04bff")]
const START_TOTAL_DST := 192847.4


static func base_v() -> float:
	return BASE_V * LINES_PLAYER


static func bonus_of(gear: int) -> int:
	return 10 * (1 << gear)       # 10 × 2^(ギア-1)


static func lane_d(i: int) -> float:
	return (i - (LANES - 1) / 2.0) * LANE_W


static func lane_of(d: float) -> int:
	return floori(d / LANE_W + (LANES - 1) / 2.0 + 0.5)
