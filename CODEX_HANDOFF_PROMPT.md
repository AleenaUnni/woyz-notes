# Prompt for Codex on the other Mac

I want you to deploy this WOYZ Notes handover as completely new infrastructure.

Strict requirements:

1. Read `HANDOVER.md` and inspect `setup-new-project.sh` and `onboard-doctor-project.sh` before doing anything.
2. Do not open, select, rename, push to, deploy to, or modify any existing GitHub repository, local Git repository, Firebase project, or Firestore database.
3. The only permitted targets for initial deployment are a brand-new GitHub repository named `woyz-notes` and a brand-new Central Firebase project with display name `WOYZ Notes`.
4. The Central Firebase project ID must be newly generated and globally unique. Never substitute an existing project ID.
5. If the GitHub repository name already exists, stop. Do not reuse it and do not choose another name without asking me.
6. Run all preflight checks first and show me the exact GitHub owner, repository visibility, Firebase display name, generated Firebase project ID, and Firestore location.
7. Ask for my explicit confirmation immediately before creating the GitHub repository or Central Firebase project.
8. After confirmation, use the guarded setup script (`setup-new-project.sh`). Do not bypass or weaken any safety check.
9. Deploy only `firestore.rules` to the newly created Firebase project using an explicit `--project` argument.
10. Verify the new GitHub remote URL, the new Firebase project ID, the deployed rules, and the generated `firebase-config.js` when finished.

## Doctor Onboarding (Per-Doctor Target Firebase Projects)

Whenever a new doctor or clinic signs up requiring their own isolated Firebase database:

1. Use `onboard-doctor-project.sh` to provision an isolated target Firebase project (`firebase projects:create`).
2. Deploy `firestore.rules` directly to the doctor's target project (`firebase deploy --only firestore:rules --project <TARGET_PROJECT_ID>`).
3. Copy the generated `targetFirebaseConfig` JSON string output by `onboard-doctor-project.sh` and link it to the doctor's profile document in the Central Firebase database under `/users/{doctorUID}`.

Never run deletion, repository-renaming, project-switching, cloning, reset, force-push, or migration commands.
