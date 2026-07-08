
import os
import json
import logging
import datetime
import requests
import google.generativeai as genai
import googlemaps
import firebase_admin
from firebase_admin import credentials, firestore, auth
from flask import Flask, request, jsonify

# ==========================================
# 1. 設定・初期化
# ==========================================
app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# キーは環境変数のみから読む（コードへの直書きはしない。
# PythonAnywhere では WSGI設定ファイル or .env + Web タブの環境変数で設定する）
GOOGLE_MAPS_API_KEY = os.environ.get("GOOGLE_MAPS_API_KEY")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
OPENWEATHER_API_KEY = os.environ.get("OPENWEATHER_API_KEY")

for name, val in [("GOOGLE_MAPS_API_KEY", GOOGLE_MAPS_API_KEY),
                  ("GEMINI_API_KEY", GEMINI_API_KEY),
                  ("OPENWEATHER_API_KEY", OPENWEATHER_API_KEY)]:
    if not val:
        logger.error(f"❌ 環境変数 {name} が未設定です")

# Firebase初期化
FIREBASE_CRED_PATH = "/home/aisleep/serviceAccountKey.json"
db = None
if not firebase_admin._apps:
    try:
        if os.path.exists(FIREBASE_CRED_PATH):
            cred = credentials.Certificate(FIREBASE_CRED_PATH)
            firebase_admin.initialize_app(cred)
            logger.info("✅ Firebase Initialized")
        else:
            logger.error(f"❌ {FIREBASE_CRED_PATH} not found — 認証・課金判定が機能しません")
    except Exception as e:
        logger.error(f"❌ Firebase Init Error: {e}")

if firebase_admin._apps:
    db = firestore.client()

if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)
gmaps_client = googlemaps.Client(key=GOOGLE_MAPS_API_KEY) if GOOGLE_MAPS_API_KEY else None

# 1日あたりの利用上限（コスト保険。正常利用では到達しない値にしてある）
DAILY_LIMITS = {
    "suggest_free": 5,       # 無料: タスク生成（アプリは通常1〜2回/日）
    "suggest_premium": 30,   # 有料: 再生成を多用しても十分
    "travel_premium": 120,   # 有料: 朝の交通監視（15分間隔×数時間でも余裕）
    "weather": 200,          # 天気: フォアグラウンド復帰ごとに1回
}

# ==========================================
# 2. ヘルパー関数
# ==========================================

def get_uid_or_none():
    """AuthorizationヘッダのBearerトークンを検証してUIDを返す。無効ならNone"""
    id_token = request.headers.get("Authorization", "")
    if id_token.startswith("Bearer "):
        try:
            decoded = auth.verify_id_token(id_token.split("Bearer ")[1])
            return decoded["uid"]
        except Exception:
            pass
    return None


def get_user_premium_status(uid):
    """課金状態は Firestore のみを信頼する。
    ※クライアントが送ってくる is_premium は絶対に信用しないこと。
      （以前はリクエストボディ/URLパラメータで誰でも上書きできた）"""
    if not (db and uid):
        return False
    try:
        doc = db.collection("users").document(uid).get()
        return doc.to_dict().get("isPremium", False) if doc.exists else False
    except Exception as e:
        logger.error(f"Premium check error: {e}")
        return False


def check_daily_quota(uid, kind):
    """uidごと・日ごとの利用回数を Firestore でカウントし、上限内なら True。
    Firestoreが使えない場合は安全側（許可）に倒す（サービス全停止を避ける）"""
    if not db:
        return True
    limit = DAILY_LIMITS.get(kind, 100)
    today = datetime.date.today().isoformat()
    field = f"{today}_{kind}"
    ref = db.collection("usage").document(uid)
    try:
        snap = ref.get()
        count = (snap.to_dict() or {}).get(field, 0) if snap.exists else 0
        if count >= limit:
            logger.warning(f"⛔ quota exceeded: uid={uid} kind={kind} count={count}")
            return False
        ref.set({field: firestore.Increment(1)}, merge=True)
        return True
    except Exception as e:
        logger.error(f"Quota check error: {e}")
        return True


def require_auth():
    """認証必須エンドポイントの共通ガード。UID か エラー応答を返す"""
    uid = get_uid_or_none()
    if not uid:
        return None, (jsonify({"error": "Unauthorized"}), 401)
    return uid, None

# ==========================================
# 3. APIエンドポイント
# ==========================================

@app.route("/", methods=["GET"])
def health():
    return "Stellise Backend Running", 200


# --- 天気（要認証。OpenWeatherの無料枠を外部から焼かれないように） ---
@app.route("/get_weather", methods=["GET"])
def get_weather():
    uid, err = require_auth()
    if err:
        return err
    if not check_daily_quota(uid, "weather"):
        return jsonify({"error": "Too Many Requests"}), 429
    if not OPENWEATHER_API_KEY:
        return jsonify({"error": "No API Key"}), 500

    lat, lon = request.args.get("lat"), request.args.get("lon")
    url = "https://api.openweathermap.org/data/2.5/weather"
    try:
        resp = requests.get(
            url,
            params={"lat": lat, "lon": lon, "appid": OPENWEATHER_API_KEY,
                    "units": "metric", "lang": "ja"},
            timeout=10,
        )
        return jsonify(resp.json())
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# --- 交通時間（要認証＋プレミアム限定。Google Mapsは従量課金のため） ---
@app.route("/get_travel_time", methods=["GET"])
def get_travel_time():
    uid, err = require_auth()
    if err:
        return err

    # アプリ設計上、無料ユーザーは端末内MapKitで計算するのでここには来ない。
    # 来た場合は改造クライアント等なので拒否してMaps課金を守る
    if not get_user_premium_status(uid):
        return jsonify({"error": "Premium Required",
                        "duration_seconds": 1800, "has_delay": False,
                        "summary": "プレミアム限定"}), 403

    if not check_daily_quota(uid, "travel_premium"):
        return jsonify({"error": "Too Many Requests",
                        "duration_seconds": 1800, "has_delay": False,
                        "summary": "上限到達"}), 429

    if not gmaps_client:
        logger.error("❌ Google Maps Client is None! Check API Key.")
        return jsonify({"duration_seconds": 1800, "has_delay": False,
                        "summary": "サーバ設定エラー"}), 200

    origin = request.args.get("origin")
    destination = request.args.get("destination")
    mode = request.args.get("mode", "driving")

    try:
        now = datetime.datetime.now()
        logger.info(f"🗺 Requesting Map: {origin} -> {destination} ({mode})")

        matrix = gmaps_client.distance_matrix(
            origins=[origin], destinations=[destination],
            mode=mode, language="ja", departure_time=now,
        )

        # ※アプリ側は {duration_seconds, has_delay, summary} の3点セットで
        #   デコードするため、どの分岐でも必ず has_delay を含めて返すこと
        if matrix["status"] != "OK":
            logger.error(f"❌ Maps API Error: {matrix}")
            return jsonify({"duration_seconds": 1800, "has_delay": False,
                            "summary": f"API Error: {matrix['status']}"}), 200

        elem = matrix["rows"][0]["elements"][0]
        if elem["status"] != "OK":
            logger.error(f"❌ Route Not Found: {elem['status']}")
            return jsonify({"duration_seconds": 1800, "has_delay": False,
                            "summary": f"経路不明 ({elem['status']})"}), 200

        duration = elem["duration"]["value"]
        duration_traffic = elem.get("duration_in_traffic", {"value": duration})["value"]
        delay = duration_traffic - duration
        has_delay = delay > 300

        return jsonify({
            "duration_seconds": duration_traffic,
            "has_delay": has_delay,
            "summary": f"渋滞 (+{int(delay / 60)}分)" if has_delay else "順調",
        })

    except Exception as e:
        logger.error(f"❌ Maps Exception: {e}")
        return jsonify({"duration_seconds": 1800, "has_delay": False,
                        "summary": "取得エラー"}), 200


# --- AIタスク提案（要認証。無料/有料でモデルとクォータを分ける） ---
@app.route("/suggest_tasks", methods=["POST"])
def suggest_tasks():
    uid, err = require_auth()
    if err:
        return err

    data = request.json or {}
    is_premium = get_user_premium_status(uid)  # Firestoreのみを信頼

    if not check_daily_quota(uid, "suggest_premium" if is_premium else "suggest_free"):
        # 429を返すとアプリは端末内フォールバック生成に切り替わる（UXは維持される）
        return jsonify({"error": "Too Many Requests"}), 429

    # トークン費の上限化: プロンプトに入れる件数を制限
    feedback_history = (data.get("feedback_history") or [])[:10]
    master_tasks = [t.get("title") for t in (data.get("user_master_tasks") or [])[:20]]
    calendar_events = (data.get("calendar_events") or [])[:10]

    good_tasks = [f["title"] for f in feedback_history if f.get("is_good")]
    bad_tasks = [f["title"] for f in feedback_history if not f.get("is_good")]

    feedback_prompt = ""
    if good_tasks or bad_tasks:
        feedback_prompt = f"""
        【過去のユーザーの好み（超重要）】
        - ユーザーが喜んだ提案(Good): {good_tasks}
        - ユーザーが不要だと感じた提案(Bad): {bad_tasks}
        -> 上記のBadリストにあるタスクや、それに似たタスクは【絶対に二度と提案しないでください】。
        -> Goodリストにある傾向を学習し、それに沿った気遣いタスクを生成してください。
        """

    if is_premium:
        # 【有料】執事モード
        model_name = "gemini-flash-latest"
        prompt = f"""
        あなたはユーザー専属の、非常に気が利く優秀な執事です。
        以下の「ユーザーの状況」を深く読み取り（汲み取り）、最適な朝のタスクリスト(JSON)を作成してください。
        {feedback_prompt}

        【ユーザーの状況】
        1. 天気: {data.get('weather_info', {}).get('weather', [{}])[0].get('description', '不明')}
           (気温: {data.get('weather_info', {}).get('main', {}).get('temp', 0)}℃)
           -> 雨なら「傘を持つ」タスクを追加したり、移動の準備を早めてください。
           -> 寒いなら「コートを着る」「マフラーを持つ」などを考慮してください。
        2. 昨晩の睡眠スコア: {data.get('sleep_score', '不明')} / 100
           -> 70点未満なら「寝不足」です。準備時間を長めに確保し、気遣いタスクは休息系（白湯を飲む、深呼吸 等）だけに絞り、タスク総数を最小限にしてください。
           -> 90点以上なら「絶好調」です。朝の勉強や運動など、積極的なタスクを提案しても良いでしょう。
        3. 出発時刻: {data.get('departure_time', '指定なし')}
        4. マスタタスク(ルーティン): {master_tasks}
        5. カレンダーの予定: {json.dumps(calendar_events, ensure_ascii=False)}

        【スケジュール作成の絶対ルール（厳守）】
        1. 時間計算:
           - 予定（出発時刻）がある場合: 起床から「出発時刻（{data.get('departure_time', '指定なし')}）」までの間にすべてのタスクが終わるように逆算すること。
           - 予定（出発時刻）が「指定なし」の場合: 起床から「2時間後まで」の間にすべてのタスクが終わるようにゆったりと組むこと。
        2. 時間帯の制限:
           いかなる場合でも、夜や深夜（20:00〜04:00など）の時間は絶対に出力しないこと。必ず「朝（04:00以降）」の時刻を設定すること。
        3. タスクの順番（超重要）:
           提供された「マスタタスク(ルーティン)」の配列の順番を【絶対に】変更せず、上から順番通りにスケジュールを組むこと。AIの判断で勝手に並び替えを行わないでください。
        4. 気遣いタスクの追加:
           マスタタスクの順番を維持した上で、その前後や合間に、天候や睡眠スコアに合わせた「気遣いタスク（傘を持つ、水を飲む 等）」を自然な流れで追加してください。
        5. 最初のタスク（超重要）:
           スケジュールの先頭には必ず、起床直後の寝ぼけた頭でも迷わず実行できる1〜3分のマイクロタスク
           （「コップ一杯の水を飲む」「カーテンを開けて日光を浴びる」等）を1つ置くこと。
           起床直後は認知機能が低下しているため、複雑な判断が必要なタスクを先頭に置いてはいけません。

        【出力ルール】
        - 出発時刻には絶対に間に合わせること。
        - フォーマット: [ {{"title": "タスク名", "time": "HH:MM", "duration": "XX min", "source": "ai"}} ]
        - JSONのみを出力してください。Markdown記法は不要です。
        """
    else:
        # 【無料】シンプルモード（flash-liteでコストを約1/4に）
        model_name = "gemini-flash-lite-latest"
        prompt = f"""
        あなたはユーザーの「朝のルーティン」を作成する優秀なAIアシスタントです。
        以下の予定とタスクから、今日の朝のスケジュールを作成してください。

        予定: {json.dumps(calendar_events, ensure_ascii=False)}
        タスク: {master_tasks}
        出発時刻: {data.get('departure_time', '指定なし')}
        昨晩の睡眠スコア: {data.get('sleep_score', '不明')} / 100
        （70点未満なら寝不足です。新しいタスクは追加せず、各タスクの所要時間と間隔にゆとりを持たせてください）

        【スケジュール作成の絶対ルール（厳守）】
        1. 時間計算:
           - 予定（出発時刻）がある場合: 起床から「出発時刻（{data.get('departure_time', '指定なし')}）」までの間にすべてのタスクが終わるように時間を逆算して組むこと。
           - 予定（出発時刻）が「指定なし」の場合: 起床から「2時間後まで」の間にすべてのタスクが終わるようにゆったりと組むこと。
        2. 時間帯の制限:
           いかなる場合でも、夜や深夜（20:00〜04:00など）の時間は絶対に出力しないこと。必ず「朝（04:00以降）」の時刻を設定すること。
        3. タスクの順番（超重要）:
           提供された「タスク」の配列の順番を【絶対に】変更せず、リストの上から順番通りにスケジュールを組むこと。AIの判断で勝手に並び替えを行わないでください。

        出力: [ {{"title": "...", "time": "HH:MM", "duration": "XX min", "source": "ai"}} ]
        - JSONのみを出力してください。Markdown記法や余計な文章は一切不要です。
        """

    try:
        model = genai.GenerativeModel(
            model_name,
            generation_config={"response_mime_type": "application/json"},
        )
        resp = model.generate_content(prompt)
        tasks = json.loads(resp.text)
        # 形式検証: アプリは [{title,time,duration,source}] を期待する
        if not isinstance(tasks, list):
            return jsonify([])
        return jsonify(tasks)
    except Exception as e:
        logger.error(f"Gemini Error: {e}")
        # エラー時は空配列 → アプリ側が端末内フォールバック生成に切り替わる
        return jsonify([])


# --- 睡眠ログ ---
@app.route("/upload_sleep_log", methods=["POST"])
def upload_sleep_log():
    uid, err = require_auth()
    if err:
        return err
    if not db:
        return jsonify({"error": "Server Unavailable"}), 503

    payload = request.json or {}
    date_key = str(payload.get("date", ""))
    # dateはYYYY-MM-DD形式のみ許可（任意文字列をドキュメントIDにしない）
    try:
        datetime.date.fromisoformat(date_key)
    except ValueError:
        return jsonify({"error": "Invalid date"}), 400
    # 保存サイズの上限（異常データでFirestoreを埋められないように）
    if len(json.dumps(payload)) > 10_000:
        return jsonify({"error": "Payload Too Large"}), 413

    try:
        db.collection("users").document(uid).collection("sleep_logs").document(date_key).set(payload)
        return jsonify({"status": "saved"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
