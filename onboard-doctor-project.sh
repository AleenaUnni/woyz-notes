#!/usr/bin/env bash
set -euo pipefail

# Automated Doctor/Clinic Target Project Onboarding Script for WOYZ Notes
# Provisions a new isolated target Firebase project, deploys Cloud Firestore rules,
# and generates the targetFirebaseConfig JSON snippet for central database integration.

FIRESTORE_LOCATION="${FIRESTORE_LOCATION:-asia-south1}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

for command_name in firebase node git; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name CLI tool is required."
done

firebase login:list >/dev/null 2>&1 || fail "Firebase CLI is not signed in. Run: firebase login"

echo "============================================================"
echo "    WOYZ Notes — Doctor Target Project Onboarding Assistant  "
echo "============================================================"
echo

# Prompt for clinic/doctor details if not supplied in environment
if [[ -z "${CLINIC_NAME:-}" ]]; then
  read -rp "Enter Doctor/Clinic Display Name (e.g., Smith Clinic): " CLINIC_NAME
fi

if [[ -z "${DOCTOR_EMAIL:-}" ]]; then
  read -rp "Enter Doctor Email Address (e.g., drsmith@gmail.com): " DOCTOR_EMAIL
fi

[[ -n "$CLINIC_NAME" ]] || fail "Clinic name cannot be empty."
[[ -n "$DOCTOR_EMAIL" ]] || fail "Doctor email cannot be empty."

# Generate a clean, globally unique Firebase project ID
SLUG=$(echo "$CLINIC_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c 1-18)
[[ -n "$SLUG" ]] || SLUG="clinic"
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
RAND_SUFFIX=$(printf '%04x' "$((RANDOM % 65536))")
TARGET_PROJECT_ID="${TARGET_PROJECT_ID:-woyz-${SLUG}-${TIMESTAMP}-${RAND_SUFFIX}}"

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

# Automatically query Central Firestore to find doctor UID by email if not supplied
if [[ -z "${DOCTOR_UID:-}" ]]; then
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
      echo ">>> Automatically found Central Auth UID for $DOCTOR_EMAIL: $DOCTOR_UID"
    fi
  fi
fi

echo
echo "Target Setup Details:"
echo "--------------------"
echo "Doctor Email:      $DOCTOR_EMAIL"
echo "Clinic Name:       $CLINIC_NAME"
echo "Target Project ID: $TARGET_PROJECT_ID"
echo "Central Project:   ${CENTRAL_PROJECT_ID:-woyz-notes-8c87f}"
echo "Database Location: $FIRESTORE_LOCATION"
echo

read -rp "Proceed with project creation & rules deployment? (y/N): " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
  echo "Aborted by user."
  exit 0
fi

echo
echo "[1/4] Creating new Firebase Project ($TARGET_PROJECT_ID)..."
firebase projects:create "$TARGET_PROJECT_ID" --display-name "$CLINIC_NAME" || fail "Failed to create Firebase project $TARGET_PROJECT_ID."

echo "[2/4] Deploying Firestore Security Rules to target project..."
[[ -f firestore.rules ]] || fail "firestore.rules file missing from current directory."
firebase deploy --only firestore:rules --project "$TARGET_PROJECT_ID" || fail "Failed to deploy firestore.rules to $TARGET_PROJECT_ID."

echo "[3/4] Registering Web App inside target project..."
firebase apps:create WEB "WOYZ Web App" --project "$TARGET_PROJECT_ID" || true

echo "[4/4] Extracting Target Firebase Configuration..."
RAW_CONFIG=$(firebase apps:sdkconfig WEB --project "$TARGET_PROJECT_ID" || fail "Unable to fetch SDK config.")

# Parse SDK config output to extract JSON object
TARGET_JSON=$(echo "$RAW_CONFIG" | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  try {
    const match = input.match(/const\s+firebaseConfig\s*=\s*(\{[\s\S]*?\});/);
    if (match) {
      const obj = (new Function("return " + match[1]))();
      console.log(JSON.stringify(obj));
    } else {
      console.log("{}");
    }
  } catch (e) {
    console.log("{}");
  }
});
')

# Optional automated central database update if DOCTOR_UID is provided
CENTRAL_LINKED="false"
if [[ -n "${DOCTOR_UID:-}" && "$TARGET_JSON" != "{}" ]]; then
  echo "[5/5] Attempting automatic link in Central Database (woyz-notes-8c87f)..."
  TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)
  if [[ -n "$TOKEN" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      "https://firestore.googleapis.com/v1/projects/${CENTRAL_PROJECT_ID:-woyz-notes-8c87f}/databases/(default)/documents/users/${DOCTOR_UID}?updateMask.fieldPaths=targetFirebaseConfig&updateMask.fieldPaths=targetProjectId&updateMask.fieldPaths=email" \
      -d "{
        \"fields\": {
          \"email\": {\"stringValue\": \"$DOCTOR_EMAIL\"},
          \"targetProjectId\": {\"stringValue\": \"$TARGET_PROJECT_ID\"},
          \"targetFirebaseConfig\": {\"stringValue\": \"$TARGET_JSON\"}
        }
      }" || echo "500")
    if [[ "$HTTP_CODE" == "200" ]]; then
      CENTRAL_LINKED="true"
      echo ">>> Successfully linked targetFirebaseConfig directly to Central Firestore document users/$DOCTOR_UID!"
    fi
  fi
fi

echo
echo "============================================================"
echo "    AUTOMATED TARGET SETUP COMPLETE!                        "
echo "============================================================"
echo
echo "Target Project ID: $TARGET_PROJECT_ID"
echo
echo "Generated targetFirebaseConfig JSON String:"
echo "------------------------------------------"
echo "$TARGET_JSON"
echo "------------------------------------------"
echo

if [[ "$CENTRAL_LINKED" == "true" ]]; then
  echo ">>> Central Firestore Link: AUTOMATICALLY COMPLETED for user $DOCTOR_UID!"
else
  echo "============================================================"
  echo "    MANUAL CENTRAL LINKING (If not automatically linked)    "
  echo "============================================================"
  echo "Open Central Firebase Console: https://console.firebase.google.com/project/${CENTRAL_PROJECT_ID:-woyz-notes-8c87f}/firestore"
  echo "Go to 'users' collection -> Select document for '$DOCTOR_EMAIL' (UID: ${DOCTOR_UID:-'doctor-uid'})."
  echo "Add field 'targetFirebaseConfig' (string) = (Paste JSON above)"
  echo "Add field 'targetProjectId' (string) = \"$TARGET_PROJECT_ID\""
  echo
fi

echo "============================================================"
echo "    VERIFICATION CHECKLIST                                  "
echo "============================================================"
echo "1. Ensure your GitHub Pages domain (e.g. username.github.io) is in Authorized Domains."
echo "2. Open your GitHub Pages URL (e.g. https://username.github.io/woyz-notes/)."
echo "3. Log in as $DOCTOR_EMAIL."
echo "4. Save a note and verify it appears directly inside $TARGET_PROJECT_ID Firestore!"
echo
