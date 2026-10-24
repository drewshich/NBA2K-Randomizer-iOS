import json
import subprocess

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
phones = [device for runtime, items in devices["devices"].items() if "iOS" in runtime
          for device in items if device.get("isAvailable") and "iPhone" in device["name"]]
if not phones:
    raise SystemExit("No available iPhone simulator was found on this Mac runner")
selected = phones[0]
print("id=" + selected["udid"])
print("name=" + selected["name"])
