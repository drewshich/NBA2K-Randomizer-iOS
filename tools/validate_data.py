import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
resources = root / "ios/Resources"


def validate_pair(players, details, label):
    assert len(players) == len(details) == 100, f"{label}: expected 100 players and details"
    ids = [p["id"] for p in players]
    assert len(set(ids)) == len(ids), f"{label}: duplicate player identifiers"
    detail_map = {p["id"]: p for p in details}
    assert len(detail_map) == len(details), f"{label}: duplicate details identifiers"
    assert set(ids) == set(detail_map), f"{label}: roster and details do not match"
    for player in players:
        assert player["name"] == detail_map[player["id"]]["name"], f"{label}: player name mismatch"
        assert player["url"].startswith("https://"), f"{label}: invalid player URL"
        for field in ["overall", "threePointRating", "dunkRating"]:
            assert 0 <= player[field]["value"] <= 100, f"{label}: invalid rating"
        assert isinstance(player["height"], int) and player["height"] > 0
        assert isinstance(player["position"], str) and player["position"]
        assert detail_map[player["id"]]["attributes"], f"{label}: missing attributes"
        for group in detail_map[player["id"]]["attributes"]:
            assert isinstance(group["rating"]["value"], int)
            assert all(isinstance(item["value"], int) for item in group["parameters"])


def main():
    for era in ["current", "all_time"]:
        for version in ["2k25", "2k26"]:
            players = json.loads((resources / f"{era}_players_{version}.json").read_text(encoding="utf-8"))
            details = json.loads((resources / f"{era}_players_details_{version}.json").read_text(encoding="utf-8"))
            validate_pair(players, details, f"{era}/{version}")
            print(f"OK: {era}/{version} — {len(players)} players and matching details")


if __name__ == "__main__":
    main()
