# Abençoada Diesel

A mobile-friendly diesel refueling log for agricultural fleets. The field form works without a login and stores entries on the device when there is no internet. Managers use a separate, protected dashboard.

The website runs on GitHub Pages. Supabase stores the records and handles administrator authentication. The interface is in Portuguese.

- [Field form](https://abencoada-agricola.github.io/diesel/)
- [Administration](https://abencoada-agricola.github.io/diesel/admin.html)

## Field use

Open the form, enter the worker's name and fleet code, fill in the readings, and tap **Enviar abastecimento**. Fleet codes can be typed or selected from the suggestions.

Each entry requires:

- Worker name
- Fleet code
- Engine hour meter
- Elevator hour meter
- Mileage (KM)
- Initial and final dispenser readings
- Liters supplied

The date and time are recorded automatically when the entry is saved. The worker's name becomes the signature. This is a declared name, not a verified identity. Earlier records submitted through an account keep their original account signature.

All readings are required. Liters must be greater than zero, and the final dispenser reading must exceed the initial reading. Mileage and both hour meters cannot fall below the highest readings already recorded for that fleet. Equal readings are allowed. Managers can also require liters to match the difference between the dispenser readings, with a tolerance of 0.02 L.

## Offline use

Open the app with internet at least once so it can download the form and fleet catalog. Before going to the field, test reopening it in airplane mode. On Android, use Chrome's **Install app** or **Add to Home screen** option.

Drafts and pending entries are stored in the browser's IndexedDB on that device. No login is needed to reopen the field form. With the app open, synchronization runs when the connection returns, every 15 seconds, or when **Tentar enviar** is tapped.

An entry stays on the device until the database confirms receipt. Each submission has a unique ID and confirmation key to prevent duplicate records after a retry. Date, time, and worker name are preserved during synchronization.

The app checks readings against its saved catalog and local queue. The database checks them again against the latest received readings. If another device has submitted a higher reading, the conflicting entry remains on the original device for correction and resubmission.

Do not clear browser storage while entries are pending. Pending entries do not transfer to another phone. Automatic synchronization requires the app to be open; it is not guaranteed after the app is closed. Pending entries from the earlier account-based form still require the original account session to synchronize.

## Administration

Administrators sign in with a username and password. They can view and filter records by fleet, worker, date, and synchronization status, inspect readings, export CSV files, and print reports. Received records cannot be edited or deleted through the app.

The dashboard checks for new records every 15 seconds while open and shows unread notices in the bell. Optional browser notifications also require the dashboard to remain open.

**Frotas** manages the fleet catalog. **Configurações** manages access permissions, usernames, and validation rules. Account passwords are managed in Supabase. Usernames contain 3–30 letters without accents, numbers, dots, hyphens, or underscores; capitalization does not matter. Email login remains available for existing accounts during the transition.

Public access is limited to the fleet catalog, latest readings, validation rules, and validated submissions. Stored record history and worker names can only be retrieved by authorized accounts. Administration requires a manager account. Database tables have Row Level Security and cannot be accessed directly by public clients.

## Setup and deployment

For a new Supabase project:

1. Run `supabase/schema.sql`, then `supabase/fleets.sql` in the SQL Editor. The bundled catalog contains 246 fleets exported on October 7, 2026.
2. Disable public account signup in Supabase Authentication and create the manager's account there.
3. Register that account in the database, using its lowercase email:

   ```sql
   insert into public.members (email, name, role)
   values ('manager@example.com', 'Manager Name', 'admin');
   ```

4. Run `supabase/usernames.sql`, then `supabase/field-access.sql`, once and in that order. The username migration assigns existing accounts an initial username based on their email prefix. It can be changed in the dashboard.
5. Deploy `supabase/functions/diesel-login/index.ts` as **diesel-login**, using `supabase/config.toml`. Keep `verify_jwt = true`. The function resolves usernames on the server and checks passwords with Supabase Auth. Login attempts are limited by username and IP address.
6. Add these repository variables under **Settings → Secrets and variables → Actions → Variables**:

   | Variable | Value |
   | --- | --- |
   | `SUPABASE_URL` | Project URL |
   | `SUPABASE_PUBLISHABLE_KEY` | Public publishable key |
   | `SUPABASE_LOGIN_KEY` | Public legacy `anon` JWT key for the login function |

7. Enable GitHub Pages with **GitHub Actions** as the source, then run **Publicar sistema** or push to `main`.

Existing installations should apply only migrations they have not already run. Do not rerun the initial schema on an existing database.

The workflow runs tests, builds the site, and deploys `dist/`. Administrative keys stay in the Supabase function environment. Never place passwords, secret keys, or `service_role` keys in the website or repository.

## Development

Use Node.js 22 or later.

```sh
npm ci
npm run dev
npm test
npm run build
```

`npm run dev` serves the local interface. Backend access requires Supabase configuration. The build reads the deployment variables above and writes the configured site to `dist/`.

The service worker caches the interface, fleet catalog, and authentication SDK. Versioned asset names keep deployed updates consistent. Tests use a local PostgreSQL-compatible database to check permissions, required fields, meter rules, declared signatures, and duplicate submissions. Login tests check session handling and failure responses. They do not write to the production database.
