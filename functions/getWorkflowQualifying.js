/**
 * Get Workflow Qualifying - Firebase Cloud Function
 * 
 * Returns qualifying questions for both:
 * - Vendor workflows (book_movers, cleaning_service, etc.)
 * - Mini-assessment workflows (address_change_financial, etc.)
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { deletionError } = require('./accountDeletionFence');
const { createHash } = require('node:crypto');
const { WORKFLOW_QUALIFYING } = require('./workflowQualifying');
const { MINI_ASSESSMENT_WORKFLOWS } = require('./miniAssessmentWorkflows');
const {
  buildCompletedContract,
  buildWaitingOnExternalContract,
  validateDispositionContract
} = require('./dispositionContract');

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
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Must be signed in to submit workflow answers.');
    }

    const { workflowId, answers } = request.data || {};
    
    if (!workflowId || !answers) {
      throw new HttpsError('invalid-argument', 'workflowId and answers are required');
    }
    const submissionToken = validateSubmissionToken(request.data?.submissionToken);
    
    console.log(`Submitting answers for workflow: ${workflowId}, user: ${userId}`);
    try {
      return await executeWorkflowAnswers(
        admin.firestore(), userId, workflowId, answers, undefined, undefined, submissionToken
      );

    } catch (error) {
      console.error('Error submitting workflow answers:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', 'Failed to submit answers');
    }
  }
);

function taskResetIsActive(snapshot) {
  const state = snapshot.get('taskReset')?.state;
  return state === 'deleting' || state === 'awaiting_local_reset';
}

function canonicalJSON(value) {
  const ancestors = new Set();

  function encode(current) {
    if (current === null) return 'null';
    if (typeof current === 'string' || typeof current === 'boolean') {
      return JSON.stringify(current);
    }
    if (typeof current === 'number') {
      return Number.isFinite(current) ? JSON.stringify(current) : 'null';
    }
    if (typeof current === 'undefined' || typeof current === 'function' ||
        typeof current === 'symbol') {
      return undefined;
    }
    if (typeof current === 'bigint') {
      throw new TypeError('BigInt is not JSON serializable');
    }
    if (typeof current.toJSON === 'function') {
      return encode(current.toJSON());
    }
    if (ancestors.has(current)) {
      throw new TypeError('Circular value is not JSON serializable');
    }

    ancestors.add(current);
    let encoded;
    if (Array.isArray(current)) {
      encoded = `[${current.map((item) => encode(item) ?? 'null').join(',')}]`;
    } else {
      const entries = [];
      for (const key of Object.keys(current).sort()) {
        const item = encode(current[key]);
        if (item !== undefined) entries.push(`${JSON.stringify(key)}:${item}`);
      }
      encoded = `{${entries.join(',')}}`;
    }
    ancestors.delete(current);
    return encoded;
  }

  return encode(value);
}

function sha256Hex(value) {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function validateSubmissionToken(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || value.length === 0 || value.trim() !== value ||
      Buffer.byteLength(value, 'utf8') > 256) {
    throw new HttpsError(
      'invalid-argument',
      'submissionToken must be a trimmed, non-empty string of at most 256 UTF-8 bytes'
    );
  }
  return value;
}

function workflowSubmissionFingerprint(workflowId, answers) {
  let canonical;
  try {
    canonical = canonicalJSON({ workflowId, answers });
  } catch (error) {
    throw new HttpsError('invalid-argument', 'workflow submission must be JSON serializable');
  }
  return `wf1_${sha256Hex(canonical)}`;
}

function workflowSubmissionId(userId, submissionToken) {
  const token = validateSubmissionToken(submissionToken);
  if (!token) {
    throw new HttpsError('invalid-argument', 'submissionToken is required for deterministic identity');
  }
  return `ws1_${sha256Hex(canonicalJSON({ owner: userId, submissionToken: token })).slice(0, 40)}`;
}

function replayWorkflowSubmission(snapshot, { fingerprint, owner, workflowId }) {
  const data = snapshot.data() || {};
  const exactIntent = data.fingerprint === fingerprint && data.owner === owner &&
    data.workflowId === workflowId && Object.prototype.hasOwnProperty.call(data, 'result');
  if (!exactIntent) {
    throw new HttpsError(
      'failed-precondition',
      'This submissionToken was already used for a different workflow submission'
    );
  }
  return data.result;
}

function requireWaitingInput(answers, workflowId) {
  const owner = answers?.waiting_owner;
  const nextAction = answers?.waiting_next_action;
  const resumeDestination = answers?.waiting_resume_destination;
  const nextTrigger = answers?.waiting_next_trigger;
  if (![owner, nextAction, resumeDestination].every((value) =>
    typeof value === 'string' && value.trim()
  ) || !nextTrigger) {
    throw new HttpsError(
      'failed-precondition',
      `Contracted vendor workflow ${workflowId} requires explicit waiting evidence`
    );
  }
  return {
    owner,
    nextAction,
    resumeDestination,
    nextTrigger,
    visibleStatusCopy: `Waiting on ${owner.trim()} for ${workflowId.replaceAll('_', ' ')}`,
    externalSubmission: true
  };
}

async function executeWorkflowAnswers(
  db,
  userId,
  workflowId,
  answers,
  now = new Date(),
  serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp(),
  submissionToken = null
) {
  const normalizedSubmissionToken = validateSubmissionToken(submissionToken);
  const userRef = db.collection('users').doc(userId);
  const tasksRef = userRef.collection('tasks');
  const isMiniAssessment = workflowId in MINI_ASSESSMENT_WORKFLOWS;
  const isGuidance = WORKFLOW_QUALIFYING[workflowId]?.workflowType === 'guidance';
  const taskDocumentId = workflowId === 'supplies_kit' ? 'PACKING_SUPPLIES_KIT' : workflowId;
  const taskRefs = [];
  if (isMiniAssessment) {
    for (const answer of answers) {
      taskRefs.push(tasksRef.doc(`${workflowId}_${answer.id}`));
    }
  } else {
    taskRefs.push(tasksRef.doc(taskDocumentId));
  }
  const isVendorSubmission = !isGuidance && !isMiniAssessment;
  const fingerprint = isVendorSubmission && normalizedSubmissionToken
    ? workflowSubmissionFingerprint(workflowId, answers)
    : null;
  let submissionRef = null;
  if (isVendorSubmission) {
    const submissionsRef = db.collection('workflowSubmissions');
    submissionRef = normalizedSubmissionToken
      ? submissionsRef.doc(workflowSubmissionId(userId, normalizedSubmissionToken))
      : submissionsRef.doc();
  }

  return db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(userRef);
    const priorSubmission = fingerprint
      ? await transaction.get(submissionRef)
      : null;
    if (priorSubmission?.exists) {
      return replayWorkflowSubmission(priorSubmission, {
        fingerprint,
        owner: userId,
        workflowId
      });
    }
    // C6.1 root fence: every committing branch requires accountDeletion absent on the owner root.
    if (rootSnapshot.exists && rootSnapshot.data()?.accountDeletion !== undefined) throw deletionError('ACCOUNT_DELETION_FENCED');
    if (taskResetIsActive(rootSnapshot)) {
      throw new HttpsError('failed-precondition', 'Task reset is active');
    }
    const taskSnapshots = [];
    for (const ref of taskRefs) taskSnapshots.push(await transaction.get(ref));

    if (isGuidance) {
      transaction.set(userRef.collection('workflowResponses').doc(workflowId), {
        workflowId,
        answers,
        workflowType: 'guidance',
        completedAt: serverTimestamp()
      });
      const snapshot = taskSnapshots[0];
      if (snapshot.exists) {
        const data = snapshot.data() || {};
        const update = {
          status: 'Completed',
          completedAt: serverTimestamp(),
          qualifyingAnswers: answers
        };
        if (data.dispositionContract !== undefined) {
          validateDispositionContract(data.status, data.dispositionContract, now);
          update.dispositionContract = buildCompletedContract(
            data.dispositionContract,
            'Guidance complete'
          );
        }
        transaction.update(taskRefs[0], update);
      }
      return { success: true, status: 'completed' };
    }

    if (isMiniAssessment) {
      for (const snapshot of taskSnapshots) {
        if (snapshot.exists && snapshot.data()?.dispositionContract !== undefined) {
          throw new HttpsError(
            'failed-precondition',
            'Mini-assessment may not overwrite a contracted task'
          );
        }
      }
      transaction.set(userRef.collection('mini_assessments').doc(workflowId), {
        workflowId,
        answers,
        completedAt: serverTimestamp(),
        status: 'completed'
      });
      const workflow = MINI_ASSESSMENT_WORKFLOWS[workflowId];
      for (const [index, answer] of answers.entries()) {
        const taskId = `${workflowId}_${answer.id}`;
        const taskTitle = `${workflow.taskTemplate.titlePrefix} ${answer.textEntry || answer.displayName}`;
        transaction.set(taskRefs[index], {
          id: taskId,
          title: taskTitle,
          subtitle: 'Update your address',
          category: workflow.taskTemplate.category,
          subcategory: workflow.taskTemplate.subcategory,
          status: 'pending',
          priority: workflow.taskTemplate.priority,
          createdAt: serverTimestamp(),
          source: 'mini_assessment'
        });
      }
      return { success: true, tasksCreated: answers.length };
    }

    const result = { success: true, status: 'matching_in_progress' };
    const submission = {
      workflowId,
      userId,
      answers,
      submittedAt: serverTimestamp(),
      status: 'pending_matching'
    };
    if (normalizedSubmissionToken) {
      Object.assign(submission, {
        owner: userId,
        submissionToken: normalizedSubmissionToken,
        fingerprint,
        result
      });
    }
    transaction.create(submissionRef, submission);
    transaction.set(userRef.collection('workflowResponses').doc(workflowId), {
      workflowId,
      answers,
      submittedAt: serverTimestamp()
    });
    const snapshot = taskSnapshots[0];
    if (snapshot.exists) {
      const data = snapshot.data() || {};
      const update = {
        status: 'matching_in_progress',
        qualifyingAnswers: answers,
        qualifyingCompletedAt: serverTimestamp()
      };
      if (data.dispositionContract !== undefined) {
        validateDispositionContract(data.status, data.dispositionContract, now);
        update.dispositionContract = buildWaitingOnExternalContract(
          data.dispositionContract,
          requireWaitingInput(answers, workflowId),
          now
        );
      }
      transaction.update(taskRefs[0], update);
    }
    return result;
  });
}

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

module.exports = {
  getWorkflowQualifying,
  submitWorkflowAnswers,
  getMiniAssessmentTypes,
  executeWorkflowAnswers,
  requireWaitingInput,
  taskResetIsActive,
  canonicalJSON,
  validateSubmissionToken,
  workflowSubmissionFingerprint,
  workflowSubmissionId,
  replayWorkflowSubmission
};
