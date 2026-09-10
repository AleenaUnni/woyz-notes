# Prompt for Codex on the other Mac

I want you to deploy this WOYZ Notes handover as completely new infrastructure.

---

## Phase 1: Initial Central Infrastructure Setup (EXECUTE NOW)

Strict requirements:

1. Read `HANDOVER.md` and inspect `setup-new-project.sh` and `onboard-doctor-project.sh` before doing anything.
2. Do not open, select, rename, push to, deploy to, or modify any existing GitHub repository, local Git repository, Firebase project, or Firestore database.
3. The only permitted targets for initial deployment are a brand-new GitHub repository named `woyz-notes` and a brand-new Central Firebase project with display name `WOYZ Notes`.
4. The Central Firebase project ID must be newly generated and globally unique. Never substitute an existing project ID.
5. If the GitHub repository name already exists, stop. Do not reuse it and do not choose another name without asking me.
6. Run all preflight checks first and show me the exact GitHub owner, repository visibility, Firebase display name, generated Firebase project ID, and Firestore location.
7. Ask for my explicit confirmation immediately before creating the GitHub repository or Central Firebase project.
8. After confirmation, use the guarded setup script (`setup-new-project.sh`). Do not bypass or weaken any safety check.
9. Deploy only `firestore.rules` to the newly created Central Firebase project using an explicit `--project` argument.
10. Verify the new GitHub remote URL, the new Firebase project ID, the deployed rules, and the generated `firebase-config.js` when finished.
11. **When Phase 1 is complete**, inform me that Central setup is finished and remind me how to trigger doctor onboarding in the future by printing:
    > *"Initial Central infrastructure setup is complete! Whenever you need to onboard a doctor in the future, simply prompt me with:*
    > `We have a new doctor drpatel@gmail.com. Please onboard their target project patel-clinic.`"

---

## Phase 2: Doctor Onboarding (EXECUTE LATER ON-DEMAND)

**Do NOT execute this phase during initial setup.** Only execute Phase 2 when requested in the future to onboard a specific doctor/clinic requiring their own isolated Firebase database:

1. Provision an isolated target Firebase project (`firebase projects:create <TARGET_PROJECT_ID>`) and register a Web App (`firebase apps:create WEB`) to obtain the doctor's `targetFirebaseConfig` JSON.
2. Ensure the admin account (or signed-in Firebase CLI account) is granted **Editor** or **Owner** permission under **Project settings ➔ Users and permissions** in the doctor's target project so CLI rules deployment is authorized.
3. Ensure the doctor has signed into WOYZ Notes at least once so their profile document (`/users/{doctorUID}`) exists in Central Firestore.
4. Run `onboard-doctor-project.sh` (supplying `DOCTOR_EMAIL`, `TARGET_PROJECT_ID`, and `TARGET_JSON`). The script will automatically deploy `target-firestore.rules` to the doctor's target project and automatically link `targetFirebaseConfig` into the doctor's user document in Central Firestore under `/users/{doctorUID}`.

Never run deletion, repository-renaming, project-switching, cloning, reset, force-push, or migration commands.
