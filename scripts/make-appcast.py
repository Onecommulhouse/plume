"""Écrit les notes de version et la fiche des versions (appcast.xml) que Sparkle lit dans Plume."""
import argparse
import email.utils
import html
import xml.dom.minidom

parser = argparse.ArgumentParser()
for name in ("commit", "notes-out", "out", "version", "build", "length", "signature", "url"):
    parser.add_argument(f"--{name}", required=True)
args = parser.parse_args()

# Notes : le message du commit, sans les lignes techniques ni les marqueurs de compilation.
lines = []
for line in open(args.commit, encoding="utf-8").read().splitlines():
    if line.startswith(("Co-Authored-By:", "Claude-Session:")):
        continue
    lines.append(line.replace("[skip ci]", "").rstrip())
notes = "\n".join(lines).strip() or "Améliorations de Plume."
with open(args.notes_out, "w", encoding="utf-8") as f:
    f.write(notes + "\n")

paragraphs = "".join(
    "<p>" + html.escape(block.strip()).replace("\n", "<br>") + "</p>"
    for block in notes.split("\n\n")
    if block.strip()
).replace("]]>", "]]&gt;")

attr = lambda value: html.escape(str(value), quote=True)
appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Plume</title>
    <item>
      <title>Plume {attr(args.version)} ({attr(args.build)})</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{attr(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{attr(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{paragraphs}]]></description>
      <enclosure url="{attr(args.url)}" length="{attr(args.length)}" type="application/octet-stream" sparkle:edSignature="{attr(args.signature)}"/>
    </item>
  </channel>
</rss>
"""
xml.dom.minidom.parseString(appcast.encode("utf-8"))  # échoue si le XML est mal formé
with open(args.out, "w", encoding="utf-8") as f:
    f.write(appcast)
print(f"appcast.xml prêt : Plume {args.version} ({args.build})")
