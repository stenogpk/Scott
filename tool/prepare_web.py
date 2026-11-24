#!/usr/bin/env python3
import json
from pathlib import Path

web = Path("web")
index = web / "index.html"
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
    <meta name="twitter:card" content="summary">
    <meta name="theme-color" content="#111111">
    '''
    if 'property="og:title"' not in html:
        html = html.replace("</head>", tags + "\\n</head>")
    index.write_text(html)

manifest = web / "manifest.json"
if manifest.exists():
    data = json.loads(manifest.read_text())
    data["name"] = "SCOTT"
    data["short_name"] = "SCOTT"
    data["description"] = "SCOTT — an independent multi-game platform. Developed by Shartendu."
    data["background_color"] = "#111111"
    data["theme_color"] = "#111111"
    manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\\n")
