#!/usr/bin/env python3
"""Fabrique source.json pour SideStore : appli + notes de patch (onglet News + « Nouveautés » de la version).
usage : make-source.py REPO TAG SIZE DATE > source.json"""
import json, sys, os
repo, tag, size, date = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
here = os.path.dirname(os.path.abspath(__file__))
notes = json.load(open(os.path.join(here, 'patchnotes.json'), encoding='utf-8'))
ver = tag.replace('ios-', '')
build = ver.split('.')[-1]
url = f"https://github.com/{repo}/releases/download/{tag}/LaMathias.ipa"
icon = f"https://raw.githubusercontent.com/{repo}/main/icon.png"
def txt(n): return '\n'.join('• ' + x for x in n['notes'])
last = notes[0] if notes else None
whatsnew = (f"Version {last['v']} — {last['title']}\n{txt(last)}" if last else '')
app = {"name": "La Mathias", "bundleIdentifier": "fr.lamathias.app", "developerName": "La Mathias",
       "subtitle": "Ta voiture, tes trajets", "localizedDescription": "Trajets, conso et OBD pour la Sandero.",
       "iconURL": icon, "tintColor": "00E5FF", "version": ver, "versionDate": date,
       "versionDescription": whatsnew, "downloadURL": url, "size": size,
       "versions": [{"version": ver, "buildVersion": build, "date": date, "localizedDescription": whatsnew,
                     "downloadURL": url, "size": size, "minOSVersion": "16.0"}],
       "appPermissions": {"entitlements": [], "privacy": {}}}
news = [{"title": f"{n['v']} · {n['title']}", "identifier": f"lm-{n['v']}", "caption": txt(n),
         "date": n['date'], "tintColor": "00E5FF", "appID": "fr.lamathias.app", "notify": i == 0}
        for i, n in enumerate(notes[:15])]
src = {"name": "La Mathias", "identifier": "fr.lamathias.source",
       "sourceURL": f"https://github.com/{repo}/releases/latest/download/source.json",
       "iconURL": icon, "tintColor": "00E5FF", "apps": [app], "news": news}
print(json.dumps(src, ensure_ascii=False, indent=1))
