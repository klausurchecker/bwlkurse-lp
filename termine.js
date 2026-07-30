/* ===================================================================
   termine.js — die einzige Stelle, an der Klausurtermine stehen.

   Warum es diese Datei gibt:
   Vorher lagen die Termine als feste Daten in 13 HTML-Dateien. Die
   Logik kannte nur zwei Zustaende — "laeuft noch" und "vorbei" — und
   bei "vorbei" verschwand das Angebotsband samt Preis und CTA. Nach
   der Klausurphase blieb also eine Seite uebrig, die nichts mehr
   anbietet, obwohl das Produkt unveraendert nutzbar ist.

   Diese Datei kennt DREI Zustaende. Der dritte ("zwischen") ist der
   Normalfall zwischen zwei Semestern: alles bleibt sichtbar und
   kaufbar, nur der Countdown weicht dem naechsten Termin.

   Semesterwechsel = in TERMINE eine Zeile ergaenzen. Sonst nichts.
   Laeuft ein Termin ab, rueckt der naechste automatisch nach.
   =================================================================== */
(function () {
  "use strict";

  /* ---------------------------------------------------------------
     1. Die Termine.

     termine[]  chronologisch, aelteste zuerst. Abgelaufene duerfen
                stehen bleiben — sie werden uebersprungen, nicht
                geloescht. So bleibt die Historie lesbar.
     fenster    wenn der naechste Termin nur grob feststeht. Dann
                zeigt die Seite das Fenster als Text statt eines
                Countdowns: kein falscher Countdown auf ein Datum,
                das noch niemand kennt.
     null       Fach ohne kuenftigen Termin (BMAK: Wiederholungs-
                klausur ohne Zweittermin, SoSe 2026 ohne Vorlesung).
     --------------------------------------------------------------- */
  var TERMINE = {
    bmgt: {
      kuerzel: "BMGT", dozent: "Prof. Friebel",
      termine: [{ iso: "2026-07-27T11:00", was: "Klausur" }],
      fenster: NACHSCHREIBEN()
    },
    osta: {
      kuerzel: "OSTA", dozent: "Prof. Hassler",
      termine: [{ iso: "2026-07-28T08:00", was: "Klausur" }],
      fenster: NACHSCHREIBEN()
    },
    omik: {
      kuerzel: "OMIK", dozent: "Prof. Blonski",
      termine: [],                    // Geschenk-Kurs, war nie an einen Termin gebunden
      fenster: null
    },
    ofin: {
      kuerzel: "OFIN", dozent: "Prof. Schmeling",
      termine: [{ iso: "2026-07-29T08:00", was: "Klausur" }],
      fenster: NACHSCHREIBEN()
    },
    bfin: {
      kuerzel: "BFIN", dozent: "Prof. Hackethal",
      termine: [{ iso: "2026-07-29T11:00", was: "Klausur" }],
      fenster: NACHSCHREIBEN()
    },
    bmak: {
      kuerzel: "BMAK", dozent: "Dr. Johannes Zahner",
      termine: [{ iso: "2026-07-30T11:00", was: "Wiederholungsklausur" }],
      fenster: null                   // ausdruecklich KEIN Zweittermin
    }
  };

  /* Das Nachschreibfenster ist fuer alle regulaeren Faecher gleich.
     Eine Funktion, damit jedes Fach eine eigene Kopie bekommt und
     ein spaeteres fachspezifisches Datum niemanden sonst umwirft. */
  function NACHSCHREIBEN() {
    return {
      text: "Nachschreibetermine Ende September bis Mitte Oktober",
      kurz: "Nachschreiben ab Ende September",
      /* Grenzen nur fuer den Waechter (siehe unten) — nicht fuer die
         Anzeige. Sobald die echten Termine feststehen, wandern sie
         als normale Eintraege nach termine[] und das Fenster faellt
         von selbst weg. */
      von: "2026-09-21",
      bis: "2026-10-17"
    };
  }

  /* ---------------------------------------------------------------
     2. Phasenbestimmung
     --------------------------------------------------------------- */

  function jetzt() { return new Date(); }

  function alsDatum(iso) {
    var d = new Date(iso);
    return isNaN(d.getTime()) ? null : d;
  }

  /* Der naechste noch nicht abgelaufene Termin — oder null. */
  function naechsterTermin(fach) {
    var eintrag = TERMINE[fach];
    if (!eintrag) return null;
    var n = jetzt();
    for (var i = 0; i < eintrag.termine.length; i++) {
      var d = alsDatum(eintrag.termine[i].iso);
      if (d && d > n) return { datum: d, was: eintrag.termine[i].was };
    }
    return null;
  }

  /* "laufend"     — es kommt noch ein datierter Termin
     "zwischen"    — alle Termine durch, aber ein Fenster ist bekannt
     "ohne-termin" — kein Termin, kein Fenster (OMIK, BMAK)          */
  function phase(fach) {
    var eintrag = TERMINE[fach];
    if (!eintrag) return "ohne-termin";
    if (naechsterTermin(fach)) return "laufend";
    return eintrag.fenster ? "zwischen" : "ohne-termin";
  }

  /* Laeuft irgendwo noch ein Termin? Entscheidet, ob abgelaufene
     Faecher ueberhaupt abgewertet werden duerfen. Wenn ohnehin
     nichts mehr laeuft, gibt es keinen Grund, irgendetwas grau zu
     machen — dann stehen alle Faecher gleichwertig nebeneinander. */
  function irgendwoLaufend() {
    for (var fach in TERMINE) {
      if (Object.prototype.hasOwnProperty.call(TERMINE, fach) && phase(fach) === "laufend") return true;
    }
    return false;
  }

  function stundenBis(fach) {
    var t = naechsterTermin(fach);
    return t ? (t.datum - jetzt()) / 36e5 : Infinity;
  }

  /* ---------------------------------------------------------------
     3. Texte
     --------------------------------------------------------------- */

  /* Kurzlabel fuer die Kachel auf der Startseite. */
  function kachelLabel(fach) {
    var eintrag = TERMINE[fach];
    if (!eintrag) return "";
    switch (phase(fach)) {
      case "laufend":
        var h = stundenBis(fach);
        return h < 48 ? "noch " + Math.floor(h) + " Std"
                      : "noch " + Math.floor(h / 24) + " Tage";
      case "zwischen":
        return eintrag.fenster.kurz;
      default:
        return fach === "omik" ? "ohne Klausurtermin" : "jederzeit startklar";
    }
  }

  /* Fristzeile im Angebotsband. Der Leistungstext dahinter ist
     fachspezifisch und bleibt im HTML stehen — hier wird nur das
     ersetzt, was mit Zeit zu tun hat. */
  function bandFrist(fach) {
    var eintrag = TERMINE[fach];
    if (!eintrag) return "";
    switch (phase(fach)) {
      case "laufend":
        var t = naechsterTermin(fach);
        return "Online&#8209;Vorteil bis " + datumLang(t.datum) + ":";
      case "zwischen":
        return eintrag.fenster.text + ":";
      default:
        return "Jederzeit startklar:";
    }
  }

  var MONATE = ["Januar", "Februar", "März", "April", "Mai", "Juni",
                "Juli", "August", "September", "Oktober", "November", "Dezember"];
  var TAGE = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];

  function datumLang(d) {
    return d.getDate() + ".&nbsp;" + MONATE[d.getMonth()] + "&nbsp;" + d.getFullYear();
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n; }

  /* Hinweisbalken der Lektionsseiten. Trug vorher ein festes Datum
     im HTML und verschwand nach Fristablauf ersatzlos — ausgerechnet
     auf den Seiten, die den Gratis-Einstieg tragen. Jetzt wechselt
     er den Text und bleibt stehen. */
  function freebarText(fach) {
    var eintrag = TERMINE[fach];
    if (!eintrag) return null;
    switch (phase(fach)) {
      case "laufend":
        var t = naechsterTermin(fach), d = t.datum;
        return "★ " + t.was + " " + TAGE[d.getDay()] + " " + pad2(d.getDate()) + "." +
               pad2(d.getMonth() + 1) + "." + d.getFullYear() + ", " +
               pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + " Uhr (" +
               eintrag.dozent + ") – sichere dir jetzt deine Unterlagen.";
      case "zwischen":
        return "★ " + eintrag.fenster.text +
               " – bereite dich jetzt in Ruhe vor, der komplette Kurs steht bereit.";
      default:
        return "★ Kompletter Kurs jederzeit verfügbar – starte, wann es dir passt.";
    }
  }

  /* ---------------------------------------------------------------
     4. Angebotsband — laeuft auf JEDER Seite, die eines hat.

     Frueher: nach Fristablauf display:none, das Band war weg.
     Jetzt:   das Band bleibt immer stehen. Nur die Fristzeile und
              die Uhr wechseln. Preis, Leistung und CTA sind nie
              wieder an ein Datum gekoppelt.
     --------------------------------------------------------------- */
  function bandAktualisieren(fach) {
    var frist = document.querySelector(".os-frist");
    var uhr   = document.getElementById("osClock");
    var pille = document.getElementById("pillCount");
    var p     = phase(fach);

    if (frist) frist.innerHTML = bandFrist(fach);

    if (p !== "laufend") {
      /* Kein Countdown ohne Datum — aber auch kein Loch: die Uhr
         verschwindet, das Band bleibt. */
      if (uhr) uhr.style.display = "none";
      if (pille) {
        var eintrag = TERMINE[fach];
        pille.innerHTML = (eintrag && eintrag.fenster) ? eintrag.fenster.kurz : "jederzeit startklar";
      }
      return;
    }

    var ende = naechsterTermin(fach).datum;
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function tick() {
      var ms = ende.getTime() - Date.now();
      if (ms <= 0) { bandAktualisieren(fach); return; }   // Phasenwechsel im laufenden Betrieb
      var s = Math.floor(ms / 1000);
      var txt = Math.floor(s / 86400) + " T " + pad(Math.floor(s % 86400 / 3600)) +
                ":" + pad(Math.floor(s % 3600 / 60)) + ":" + pad(s % 60);
      if (uhr) { uhr.style.display = ""; uhr.textContent = "endet in " + txt; }
      if (pille) pille.innerHTML = "Online&#8209;Vorteil endet in <b>" + txt + "</b>";
    }
    tick();
    setInterval(tick, 1000);
  }

  /* ---------------------------------------------------------------
     5. Kacheln — nur auf der Startseite.
     --------------------------------------------------------------- */
  function kachelnAktualisieren() {
    var wrap = document.querySelector(".courses");
    if (!wrap) return;
    var kacheln = [].slice.call(wrap.querySelectorAll(".course"));
    var nochAktiv = irgendwoLaufend();

    function beschriften() {
      kacheln.forEach(function (el) {
        var fach = el.getAttribute("data-fach");
        var feld = el.querySelector(".c-count") || el.querySelector(".c-date");
        if (!feld || !TERMINE[fach]) return;
        feld.textContent = kachelLabel(fach);
        /* Abwerten nur, solange anderswo wirklich noch etwas laeuft.
           Sonst waere die halbe Startseite grau, ohne dass es dem
           Besucher irgendetwas sagt. */
        el.classList.toggle("course-vorbei", nochAktiv && phase(fach) !== "laufend" && fach !== "omik");
      });
    }

    function sortieren() {
      kacheln.slice().sort(function (a, b) {
        return stundenBis(a.getAttribute("data-fach")) - stundenBis(b.getAttribute("data-fach"));
      }).forEach(function (el) { wrap.appendChild(el); });

      kacheln.forEach(function (el) { el.classList.remove("course-ziel"); });
      if (!nochAktiv) return;                 // ohne laufenden Termin kein Ziel-Hervorheben
      var naechste = kacheln.filter(function (el) {
        return phase(el.getAttribute("data-fach")) === "laufend";
      }).sort(function (a, b) {
        return stundenBis(a.getAttribute("data-fach")) - stundenBis(b.getAttribute("data-fach"));
      })[0];
      if (naechste) naechste.classList.add("course-ziel");
    }

    function ausLink() {
      var m = /[?&]fach=([a-z]{4})/i.exec(location.search);
      if (!m) return;
      var ziel = wrap.querySelector('.course[data-fach="' + m[1].toLowerCase() + '"]');
      if (!ziel) return;
      wrap.insertBefore(ziel, wrap.firstChild);
      kacheln.forEach(function (el) { el.classList.remove("course-ziel"); });
      ziel.classList.add("course-ziel");
      setTimeout(function () { ziel.scrollIntoView({ behavior: "smooth", block: "center" }); }, 250);
    }

    beschriften(); sortieren(); ausLink();
    setInterval(beschriften, 60000);
  }

  /* ---------------------------------------------------------------
     6. Hero-Zeile der Startseite — darf der Kachelaussage nicht
        widersprechen. "Klausurphase" stimmt nur, solange eine ist.
     --------------------------------------------------------------- */
  function heroAktualisieren() {
    var kicker = document.querySelector(".hero .kicker");
    if (!kicker || irgendwoLaufend()) return;
    kicker.textContent = "Vorbereitung für die Nachschreibetermine · Ende September bis Mitte Oktober";
  }

  /* ---------------------------------------------------------------
     7. Zaehlpille im Kopf der Startseite.

     Die Startseite gehoert keinem Fach — ihr <body data-fach="OSTA">
     ist ein Ueberbleibsel aus der Zeit, als die Schale aus der
     OSTA-Seite entstand. Deshalb zeigt die Pille hier den naechsten
     Termin ueber ALLE Faecher, nicht den eines einzelnen.
     --------------------------------------------------------------- */
  function pilleStartseite() {
    var pille = document.getElementById("pillCount");
    if (!pille) return;

    if (!irgendwoLaufend()) {
      pille.textContent = "Nachschreibetermine ab Ende September";
      return;
    }

    var naechstes = null;
    for (var fach in TERMINE) {
      if (!Object.prototype.hasOwnProperty.call(TERMINE, fach)) continue;
      var t = naechsterTermin(fach);
      if (t && (!naechstes || t.datum < naechstes)) naechstes = t.datum;
    }
    if (!naechstes) return;

    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function tick() {
      var ms = naechstes.getTime() - Date.now();
      if (ms <= 0) { pille.textContent = "Nachschreibetermine ab Ende September"; return; }
      var s = Math.floor(ms / 1000);
      pille.innerHTML = "N&auml;chste Klausur in <b>" + Math.floor(s / 86400) + " T " +
                        pad(Math.floor(s % 86400 / 3600)) + ":" +
                        pad(Math.floor(s % 3600 / 60)) + ":" + pad(s % 60) + "</b>";
    }
    tick();
    setInterval(tick, 1000);
  }

  /* ---------------------------------------------------------------
     8. Start.

     Die Startseite erkennt man an der Kachelliste, nicht am
     data-fach des Body — siehe oben. Fachseiten bekommen ihr
     Angebotsband, die Startseite Kacheln, Hero und Pille.
     --------------------------------------------------------------- */
  function start() {
    if (document.querySelector(".courses")) {
      kachelnAktualisieren();
      heroAktualisieren();
      pilleStartseite();
      return;
    }
    var fach = (document.body.getAttribute("data-fach") || "").toLowerCase();
    if (!fach || !TERMINE[fach]) return;

    if (document.getElementById("offerstrip")) bandAktualisieren(fach);   // Fachseiten

    var balken = document.getElementById("freebar");                      // Lektionsseiten
    if (balken) {
      var txt = freebarText(fach);
      if (txt) balken.textContent = txt;
      balken.style.display = "";      // nie wieder ausblenden
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }

  /* ---------------------------------------------------------------
     9. API fuer die Apps.

     Die sechs Klausur-Apps liegen in eigenen Repos auf eigenen
     Subdomains und laden diese Datei per <script src="https://www.
     klausurchecker.de/termine.js">. Sie haben ihre Termine bisher
     doppelt gefuehrt (planData.klausur + eine KLAUSUR-Konstante) und
     zeigten nach dem Termin "Die Klausur ist geschrieben" sowie
     "0 Tage bis Klausur" — auch fuer jemanden, der gerade erst fuer
     den Nachschreibtermin gekauft hat.

     Statt in sechs Apps eigene Logik zu bauen, liefert diese Funktion
     alle Texte fertig. Die Apps fragen nur noch ab.
     --------------------------------------------------------------- */
  function appTexte(fach) {
    var eintrag = TERMINE[fach];
    var t = eintrag ? naechsterTermin(fach) : null;
    var p = eintrag ? phase(fach) : "ohne-termin";

    var erg = {
      phase: p,
      /* ISO-Tag fuer die Countdown-Rechnung der App, null wenn offen */
      klausurTag: t ? (t.datum.getFullYear() + "-" + pad2(t.datum.getMonth() + 1) + "-" + pad2(t.datum.getDate())) : null,
      klausurIso: t ? (t.datum.getFullYear() + "-" + pad2(t.datum.getMonth() + 1) + "-" + pad2(t.datum.getDate()) +
                       "T" + pad2(t.datum.getHours()) + ":" + pad2(t.datum.getMinutes())) : null,
      /* Ersatzbeschriftung, wenn kein Datum feststeht */
      zaehlerWert: "–",
      zaehlerLabel: "Termin folgt",
      hubSub: "",
      planZusatz: ""
    };

    if (p === "laufend") {
      erg.hubSub = "Klausur bei " + eintrag.dozent + " am " +
                   pad2(t.datum.getDate()) + "." + pad2(t.datum.getMonth() + 1) + "." +
                   t.datum.getFullYear() + ". Ein Kapitel nach dem anderen.";
      return erg;                       // Zaehler rechnet die App selbst
    }

    if (p === "zwischen") {
      erg.zaehlerLabel = "bis zum Nachschreiben";
      erg.hubSub = eintrag.fenster.text + ". Der komplette Kurs bleibt für dich offen.";
      erg.planZusatz = "Dein nächster Anlauf: " + eintrag.fenster.text +
                       ". Sobald dein Termin feststeht, rechnet der Plan wieder rückwärts – " +
                       "bis dahin stehen dir alle Kapitel offen.";
      return erg;
    }

    /* ohne-termin: unterscheiden, ob es je einen Termin gab. OMIK hatte
       nie einen (Geschenk-Kurs) — "Die Klausur ist geschrieben" waere
       dort schlicht falsch. */
    var hatteTermin = eintrag && eintrag.termine.length > 0;
    erg.zaehlerLabel = hatteTermin ? "Klausur geschrieben" : "ohne Termin";
    erg.hubSub = hatteTermin
      ? "Die Klausur ist geschrieben. Der komplette Kurs bleibt für dich offen."
      : "Kein fester Klausurtermin – lern in deinem Tempo.";
    erg.planZusatz = hatteTermin
      ? "Der komplette Kurs bleibt für dich offen – für eine Wiederholung oder zum Nachschlagen."
      : "Für diesen Kurs gibt es keinen festen Klausurtermin. Alle Kapitel stehen dir dauerhaft offen.";
    erg.hatteTermin = !!hatteTermin;
    return erg;
  }

  /* Nach aussen sichtbar — der Site-Check liest TERMINE aus, um zu
     warnen, bevor alle Termine veraltet sind; die Apps holen sich
     ueber appTexte() ihre Beschriftungen. */
  window.BWLK_TERMINE = {
    tabelle: TERMINE,
    phase: phase,
    naechsterTermin: naechsterTermin,
    irgendwoLaufend: irgendwoLaufend,
    kachelLabel: kachelLabel,
    appTexte: appTexte
  };
})();
