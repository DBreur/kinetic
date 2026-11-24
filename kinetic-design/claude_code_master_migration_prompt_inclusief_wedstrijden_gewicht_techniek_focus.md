# Claude Code Master Migration Prompt & Implementation Guide: Kinetic Redesign (Inclusief Wedstrijden, Gewichtstracking & Live Techniek Focus)

> **Gebruiksaanwijzing:** Kopieer onderstaande master prompt (Sectie 1) en plak deze direct in **Claude Code** (of voeg het toe als `CLAUDE.md` in de root van je bestaande codebase). 
> Het is specifiek geformuleerd om:
> 1. Je **bestaande database & backend data-schema's 100% intact te houden** en te koppelen (geen dataverlies).
> 2. De **volledige visuele stijl, componenten, iconen en logo's** van Kinetic toe te passen.
> 3. Een naadloze **Light / Dark Mode switch** in te bouwen.
> 4. Alle schermen (Today, Trainingslog, Eet Logboek, Live Session Timer, Telemetrie & Export, Technieken, én het nieuwe **Wedstrijden & Gewichtstracking** scherm) stapsgewijs te transformeren.
> 5. De **Dexcom-stijl interactieve, horizontaal scrollbare trendgrafiek met individuele meetpunten** exact na te bootsen.
> 6. De **Technique Vault (Ontdekken & Bibliotheek)** te structureren met uitklapbare categorieën (**'Striking'** en **'Throws'**).
> 7. **Wedstrijdvoorbereiding, streefgewicht & dagelijks inwegen** toe te voegen met automatische gewichtsverloopcurve.
> 8. **Live Techniek Focus tijdens sessies** direct op het live round-timer scherm te tonen met real-time succestellers.

---

```markdown
# 🚀 PROMPT VOOR CLAUDE CODE (Kopieer vanaf hier)

Je bent een senior mobile frontend engineer en UI/UX architect. Jouw taak is om mijn **bestaande mobile app volledig visueel te herontwerpen en moderniseren** naar het **Kinetic Athletic & Metabolic Training** design system.

### ⚠️ CRUCIALE VEREISTE #1: BEHOUD DE BESTAANDE DATABASE EN LOGICA
- Verwijder of breek GEEN bestaande databasemodellen, SQLite/WatermelonDB tabellen, Firebase/Supabase collecties of API-endpoints af.
- De bestaande data (trainingen, logs, gebruikersprofiel, opgeslagen tijden, technieken, gewichten) MOET 1-op-1 behouden blijven en gekoppeld worden aan de nieuwe UI-componenten via adapter/mapping layers waar nodig.
- Breid datamodellen alleen uit met optionele velden indien vereist voor nieuwe telemetrie en wedstrijdbeheer:
  - `weight_entries`: `id`, `date`, `weight_kg`, `hydration_pct`, `notes`.
  - `competitions`: `id`, `name`, `date`, `target_weight_kg`, `weight_class`, `sport`, `status` ('prep', 'completed').
  - `session_technique_focus`: `technique_id`, `success_count`, `attempt_count`, `notes`.

### ⚠️ CRUCIALE VEREISTE #2: DUAL THEME (LIGHT & DARK MODE) MET LIVE SWITCH
- Implementeer een globale theme context/store (`useThemeStore` of vergelijkbaar).
- Ondersteun live wisselen tussen:
  - **Light Mode (`Kinetic`)**: Schone, sportieve lichte interface.
  - **Dark Mode (`Kinetic Metabolic Combat`)**: High-contrast koolstof-donkere interface geoptimaliseerd voor vechtsportzalen, dojo's en schemerige trainingsruimtes.
- Sla de themakeuze lokaal op (persist) en respecteer optioneel het OS-systeemthema.

### ⚠️ CRUCIALE VEREISTE #3: DEXCOM-STIJL INTERACTIEVE SCROLLBARE TRENDGRAFIEK MET PUNTJES
- De glucose trend grafiek op het Today dashboard en in sessie-overzichten MOET exact werken zoals in de officiële **Dexcom app**:
  1. **Horizontaal scrollbaar / pannen door de tijd**: De gebruiker kan horizontaal swipen/scrollen om terug te kijken in de tijd (bijv. 3u, 6u, 12u, 24u tijdsvensters).
  2. **Individuele telemetrie data-dots (meetpunten)**: Toon de continue glucosewaarden als individuele afgeronde puntjes/dots per 5 minuten (met subtiele verbindingslijn/curve ertussen).
  3. **Kleurcodering per punt**:
     - *In bereik (4.0 - 10.0 mmol/L)*: Teal / Kinetic Emerald (`#0D9488` / `#14B8A6`).
     - *Bovengrens / Hyper (>10.0 mmol/L)*: Amber / Geel waarschuwingskleur (`#F59E0B`).
     - *Ondergrens / Hypo (<4.0 mmol/L)*: Rood alert signaalkleur (`#EF4444`).
  4. **Target Range Corridor**: Horizontale doelcorridor arcering tussen 4.0 en 10.0 mmol/L met subtiele stippellijnen.
  5. **Interactieve Scrubber / Tooltip**: Tik of sleep over de grafiek om een verticale indicatorlijn te tonen met exacte tijd, exacte glucosewaarde en trendpijl voor dat specifieke meetpunt.

### ⚠️ CRUCIALE VEREISTE #4: TECHNIEKEN & VAULT INDELING (ACCORDION MET 'STRIKING' EN 'THROWS')
- Bij het onderdeel **Technieken / Ontdekken (Technique Vault)**:
  1. **Naamgeving**: Gebruik verplicht de categorienaam **`Striking`** (dus expliciet **NIET** *'Strikes'*).
  2. **Geclusterde uitklapbare categorieën (Accordion / Collapsible Lists)**: Alle technieken moeten per hoofdcategorie onder één overzichtelijk uitklapbaar kopje vallen:
     - **`Throws`** (Worpen): Alle worpen (bijv. *Harai Goshi*, *Seoi Nage*, *Uchi Mata*) vallen onder dit ene kopje en zijn soepel in- en uitklapbaar met count-badge (bijv. *12 technieken*).
     - **`Striking`** (Slag- en traptechnieken): Alle stoten, trappen en combinaties vallen onder dit kopje (uitklapbaar).
     - **`Submissions & Locks`**: Alle klemmen, armbars en chokes geclusterd (uitklapbaar).
     - **`Sweeps & Guard Passes`**: Alle reversals en passes (uitklapbaar).
  3. **Ontdekken & Zoeken**: Het 'Ontdekken'-gedeelte (search bar, discipline filters: *Combat Sambo*, *BJJ*, *Judo*, *MMA*) blijft volledig behouden en functioneel.

### ⚠️ CRUCIALE VEREISTE #5: WEDSTRIJDEN, GEWICHTSTRACKING & LIVE TECHNIEK FOCUS (NIEUW)
- **Wedstrijden & Gewicht Beheer (`/fight-prep` of `/weight`)**:
  1. **Aankomende Wedstrijd Card**: Naam toernooi (bijv. *Dutch Combat Sambo Open*), aftellende dagen, gewichtsklasse (bijv. *-77.0 kg Weltergewicht*), huidig geregistreerd gewicht en resterend te cutten gewicht (bijv. *-1.4 kg te gaan*).
  2. **Snel Wegen Invoeren**: Widget om ochtendgewicht in te voeren met 1 decimaal (bijv. `78.4 kg`), trend t.o.v. gisteren, en optionele hydratatiestatus.
  3. **Gewichtsverloop Grafiek**: Trajectcurve die het gewichtsverloop over de weken toont afgezet tegen de streeflijn richting de weegdatum.
  4. **Wedstrijd Agenda & Historie**: Lijst met geplande wedstrijden en voltooide toernooien inclusief gewogen gewicht en behaalde prestatie.
- **Live Sessie Timer met Techniek Focus (`/session/live`)**:
  1. **Prominente Techniek Focus Sectie**: Direct zichtbaar onder de grote ronde-timer (bijv. `03:41`, Ronde 3/5).
  2. **Geselecteerde Focus Technieken**: Toont de voor deze training gekozen technieken (bijv. *Harai Goshi* en *Liver Punch Setup*).
  3. **Directe Mat-Counters**: Eenvoudige grote tapknoppen om tijdens of tussen rondes te tellen: *Geslaagd (4x)* en *Geprobeerd (7x)*.

---

## 🎨 1. DESIGN TOKENS & TAILWIND / NATIVEWIND CONFIGURATIE

```javascript
module.exports = {
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        kinetic: {
          teal: {
            DEFAULT: '#0D9488',
            accent: '#14B8A6',
            glow: '#2DD4BF',
            dark: '#0F766E',
            subtle: '#5EEAD4',
          },
          dark: {
            surface: '#0A0E13',
            container: '#121820',
            elevated: '#181C21',
            border: '#1E293B',
            text: '#F8F9FF',
            muted: '#94A3B8',
          },
          light: {
            surface: '#F8F9FF',
            container: '#FFFFFF',
            elevated: '#EFF4FF',
            border: '#E2E8F0',
            text: '#0F172A',
            muted: '#64748B',
          }
        }
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['Inter', 'Courier', 'monospace'],
      },
      borderRadius: {
        'kinetic-sm': '8px',
        'kinetic': '12px',
        'kinetic-lg': '16px',
        'pill': '9999px',
      }
    }
  }
}
```

---

## 🏗️ 2. CORE SCHERMEN SPECIFICATIE & MIGRATIEPLAN

1. **Top App Bar & Shell**: Kinetic logo, view titel, theme switch (`Sun`/`Moon`), profiel avatar.
2. **Today Dashboard (`/today`)**: Dexcom-stijl interactieve scrollbare curve met dots per 5 min, live CGM card, dagtraining.
3. **Trainingslog (`/training`)**: Sportfilters, weekoverzicht mattijd, glycemisch traject start-piek-eind.
4. **Live Sessie Timer & Techniek Focus (`/session/live`)**:
   - Grote timer typografie (`03:41`).
   - **Techniek Focus Widget**: Geselecteerde technieken van vandaag (bijv. *Harai Goshi*, *Liver Punch*) met live 'Geslaagd' / 'Geprobeerd' tikknoppen.
   - Noodknop `+15g Snelle Carbs` en live hartslag/glucose indicator.
5. **Eet Logboek (`/fuel`)**: Carb tracking, maaltijdkaarten met glucosepiek respons.
6. **Technique Vault (`/techniques`)**: Zoeken/filteren, uitklapbare accordeons: **`Throws`**, **`Striking`**, **`Submissions & Locks`**, **`Sweeps & Guard Passes`**.
7. **Wedstrijden & Gewichtstracking (`/fight-prep` of `/weight`)**:
   - Wedstrijd afteller & gewichtsklasse doelstelling (*bijv. -77 kg Weltergewicht, nog 1.4 kg te gaan*).
   - Dagelijkse gewichtsinvoer met trendpijlen en gewichtsverloopgrafiek richting weegmoment.
   - Wedstrijd agenda & behaalde resultaten.
8. **Telemetrie & Export Instellingen (`/settings/telemetry`)**: Sensorenkoppeling, metabole drempels, medische PDF/CSV export.
```
