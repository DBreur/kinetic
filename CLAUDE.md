web application/stitch/projects/1050067765006377206/screens/f4dfa10aa435475c8c4845b4cc486f8f

# Kinetic Master Migration & Implementation Prompt voor Claude Code (Inclusief Supabase Backend Configuratie)

> **Doel:** Bouw of refactor de mobiele applicatie **Kinetic** (Combat Sports, Atletische Telemetrie & Type 1 Diabetes / CGM monitoring) met behulp van Claude Code. Dit document bevat de complete specificatie van alle interactieve schermen, navigatie flows, biometrische state-logica, handschoenvriendelijke mat-interacties, design tokens én de directe **Supabase database configuratie & CLI-koppeling**.

---

## 🗄️ 1. Supabase Database & Backend Specificaties

De applicatie draait op Supabase. Claude Code moet deze database instantie en tabellen direct koppelen en respecteren zonder schema's te overschrijven.

### Supabase Project Details & Verbinding

```bash
# 1. Supabase CLI Authenticatie & Koppeling
supabase login
supabase link --project-ref wpexdeglubtzkdejehkj

# 2. Database Export / Schema Inspectie
supabase db dump --data-only -f db_export/backup.sql
```

### Environment & Connectiestrings (.env)

```env
# Supabase API Koppeling (App client)
NEXT_PUBLIC_SUPABASE_URL=https://wpexdeglubtzkdejehkj.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_publishable_zzzXBVJMVGY5BL5HiY95BA_S70qx7ZC
SUPABASE_PROJECT_REF=wpexdeglubtzkdejehkj

# Directe PostgreSQL Verbinding (DBeaver, psql, migrations, backend scripts)
DATABASE_URL=postgresql://postgres:[JOUW_DATABASEWACHTWOORD]@db.wpexdeglubtzkdejehkj.supabase.co:5432/postgres

# Session Pooler (IPv4 ondersteuning voor lokale dev omgevingen)
# aws-0-<regio>.pooler.supabase.com:5432 / postgres.wpexdeglubtzkdejehkj
DATABASE_POOLER_URL=postgresql://postgres.wpexdeglubtzkdejehkj:[JOUW_DATABASEWACHTWOORD]@aws-0-eu-central-1.pooler.supabase.com:5432/postgres
```

> **Belangrijk voor Claude Code:**
>
> - Behoud alle bestaande tabellen, relaties en Row Level Security (RLS) policies.
> - Gebruik de Supabase JavaScript/TypeScript client (`@supabase/supabase-js`) met de publishable anon key.
> - De authenticatie verloopt via Supabase Auth (`supabase.auth.getSession()`).

---

## 🏗️ 2. Project Architectuur & Technologie Stack

- **Framework**: React Native (Expo SDK 51+ met Expo Router) óf React / Next.js PWA met Tailwind CSS.
- **Backend / Database**: Supabase (PostgreSQL, Supabase Auth, Row Level Security, Realtime subscriptions voor biometrie).
- **State Management**: Zustand voor synchrone biometrische state (`useKineticStore.ts`).
- **Styling**: Tailwind CSS / NativeWind geconfigureerd met het officiële Kinetic Dark Palette.
- **Hardware Integratie**: Dexcom Web API / BLE CGM receiver simulation, Polar H10 BLE Heart Rate sensor (R-R intervallen / ECG).

---

## 🎨 3. Design Tokens & Styling (Kinetic Dark Theme)

```css
:root {
  /* Achtergrond & Surface Obsidian */
  --kinetic-bg-dark: #101419;
  --kinetic-surface: #181c21;
  --kinetic-surface-container: #1e2329;
  --kinetic-surface-high: #262c33;
  --kinetic-surface-elevated: #2d333b;

  /* Primary Kinetic Teal & Accenten */
  --kinetic-teal-primary: #14b8a6; /* Tailwind teal-500 */
  --kinetic-teal-light: #5eead4; /* Tailwind teal-300 */
  --kinetic-teal-glow: rgba(20, 184, 166, 0.25);

  /* Biometrische & Status Alerts */
  --kinetic-accent-warning: #f59e0b; /* Glucose stijging / Alert */
  --kinetic-accent-danger: #ef4444; /* Hypo gevaar < 4.0 mmol/L */
  --kinetic-accent-success: #10b981; /* In Target 4.2 - 9.0 mmol/L */
  --kinetic-accent-purple: #a855f7; /* BJJ / Grappling */
  --kinetic-accent-blue: #3b82f6; /* Polar H10 / Hydratatie */

  /* Typografie & Borders */
  --kinetic-text-primary: #f8fafc;
  --kinetic-text-secondary: #94a3b8;
  --kinetic-text-muted: #64748b;
  --kinetic-border: #262c33;
  --kinetic-radius: 12px;
  --kinetic-radius-lg: 16px;
  --kinetic-radius-full: 9999px;
  --kinetic-font-family: "Inter", -apple-system, sans-serif;
}
```

---

## 📱 4. Navigatie Structuur & Routes

De app hanteert een **5-tabs Bottom Navigation Bar** voor overzichten en **Full-Screen Stack Modals** voor live mat-activiteit:

### Hoofdtabs (Bottom Navigation)

1. **`/vandaag` (Vandaag / Today)** — Dashboard, telemetrietijdlijn, snelle logs, live mat-status.
2. **`/training` (Training Historie)** — Trainingsvolume, mat-tijd verdeling, voltooide sessies en glucose safe-zone %.
3. **`+` (Centrale Quick-Action)** — Zwevende action button die direct de actiemenu-sheet opent (Start Sparring, Snelle Carbs, Inwegen, Sensor Kalibratie).
4. **`/technieken` (Technieken Vault)** — Biomechanische vault met accordeons, filterchips en _Focus in Sessie_ selectie.
5. **`/eten` (Eet Logboek met Bottom Sheet)** — Dagoverzicht brandstof, actieve macro-barometer en de interactieve maaltijd modal.

### Stack Schermen (Full-Screen Modals & Live Views)

6. **`/live-session` (Live Sparring & Mat-Modus)** — Handschoenvriendelijke live round timer, live Dexcom G7 + Polar H10 data, scoring van geselecteerde technieken en coach spraakmemo.
7. **`/ronde-rust` (Ronde Rust - 1 min Herstel & Glucose-Check)** — 60s countdown hersteltimer, acute glucose trend evaluatie, HRV herstelsnelheid, vagale ademhaling en snelle mat-interventies (+15g Dextrose / +200ml Isotone drank).
8. **`/competitions` (Wedstrijden & Gewicht / Fight Prep)** — Toernooi aftelling, interactieve ochtendinweging (+ / - 0.1 kg), gewichtscurve met richtlijn, en het T1D Weegprotocol.
9. **`/telemetrie-export` (Instellingen & Data Export)** — CSV/JSON export, Dexcom/Polar sync status en data-anonimisering.

---

## ⚡ 5. Scherm-voor-Scherm Functionele Specificaties & Interacties

### A. Vandaag (`/vandaag`)

- **Combat Sambo Fight Prep Banner**:
  - Toont `Combat Sambo Open • Nog 18 dagen` en huidig gewicht `78.4 kg (-1.4 kg target)`.
  - Klikken op de banner of knop `"Inwegen & Prep ⚖️"` navigeert direct naar `/competitions`.
- **Dexcom G7 Horizontale Telemetrie Graph**:
  - Horizontaal scrollbare 12-uurs tijdlijn met continue glucosecurve en meetpunten.
  - Tikken op meetpunten toont tooltip met exacte tijd en meetwaarde (bijv. `17:45 - 6.4 mmol/L • Stabiel`).
  - Toont IOB (Insuline Actief): bijv. `0.4 E`.
- **Start Live Sparring CTA**:
  - Grote kinetische teal kaart die bij aanklikken de sensor vergrendelt en navigeert naar `/live-session`.
- **Snelle 1-Tap Knoppen**:
  - **Vocht**: Directe interactieve knop `Tik voor +250ml`. Verhoogt direct de dagteller (bijv. 3.2L ➔ 3.45L) met toast-bevestiging.
  - **Eten & Carbs**: Opent direct de maaltijd-modal op `/eten`.
- **Dagelijkse Output Cards**: Verbranding (`840 kcal`), Tijd op Mat (`65 min`), HRV Herstel (`88% Hoog`), Slaap (`7h 42m`).

---

### B. Wedstrijden & Gewicht (`/competitions`)

- **Doelstelling**: Biedt een veilige gewichtscut-begeleiding voor vechters met Type 1 Diabetes om diabetische ketoacidose (DKA) en ernstige dehydratatie te voorkomen.
- **Interactieve Inweeg Calculator**:
  - Knoppen `[-]` en `[+]` passen het geregistreerde gewicht aan met stappen van `0.1 kg`.
  - Update realtime de "Nog af te vallen" berekening (`-1.4 kg naar doel`).
  - Knop `"Gewicht Registreren"` slaat de meeting op in de historische gewichtscurve (gesynchroniseerd met Supabase `weigh_ins` tabel).
- **Target Curve Grafiek**:
  - Toont de veilige afvalcorridor (max 0.5 - 0.8 kg/week) t.o.v. de weegdag (12 april).
- **T1D Weegprotocol & Rehydratatie Checklist**:
  - Interactieve checkboxes:
    1. _Geen Extreme Uitdroging (Water Cut < 2.5%)_
    2. _Glycogeen Restoratie Post-Weeging (hypertoon elektrolyt + insulineverlaging 30-40%)_
    3. _Sensor Calibratie bij Vochtverschuivingen_
  - Dynamische counter toont voortgang (bijv. `0 / 3 Voldaan`).

---

### C. Eet Logboek met Interactieve Modal (`/eten`)

- **Macro Barometer**:
  - Dynamische progress bar voor Koolhydraten (`165 / 210g` — `45g resterend`), Eiwit (`145 / 170g`) en Vetten (`52 / 65g`).
- **Snelle Carb Presets**:
  - Eén-tiks knoppen: `+15g Dextrose`, `+30g Snack/Fruit`, `+50g Maaltijd`.
  - Tikken verhoogt direct de totale koolhydratenteller en actualiseert de resterende behoefte realtime.
- **Interactieve Bottom Sheet Modal (`isMealModalOpen`)**:
  - Getriggerd door de knop `+ Maaltijd of Snelle Carbs Toevoegen`.
  - **Invoervelden**:
    - Tekstveld: Maaltijd/Brandstof naam (bijv. _"Banaan + Dextrose Gel"_).
    - Numerieke macro-invoer: Koolhydraten (g), Eiwitten (g), Vetten (g).
    - Context Selector Chips: `⚡ Vóór Training / Sparring (~30m)`, `🔄 Direct Na Training`, `🛡️ Acute Mat-Interventie`, `🥗 Regulier Herstel`.
    - **Verwachte Glucose Impact Predictor**: Geeft realtime feedback over verwachte stijging (bijv. _+1.2 tot +1.8 mmol/L_) en Dexcom G7 auto-annotatie tag.
    - Primaire actie: `"Opslaan in Dagoverzicht"` (slaat op in Supabase `meals` tabel) en actualiseert de macrobarometer.

---

### D. Live Sessie & Sparring Modus (`/live-session`)

- **Handschoenvriendelijk UX**: Extra grote touch targets (minimaal 64px hoogte) en hoog contrast voor leesbaarheid op de mat.
- **Ronde & Werk Timer**:
  - Statusindicatie: `🔴 ACTIEVE SPARRING • LIVE` (5 min werk / 1 min rust).
  - Ronde indicator (bijv. `Ronde 3 / 5`) met visuele ronde-voortgang.
  - Grote countdown timer (`03:18`).
  - Grote bediening onderaan: `⏸ PAUZE / HERVAT` en `⏭ VOLGENDE` (triggert overgang naar `/ronde-rust`).
- **Dual Biometrische Telemetrie**:
  - **Dexcom G7 Widget**: Live glucose (`6.5 mmol/L ➔`), doelbereik badge `Stabiel doelbereik 4.2 - 9.0 mmol/L`.
  - **Polar H10 Widget**: Live hartslag (`164 BPM`), hartslagzone (`Zone 4 • Drempel / 88% max HR`).
- **Live Techniek Focus Counters (Mat-Tap)**:
  - Dynamisch geladen vanuit de selectie in de Technieken Vault.
  - Voorbeeld: **Harai Goshi** (Grappling) met 3 interactieve telknoppen:
    - `Geslaagd (4)`
    - `Poging (7)`
    - `Gecounterd (1)`
  - Voorbeeld: **Liver Punch Setup** (Striking):
    - `Clean Hit (3)`
    - `Geblokt (5)`
    - `Tegenstoot (2)`
- **Coach Voice Memo**:
  - `Snelle Spraaknotitie Coach (REC)`: Togglet audio-opname voor tactische feedback na de ronde.

---

### E. Ronde Rust & Glucose-Check (`/ronde-rust`)

- **60-Seconden Herstel Countdown**:
  - Cirkelvormige countdown timer (`00:45 HERSTELTIJD`).
  - Sneltoets knop: `⏩ Sla rust over • Start R4 direct`.
- **Acute Glucose Evaluatie**:
  - Dexcom G7 widget met trendpijl (bijv. `6.7 mmol/L ↗`, `IOB: 0.15 E`).
  - Dynamische veiligheidsbadge: `Veilig voor R4` of waarschuwing bij dalende trend.
- **Polar H10 ECG & Herstel**:
  - Live hartslag (`137 BPM`), Herstelsnelheid (`-30 BPM / 45s`), vagale ademhaling begeleider (`Inademen 4s / Uitademen 6s`).
- **Acute Mat-Interventies**: Grote knoppen voor coach of atleet:
  - `+15g Dextrose (Snelwerkende Gel)`
  - `+200ml Isotone Drank (14g Koolh.)`
- **Coach Focus voor de Volgende Ronde**:
  - Instructie voor Ronde 4 (_"Low Calf Kick ➔ Counter Left Hook"_).
  - Knoppen onderaan: `+30s Rust` en `🥋 KLAAR VOOR RONDE 4`.

---

### F. Technieken Vault (`/technieken`)

- **Accordeon Categorieën**:
  - `Strikes & Combinaties` (Jab & Cross, Lever Hook, Low Calf Kick, Spinning Back Fist, Muay Thai Switch Kick).
  - `Throws & Takedowns` (Judo heupworpen, worstel single/double leg entries).
  - `Submissions & Grondwerk` (Chokes, armbars, guard retention).
  - `Verdediging & Counters` (Takedown defense, sprawls, counters).
- **Per Techniek**:
  - Mastery Index meter (bijv. `92%`), Bag Volume (`2.450 reps`), Target / Doelwit.
  - **Interactieve Toggle `Focus in Sessie`**: Schakelt de techniek in voor de live mat-teller op `/live-session`.

---

### G. Training Historie (`/training`)

- **Periode Filters**: `Deze Week`, `Maand`, `Fight Camp (8w)`, `Alle`.
- **Weekoverzicht & Intensiteitsgrafiek**: Mat volume `8u 45m`, Glucose Safe-Zone `94%`.
- **Sessie Kaarten**: Detailkaarten per discipline met kcal, hartslagzones, rondes en submission ratio's.

---

## 💻 6. Zustand State Store Voorbeeld (`useKineticStore.ts`)

```typescript
import { create } from "zustand";

interface TechniqueFocus {
  id: string;
  name: string;
  category: "grappling" | "striking";
  successCount: number;
  attemptCount: number;
  counteredCount: number;
  activeInSession: boolean;
}

interface KineticState {
  // Telemetrie
  currentGlucose: number;
  glucoseTrend: "flat" | "up_slow" | "up_fast" | "down_slow" | "down_fast";
  heartRate: number;
  heartRateZone: number;
  iob: number;

  // Fight Prep
  currentWeightKg: number;
  targetWeightKg: number;
  weighInChecklist: { [key: string]: boolean };

  // Sparring Timer
  isSparringActive: boolean;
  currentRound: number;
  totalRounds: number;
  roundSecondsRemaining: number;
  isRestPhase: boolean;
  restSecondsRemaining: number;

  // Voeding
  carbsConsumed: number;
  carbsTarget: number;
  isMealModalOpen: boolean;

  // Focus Technieken
  techniques: TechniqueFocus[];

  // Acties
  adjustWeight: (delta: number) => void;
  toggleChecklist: (key: string) => void;
  addCarbs: (amount: number) => void;
  setMealModalOpen: (open: boolean) => void;
  incrementTechniqueStat: (
    id: string,
    field: "successCount" | "attemptCount" | "counteredCount",
  ) => void;
  toggleSparringTimer: () => void;
  advanceToRestPhase: () => void;
  startNextRound: () => void;
}

export const useKineticStore = create<KineticState>((set) => ({
  currentGlucose: 6.5,
  glucoseTrend: "flat",
  heartRate: 164,
  heartRateZone: 4,
  iob: 0.4,

  currentWeightKg: 78.4,
  targetWeightKg: 77.0,
  weighInChecklist: {
    hydration: false,
    glycogen: false,
    calibration: false,
  },

  isSparringActive: true,
  currentRound: 3,
  totalRounds: 5,
  roundSecondsRemaining: 198, // 03:18
  isRestPhase: false,
  restSecondsRemaining: 60,

  carbsConsumed: 165,
  carbsTarget: 210,
  isMealModalOpen: false,

  techniques: [
    {
      id: "harai-goshi",
      name: "Harai Goshi",
      category: "grappling",
      successCount: 4,
      attemptCount: 7,
      counteredCount: 1,
      activeInSession: true,
    },
    {
      id: "liver-punch",
      name: "Liver Punch Setup",
      category: "striking",
      successCount: 3,
      attemptCount: 5,
      counteredCount: 2,
      activeInSession: true,
    },
  ],

  adjustWeight: (delta) =>
    set((s) => ({
      currentWeightKg: Number((s.currentWeightKg + delta).toFixed(1)),
    })),
  toggleChecklist: (key) =>
    set((s) => ({
      weighInChecklist: {
        ...s.weighInChecklist,
        [key]: !s.weighInChecklist[key],
      },
    })),
  addCarbs: (amount) =>
    set((s) => ({ carbsConsumed: s.carbsConsumed + amount })),
  setMealModalOpen: (open) => set({ isMealModalOpen: open }),
  incrementTechniqueStat: (id, field) =>
    set((s) => ({
      techniques: s.techniques.map((t) =>
        t.id === id ? { ...t, [field]: t[field] + 1 } : t,
      ),
    })),
  toggleSparringTimer: () =>
    set((s) => ({ isSparringActive: !s.isSparringActive })),
  advanceToRestPhase: () =>
    set({
      isRestPhase: true,
      isSparringActive: false,
      restSecondsRemaining: 60,
    }),
  startNextRound: () =>
    set((s) => ({
      isRestPhase: false,
      isSparringActive: true,
      currentRound: Math.min(s.currentRound + 1, s.totalRounds),
      roundSecondsRemaining: 300,
    })),
}));
```

---

## 🚀 7. Directe Uitvoeringsinstructie voor Claude Code

Plak de volgende prompt in je Claude Code terminal:

```bash
claude "Lees dit specificatiedocument en koppel direct de Supabase backend van Kinetic. Zorg voor het volgende:
1. Koppel het Supabase project met project ref: wpexdeglubtzkdejehkj (URL: https://wpexdeglubtzkdejehkj.supabase.co, publishable key: sb_publishable_zzzXBVJMVGY5BL5HiY95BA_S70qx7ZC).
2. Behoud alle bestaande PostgreSQL tabellen, data en RLS policies (Directe host: db.wpexdeglubtzkdejehkj.supabase.co / port 5432).
3. Implementeer alle schermen exact volgens het Kinetic Dark Theme (#101419 obsidian met #14B8A6 teal).
4. Bouw de 5-tabs navigatiebalk (/vandaag, /training, /technieken, /eten) met de centrale '+' quick action button.
5. Zorg dat de full-screen timers (/live-session en /ronde-rust) naadloos functioneren met handschoenvriendelijke tellers en acute Dexcom G7 checks.
6. Synchroniseer maaltijden en inwegingen direct met de Supabase tabellen en werk realtime de macrobarometer en gewichtscurve bij."
```
