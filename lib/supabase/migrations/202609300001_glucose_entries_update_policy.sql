-- glucose_entries had select/insert/delete policies maar geen update-policy,
-- terwijl de app een vingerprik-meting wel laat bewerken
-- (GlucoseEntryRepository.update, gebruikt in now_screen.dart en beide
-- sessiecontrollers). Zonder deze policy faalt dat updaten stil op de
-- achtergrond. Puur additief: geen bestaande rijen worden aangeraakt.
drop policy if exists "Users can update own glucose entries" on public.glucose_entries;
create policy "Users can update own glucose entries"
  on public.glucose_entries for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
