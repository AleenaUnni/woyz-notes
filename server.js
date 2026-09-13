const express = require('express');
const cors = require('cors');
const path = require('path');
const { exec } = require('child_process');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'woyz-notes-backend', timestamp: new Date().toISOString() });
});

app.post('/api/deploy-rules', (req, res) => {
  const { targetProjectId } = req.body;
  if (!targetProjectId) {
    return res.status(400).json({ success: false, message: 'Missing targetProjectId in request body.' });
  }

  console.log(`[server.js] Deploying target firestore rules to project: ${targetProjectId}...`);

  const targetConfigFile = path.join(__dirname, 'firebase.target.json');
  const tokenFlag = process.env.FIREBASE_TOKEN ? `--token "${process.env.FIREBASE_TOKEN}"` : '';
  const cmd = `npx --yes firebase-tools@latest deploy --only firestore:rules --project ${targetProjectId} --config "${targetConfigFile}" ${tokenFlag}`;

  exec(cmd, { cwd: __dirname }, (error, stdout, stderr) => {
    if (error) {
      console.warn(`[server.js] CLI error for ${targetProjectId}:`, stderr || error.message);
      return res.status(500).json({
        success: false,
        message: stderr || error.message || 'Firebase CLI deployment failed.'
      });
    }

    console.log(`[server.js] Successfully deployed rules to ${targetProjectId}:\n`, stdout);
    return res.json({
      success: true,
      message: `Rules successfully deployed to target project ${targetProjectId}!`,
      output: stdout
    });
  });
});

app.listen(PORT, () => {
  console.log(`🚀 WOYZ Notes Rules Deployment Server running on http://localhost:${PORT}`);
});
