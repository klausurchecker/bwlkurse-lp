# Site-Check — der Waechter fuer klausurchecker.de

Ersetzt das manuelle Durchklicken nach jedem Deploy und nach jedem neuen Fach.

## Die drei Teile

| Datei | Rolle |
|---|---|
| `site-manifest.json` | **Die Wahrheit.** Welche Faecher es gibt, welche Seiten/Apps/Stripe-Links dazugehoeren, welche Regeln gelten. |
| `check-site.ps1` | **Der Pruefer.** Holt die LIVE-Seiten und vergleicht sie mit dem Manifest. |
| `../workflows/site-check.yml` | **Die Automatik.** Taeglich 08:00 Berlin + nach jedem Push auf `main`. Bei Fehlern: GitHub-Issue. |

## Bei einem neuen Fach: genau ein Eintrag

Im Manifest unter `faecher` einen Block ergaenzen (Kuerzel, Fachseite, Gratis-Lektion,
App-URL, Stripe-Links). Ab dann prueft die Automatik das neue Fach ueberall mit —
Startseite, Preise, Anmeldung, Bestaetigung, Fach-Listen der Apps, Stripe-Zuordnung.

Solange ein Fach noch nicht live ist: `"aktiv": false` setzen. Kuerzel ohne Seite
gehoeren nach `nichtLive` (dann meldet der Check sie als Blindgaenger statt als Fehler).

## Lokal starten

```powershell
.\pruefen.ps1                    # alles (im Projektroot)
.\pruefen.ps1 -Nur Fachpraesenz  # nur ein Bereich
.\pruefen.ps1 -Bericht           # schreibt analytics\site-check-<datum>.md
```

Bereiche: `Erreichbarkeit`, `ToteLinks`, `Fachpraesenz`, `AppFaecher`, `Farblogik`,
`StripeZuordnung`, `Texte`.

Exit-Code 0 = gruen, 1 = mindestens ein FEHLER. Warnungen allein sind nicht rot.

## Was geprueft wird

1. **Erreichbarkeit** — jede Seite, jede App, jeder Stripe-Link, jeder `/app/<fach>/`-Stub → HTTP 200
2. **ToteLinks** — jeder interne Link auf jeder Seite → HTTP 200
3. **Fachpraesenz** — jedes aktive Fach kommt auf Startseite, Preise, Anmeldung und
   Bestaetigungsseite vor und ist von den anderen Fachseiten erreichbar
4. **AppFaecher** — jede App fuehrt **alle** Faecher in ihrer `FAECHER`-Liste, mit richtigem Namen
5. **Farblogik** — jeder Kauf-CTA traegt eine Kaufklasse (`btn-kauf` bzw. `pkbtn`), sieht also
   nicht kostenlos aus. Siehe Memory `cta-farblogik`.
6. **StripeZuordnung** — auf einer Fachseite stehen nur die Stripe-Links dieses Fachs
   (faengt Copy-Paste-Regressionen beim Klonen)
7. **Texte** — Zahlwoerter wie „alle drei", die bei einem vierten Fach falsch werden;
   doppelte Kuerzel in den JS-Fachlisten (= ein Fach-Slot wurde von der Fabrik ueberschrieben);
   Verweise auf noch nicht live geschaltete Faecher

## Zwei Fallen, die hier schon zugeschlagen haben

- **Kein stilles Ueberspringen.** Ist eine Seite nicht abrufbar, meldet der Check das
  („nicht pruefbar") statt sie zu ignorieren — sonst taeuscht ein gruener Lauf Sicherheit vor.
  `Get-Seite` versucht es bis zu 3-mal, weil GitHub Pages bei schnellen Serien drosselt.
- **PowerShell-Variablen sind case-insensitiv.** Eine Schleifenvariable `$m` ueberschreibt
  ein Manifest in `$M`. Genau das hat hier dazu gefuehrt, dass Sektion 7 nur noch 8 statt
  17 Seiten geprueft hat — ohne jede Fehlermeldung. Deshalb heisst das Manifest `$Cfg`.

## Was der Check NICHT kann

Er liest nur HTML. Ob ein Element **sichtbar** ist (nicht in einem `hidden`-Container haengt)
und welche Farbe es tatsaechlich hat, entscheidet erst der Browser — die Lektionsseiten setzen
ihre `kauf`-Klasse z. B. zur Laufzeit per JS. Fuer solche Fragen bleibt eine Browser-Pruefung
noetig; Fallstricke dazu in Memory `browser-messfallstrick`.
