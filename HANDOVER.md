# WOYZ Notes — guarded new-project handover

This folder is designed for a different Mac where GitHub CLI (`gh`) and Firebase CLI (`firebase`) are already installed and signed in.

## Safety contract

The setup must create only:

- a new GitHub repository named `woyz-notes`;
- a new Firebase project whose display name is **WOYZ Notes**;
- a new `(default)` Firestore database inside that new project;
- a new Firebase Web app inside that new project.

It must not select, reuse, rename, deploy to, push to, or modify any existing repository or Firebase project.

The script refuses to run when:

- the extracted folder is inside an existing Git repository;
- `woyz-notes` already exists under the signed-in GitHub account;
- the generated Firebase project ID already exists;
- required files or CLIs are missing;
- the exact confirmation phrase is not entered.

## Names

- GitHub repository: `woyz-notes`
- Firebase display name: `WOYZ Notes`
- Firebase project ID: generated as `woyz-notes-<UTC timestamp>-<random suffix>` because Firebase IDs must be globally unique and cannot contain spaces.
- Firestore database: `(default)` in the new Firebase project.

## Run

1. Extract the ZIP into a brand-new standalone folder that is not inside another Git repository.
2. Open Terminal in that extracted folder.
3. Review `setup-new-project.sh` before running it.
4. Run:

```bash
chmod +x setup-new-project.sh
./setup-new-project.sh
```

5. Verify the printed GitHub owner, repository name, Firebase display name, generated project ID, visibility, and Firestore location.
6. Type the exact confirmation phrase only if every target is correct.

Defaults:

- GitHub visibility: `private`
- Firestore location: `asia-south1`
- Firestore delete protection: enabled

Optional overrides:

```bash
GITHUB_VISIBILITY=public FIRESTORE_LOCATION=asia-south1 ./setup-new-project.sh
```

The Firestore location is permanent. Change it before running if `asia-south1` is not desired.

## After creation

The script prints the remaining console steps:

1. Enable Email/Password Authentication.
2. Create users in Firebase Authentication.
3. Add the GitHub Pages hostname to Authentication Authorized Domains when using GitHub Pages.
4. Enable GitHub Pages if desired.

The application stores notes at `users/{uid}/notes/{noteId}`. The included rules restrict each account to its own UID path.
