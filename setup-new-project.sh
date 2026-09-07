#!/usr/bin/env bash
set -euo pipefail

# Guarded creator for a NEW GitHub repository and a NEW Firebase project.
# It intentionally refuses to reuse or alter existing repositories/projects.

REPO_NAME="woyz-notes"
DISPLAY_NAME="WOYZ Notes"
GITHUB_VISIBILITY="${GITHUB_VISIBILITY:-private}"
FIRESTORE_LOCATION="${FIRESTORE_LOCATION:-asia-south1}"
PROJECT_ID="${FIREBASE_PROJECT_ID:-woyz-notes-$(date -u +%Y%m%d%H%M%S)-$(printf '%04x' "$((RANDOM % 65536))")}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

for command_name in gh firebase git node; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name is required."
done

case "$GITHUB_VISIBILITY" in
  public|private|internal) ;;
  *) fail "GITHUB_VISIBILITY must be public, private, or internal." ;;
esac

[[ -f index.html ]] || fail "Run this script from the extracted handover folder."
[[ -f firestore.rules ]] || fail "firestore.rules is missing."
[[ -f firebase.json ]] || fail "firebase.json is missing."

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "This folder is inside an existing Git repository. Extract the handover into a completely separate folder and try again."
fi

gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not signed in. Run: gh auth login"
firebase login:list >/dev/null 2>&1 || fail "Firebase CLI is not signed in. Run: firebase login"

GITHUB_OWNER="$(gh api user --jq .login)"
if gh repo view "$GITHUB_OWNER/$REPO_NAME" >/dev/null 2>&1; then
  fail "GitHub repository $GITHUB_OWNER/$REPO_NAME already exists. Nothing was changed."
fi

if firebase projects:list --json | node -e '
let input="";
process.stdin.on("data",chunk=>input+=chunk);
process.stdin.on("end",()=>{
  const data=JSON.parse(input);
  const projects=data.result || data;
  const target=process.argv[1];
  process.exit(Array.isArray(projects) && projects.some(project=>project.projectId===target) ? 0 : 1);
});
' "$PROJECT_ID"; then
  fail "Firebase project $PROJECT_ID already exists. Nothing was changed."
fi

echo
echo "A NEW setup will be created."
echo "GitHub:   $GITHUB_OWNER/$REPO_NAME ($GITHUB_VISIBILITY)"
echo "Firebase: $DISPLAY_NAME"
echo "Project:  $PROJECT_ID"
echo "Firestore location: $FIRESTORE_LOCATION"
echo
echo "No existing GitHub repository or Firebase project will be selected, reused, renamed, or modified."
read -r -p 'Type CREATE NEW WOYZ NOTES to continue: ' confirmation
[[ "$confirmation" == "CREATE NEW WOYZ NOTES" ]] || fail "Confirmation did not match. Nothing was changed."

echo "Creating a new local Git repository..."
git init -b main
git add index.html firebase-config.js firestore.rules firebase.json README.md .firebaserc.example setup-new-project.sh HANDOVER.md CODEX_HANDOFF_PROMPT.md
git commit -m "Initial WOYZ Notes application"

echo "Creating a brand-new GitHub repository..."
gh repo create "$REPO_NAME" "--$GITHUB_VISIBILITY" --source=. --remote=origin --description "WOYZ Notes" --push

echo "Creating a brand-new Firebase project..."
firebase projects:create "$PROJECT_ID" --display-name "$DISPLAY_NAME"

echo "Creating the new project's default Firestore database..."
firebase firestore:databases:create '(default)' --location="$FIRESTORE_LOCATION" --delete-protection ENABLED --project "$PROJECT_ID"

echo "Registering a new Firebase Web app..."
temporary_dir="$(mktemp -d)"
firebase apps:create WEB "WOYZ Notes Web" --project "$PROJECT_ID" --json > "$temporary_dir/app.json"

APP_ID="$(node -e '
const fs=require("fs");
const data=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const result=data.result || data;
const id=result.appId || result.app?.appId;
if(!id) process.exit(1);
process.stdout.write(id);
' "$temporary_dir/app.json")" || fail "The Web app was created, but its app ID could not be read. Stop and ask Codex to inspect $temporary_dir/app.json before continuing."

firebase apps:sdkconfig WEB "$APP_ID" --project "$PROJECT_ID" --json > "$temporary_dir/sdk.json"
node -e '
const fs=require("fs");
const input=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
let config=input.result?.sdkConfig ?? input.result?.config ?? input.result ?? input.sdkConfig ?? input;
if(typeof config === "string") {
  const jsonMatch=config.match(/\{[\s\S]*\}/);
  if(!jsonMatch) throw new Error("SDK configuration was not recognized.");
  config=JSON.parse(jsonMatch[0]);
}
const allowed=["apiKey","authDomain","projectId","storageBucket","messagingSenderId","appId","measurementId"];
const clean=Object.fromEntries(allowed.filter(key=>config[key] != null).map(key=>[key,config[key]]));
if(!clean.apiKey || !clean.projectId || !clean.appId) throw new Error("SDK configuration is incomplete.");
fs.writeFileSync("firebase-config.js",`export const firebaseConfig = ${JSON.stringify(clean,null,2)};\n`);
' "$temporary_dir/sdk.json"

cat > .firebaserc <<EOF
{
  "projects": {
    "default": "$PROJECT_ID"
  }
}
EOF

echo "Deploying only the included Firestore rules to the NEW project..."
firebase deploy --only firestore:rules --project "$PROJECT_ID"

git add firebase-config.js .firebaserc
git commit -m "Configure new Firebase project"
git push origin main

echo
echo "NEW WOYZ Notes resources created successfully."
echo "GitHub repository: https://github.com/$GITHUB_OWNER/$REPO_NAME"
echo "Firebase project ID: $PROJECT_ID"
echo
echo "Next manual steps:"
echo "1. Enable Email/Password in Firebase Authentication."
echo "2. Create the required users in Firebase Authentication."
echo "3. If using GitHub Pages, add $GITHUB_OWNER.github.io to Authentication > Authorized domains."
echo "4. Enable GitHub Pages for the repository if desired."
