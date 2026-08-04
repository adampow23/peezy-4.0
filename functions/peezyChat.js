const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const Anthropic = require("@anthropic-ai/sdk");
const { getAIConfig } = require("./aiConfig");
const { buildChatSystemPrompt } = require("./systemPrompt");

const HISTORY_LIMIT = 20;
const MAX_MESSAGE_LENGTH = 8000;
const CHAT_MAX_TOKENS = 1200;
const CHAT_TIMEOUT_MS = 105000;
const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000;
const MARKDOWN_URL_PATTERN = /\[([^\]]+)\]\(\s*(?:(?:https?|ftp):\/\/|www\.)[^)\s]+(?:\s+["'][^"']*["'])?\s*\)/gi;
const SCHEME_URL_PATTERN = /\b[a-z][a-z0-9+.-]*:[^\s<>"'`]+/gi;
const PROTOCOL_RELATIVE_URL_PATTERN = /\/\/(?:[a-z0-9-]+\.)+[a-z]{2,63}[^\s<>"'`]*/gi;
const WWW_URL_PATTERN = /\bwww\.[^\s<>"'`]+/gi;
const BARE_URL_PATTERN = /(?<![@\w])(?:[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\.)+[a-z]{2,63}(?::\d{2,5})?(?:\/[^\s<>"'`]*)?/gi;
const IP_URL_PATTERN = /\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{2,5})?(?:\/[^\s<>"'`]*)?/g;
const LOCALHOST_URL_PATTERN = /\blocalhost(?::\d{2,5})?(?:\/[^\s<>"'`]*)?/gi;

const APP_FACTS = Object.freeze({
  movePass: "A one-time payment provides six months of access. Nothing renews.",
  freeTier: "The free tier shows the task list.",
  restorePurchases: "Restore Purchases lives in Settings.",
  accountAndBillingHelp: "support@peezymove.com"
});

let anthropicClient = null;

function getAnthropicClient() {
  if (!anthropicClient) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error("ANTHROPIC_API_KEY environment variable is required");
    }
    anthropicClient = new Anthropic({ apiKey });
  }
  return anthropicClient;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validateInput(data) {
  const surface = data?.surface;
  if (surface !== "task" && surface !== "support") {
    throw new HttpsError("invalid-argument", "surface must be task or support");
  }

  const message = typeof data?.message === "string" ? data.message.trim() : "";
  if (!message) {
    throw new HttpsError("invalid-argument", "message is required");
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    throw new HttpsError("invalid-argument", "message is too long");
  }

  const taskId = typeof data?.taskId === "string" ? data.taskId.trim() : "";
  if (surface === "task" && (!taskId || taskId.length > 200 || taskId.includes("/"))) {
    throw new HttpsError("invalid-argument", "taskId must be a valid string for task chat");
  }

  return {
    surface,
    taskId: surface === "task" ? taskId : null,
    message
  };
}

function normalizeFirestoreValue(value, depth = 0) {
  if (depth > 8 || value === undefined) return null;
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value?.toDate === "function") return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map((entry) => normalizeFirestoreValue(entry, depth + 1));
  if (isPlainObject(value)) {
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [
      key,
      normalizeFirestoreValue(entry, depth + 1)
    ]));
  }
  return String(value);
}

function unwrapKnowledgeEntries(knowledgeData) {
  const entries = isPlainObject(knowledgeData?.entries) ? knowledgeData.entries : {};
  return Object.fromEntries(Object.entries(entries).map(([key, entry]) => [
    key,
    normalizeFirestoreValue(isPlainObject(entry) && Object.prototype.hasOwnProperty.call(entry, "value")
      ? entry.value
      : entry)
  ]));
}

function dateFromValue(value) {
  if (!value) return null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (typeof value?.toDate === "function") {
    const date = value.toDate();
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value === "string" || typeof value === "number") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function daysUntil(date, now = new Date()) {
  if (!date) return null;
  return Math.ceil((date.getTime() - now.getTime()) / MILLISECONDS_PER_DAY);
}

function activeInventoryItems(inventoryDocuments) {
  return inventoryDocuments
    .filter((document) => document.id !== "_metadata")
    .flatMap((document) => Array.isArray(document.data.items) ? document.data.items : [])
    .filter((item) => isPlainObject(item) && item.shouldMove !== false);
}

function itemQuantity(item) {
  const quantity = Number(item?.quantity);
  return Number.isFinite(quantity) && quantity > 0 ? quantity : 1;
}

function itemCubicFeet(item) {
  const cubicFeet = Number(item?.cubicFeet);
  return Number.isFinite(cubicFeet) && cubicFeet > 0 ? cubicFeet : 0;
}

function isHeavyInventoryItem(item) {
  return item?.isHeavy === true ||
    item?.heavy === true ||
    String(item?.sizeEstimate || "").toLowerCase() === "oversized";
}

function uniqueItemNames(items) {
  return [...new Set(items
    .map((item) => typeof item?.name === "string" ? item.name.trim() : "")
    .filter(Boolean))];
}

function summarizeCompletedInventory(inventorySnapshot) {
  const documents = inventorySnapshot.docs.map((document) => ({
    id: document.id,
    data: document.data()
  }));
  const metadata = documents.find((document) => document.id === "_metadata")?.data;
  if (metadata?.submissionStatus !== "submitted") return null;

  const roomDocuments = documents.filter((document) => document.id !== "_metadata");
  const items = activeInventoryItems(documents);
  const heavyItems = items.filter(isHeavyInventoryItem);
  const fragileItems = items.filter((item) => item.isFragile === true);
  const totalCube = items.reduce(
    (total, item) => total + itemCubicFeet(item) * itemQuantity(item),
    0
  );

  return {
    roomCount: roomDocuments.length,
    itemCount: items.length,
    hasHeavyItems: heavyItems.length > 0,
    heavyItemNames: uniqueItemNames(heavyItems),
    hasFragileItems: fragileItems.length > 0,
    fragileItemNames: uniqueItemNames(fragileItems),
    totalCube: Number(totalCube.toFixed(1))
  };
}

function taskDefinition(taskId, catalogData) {
  return {
    taskId,
    title: typeof catalogData.title === "string" ? catalogData.title : "",
    desc: typeof catalogData.desc === "string" ? catalogData.desc : "",
    whyNeeded: typeof catalogData.whyNeeded === "string" ? catalogData.whyNeeded : "",
    tips: normalizeFirestoreValue(catalogData.tips)
  };
}

async function loadUserContext(db, uid, now = new Date()) {
  const userRef = db.collection("users").doc(uid);
  const [identitySnapshot, knowledgeSnapshot, assessmentSnapshot, inventorySnapshot] = await Promise.all([
    userRef.collection("identity").doc("identity").get(),
    db.collection("userKnowledge").doc(uid).get(),
    userRef.collection("user_assessments").limit(1).get(),
    userRef.collection("inventory").get()
  ]);

  const identity = identitySnapshot.data() || {};
  const rawAssessment = assessmentSnapshot.empty ? {} : assessmentSnapshot.docs[0].data();
  const assessmentAnswers = {
    ...normalizeFirestoreValue(rawAssessment),
    ...unwrapKnowledgeEntries(knowledgeSnapshot.data() || {})
  };
  const moveDate = dateFromValue(identity.moveDate) ||
    dateFromValue(assessmentAnswers.moveDate) ||
    dateFromValue(rawAssessment.moveDate);

  return {
    identity: {
      name: identity.name || assessmentAnswers.userName || null,
      currentAddress: normalizeFirestoreValue(identity.currentAddress || assessmentAnswers.currentAddress || null),
      newAddress: normalizeFirestoreValue(identity.newAddress || assessmentAnswers.newAddress || null),
      moveDate: moveDate ? moveDate.toISOString() : null,
      daysUntilMove: daysUntil(moveDate, now),
      moveDistanceMiles: normalizeFirestoreValue(identity.moveDistanceMiles),
      isInterstate: normalizeFirestoreValue(identity.isInterstate),
      newAddressPending: normalizeFirestoreValue(identity.newAddressPending),
      moveDatePending: normalizeFirestoreValue(identity.moveDatePending)
    },
    assessmentAnswers,
    inventorySummary: summarizeCompletedInventory(inventorySnapshot)
  };
}

async function loadChatContext(db, uid, surface, taskId) {
  const userContextPromise = loadUserContext(db, uid);

  if (surface === "support") {
    return {
      ...await userContextPromise,
      appFacts: APP_FACTS
    };
  }

  const userRef = db.collection("users").doc(uid);
  const [userContext, catalogSnapshot, researchSnapshot] = await Promise.all([
    userContextPromise,
    db.collection("taskCatalog").doc(taskId).get(),
    userRef.collection("research").doc(taskId).get()
  ]);

  if (!catalogSnapshot.exists) {
    throw new HttpsError("not-found", "task catalog definition not found");
  }

  const researchData = researchSnapshot.data();
  const readyResearch = researchSnapshot.exists && researchData?.status === "ready"
    ? normalizeFirestoreValue({
      generatedAt: researchData.generatedAt,
      degraded: researchData.degraded,
      brief: researchData.brief,
      prefsUsed: researchData.prefsUsed
    })
    : null;

  return {
    ...userContext,
    task: taskDefinition(taskId, catalogSnapshot.data() || {}),
    research: readyResearch
  };
}

function historyFromSnapshot(snapshot) {
  return snapshot.docs
    .slice()
    .reverse()
    .map((document) => document.data())
    .filter((message) => (
      (message.sender === "user" || message.sender === "assistant") &&
      typeof message.text === "string" &&
      message.text.trim()
    ))
    .map((message) => ({
      role: message.sender,
      content: message.text.trim()
    }));
}

function collapseConsecutiveRoles(messages) {
  return messages.reduce((collapsed, message) => {
    const previous = collapsed[collapsed.length - 1];
    if (previous?.role === message.role) {
      previous.content = `${previous.content}\n\n${message.content}`;
    } else {
      collapsed.push({ ...message });
    }
    return collapsed;
  }, []);
}

function stripURLs(text) {
  return text
    .replace(MARKDOWN_URL_PATTERN, "$1")
    .replace(/mailto:([^\s<>"'`]+)/gi, "$1")
    .replace(/tel:[^\s<>"'`]+/gi, "")
    .replace(SCHEME_URL_PATTERN, "")
    .replace(PROTOCOL_RELATIVE_URL_PATTERN, "")
    .replace(WWW_URL_PATTERN, "")
    .replace(BARE_URL_PATTERN, "")
    .replace(IP_URL_PATTERN, "")
    .replace(LOCALHOST_URL_PATTERN, "")
    .replace(/\(\s*\)|\[\s*\]|<\s*>/g, "")
    .replace(/[ \t]+([,.;:!?])/g, "$1")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function requireChatModel(value) {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("failed-precondition", "AI config key chatModel is invalid");
  }
  return value.trim();
}

function responseText(response) {
  const text = (response?.content || [])
    .filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("\n")
    .trim();

  if (!text) {
    throw new Error("Chat response was empty");
  }
  return text;
}

function withTimeout(operation) {
  let timer;
  try {
    return Promise.race([
      operation,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("Chat response timed out")), CHAT_TIMEOUT_MS);
      })
    ]);
  } finally {
    operation.finally(() => clearTimeout(timer)).catch(() => {});
  }
}

async function generateAssistantText({ model, context, messages }) {
  const response = await withTimeout(getAnthropicClient().messages.create({
    model,
    max_tokens: CHAT_MAX_TOKENS,
    temperature: 0.3,
    system: buildChatSystemPrompt(context),
    messages
  }));

  if (response.stop_reason === "refusal") {
    throw new Error("Chat request was refused");
  }

  const safeText = stripURLs(responseText(response));
  if (!safeText) {
    throw new Error("Chat response contained no displayable text");
  }
  return safeText;
}

const peezyChat = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 120
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated");
    }

    const { surface, taskId, message } = validateInput(request.data);
    const db = admin.firestore();
    const chatId = surface === "task" ? taskId : "support";
    const messagesRef = db.collection("users").doc(request.auth.uid)
      .collection("chats").doc(chatId).collection("messages");

    const historySnapshot = await messagesRef
      .orderBy("timestamp", "desc")
      .limit(HISTORY_LIMIT)
      .get();

    const userMessageRef = messagesRef.doc();
    await userMessageRef.set({
      text: message,
      sender: "user",
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });

    try {
      const [context, configuredModel] = await Promise.all([
        loadChatContext(db, request.auth.uid, surface, taskId),
        getAIConfig("chatModel")
      ]);
      const messages = collapseConsecutiveRoles([
        ...historyFromSnapshot(historySnapshot),
        { role: "user", content: message }
      ]);
      const text = await generateAssistantText({
        model: requireChatModel(configuredModel),
        context,
        messages
      });

      const assistantMessageRef = messagesRef.doc();
      await assistantMessageRef.set({
        text,
        sender: "assistant",
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });

      return {
        id: assistantMessageRef.id,
        text,
        sender: "assistant"
      };
    } catch (error) {
      console.error("peezyChat failed", {
        uid: request.auth.uid,
        surface,
        taskId,
        error: error?.message
      });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Chat response could not be generated");
    }
  }
);

module.exports = {
  peezyChat,
  _test: {
    collapseConsecutiveRoles,
    daysUntil,
    historyFromSnapshot,
    stripURLs,
    summarizeCompletedInventory,
    validateInput
  }
};
