/**
 * Get Workflow Qualifying - Firebase Cloud Function
 * 
 * Returns qualifying questions for both:
 * - Vendor workflows (book_movers, cleaning_service, etc.)
 * - Mini-assessment workflows (address_change_financial, etc.)
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const twilio = require('twilio');
const { WORKFLOW_QUALIFYING } = require('./workflowQualifying');
const { MINI_ASSESSMENT_WORKFLOWS } = require('./miniAssessmentWorkflows');

// Initialize Firebase Admin if not already
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Get workflow qualifying questions
 */
const getWorkflowQualifying = onCall(
  { timeoutSeconds: 10, memory: '256MiB' },
  async (request) => {
    const { workflowId } = request.data;

    if (!workflowId) {
      throw new HttpsError('invalid-argument', 'workflowId is required');
    }

    console.log(`Getting workflow: ${workflowId}`);

    // Firestore-first (Spec 04): the flowDefinitions collection is the
    // definition source for the config-driven FlowEngine. Served through
    // this callable because deployed rules grant no direct client read.
    // Adding a vertical stays a Firestore write.
    try {
      const definitionDoc = await admin.firestore()
        .collection('flowDefinitions')
        .doc(workflowId)
        .get();
      if (definitionDoc.exists) {
        return { flowDefinition: definitionDoc.data() };
      }
    } catch (err) {
      console.error(`flowDefinitions lookup failed for ${workflowId}:`, err.message);
    }

    // Check vendor workflows first
    if (WORKFLOW_QUALIFYING[workflowId]) {
      return WORKFLOW_QUALIFYING[workflowId];
    }

    // Check mini-assessment workflows
    if (MINI_ASSESSMENT_WORKFLOWS[workflowId]) {
      const miniWorkflow = MINI_ASSESSMENT_WORKFLOWS[workflowId];

      // Convert to the standard format expected by iOS
      return {
        workflowId: miniWorkflow.id,
        title: miniWorkflow.title,
        intro: miniWorkflow.intro,
        questions: miniWorkflow.questions.map(q => ({
          id: q.id,
          question: q.question,
          icon: q.icon,
          options: null,  // Mini-assessments use yes/no, not multi-choice
          textEntryPrompt: q.textEntryPrompt || null,
          textEntryPlaceholder: q.textEntryPlaceholder || null,
          allowMultiple: q.allowMultiple || false
        })),
        recap: null,  // Mini-assessments don't use recap
        review: miniWorkflow.review,
        taskTemplate: miniWorkflow.taskTemplate
      };
    }

    // Generic fallback: 3-question survey for any unrecognized workflowId
    console.log(`No specific qualifying found for ${workflowId} — returning generic survey`);
    const genericQuestions = [
      {
        id: "priority",
        question: "What's most important to you for this?",
        subtitle: null,
        type: "single_select",
        options: [
          { id: "low_cost",       label: "Low cost",       icon: "dollarsign.circle.fill", subtitle: null, exclusive: null },
          { id: "high_quality",   label: "High quality",   icon: "star.fill",              subtitle: null, exclusive: null },
          { id: "fast_timeline",  label: "Fast timeline",  icon: "clock.fill",             subtitle: null, exclusive: null },
          { id: "flexible",       label: "I'm flexible",   icon: "hand.wave.fill",         subtitle: null, exclusive: null }
        ]
      },
      {
        id: "requirements",
        question: "Any specific requirements we should know about?",
        subtitle: null,
        type: "single_select",
        options: [
          { id: "no_req",         label: "No requirements", icon: "checkmark.circle.fill", subtitle: null, exclusive: null },
          { id: "will_discuss",   label: "I'll explain later", icon: "bubble.left.fill",   subtitle: null, exclusive: null }
        ]
      },
      {
        id: "timeline",
        question: "What's your preferred timeline?",
        subtitle: null,
        type: "single_select",
        options: [
          { id: "asap",           label: "ASAP",            icon: "bolt.fill",             subtitle: null, exclusive: null },
          { id: "within_week",    label: "Within a week",   icon: "calendar.badge.clock",  subtitle: null, exclusive: null },
          { id: "within_month",   label: "Within a month",  icon: "calendar",              subtitle: null, exclusive: null },
          { id: "no_rush",        label: "No rush",         icon: "leaf.fill",             subtitle: null, exclusive: null }
        ]
      }
    ];

    return {
      workflowId,
      intro: {
        title: "Quick questions",
        subtitle: "Just a few things to help us get started."
      },
      questions: genericQuestions,
      questionCount: genericQuestions.length,
      recap: {
        title: "Got it.",
        closing: "We'll be in touch shortly.",
        button: "Submit"
      }
    };
  }
);

/**
 * Submit workflow answers
 */
const submitWorkflowAnswers = onCall(
  { timeoutSeconds: 15, memory: '256MiB' },
  async (request) => {
    const { workflowId, answers, userId } = request.data;
    
    if (!workflowId || !answers || !userId) {
      throw new HttpsError('invalid-argument', 'workflowId, answers, and userId are required');
    }
    
    console.log(`Submitting answers for workflow: ${workflowId}, user: ${userId}`);
    
    try {
      const db = admin.firestore();
      
      // Determine workflow type: mini-assessment, guidance, or vendor
      const isMiniAssessment = workflowId in MINI_ASSESSMENT_WORKFLOWS;
      const isGuidance = WORKFLOW_QUALIFYING[workflowId]?.workflowType === 'guidance';
      
      if (isGuidance) {
        // Guidance workflow: user acknowledged the guidance — mark task complete
        console.log(`Guidance workflow completed: ${workflowId} for user ${userId}`);
        
        // Save the answers (may be empty for zero-question workflows)
        await db.collection('users')
          .doc(userId)
          .collection('workflowResponses')
          .doc(workflowId)
          .set({
            workflowId,
            answers,
            workflowType: 'guidance',
            completedAt: admin.firestore.FieldValue.serverTimestamp()
          });

        // Mark the task as Completed
        try {
          await db.collection('users')
            .doc(userId)
            .collection('tasks')
            .doc(workflowId)
            .update({
              status: 'Completed',
              completedAt: admin.firestore.FieldValue.serverTimestamp(),
              qualifyingAnswers: answers
            });
        } catch (updateErr) {
          // Task doc may use the catalog taskId (uppercase) instead of workflowId
          console.warn(`Could not update task ${workflowId}: ${updateErr.message}`);
        }

        return {
          success: true,
          status: 'completed'
        };

      } else if (isMiniAssessment) {
        // Mini-assessment: answers is an array of { id, displayName, textEntry? }
        await db.collection('users')
          .doc(userId)
          .collection('mini_assessments')
          .doc(workflowId)
          .set({
            workflowId,
            answers,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            status: 'completed'
          });
        
        // Generate tasks for each answer
        const workflow = MINI_ASSESSMENT_WORKFLOWS[workflowId];
        const batch = db.batch();
        const tasksRef = db.collection('users').doc(userId).collection('tasks');
        
        for (const answer of answers) {
          const taskId = `${workflowId}_${answer.id}`;
          const taskRef = tasksRef.doc(taskId);
          
          let taskTitle = `${workflow.taskTemplate.titlePrefix} ${answer.displayName}`;
          if (answer.textEntry) {
            taskTitle = `${workflow.taskTemplate.titlePrefix} ${answer.textEntry}`;
          }
          
          batch.set(taskRef, {
            id: taskId,
            title: taskTitle,
            subtitle: 'Update your address',
            category: workflow.taskTemplate.category,
            subcategory: workflow.taskTemplate.subcategory,
            status: 'pending',
            priority: workflow.taskTemplate.priority,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            source: 'mini_assessment'
          });
        }
        
        await batch.commit();
        
        return {
          success: true,
          tasksCreated: answers.length
        };
        
      } else {
        // Vendor workflow: answers is { questionId: [optionIds] }
        await db.collection('workflowSubmissions').add({
          workflowId,
          userId,
          answers,
          submittedAt: admin.firestore.FieldValue.serverTimestamp(),
          status: 'pending_matching'
        });

        // Save to user's workflowResponses for easy per-user lookup and manual review
        await db.collection('users')
          .doc(userId)
          .collection('workflowResponses')
          .doc(workflowId)
          .set({
            workflowId,
            answers,
            submittedAt: admin.firestore.FieldValue.serverTimestamp()
          });

        console.log(`Workflow submission saved — user: ${userId}, workflowId: ${workflowId}, answers:`, JSON.stringify(answers));

        // Update the user's task status (best-effort: task doc may not exist for generic workflows)
        try {
          const taskDocumentId = workflowId === 'supplies_kit'
            ? 'PACKING_SUPPLIES_KIT'
            : workflowId;
          await db.collection('users')
            .doc(userId)
            .collection('tasks')
            .doc(taskDocumentId)
            .update({
              status: 'matching_in_progress',
              qualifyingAnswers: answers,
              qualifyingCompletedAt: admin.firestore.FieldValue.serverTimestamp()
            });
        } catch (updateErr) {
          console.warn(`Could not update task status for ${workflowId} (task may not exist):`, updateErr.message);
        }
        
        // Booking and kit notifications are direct, best-effort Twilio SMS.
        // Full submissions remain in Firestore; texts stay decision-sized.
        await notifyMoverSubmission(workflowId, answers);
        await notifySuppliesKitSubmission(workflowId, answers);

        return {
          success: true,
          status: 'matching_in_progress'
        };
      }

    } catch (error) {
      console.error('Error submitting workflow answers:', error);
      throw new HttpsError('internal', 'Failed to submit answers');
    }
  }
);

/**
 * Get all available mini-assessment workflow IDs
 */
const getMiniAssessmentTypes = onCall(
  { timeoutSeconds: 5, memory: '128MiB' },
  async () => {
    return Object.keys(MINI_ASSESSMENT_WORKFLOWS).map(id => ({
      id,
      title: MINI_ASSESSMENT_WORKFLOWS[id].title,
      taskTitle: MINI_ASSESSMENT_WORKFLOWS[id].taskTitle,
      category: 'address_change'
    }));
  }
);

async function notifyMoverSubmission(workflowId, answers) {
  if (workflowId !== 'book_movers') return;

  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const fromNumber = process.env.TWILIO_FROM_NUMBER;
  const notifyNumber = process.env.ADAM_NOTIFY_NUMBER;

  if (!accountSid || !authToken || !fromNumber || !notifyNumber ||
      accountSid === 'placeholder_will_set_later') {
    console.warn('SMS notify not configured');
    return;
  }

  try {
    const client = twilio(accountSid, authToken);
    await client.messages.create({
      body: buildMoverNotificationBody(answers),
      from: fromNumber,
      to: notifyNumber
    });
    console.log('Mover submission SMS sent');
  } catch (err) {
    console.error('SMS notify failed:', err.message);
  }
}

async function notifySuppliesKitSubmission(workflowId, answers) {
  if (workflowId !== 'supplies_kit') return;

  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const fromNumber = process.env.TWILIO_FROM_NUMBER;
  const notifyNumber = process.env.ADAM_NOTIFY_NUMBER;

  if (!accountSid || !authToken || !fromNumber || !notifyNumber ||
      accountSid === 'placeholder_will_set_later') {
    console.warn('SMS notify not configured');
    return;
  }

  try {
    const client = twilio(accountSid, authToken);
    await client.messages.create({
      body: buildKitNotificationBody(answers),
      from: fromNumber,
      to: notifyNumber
    });
    console.log('Kit order SMS sent');
  } catch (err) {
    console.error('SMS notify failed:', err.message);
  }
}

function buildMoverNotificationBody(answers) {
  const identity = parsedAnswerObject(answers, 'identity');
  const estimate = parsedAnswerObject(answers, 'estimate');
  const vendor = parsedAnswerObject(answers, 'chosen_vendor');
  const firstName = String(identity.name || 'Customer').trim().split(/\s+/)[0];
  const originCity = String(identity.currentAddress?.city || 'Origin');
  const destCity = String(identity.newAddress?.city || 'Destination');
  const date = normalizedMoveDate(identity.moveDate);

  if (firstAnswer(answers, 'quoteRequest') === 'true') {
    return `PEEZY QUOTE REQ: ${firstName}, ${originCity}→${destCity}, ${date}.`;
  }

  const vendorName = String(vendor.name || 'Vendor pending');
  const low = normalizedMoney(estimate.low);
  const high = normalizedMoney(estimate.high);
  return `PEEZY BOOKING: ${firstName}, ${originCity}→${destCity}, ${date}, ${vendorName}, est $${low}–$${high}.`;
}

function buildKitNotificationBody(answers) {
  const identity = parsedAnswerObject(answers, 'identity');
  const kit = parsedAnswerObject(answers, 'kit');
  const firstName = String(identity.name || 'Customer').trim().split(/\s+/)[0];
  const city = String(identity.newAddress?.city || identity.currentAddress?.city || 'City pending');
  const date = normalizedMoveDate(identity.moveDate);
  const dollars = normalizedCents(kit.totalPriceCents);
  const summary = [
    `${normalizedCount(kit.small)}S`,
    `${normalizedCount(kit.medium)}M`,
    `${normalizedCount(kit.large)}L`,
    `${normalizedCount(kit.wardrobe)}W`,
    `${normalizedCount(kit.mattressBags)}MB`
  ].join('/');
  return `PEEZY KIT ORDER: ${firstName}, ${city}, ${date}, ${summary}, $${dollars}.`;
}

function answerMap(answers) {
  if (answers?.answers && typeof answers.answers === 'object') return answers.answers;
  return answers && typeof answers === 'object' ? answers : {};
}

function firstAnswer(answers, key) {
  const value = answerMap(answers)[key];
  if (Array.isArray(value)) return String(value[0] ?? '');
  return String(value ?? '');
}

function parsedAnswerObject(answers, key) {
  try {
    const parsed = JSON.parse(firstAnswer(answers, key));
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch (_) {
    return {};
  }
}

function normalizedMoveDate(value) {
  const raw = String(value || '').trim();
  const isoDay = raw.match(/^\d{4}-\d{2}-\d{2}/)?.[0];
  return isoDay || 'date pending';
}

function normalizedMoney(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number).toString() : 'pending';
}

function normalizedCount(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.round(number)).toString() : '0';
}

function normalizedCents(value) {
  const number = Number(value);
  return Number.isFinite(number) ? (Math.max(0, number) / 100).toFixed(2) : 'pending';
}

module.exports = {
  getWorkflowQualifying,
  submitWorkflowAnswers,
  getMiniAssessmentTypes,
  buildMoverNotificationBody,
  buildKitNotificationBody
};
