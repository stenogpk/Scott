from pathlib import Path
from PIL import Image

ROOT = Path("android/app/src/main/res")
SOURCE = Path("assets/scott_launcher.png")
if not SOURCE.is_file():
    raise SystemExit(f"Launcher image not found: {SOURCE}")

image = Image.open(SOURCE).convert("RGBA")
legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
foreground = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

for density, size in legacy.items():
    folder = ROOT / f"mipmap-{density}"
    folder.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(folder / "ic_launcher.png", optimize=True)

for density, size in foreground.items():
    folder = ROOT / f"mipmap-{density}"
    folder.mkdir(parents=True, exist_ok=True)
    artwork = image.resize((int(size * 0.72), int(size * 0.72)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(artwork, ((size - artwork.width) // 2, (size - artwork.height) // 2))
    canvas.save(folder / "ic_launcher_foreground.png", optimize=True)

adaptive = ROOT / "mipmap-anydpi-v26"
adaptive.mkdir(parents=True, exist_ok=True)
(adaptive / "ic_launcher.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/scott_icon_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n',
    encoding="utf-8",
)
values = ROOT / "values"
values.mkdir(parents=True, exist_ok=True)
(values / "scott_icon_colors.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources><color name="scott_icon_background">#000000</color></resources>\n',
    encoding="utf-8",
)
print("SCOTT launcher icon generated for legacy and adaptive Android launchers.")
