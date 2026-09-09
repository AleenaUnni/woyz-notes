# WOYZ Firebase deployment

This package uses Firebase Authentication and Cloud Firestore. Notes are stored at:

`users/{firebaseAuthUid}/notes/{noteId}`

The UID comes from the signed-in Firebase account. The included Firestore rules prevent one user from reading or changing another user's notes. The same account can remain signed in on multiple devices, and Firestore listeners synchronize changes in real time.

---

## 📋 Doctor Pre-Requisites (Before Running Onboarding Script)

Before onboarding a doctor to their own isolated database, complete these 6 steps:

1. **Create a Firebase Project**: Go to [Firebase Console](https://console.firebase.google.com/), click **Add project**, enter a name (e.g. `Dr Patel Clinic`), and note the auto-generated **Project ID** (e.g., `patel-clinic-1a2b3`).
2. **Enable Cloud Firestore**: In doctor's project, go to **Build ➔ Firestore Database**, click **Create database**, choose location and select **Start in production mode**.
3. **Register Web App & Copy Config**: Go to **Project settings ⚙️ ➔ General**, under "Your apps" click the Web icon `</>`, register app, and copy the `firebaseConfig` snippet.
4. **Create Doctor Account in Central Firebase (Admin Task)**: In Central Firebase Console ➔ **Authentication ➔ Users**, click **Add user** to create the doctor's account (`drpatel@clinic.com`) and temporary password.
5. **Grant Admin Editor Permission (For Automated Rules Deployment)**: In the doctor's target project in Firebase Console, go to **Project settings ⚙️ ➔ Users and permissions** tab, click **Add member**, and add the Admin / Central Firebase account email as **Editor** or **Owner**. This allows the onboarding script to deploy `firestore.rules` automatically.
6. **Sign In Once on WOYZ Notes**: Open the WOYZ Notes app in browser and sign in once with the doctor's account. This automatically provisions the doctor's document (`users/{uid}`) in Central Firestore so the script can link their database config.

### ⏰ When to Run the Onboarding Script

Run `./onboard-doctor-project.sh` **AFTER** completing all 6 doctor pre-requisites listed above.

Specifically, run it when:
- A new doctor is being onboarded who requires data isolation in their own Firebase project.
- The Admin has already created the doctor's account in Central Firebase Authentication (`drpatel@clinic.com`).
- The doctor has logged into WOYZ Notes at least once (so their user record exists in Central Firestore) and provided their Firebase Project ID and Web App `firebaseConfig`.

### 🚀 Running the Automated Onboarding Script

Run the onboarding script in your terminal:

```bash
firebase login  # Log in with Google account having owner/editor access to doctor's project
./onboard-doctor-project.sh
```

Follow the prompts to enter:
1. Doctor's Email (`drpatel@clinic.com`)
2. Doctor's Target Firebase Project ID (`patel-clinic-1a2b3`)
3. Doctor's `firebaseConfig` snippet

---

## 1. Create and configure Firebase

1. Create a Firebase project.
2. Add a Web app in **Project settings > Your apps**.
3. Copy its configuration values into `firebase-config.js`.
4. Open **Authentication > Sign-in method** and enable **Email/Password**.
5. Create each doctor/user under **Authentication > Users**.
6. Create a Cloud Firestore database in production mode.

## 2. Deploy the Firestore rules

Install and authenticate the Firebase CLI, then run from this directory:

```bash
firebase login
cp .firebaserc.example .firebaserc
firebase deploy --only firestore:rules
```

Replace `YOUR_PROJECT_ID` in `.firebaserc` before deployment. You can alternatively paste `firestore.rules` into **Firestore Database > Rules** in the Firebase console and publish it there.

## 3. Publish the web files

For GitHub Pages, commit at least:

- `index.html`
- `firebase-config.js`

In Firebase Authentication settings, add the GitHub Pages hostname (for example, `username.github.io`) to **Authorized domains**.

For Firebase Hosting, run:

```bash
firebase deploy --only hosting
```

## Data behavior

- The app opens on today's date after sign-in.
- Previous, next, and calendar-date controls load notes for that date.
- Each user sees only documents under their own UID.
- New drafts are immediately created in Firestore.
- Generated text is saved back to the draft.
- **Save Draft** finalizes and persists the note.
- Draft deletion removes the Firestore document.
- Real-time listeners allow the same user to see changes across multiple devices.

## Important

The Firebase web configuration is not a server secret. Access control depends on Firebase Authentication and the deployed `firestore.rules`. Never use permissive test rules in production.
