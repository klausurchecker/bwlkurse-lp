<#
  check-site.ps1 - Regressionstest fuer klausurchecker.de (Landingpage + Apps)

  Prueft die LIVE-Seiten gegen site-manifest.json. Kein Browser noetig,
  laeuft lokal (Windows) und in GitHub Actions (ubuntu-latest, pwsh).

  Aufruf:
    pwsh .github/checks/check-site.ps1
    pwsh .github/checks/check-site.ps1 -Nur Fachpraesenz
    pwsh .github/checks/check-site.ps1 -Markdown bericht.md

  Exit-Code 0 = alles gruen, 1 = mindestens ein FEHLER.
  WARNUNGEN allein setzen den Exit-Code nicht.
#>
[CmdletBinding()]
param(
  [string]$Manifest = "$PSScriptRoot/site-manifest.json",
  [string]$Markdown = "",
  [string]$Nur = "",
  [int]$TimeoutSek = 30
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$script:Befunde  = @()
$script:Cache    = @{}
$script:Gemeldet = [System.Collections.Generic.HashSet[string]]::new()

# Ein abgestuerzter Waechter darf NIE als "gruen" durchgehen. Ohne diesen Trap
# endet das Skript beim Fehler und $LASTEXITCODE bleibt auf dem alten Wert stehen.
trap {
  Write-Host ""
  Write-Host "ABBRUCH - der Check selbst ist gescheitert:" -ForegroundColor Red
  Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "  bei: $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
  exit 2
}

function Add-Befund {
  param([ValidateSet("FEHLER","WARNUNG","INFO")][string]$Stufe, [string]$Bereich, [string]$Text)
  $script:Befunde += [pscustomobject]@{ Stufe = $Stufe; Bereich = $Bereich; Text = $Text }
}

function Get-Seite {
  param([string]$Url)
  if ($script:Cache.ContainsKey($Url)) { return $script:Cache[$Url] }
  $erg = [pscustomobject]@{ Url = $Url; Code = 0; Inhalt = ""; Ok = $false }
  # Bis zu 3 Versuche: GitHub Pages drosselt bei schnellen Serien. Ohne Retry
  # verschwinden Befunde still, weil die Pruefung die Seite dann ueberspringt.
  for ($versuch = 1; $versuch -le 3; $versuch++) {
    try {
      $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSek
      $erg.Code = [int]$r.StatusCode; $erg.Inhalt = [string]$r.Content; $erg.Ok = ($erg.Code -eq 200)
      break
    } catch {
      try { $erg.Code = [int]$_.Exception.Response.StatusCode } catch { $erg.Code = 0 }
      # 404 ist eine echte Antwort - nicht erneut versuchen.
      if ($erg.Code -ge 400 -and $erg.Code -lt 500) { break }
      if ($versuch -lt 3) { Start-Sleep -Milliseconds (400 * $versuch) }
    }
  }
  $script:Cache[$Url] = $erg
  return $erg
}

# Seite fuer eine inhaltliche Pruefung holen. Ist sie nicht abrufbar, wird das
# GEMELDET statt still uebersprungen - sonst taeuscht ein gruener Lauf Sicherheit vor.
function Get-SeiteFuerPruefung {
  param([string]$Url, [string]$Bereich, [string]$Was)
  $s = Get-Seite -Url $Url
  if (-not $s.Ok -and -not $script:Gemeldet.Contains($Url)) {
    $script:Gemeldet.Add($Url) | Out-Null
    Add-Befund WARNUNG $Bereich "$Was nicht pruefbar - Abruf ergab HTTP $($s.Code): $Url"
  }
  return $s
}

function Test-Erreichbar {
  param([string]$Url, [string]$Bereich, [string]$Was)
  $s = Get-Seite -Url $Url
  if (-not $s.Ok) { Add-Befund FEHLER $Bereich "$Was nicht erreichbar (HTTP $($s.Code)): $Url" }
  return $s
}

function Soll-Laufen { param([string]$Name) return ([string]::IsNullOrWhiteSpace($Nur) -or $Nur -eq $Name) }

# Umlaute + JS-Unicode-Escapes vereinheitlichen, damit Namensvergleiche nicht an
# "Mikrooekonomie" vs "Mikroökonomik" scheitern.
function Normalisiere {
  param([string]$Text)
  if (-not $Text) { return "" }
  $t = $Text -replace '\\u00f6', 'ö' -replace '\\u00e4', 'ä' -replace '\\u00fc', 'ü' -replace '\\u00df', 'ß'
  $t = $t -replace 'ö', 'oe' -replace 'ä', 'ae' -replace 'ü', 'ue' -replace 'ß', 'ss'
  return $t.ToLower()
}

# ---------------------------------------------------------------- Manifest
if (-not (Test-Path $Manifest)) { Write-Error "Manifest nicht gefunden: $Manifest"; exit 2 }
$Cfg      = Get-Content $Manifest -Raw | ConvertFrom-Json
$Basis  = $Cfg.basis.TrimEnd("/")
$Aktive = @($Cfg.faecher | Where-Object { $_.aktiv })

Write-Host ""
Write-Host "Klausurchecker Site-Check - $($Aktive.Count) aktive Faecher: $(($Aktive.kuerzel) -join ', ')" -ForegroundColor Cyan
Write-Host ("=" * 78)

# ---------------------------------------------------------- 1 Erreichbarkeit
if (Soll-Laufen "Erreichbarkeit") {
  Write-Host "1/8  Erreichbarkeit ..." -NoNewline
  foreach ($g in $Cfg.globaleSeiten) {
    $s = Test-Erreichbar "$Basis/$($g.pfad)" "Erreichbarkeit" "Seite $($g.pfad)"
    if ($s.Ok -and $g.titelEnthaelt) {
      $t = [regex]::Match($s.Inhalt, '(?is)<title>(.*?)</title>').Groups[1].Value
      if ($t -notmatch [regex]::Escape($g.titelEnthaelt)) {
        Add-Befund WARNUNG "Erreichbarkeit" "$($g.pfad): Titel '$t' enthaelt nicht '$($g.titelEnthaelt)'"
      }
    }
  }
  foreach ($f in $Aktive) {
    Test-Erreichbar "$Basis/$($f.fachseite)"     "Erreichbarkeit" "$($f.kuerzel) Fachseite"    | Out-Null
    Test-Erreichbar "$Basis/$($f.gratislektion)" "Erreichbarkeit" "$($f.kuerzel) Gratis-Lektion" | Out-Null
    Test-Erreichbar $f.app                       "Erreichbarkeit" "$($f.kuerzel) App"          | Out-Null
    if ($f.appRedirect) {
      $s = Get-Seite "$Basis/$($f.appRedirect)"
      if (-not $s.Ok) { Add-Befund FEHLER "Erreichbarkeit" "$($f.kuerzel): Redirect-Stub /$($f.appRedirect) fehlt (HTTP $($s.Code)) - anmelden.html verweist dorthin" }
    }
    foreach ($p in $f.stripe.PSObject.Properties) {
      $s = Get-Seite $p.Value
      if (-not $s.Ok) { Add-Befund FEHLER "Erreichbarkeit" "$($f.kuerzel) Stripe-Link '$($p.Name)' tot (HTTP $($s.Code)): $($p.Value)" }
    }
  }
  Write-Host " fertig"
}

# ------------------------------------------------------------ 2 Tote Links
if (Soll-Laufen "ToteLinks") {
  Write-Host "2/8  Tote Links ..." -NoNewline
  $bereichName = "ToteLinks"
  $seiten = @($Cfg.globaleSeiten.pfad) + @($Aktive.fachseite) + @($Aktive.gratislektion)
  foreach ($pfad in ($seiten | Sort-Object -Unique)) {
    $s = Get-SeiteFuerPruefung "$Basis/$pfad" $bereichName $pfad
    if (-not $s.Ok) { continue }
    $treffer = [regex]::Matches($s.Inhalt, '(?i)href\s*=\s*"([^"#][^"]*)"')
    $ziele = @()
    foreach ($t in $treffer) { $ziele += $t.Groups[1].Value }
    foreach ($z in ($ziele | Sort-Object -Unique)) {
      if ($z -match '^(javascript:|mailto:|tel:|data:|#)') { continue }
      # In JS zusammengebaute hrefs (" ' + esc(x) + '.html ") sind keine echten Ziele.
      if ($z -match "[\s'+()]" -or $z -match '\{\{') { continue }
      if ($z -match '^https?://' -and $z -notmatch 'klausurchecker\.de|buy\.stripe\.com') { continue }
      $abs = if ($z -match '^https?://') { $z } else { "$Basis/$($z.TrimStart('/'))" }
      $r = Get-Seite $abs
      if (-not $r.Ok) { Add-Befund FEHLER "ToteLinks" "$pfad verlinkt auf HTTP $($r.Code): $abs" }
    }
  }
  Write-Host " fertig"
}

# -------------------------------------------------------- 3 Fach-Praesenz LP
if (Soll-Laufen "Fachpraesenz") {
  Write-Host "3/8  Fach-Praesenz auf der Landingpage ..." -NoNewline
  foreach ($f in $Aktive) {
    foreach ($pfad in $Cfg.regeln.fachMussVorkommenAuf) {
      $s = Get-SeiteFuerPruefung "$Basis/$pfad" "Fachpraesenz" $pfad
      if (-not $s.Ok) { continue }
      if ($s.Inhalt -notmatch [regex]::Escape($f.kuerzel)) {
        Add-Befund FEHLER "Fachpraesenz" "$pfad erwaehnt $($f.kuerzel) ueberhaupt nicht - Nutzer dieses Fachs finden ihren Kurs dort nicht"
      }
    }
    if ($Cfg.regeln.fachMussAufAnderenFachseitenVorkommen) {
      foreach ($andere in ($Aktive | Where-Object { $_.kuerzel -ne $f.kuerzel })) {
        $s = Get-SeiteFuerPruefung "$Basis/$($andere.fachseite)" "Fachpraesenz" $andere.fachseite
        if (-not $s.Ok) { continue }
        if ($s.Inhalt -notmatch [regex]::Escape($f.fachseite)) {
          Add-Befund WARNUNG "Fachpraesenz" "$($andere.fachseite) verlinkt $($f.fachseite) nicht - kein Wechsel zu $($f.kuerzel) moeglich"
        }
      }
    }
  }
  Write-Host " fertig"
}

# -------------------------------------------------- 4 Fach-Liste in den Apps
if (Soll-Laufen "AppFaecher") {
  Write-Host "4/8  Fach-Liste in den Apps ..." -NoNewline
  if ($Cfg.regeln.appsMuessenAlleFaecherFuehren) {
    foreach ($f in $Aktive) {
      $s = Get-SeiteFuerPruefung $f.app "AppFaecher" "$($f.kuerzel)-App"
      if (-not $s.Ok) { continue }
      $blk = [regex]::Match($s.Inhalt, '(?s)FAECHER\s*:\s*\[(.*?)\]')
      if (-not $blk.Success) { Add-Befund WARNUNG "AppFaecher" "$($f.kuerzel)-App: FAECHER-Liste nicht gefunden (Struktur geaendert?)"; continue }
      $gefunden = @{}
      foreach ($e in [regex]::Matches($blk.Groups[1].Value, '\{\s*code\s*:\s*"([^"]+)"\s*,\s*sub\s*:\s*"([^"]*)"')) {
        $gefunden[$e.Groups[1].Value] = $e.Groups[2].Value
      }
      foreach ($soll in $Aktive) {
        if (-not $gefunden.ContainsKey($soll.kuerzel)) {
          Add-Befund FEHLER "AppFaecher" "$($f.kuerzel)-App fuehrt $($soll.kuerzel) nicht in der Fach-Liste - kein Wechsel/Cross-Sell zu diesem Fach"
        } else {
          $ist   = Normalisiere $gefunden[$soll.kuerzel]
          $stamm = Normalisiere (($soll.appName -split ' ')[0])
          $stamm = $stamm.Substring(0, [Math]::Min(5, $stamm.Length))
          if ($ist -and ($ist -notlike "*$stamm*")) {
            Add-Befund FEHLER "AppFaecher" "$($f.kuerzel)-App: $($soll.kuerzel) traegt den falschen Namen '$($gefunden[$soll.kuerzel])' (erwartet etwas mit '$($soll.appName)')"
          }
        }
      }
      foreach ($k in $gefunden.Keys) {
        if ($k -notin $Aktive.kuerzel) { Add-Befund WARNUNG "AppFaecher" "$($f.kuerzel)-App fuehrt unbekanntes Fach '$k'" }
      }

      # Die SICHTBARE Kursliste ist eine zweite, unabhaengige Struktur (Markup, nicht
      # CFG.FAECHER). Genau sie sieht der Nutzer beim Fachwechsel - sie muss getrennt
      # geprueft werden, sonst faellt ein Bruch nur in einer der beiden Listen auf.
      $kursliste = @{}
      foreach ($e in [regex]::Matches($s.Inhalt, '<a\b([^>]*)>\s*<span>\s*<b>([A-Z]{4})</b>\s*&middot;\s*([^<]+)</span>')) {
        $kursliste[$e.Groups[2].Value] = [pscustomobject]@{
          Name   = $e.Groups[3].Value.Trim()
          Aktiv  = ($e.Groups[1].Value -match 'aria-current')
        }
      }
      if ($kursliste.Count -eq 0) {
        Add-Befund WARNUNG "AppFaecher" "$($f.kuerzel)-App: sichtbare Kursliste nicht gefunden (Markup geaendert?)"
      } else {
        foreach ($soll in $Aktive) {
          if (-not $kursliste.ContainsKey($soll.kuerzel)) {
            Add-Befund FEHLER "AppFaecher" "$($f.kuerzel)-App: $($soll.kuerzel) fehlt in der sichtbaren Kursliste - der Nutzer kann nicht dorthin wechseln"
          }
        }
        # NICHT $aktive nennen - das wuerde case-insensitiv $Aktive (die Fachliste) ueberschreiben.
        $aktivMarkiert = @($kursliste.Keys | Where-Object { $kursliste[$_].Aktiv })
        if ($aktivMarkiert.Count -ne 1) {
          Add-Befund FEHLER "AppFaecher" "$($f.kuerzel)-App: $($aktivMarkiert.Count) Eintraege als 'aktiv' markiert (genau 1 erwartet)"
        } elseif ($aktivMarkiert[0] -ne $f.kuerzel) {
          Add-Befund FEHLER "AppFaecher" "$($f.kuerzel)-App markiert '$($aktivMarkiert[0])' als aktives Fach statt sich selbst"
        }
      }
    }
  }
  Write-Host " fertig"
}

# ------------------------------------------------- 5 Kauf-CTA-Farblogik
if (Soll-Laufen "Farblogik") {
  Write-Host "5/8  Kauf-CTA-Farblogik ..." -NoNewline
  $klassen = @($Cfg.regeln.kaufButtonKlassen)
  $bereichName = "Farblogik"
  $seiten  = @($Aktive.fachseite) + @("preise.html") + @($Aktive.gratislektion)
  foreach ($pfad in ($seiten | Sort-Object -Unique)) {
    $s = Get-SeiteFuerPruefung "$Basis/$pfad" $bereichName $pfad
    if (-not $s.Ok) { continue }
    # Nur Elemente pruefen, die sich als Button ausgeben (class enthaelt "btn").
    # Reine Textlinks in Kapitel-Listen sind keine CTAs und brauchen die Kaufklasse nicht.
    foreach ($a in [regex]::Matches($s.Inhalt, '(?is)<a\b([^>]*href="https://buy\.stripe\.com/[^"]+"[^>]*)>')) {
      $attr = $a.Groups[1].Value
      if ($attr -notmatch '(?i)class="[^"]*\bbtn\b') { continue }
      $markiert = $false
      foreach ($k in $klassen) { if ($attr -match [regex]::Escape($k)) { $markiert = $true; break } }
      if (-not $markiert) {
        $href = [regex]::Match($attr, 'href="([^"]+)"').Groups[1].Value
        Add-Befund FEHLER "Farblogik" "${pfad}: Kauf-Button ohne Kaufklasse ($($klassen -join '/')) - sieht damit kostenlos aus: $href"
      }
    }
  }
  Write-Host " fertig"
}

# ------------------------------- 5b Kauf-Einstieg zeigt auf die Preisliste
if ((Soll-Laufen "Farblogik") -and $Cfg.regeln.preiszielMussPreisseiteSein) {
  foreach ($f in $Aktive) {
    $s = Get-SeiteFuerPruefung "$Basis/$($f.fachseite)" "Farblogik" $f.fachseite
    if (-not $s.Ok) { continue }
    $pz = [regex]::Match($s.Inhalt, '<body[^>]*data-preisziel="([^"]*)"')
    if (-not $pz.Success) {
      Add-Befund WARNUNG "Farblogik" "$($f.fachseite): kein data-preisziel am body - der Kauf-Button faellt auf den Seitenanker zurueck"
    } else {
      $ziel = $pz.Groups[1].Value
      if ($ziel -notmatch 'preise\.html') {
        Add-Befund FEHLER "Farblogik" "$($f.fachseite): data-preisziel='$ziel' zeigt nicht auf preise.html - der Kauf-Button springt nur innerhalb der Seite, die Preisliste wird nie erreicht"
      } elseif (-not $f.gratisFach -and $ziel -notmatch "kurs=$($f.kuerzel.ToLower())") {
        Add-Befund WARNUNG "Farblogik" "$($f.fachseite): data-preisziel='$ziel' ohne 'kurs=$($f.kuerzel.ToLower())' - auf preise.html steht dann ein fremdes Fach oben"
      }
    }
    # Der Sticky-Balken traegt seinen Kauf-Link fest im Markup, unabhaengig vom body-Attribut.
    $sticky = [regex]::Match($s.Inhalt, '(?s)<div class="scta" id="v2Scta">(.*?)</div>')
    if ($sticky.Success) {
      foreach ($a in [regex]::Matches($sticky.Groups[1].Value, '<a\b[^>]*class="[^"]*btn-kauf[^"]*"[^>]*href="([^"]+)"')) {
        if ($a.Groups[1].Value -notmatch 'preise\.html') {
          Add-Befund FEHLER "Farblogik" "$($f.fachseite): Sticky-Kaufbutton zeigt auf '$($a.Groups[1].Value)' statt auf preise.html"
        }
      }
    }
  }
}

# ----------------------------------------- 6 Stripe-Links fachrein halten
if (Soll-Laufen "StripeZuordnung") {
  Write-Host "6/8  Stripe-Zuordnung ..." -NoNewline
  if ($Cfg.regeln.keineFremdenStripeLinksAufFachseite) {
    foreach ($f in $Aktive) {
      $eigene = @(); foreach ($p in $f.stripe.PSObject.Properties) { $eigene += $p.Value }
      foreach ($ort in @(@{p = $f.fachseite; n = "Fachseite" }, @{p = $f.gratislektion; n = "Gratis-Lektion" })) {
        $s = Get-SeiteFuerPruefung "$Basis/$($ort.p)" "StripeZuordnung" $ort.p
        if (-not $s.Ok) { continue }
        foreach ($sl in [regex]::Matches($s.Inhalt, 'https://buy\.stripe\.com/[A-Za-z0-9]+')) {
          if ($sl.Value -notin $eigene) {
            $fremd = ($Cfg.faecher | Where-Object { $_.stripe.PSObject.Properties.Value -contains $sl.Value } | Select-Object -First 1).kuerzel
            Add-Befund FEHLER "StripeZuordnung" "$($ort.p) ($($f.kuerzel) $($ort.n)) enthaelt fremden Stripe-Link$(if ($fremd) { " von $fremd" }): $($sl.Value)"
          }
        }
      }
      $inApp = Get-SeiteFuerPruefung $f.app "StripeZuordnung" "$($f.kuerzel)-App"
      if ($inApp.Ok) {
        foreach ($sl in [regex]::Matches($inApp.Inhalt, 'https://buy\.stripe\.com/[A-Za-z0-9]+')) {
          if ($sl.Value -notin $eigene) { Add-Befund FEHLER "StripeZuordnung" "$($f.kuerzel)-App enthaelt fachfremden Stripe-Link: $($sl.Value)" }
        }
      }
    }
  }
  Write-Host " fertig"
}

# ------------------------------------------- 7 Verbotene / veraltete Texte
if (Soll-Laufen "Texte") {
  Write-Host "7/8  Veraltete Texte & Platzhalter ..." -NoNewline
  $bereichName = "Texte"
  $alleSeiten = @($Cfg.globaleSeiten.pfad) + @($Aktive.fachseite) + @($Aktive.gratislektion)
  foreach ($pfad in ($alleSeiten | Sort-Object -Unique)) {
    $s = Get-SeiteFuerPruefung "$Basis/$pfad" $bereichName $pfad
    if (-not $s.Ok) { continue }
    foreach ($v in $Cfg.regeln.verboteneStrings) {
      if ($v.nurAufAnzahl -and $Aktive.Count -eq $v.nurAufAnzahl) { continue }
      if ($s.Inhalt -match [regex]::Escape($v.text)) {
        Add-Befund FEHLER "Texte" "$pfad enthaelt '$($v.text)', es gibt aber $($Aktive.Count) Faecher - Text zaehlt falsch"
      }
    }
    foreach ($nl in $Cfg.nichtLive) {
      if ($s.Inhalt -match "['`"/]$nl\.html") {
        Add-Befund WARNUNG "Texte" "$pfad verweist auf $nl.html - dieses Fach ist nicht live (404, evtl. nur in JS-Daten)"
      }
    }

    # Das Buchungsmodul baut Links aus einer JS-Liste: faecher: [ {k:'OMIK',n:'...'}, ... ].
    # Ein Kuerzel ohne Live-Fachseite wird dort zu einem 404, sobald das Modul geoeffnet wird.
    # Kommt in zwei Schreibweisen vor: {k:'OMIK',...} und {"k":"OMIK",...}.
    # Alle Vorkommen zusammenfassen; ein Kommentar-Treffer liefert einfach nichts.
    $inArray = @()
    foreach ($blk in [regex]::Matches($s.Inhalt, "(?s)faecher\s*:\s*\[(.*?)\]")) {
      foreach ($e in [regex]::Matches($blk.Groups[1].Value, '["'']?k["'']?\s*:\s*["'']([A-Z]+)["'']')) {
        $inArray += $e.Groups[1].Value
      }
    }
    if ($inArray.Count -gt 0) {
      # Doppelte Kuerzel = sicheres Zeichen fuer eine blinde Fabrik-Ersetzung
      # (ein Fach-Slot wurde mit einem anderen Kuerzel ueberschrieben).
      foreach ($dup in ($inArray | Group-Object | Where-Object { $_.Count -gt 1 })) {
        Add-Befund FEHLER "Texte" "$pfad fuehrt '$($dup.Name)' $($dup.Count)x in der JS-Fachliste - ein Fach-Slot wurde ueberschrieben (Fabrik-Ersetzung)"
      }
      foreach ($k in ($inArray | Sort-Object -Unique)) {
        if ($k -notin $Aktive.kuerzel) {
          Add-Befund WARNUNG "Texte" "$pfad fuehrt '$k' in der JS-Fachliste - dessen Seite $($k.ToLower()).html ist 404 (Blindgaenger im Buchungsmodul)"
        }
      }
      foreach ($f in $Aktive) {
        if ($f.kuerzel -notin $inArray) {
          Add-Befund WARNUNG "Texte" "$pfad fuehrt $($f.kuerzel) NICHT in der JS-Fachliste - Fach fehlt im Buchungsmodul"
        }
      }
    }
  }
  Write-Host " fertig"
}

# ------------------------------------------------ 8 Anmeldekette (Signup)
if ((Soll-Laufen "Signup") -and $Cfg.signup) {
  Write-Host "8/8  Anmeldekette ..." -NoNewline
  $sg = $Cfg.signup

  # a) Die Edge-Functions muessen antworten. OPTIONS ist der CORS-Preflight und
  #    voellig nebenwirkungsfrei - es wird nichts angelegt und nichts versendet.
  foreach ($fn in $sg.funktionen) {
    $u = "$($sg.funktionsBasis)/$fn"
    $code = 0
    try {
      $r = Invoke-WebRequest -Uri $u -Method Options -TimeoutSec $TimeoutSek -UseBasicParsing -Headers @{
        "Origin" = "https://www.klausurchecker.de"; "Access-Control-Request-Method" = "POST"
        "Access-Control-Request-Headers" = "content-type"
      }
      $code = [int]$r.StatusCode
    } catch { try { $code = [int]$_.Exception.Response.StatusCode } catch { $code = 0 } }
    if ($code -lt 200 -or $code -ge 300) {
      Add-Befund FEHLER "Signup" "Edge-Function '$fn' antwortet nicht (OPTIONS $code) - Anmeldung/Login betroffen: $u"
    }
  }

  # b) Jede Seite mit Anmeldeformular muss ihr EIGENES Kuerzel in der Fach-Erkennung
  #    fuehren. Fehlt es, wird die Anmeldung unter dem falschen Fach verbucht - der
  #    Nutzer meldet sich fuer Management an und landet im Fallback-Fach.
  foreach ($f in $Aktive) {
    foreach ($pfad in @($f.fachseite, $f.gratislektion)) {
      $s = Get-SeiteFuerPruefung "$Basis/$pfad" "Signup" $pfad
      if (-not $s.Ok) { continue }
      $hatFormular = $s.Inhalt -match [regex]::Escape($sg.formularAktionEnthaelt)
      if (-not $hatFormular) {
        Add-Befund WARNUNG "Signup" "$pfad hat kein Anmeldeformular auf '$($sg.formularAktionEnthaelt)' - Einstieg ins Konto fehlt dort"
        continue
      }
      $fd = [regex]::Match($s.Inhalt, 'var\s+FACH\s*=\s*\(location\.pathname\.match\(/\(([^)]*)\)/\)\s*\|\|\s*\[\]\)\[1\]\s*\|\|\s*"([a-z]+)"')
      if (-not $fd.Success) {
        Add-Befund WARNUNG "Signup" "$pfad : Fach-Erkennung nicht gefunden (Struktur geaendert?)"
        continue
      }
      $kuerzel  = $f.kuerzel.ToLower()
      $liste    = $fd.Groups[1].Value -split '\|'
      $fallback = $fd.Groups[2].Value
      if ($kuerzel -notin $liste) {
        Add-Befund FEHLER "Signup" "$pfad : eigenes Kuerzel '$kuerzel' fehlt in der Fach-Erkennung ($($fd.Groups[1].Value)) - Anmeldung wuerde als '$fallback' verbucht"
      }
      # Der Fallback muss ein lebendes Fach sein, sonst laeuft er ins Leere.
      if ($fallback -notin ($Aktive.kuerzel | ForEach-Object { $_.ToLower() })) {
        Add-Befund FEHLER "Signup" "$pfad : Fallback-Fach '$fallback' ist kein aktives Fach"
      }
    }
  }

  # c) Die Bestaetigungsseite ist das, was der Nutzer nach dem Mail-Klick sieht.
  #    Fehlt dort ein Fach, denkt der Nutzer, sein Kurs gehoere nicht dazu.
  $best = Get-SeiteFuerPruefung "$Basis/bestaetigt.html" "Signup" "bestaetigt.html"
  if ($best.Ok) {
    foreach ($f in $Aktive) {
      if ($best.Inhalt -notmatch [regex]::Escape($f.kuerzel)) {
        Add-Befund FEHLER "Signup" "bestaetigt.html nennt $($f.kuerzel) nicht - wer sich fuer dieses Fach anmeldet, sieht seinen Kurs nach der Bestaetigung nicht"
      }
    }
  }

  # d) Alle Apps muessen auf dasselbe Backend zeigen und ihren eigenen Fachcode fuehren.
  #    Ein halb migrierter Key oder ein kopierter Fachcode kippt den Login lautlos.
  foreach ($f in $Aktive) {
    $s = Get-SeiteFuerPruefung $f.app "Signup" "$($f.kuerzel)-App"
    if (-not $s.Ok) { continue }
    if ($s.Inhalt -notmatch [regex]::Escape($sg.appBackendUrl)) {
      Add-Befund FEHLER "Signup" "$($f.kuerzel)-App zeigt nicht auf $($sg.appBackendUrl) - Login unmoeglich"
    }
    if ($s.Inhalt -notmatch [regex]::Escape($sg.appAnonPraefix)) {
      Add-Befund FEHLER "Signup" "$($f.kuerzel)-App nutzt keinen Key mit Praefix '$($sg.appAnonPraefix)' (alter Legacy-JWT?) - Login bricht bei der Key-Rotation"
    }
    $fc = [regex]::Match($s.Inhalt, 'data-fachcode="([A-Z]+)"')
    if (-not $fc.Success) {
      Add-Befund WARNUNG "Signup" "$($f.kuerzel)-App: kein data-fachcode im Login-Overlay gefunden"
    } elseif ($fc.Groups[1].Value -ne $f.kuerzel) {
      Add-Befund FEHLER "Signup" "$($f.kuerzel)-App traegt data-fachcode='$($fc.Groups[1].Value)' - Login schaltet das falsche Fach frei"
    }
  }
  Write-Host " fertig"
}

# --------------------------------------------------------------- Bericht
$fehler   = @($script:Befunde | Where-Object { $_.Stufe -eq "FEHLER" })
$warnung  = @($script:Befunde | Where-Object { $_.Stufe -eq "WARNUNG" })

Write-Host ""
Write-Host ("=" * 78)
if ($fehler.Count -eq 0 -and $warnung.Count -eq 0) {
  Write-Host "ALLES GRUEN - $($script:Cache.Count) URLs geprueft, keine Beanstandung." -ForegroundColor Green
} else {
  foreach ($grp in ($script:Befunde | Group-Object Bereich)) {
    Write-Host ""
    Write-Host "[$($grp.Name)]" -ForegroundColor Yellow
    foreach ($b in $grp.Group) {
      $farbe = if ($b.Stufe -eq "FEHLER") { "Red" } else { "DarkYellow" }
      Write-Host ("  {0,-8} {1}" -f $b.Stufe, $b.Text) -ForegroundColor $farbe
    }
  }
  Write-Host ""
  Write-Host ("Ergebnis: $($fehler.Count) Fehler, $($warnung.Count) Warnungen, $($script:Cache.Count) URLs geprueft.") -ForegroundColor $(if ($fehler.Count) { "Red" } else { "DarkYellow" })
}
Write-Host ("=" * 78)

if ($Markdown) {
  $md = @("# Site-Check klausurchecker.de", "", "Geprueft: $($script:Cache.Count) URLs - **$($fehler.Count) Fehler, $($warnung.Count) Warnungen**", "")
  if ($script:Befunde.Count -eq 0) { $md += "Alles gruen." }
  foreach ($grp in ($script:Befunde | Group-Object Bereich)) {
    $md += "## $($grp.Name)"
    foreach ($b in $grp.Group) { $md += "- **$($b.Stufe)** - $($b.Text)" }
    $md += ""
  }
  $md -join "`n" | Set-Content -Path $Markdown -Encoding UTF8
  Write-Host "Bericht geschrieben: $Markdown"
}

exit ([int]($fehler.Count -gt 0))
