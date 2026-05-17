const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

const DEEPSEEK_API_KEY = defineSecret("DEEPSEEK_API_KEY");

exports.proxyDeepSeek = onCall(
  {
    secrets: [DEEPSEEK_API_KEY],
    region: "asia-east2",
    enforceAppCheck: false,
    maxInstances: 10,
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }

    const payload = request.data || {};
    const systemPrompt = payload.systemPrompt;
    const messages = payload.messages;
    const moduleId = payload.moduleId || "unknown";

    if (!systemPrompt || !Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError("invalid-argument", "bad payload");
    }

    const response = await fetch(
      "https://api.deepseek.com/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": [
            "Bearer",
            DEEPSEEK_API_KEY.value(),
          ].join(" "),
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          messages: [
            {role: "system", content: systemPrompt},
            ...messages,
          ],
          max_tokens: 320,
          temperature: 0.7,
        }),
      },
    );

    if (!response.ok) {
      throw new HttpsError("internal", `deepseek ${response.status}`);
    }

    const data = await response.json();
    const text = data.choices &&
      data.choices[0] &&
      data.choices[0].message &&
      data.choices[0].message.content;

    return {text: text || "", moduleId: moduleId};
  },
);