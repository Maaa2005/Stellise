import backend


def authenticated_client(monkeypatch):
    monkeypatch.setattr(backend, "require_auth", lambda: ("test-user", None))
    return backend.app.test_client()


def test_weather_rejects_missing_coordinates_before_quota(monkeypatch):
    client = authenticated_client(monkeypatch)
    quota_called = False

    def quota(*_args):
        nonlocal quota_called
        quota_called = True
        return True

    monkeypatch.setattr(backend, "check_daily_quota", quota)
    response = client.get("/get_weather")

    assert response.status_code == 400
    assert quota_called is False


def test_weather_rejects_non_finite_coordinates(monkeypatch):
    client = authenticated_client(monkeypatch)
    response = client.get("/get_weather?lat=nan&lon=139.7")
    assert response.status_code == 400


def test_travel_rejects_invalid_input_before_premium_check(monkeypatch):
    client = authenticated_client(monkeypatch)
    premium_checked = False

    def premium(*_args):
        nonlocal premium_checked
        premium_checked = True
        return True

    monkeypatch.setattr(backend, "get_user_premium_status", premium)
    response = client.get("/get_travel_time?origin=&destination=Tokyo&mode=rocket")

    assert response.status_code == 400
    assert premium_checked is False


def test_suggest_rejects_invalid_json_before_quota(monkeypatch):
    client = authenticated_client(monkeypatch)
    monkeypatch.setattr(backend, "GEMINI_API_KEY", "test-key")
    monkeypatch.setattr(backend, "gemini_client", object())
    quota_called = False

    def quota(*_args):
        nonlocal quota_called
        quota_called = True
        return True

    monkeypatch.setattr(backend, "check_daily_quota", quota)
    response = client.post("/suggest_tasks", data="not-json", content_type="text/plain")

    assert response.status_code == 400
    assert quota_called is False


def test_sanitize_tasks_filters_invalid_and_clamps_duration():
    tasks = [
        {"title": "起きる", "time": "06:00", "duration": "5 min"},
        {"title": "朝食", "time": "07:00", "duration": "90 min"},
        {"title": "夕食", "time": "19:00", "duration": "10 min"},
    ]

    assert backend.sanitize_tasks(tasks) == [
        {"title": "朝食", "time": "07:00", "duration": "30 min", "source": "ai"}
    ]


def test_suggest_uses_current_genai_client_and_returns_tasks(monkeypatch):
    client = authenticated_client(monkeypatch)

    class FakeResponse:
        text = '[{"title":"朝食","time":"07:00","duration":"10 min","source":"ai"}]'

    class FakeModels:
        def generate_content(self, *, model, contents, config):
            assert model == "gemini-flash-lite-latest"
            assert "朝のルーティン" in contents
            assert config == {"response_mime_type": "application/json"}
            return FakeResponse()

    class FakeClient:
        models = FakeModels()

    monkeypatch.setattr(backend, "GEMINI_API_KEY", "test-key")
    monkeypatch.setattr(backend, "gemini_client", FakeClient())
    monkeypatch.setattr(backend, "get_user_premium_status", lambda _uid: False)
    monkeypatch.setattr(backend, "check_daily_quota", lambda _uid, _kind: True)

    response = client.post("/suggest_tasks", json={
        "feedback_history": [],
        "user_master_tasks": [{"title": "朝食"}],
        "calendar_events": [],
        "weather_info": None,
        "departure_time": "08:00",
        "sleep_score": 80,
    })

    assert response.status_code == 200
    assert response.get_json() == [
        {"title": "朝食", "time": "07:00", "duration": "10 min", "source": "ai"}
    ]


def test_travel_time_logs_do_not_contain_origin_or_destination(monkeypatch, caplog):
    client = authenticated_client(monkeypatch)
    origin = "ORIGIN-SECRET-1-2-3 Shibuya"
    destination = "DEST-SECRET-4-5-6 Shinjuku"

    class FakeMaps:
        def distance_matrix(self, *, origins, destinations, **_kwargs):
            # 外部APIの応答には住所が含まれるので、エラー応答でも混ぜておく
            return {
                "status": "INVALID_REQUEST",
                "origin_addresses": origins,
                "destination_addresses": destinations,
                "rows": [],
            }

    monkeypatch.setattr(backend, "gmaps_client", FakeMaps())
    monkeypatch.setattr(backend, "get_user_premium_status", lambda _uid: True)
    monkeypatch.setattr(backend, "check_daily_quota", lambda _uid, _kind: True)

    with caplog.at_level("DEBUG"):
        response = client.get("/get_travel_time", query_string={
            "origin": origin, "destination": destination, "mode": "walking",
        })

    assert response.status_code == 200
    assert "Requesting Map" in caplog.text
    assert origin not in caplog.text
    assert destination not in caplog.text
    assert "SECRET" not in caplog.text


def test_travel_time_exception_log_does_not_contain_origin_or_destination(monkeypatch, caplog):
    client = authenticated_client(monkeypatch)
    origin = "ORIGIN-SECRET-1-2-3 Shibuya"
    destination = "DEST-SECRET-4-5-6 Shinjuku"

    class FakeMaps:
        def distance_matrix(self, *, origins, destinations, **_kwargs):
            raise RuntimeError(f"failed: origins={origins} destinations={destinations}")

    monkeypatch.setattr(backend, "gmaps_client", FakeMaps())
    monkeypatch.setattr(backend, "get_user_premium_status", lambda _uid: True)
    monkeypatch.setattr(backend, "check_daily_quota", lambda _uid, _kind: True)

    with caplog.at_level("DEBUG"):
        response = client.get("/get_travel_time", query_string={
            "origin": origin, "destination": destination,
        })

    assert response.status_code == 200
    assert "Maps Exception" in caplog.text
    assert "SECRET" not in caplog.text


def test_sanitize_tasks_log_does_not_contain_task_title(monkeypatch, caplog):
    with caplog.at_level("DEBUG"):
        backend.sanitize_tasks([{"title": "起きる SECRET-TITLE", "time": "06:00"}])

    assert "SECRET-TITLE" not in caplog.text
