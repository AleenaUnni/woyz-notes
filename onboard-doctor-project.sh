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
  echo "Paste Doctor's targetFirebaseConfig JSON string:"
  read -rp "> " TARGET_JSON
fi

[[ -n "$DOCTOR_EMAIL" ]] || fail "Doctor email cannot be empty."
[[ -n "$TARGET_PROJECT_ID" ]] || fail "Target project ID cannot be empty."
[[ -n "$TARGET_JSON" ]] || fail "targetFirebaseConfig JSON cannot be empty."

# Sanitize JSON string
TARGET_JSON=$(echo "$TARGET_JSON" | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  try {
    let str = input.trim();
    const match = str.match(/\{[\s\S]*\}/);
    if (match) str = match[0];
    try {
      const obj = JSON.parse(str);
      console.log(JSON.stringify(obj));
    } catch(e) {
      const obj = (new Function("return (" + str + ")"))();
      console.log(JSON.stringify(obj));
    }
  } catch(e2) {
    console.log(input.trim());
  }
});
' 2>/dev/null || echo "$TARGET_JSON")

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
firebase deploy --only firestore:rules --project "$TARGET_PROJECT_ID" || fail "Failed to deploy firestore.rules to $TARGET_PROJECT_ID."

echo "[2/2] Querying Central Firestore for Doctor's UID ($DOCTOR_EMAIL)..."
DOCTOR_UID=""
TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)

if [[ -n "$TOKEN" ]]; then
  LOOKUP_UID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "https://firestore.googleapis.com/v1/projects/${CENTRAL_PROJECT_ID}/databases/(default)/documents:runQuery" \
    -d "{
      \"structuredQuery\": {
        \"from\": [{\"collectionId\": \"users\"}],
        \"where\": {
          \"fieldFilter\": {
            \"field\": {\"fieldPath\": \"email\"},
            \"op\": \"EQUAL\",
            \"value\": {\"stringValue\": \"$DOCTOR_EMAIL\"}
          }
        },
        \"limit\": 1
      }
    }" | node -e '
    let input = "";
    process.stdin.on("data", chunk => input += chunk);
    process.stdin.on("end", () => {
      try {
        const data = JSON.parse(input);
        const name = data[0]?.document?.name || "";
        const uid = name.split("/").pop();
        console.log(uid || "");
      } catch(e) {
        console.log("");
      }
    });
    ' 2>/dev/null || echo "")

  if [[ -n "$LOOKUP_UID" ]]; then
    DOCTOR_UID="$LOOKUP_UID"
    echo ">>> Found Central UID for $DOCTOR_EMAIL: $DOCTOR_UID"
    
    echo "Linking targetFirebaseConfig to Central Firestore users/$DOCTOR_UID..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      "https://firestore.googleapis.com/v1/projects/${CENTRAL_PROJECT_ID}/databases/(default)/documents/users/${DOCTOR_UID}?updateMask.fieldPaths=targetFirebaseConfig&updateMask.fieldPaths=targetProjectId&updateMask.fieldPaths=email" \
      -d "{
        \"fields\": {
          \"email\": {\"stringValue\": \"$DOCTOR_EMAIL\"},
          \"targetProjectId\": {\"stringValue\": \"$TARGET_PROJECT_ID\"},
          \"targetFirebaseConfig\": {\"stringValue\": \"$TARGET_JSON\"}
        }
      }" || echo "500")

    if [[ "$HTTP_CODE" == "200" ]]; then
      echo ">>> SUCCESS: Central Firestore document users/$DOCTOR_UID linked automatically!"
    else
      echo "WARNING: Central database link returned status $HTTP_CODE."
    fi
  else
    echo "NOTICE: Doctor email $DOCTOR_EMAIL not found in Central Firestore yet. Please ensure user is created under Central Auth."
  fi
fi

echo
echo "============================================================"
echo "    DOCTOR ONBOARDING COMPLETE!                             "
echo "============================================================"
echo
echo "Doctor Email:      $DOCTOR_EMAIL"
echo "Target Project ID: $TARGET_PROJECT_ID"
echo
echo ""