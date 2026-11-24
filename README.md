# Kinetic

Combat sports, atletische telemetrie en Type 1 Diabetes/CGM-monitoring in één Flutter-app,
met Supabase als backend. De specificatie staat in `CLAUDE.md`; build- en testcommando's staan in `RUN_COMMANDS.md`.

## Structuur

| Map | Inhoud |
| --- | --- |
| `lib/state/kinetic_store.dart` | Centrale app-state (equivalent van `useKineticStore.ts` uit de spec) |
| `lib/screens/` | Vandaag, Training, Technieken, Eten, Live sessie, Ronde rust, Wedstrijden, Instellingen & export |
| `lib/core/` | Pure logica: glucoseregels/mat-clearance, IOB, maaltijd-impact, gewichtsplan, rondetimer |
| `lib/repositories/` | Supabase-toegang (bestaand schema, RLS per gebruiker) |
| `lib/services/` | Dexcom Share, Nightscout, Polar H10 (simulatie), spraakmemo, export |
| `lib/theme/kinetic_theme.dart` | Kinetic Dark Theme-tokens |
| `lib/supabase/migrations/` | SQL-migraties |

Flutter 3.50+: Material komt uit `package:material_ui`. `package:flutter/material.dart` is deprecated.
