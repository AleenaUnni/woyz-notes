#!/usr/bin/env bash
set -euo pipefail

# Doctor-Owned Target Project Onboarding Script for WOYZ Notes
# Deploys Cloud Firestore security rules to the doctor's Firebase project,
# and automatically links targetFirebaseConfig into Central Firestore by doctor email.

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

for command_name in firebase node git curl; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name CLI tool is required."
done

firebase login:list >/dev/null 2>&1 || fail "Firebase CLI is not signed in. Run: firebase login"

# Automatically detect Central Project ID from local configuration files (.firebaserc / firebase-config.js)
DETECTED_CENTRAL_ID=$(node -e '
try {
  const rc = require("./.firebaserc");
  console.log(rc.projects?.default || "");
} catch(e) {
  try {
    const fs = require("fs");
    const content = fs.readFileSync("./firebase-config.js", "utf8");
    const match = content.match(/"projectId":\s*"([^"]+)"/);
    console.log(match ? match[1] : "");
  } catch(e2) {
    console.log("");
  }
}
' 2>/dev/null || echo "")

CENTRAL_PROJECT_ID="${CENTRAL_PROJECT_ID:-${DETECTED_CENTRAL_ID:-woyz-notes-8c87f}}"

echo "============================================================"
echo "    WOYZ Notes — Doctor-Owned Project Onboarding Assistant  "
echo "============================================================"
echo

if [[ -z "${DOCTOR_EMAIL:-}" ]]; then
  read -rp "Enter Doctor's Email Address (e.g. drpatel@gmail.com): " DOCTOR_EMAIL
fi

if [[ -z "${TARGET_PROJECT_ID:-}" ]]; then
  read -rp "Enter Doctor's Target Firebase Project ID (e.g. patel-clinic): " TARGET_PROJECT_ID
fi

if [[ -z "${TARGET_JSON:-}" ]]; then
  echo "Paste Doctor's targetFirebaseConfig (single-line or multi-line paste allowed):"
  TARGET_JSON=$(node -e '
  const readline = require("readline");
  const rl = readline.createInterface({ input: process.stdin });
  let lines = [];
  rl.on("line", line => {
    lines.push(line);
    const joined = lines.join("\n");
    if (/\{[\s\S]*\}/.test(joined)) {
      rl.close();
    }
  });
  rl.on("close", () => {
    const fullText = lines.join("\n");
    const match = fullText.match(/\{[\s\S]*\}/);
    const str = match ? match[0] : fullText;
    try {
      const obj = (new Function("return (" + str + ")"))();
      console.log(JSON.stringify(obj));
    } catch(e) {
      console.log(str);
    }
    process.exit(0);
  });
  ' 2>/dev/null || echo "")
fi

[[ -n "$DOCTOR_EMAIL" ]] || fail "Doctor email cannot be empty."
[[ -n "$TARGET_PROJECT_ID" ]] || fail "Target project ID cannot be empty."
[[ -n "$TARGET_JSON" ]] || fail "targetFirebaseConfig JSON cannot be empty."

echo
echo "Doctor Onboarding Details:"
echo "--------------------------"
echo "Doctor Email:      $DOCTOR_EMAIL"
echo "Target Project ID: $TARGET_PROJECT_ID"
echo "Central Project:   $CENTRAL_PROJECT_ID"
echo

read -rp "Proceed with rules deployment & central database linking? (y/N): " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
  echo "Aborted by user."
  exit 0
fi

echo
echo "[1/2] Deploying Cloud Firestore Security Rules to Doctor's Project ($TARGET_PROJECT_ID)..."
[[ -f firestore.rules ]] || fail "firestore.rules file missing from current directory."

RULES_FILE="target-firestore.rules"
[[ -f "$RULES_FILE" ]] || RULES_FILE="firestore.rules"

if node -e '
const { execSync } = require("child_process");
const fs = require("fs");
const targetId = process.env.TARGET_PROJECT_ID;
const rulesFile = process.env.RULES_FILE;
fs.writeFileSync("firestore.rules.tmp", fs.readFileSync(rulesFile, "utf8"));
try {
  execSync(`firebase deploy --only firestore:rules --project ${targetId} --config <(echo "{\\"firestore\\":{\\"rules\\":\\"firestore.rules.tmp\\"}}")`, { shell: "/bin/bash", stdio: "inherit" });
} finally {
  try { fs.unlinkSync("firestore.rules.tmp"); } catch(e) {}
}
' 2>/dev/null; then
  echo ">>> SUCCESS: Cloud Firestore security rules deployed to $TARGET_PROJECT_ID!"
else
  echo "⚠️  NOTICE: CLI auto-deployment of rules to '$TARGET_PROJECT_ID' was skipped or encountered permission limits."
  echo "👉  MANUAL STEP REQUIRED: Please copy the contents of $RULES_FILE and paste into:"
  echo "    Firebase Console (console.firebase.google.com) -> Select project '$TARGET_PROJECT_ID' -> Firestore Database -> Rules tab -> Publish."
fi

echo
echo "[2/2] Querying Central Firestore for Doctor's UID ($DOCTOR_EMAIL)..."

export DOCTOR_EMAIL TARGET_PROJECT_ID TARGET_JSON CENTRAL_PROJECT_ID

node -e '
const fs = require("fs");
const path = require("path");
const os = require("os");

const email = process.env.DOCTOR_EMAIL;
const targetId = process.env.TARGET_PROJECT_ID;
const targetConfig = process.env.TARGET_JSON;
const centralId = process.env.CENTRAL_PROJECT_ID || "woyz-notes-8c87f";

async function run() {
  let token = "";
  try {
    const file = path.join(os.homedir(), ".config/configstore/firebase-tools.json");
    if (fs.existsSync(file)) {
      const data = JSON.parse(fs.readFileSync(file, "utf8"));
      token = data.tokens?.access_token || data.user?.tokens?.access_token || "";
    }
  } catch(e) {}

  if (!token) {
    console.error("WARNING: Could not obtain access token from Firebase CLI. Please run firebase login.");
    process.exit(1);
  }

  const queryUrl = `https://firestore.googleapis.com/v1/projects/${centralId}/databases/(default)/documents:runQuery`;
  const queryBody = {
    structuredQuery: {
      from: [{ collectionId: "users" }],
      where: {
        fieldFilter: {
          field: { fieldPath: "email" },
          op: "EQUAL",
          value: { stringValue: email }
        }
      },
      limit: 1
    }
  };

  const qRes = await fetch(queryUrl, {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(queryBody)
  });

  const qData = await qRes.json();
  const docName = qData[0]?.document?.name || "";
  if (!docName) {
    console.log(`NOTICE: Doctor email ${email} not found in Central Firestore yet. Please ensure user has logged into WOYZ Notes.`);
    process.exit(0);
  }

  const uid = docName.split("/").pop();
  console.log(`>>> Found Central UID for ${email}: ${uid}`);
  console.log(`Linking targetFirebaseConfig to Central Firestore users/${uid}...`);

  const updateUrl = `https://firestore.googleapis.com/v1/projects/${centralId}/databases/(default)/documents/users/${uid}?updateMask.fieldPaths=targetFirebaseConfig&updateMask.fieldPaths=targetProjectId&updateMask.fieldPaths=email`;
  const updateBody = {
    fields: {
      email: { stringValue: email },
      targetProjectId: { stringValue: targetId },
      targetFirebaseConfig: { stringValue: targetConfig }
    }
  };

  const uRes = await fetch(updateUrl, {
    method: "PATCH",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(updateBody)
  });

  if (uRes.status === 200) {
    console.log(`>>> SUCCESS: Central Firestore document users/${uid} linked automatically!`);
  } else {
    console.error(`WARNING: Central database link returned status ${uRes.status}.`);
  }
}

run().catch(err => {
  console.error("Linking error:", err.message);
});
'

echo
echo "============================================================"
echo "    DOCTOR ONBOARDING COMPLETE!                             "
echo "============================================================"
echo
echo "Doctor Email:      $DOCTOR_EMAIL"
echo "Target Project ID: $TARGET_PROJECT_ID"
echo
echo ""