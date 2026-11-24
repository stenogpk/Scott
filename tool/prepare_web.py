#!/usr/bin/env python3
import base64
import json
from pathlib import Path

web = Path("web")
index = web / "index.html"

# Decode the same Royal SCOTT artwork used by the Android launcher.
logo_source = Path("assets/scott_launcher.png")
logo_output = web / "assets" / "scott-royal-logo.png"
if not logo_source.is_file():
    raise SystemExit(f"SCOTT logo source not found: {logo_source}")
logo_output.parent.mkdir(parents=True, exist_ok=True)
logo_output.write_bytes(base64.b64decode(logo_source.read_text(encoding="ascii").strip()))
if index.exists():
    html = index.read_text()
    html = html.replace("<title>scott_game</title>", "<title>SCOTT</title>")
    html = html.replace("<title>Flutter Demo</title>", "<title>SCOTT</title>")
    if "<title>" in html:
        import re
        html = re.sub(r"<title>.*?</title>", "<title>SCOTT</title>", html, count=1, flags=re.I|re.S)
    else:
        html = html.replace("</head>", "<title>SCOTT</title></head>")
    tags = '''
    <meta name="description" content="SCOTT — an independent multi-game platform. Developed by Shartendu.">
    <meta property="og:type" content="website">
    <meta property="og:title" content="SCOTT">
    <meta property="og:description" content="SCOTT — an independent multi-game platform. Developed by Shartendu.">
    <meta property="og:image" content="https://stenogpk.github.io/Scott/voice-test/assets/scott-royal-logo.png">
    <meta property="og:image:alt" content="SCOTT Royal S9 playing-card emblem">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:image" content="https://stenogpk.github.io/Scott/voice-test/assets/scott-royal-logo.png">
    <meta name="theme-color" content="#111111">
    '''
    if 'property="og:title"' not in html:
        html = html.replace("</head>", tags + "\n</head>")
    index.write_text(html)

manifest = web / "manifest.json"
if manifest.exists():
    data = json.loads(manifest.read_text())
    data["name"] = "SCOTT"
    data["short_name"] = "SCOTT"
    data["description"] = "SCOTT — an independent multi-game platform. Developed by Shartendu."
    data["background_color"] = "#111111"
    data["theme_color"] = "#111111"
    manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
