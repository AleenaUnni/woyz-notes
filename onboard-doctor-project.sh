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

echo
echo "Target Setup Details:"
echo "--------------------"
echo "Doctor Email:      $DOCTOR_EMAIL"
echo "Clinic Name:       $CLINIC_NAME"
echo "Target Project ID: $TARGET_PROJECT_ID"
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
echo "============================================================"
echo "    NEXT MANUAL / INTEGRATION STEPS                         "
echo "============================================================"
echo
echo "Step 1: Link Target Config to Doctor in Central Database (woyz-notes-8c87f)"
echo "  1. Open Central Firebase Console: https://console.firebase.google.com/project/woyz-notes-8c87f/firestore"
echo "  2. Go to 'users' collection -> Select document for '$DOCTOR_EMAIL'."
echo "  3. Click '+ Add field':"
echo "       - Field Name: targetFirebaseConfig"
echo "       - Type: string"
echo "       - Value: (Paste the JSON string printed above)"
echo "  4. Add second field:"
echo "       - Field Name: targetProjectId"
echo "       - Type: string"
echo "       - Value: \"$TARGET_PROJECT_ID\""
echo
echo "Step 2: Setup Target Project Authentication (Optional / Recommended for Strict Production Rules)"
echo "  1. Open Target Project Console: https://console.firebase.google.com/project/$TARGET_PROJECT_ID/authentication"
echo "  2. Go to 'Sign-in method' -> Enable 'Email/Password'."
echo "  3. Go to 'Users' -> Click 'Add user':"
echo "       - Email: $DOCTOR_EMAIL"
echo "       - Password: (Doctor password)"
echo
echo "Step 3: Hosted Web App Verification (GitHub Pages)"
echo "  1. Ensure your GitHub Pages domain (e.g. username.github.io) is listed under:"
echo "     Target Project Console -> Authentication -> Authorized domains."
echo "  2. Open your GitHub Pages URL (e.g. https://username.github.io/woyz-notes/)."
echo "  3. Log in as $DOCTOR_EMAIL."
echo "  4. Save a note and verify it appears directly inside $TARGET_PROJECT_ID Firestore!"
echo
