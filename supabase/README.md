# Katiba Yetu Supabase

This folder was restored from the previous Katiba Yetu repository.

## Source of truth

- The SQL migrations in `supabase/migrations/` define the application database/workflow schema.
- Constitutional text remains in `public/katiba/` and is not replaced by Supabase.
- Old local `.temp` link files are intentionally excluded because they point to a previous Supabase project/environment.

## New project setup

Link this repository to the dedicated Katiba Yetu Supabase project before applying migrations. Do not link it to an unrelated project.

Frontend configuration should use Vite environment variables:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Never commit a Supabase secret/service-role key to this repository.
