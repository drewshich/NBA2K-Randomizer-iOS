import base64
from pathlib import Path

root = Path(__file__).resolve().parent.parent
icon = root / "ios/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
icon.parent.mkdir(parents=True, exist_ok=True)
icon.write_bytes(base64.b64decode((root / "ios/AppIcon.base64").read_text()))
print("Prepared iPhone app icon")
