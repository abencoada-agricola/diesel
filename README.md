# Abençoada Diesel

A diesel refueling log for agricultural fleets, with an Android app for workers and a web dashboard for managers. Both the Android app and the web field form keep pending entries on the device when there is no internet.

The website runs on GitHub Pages. Supabase stores the records and handles administrator authentication. The interface is in Portuguese.

- [Android APK](https://github.com/abencoada-agricola/diesel/releases/latest/download/abencoada-diesel.apk)
- [Field form](https://abencoada-agricola.github.io/diesel/)
- [Administration](https://abencoada-agricola.github.io/diesel/admin.html)

## Android app

Install the APK on Android 8 or later. Android may ask you to allow installation from the browser used to download it. Sign in with the username and password assigned by the manager while connected to the internet.

1. Tap **Ler QR Code** and point the camera at the fleet label. The fleet code can also be entered manually.
2. Check the previous readings shown for that fleet.
3. Enter the current reading before refueling and the liters supplied.
4. Tap **Salvar abastecimento**.

Each fleet has its own required meters. Trucks and other vehicles initially use KM, tractors use the engine hour meter, and harvesters use engine and elevator hour meters. Managers can change these choices under **Frotas → Escolher leituras**. The app only asks for the selected meters and liters; it does not ask for dispenser readings. Worker name, date, and time are recorded automatically. The server takes the signature from the signed-in account.

The QR contains a stable fleet code and descriptive information. It does not contain readings that would become outdated. The app uses the latest catalog downloaded from the database, or the saved copy when offline. Only active fleets in that catalog can be selected.

The first login needs internet. After a successful login, the app can reopen and save entries without a connection. Pending entries and drafts are stored in the app's IndexedDB on that phone. Keep the app installed and do not clear its data while entries are pending. Signing out is blocked until pending entries have been received or corrected.

With the app open, it checks for a connection every 15 seconds, when resumed, or when **Enviar** is tapped. Entries are sent in capture order and removed from the phone only after a matching database receipt. Retries use the same entry ID to avoid duplicates. If the session expires, reconnect and sign in to the original account; pending entries remain saved.

The app checks current readings against its saved readings and earlier pending entries. The database checks again against all received entries for that fleet. Lower readings are rejected. A rejected entry remains available for correction, and later entries for that fleet wait until it is resolved. Other fleets can continue to synchronize. Synchronization is not guaranteed while the app is closed.

Each accepted Android entry stores the previous meter readings, the current readings, and a reference to the previous received entry. The dashboard displays this comparison. On a disconnected phone, the previous reading may be older than another phone's latest submission; the database resolves this at synchronization.

## Web field form

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

## Web offline use

Open the app with internet at least once so it can download the form and fleet catalog. Before going to the field, test reopening it in airplane mode. On Android, use Chrome's **Install app** or **Add to Home screen** option.

Drafts and pending entries are stored in the browser's IndexedDB on that device. No login is needed to reopen the field form. With the app open, synchronization runs when the connection returns, every 15 seconds, or when **Tentar enviar** is tapped.

An entry stays on the device until the database confirms receipt. Each submission has a unique ID and confirmation key to prevent duplicate records after a retry. Date, time, and worker name are preserved during synchronization.

The app checks readings against its saved catalog and local queue. The database checks them again against the latest received readings. If another device has submitted a higher reading, the conflicting entry remains on the original device for correction and resubmission.

Do not clear browser storage while entries are pending. Pending entries do not transfer to another phone. Automatic synchronization requires the app to be open; it is not guaranteed after the app is closed. Pending entries from the earlier account-based form still require the original account session to synchronize.

## Administration

Administrators sign in with a username and password. They can view and filter records by fleet, worker, date, and synchronization status, inspect readings, export CSV files, and print reports. Received records cannot be edited or deleted through the app.

The dashboard checks for new records every 15 seconds while open and shows unread notices in the bell. Optional browser notifications also require the dashboard to remain open.

**Frotas** manages the fleet catalog and required Android meters. Use **Gerar QR Code** to download or print a fleet label, or **Imprimir todos os QR Codes** for the whole active catalog. Attach the corresponding label to each machine. The APK download is also available on this page. **Configurações** manages access permissions, usernames, and validation rules. Use **Definir senha** in **Equipe e acessos** to create a login or replace an existing password. Passwords require at least 6 characters and confirmation. The server checks the manager’s authenticated session and team membership before calling Supabase Auth; passwords are never stored in the team table. These passwords belong to Diesel and do not change GMAIS credentials. Usernames contain 3–30 letters without accents, numbers, dots, hyphens, or underscores; capitalization does not matter. Email login remains available for existing accounts during the transition.

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

4. Run `supabase/usernames.sql`, then `supabase/field-access.sql` and `supabase/mobile.sql`, once and in that order. The username migration assigns existing accounts an initial username based on their email prefix. It can be changed in the dashboard.
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

## Android builds

The **Build Android APK** workflow builds and signs the app, verifies its signature, and publishes it under GitHub Releases. It uses the same three public Supabase variables as the website. Add these repository secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded PKCS12 signing keystore, with alias `abencoada`.
- `ANDROID_KEYSTORE_PASSWORD`: the keystore password.

Keep a private backup of the original keystore and its password outside the repository. Future APK updates must use the same signing key. Do not commit keystores or passwords. The Android application ID is `br.com.abencoada.diesel`.

For local builds, install Node.js 22, Java 21, and the Android SDK, then run:

```sh
npm ci
npm run android:sync
```

Open `android/` in Android Studio to run on a phone. For a signed release, pass `ANDROID_KEYSTORE_PATH` and `ANDROID_KEYSTORE_PASSWORD` to Gradle and build `assembleRelease`. Supply the public Supabase variables before `android:sync`; a build without them only previews the interface.

The Android app bundles the interface in the APK and uses the native camera scanner. The existing web form remains available as a separate option.

## Development

Use Node.js 22 or later.

```sh
npm ci
npm run dev
npm test
npm run build
```

`npm run dev` serves the local interface. Backend access requires Supabase configuration. The build reads the deployment variables above and writes the configured site to `dist/`.

The service worker caches the interface, fleet catalog, and authentication SDK. Versioned asset names keep deployed updates consistent. Tests use a local PostgreSQL-compatible database to check permissions, required fields, meter rules, declared signatures, and duplicate submissions. Login tests check session handling and failure responses, including the Android origin. Android submission tests cover selected meters, previous readings, account signatures, conflicting entries, and permissions. QR tests generate a real image and decode it to verify the fleet code. They do not write to the production database.
