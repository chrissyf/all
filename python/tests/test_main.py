from app.main import greeting


def test_greets_by_name() -> None:
    assert greeting("world") == "Hello, world!"
