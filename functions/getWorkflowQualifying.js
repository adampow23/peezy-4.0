/**
 * Get Workflow Qualifying - Firebase Cloud Function
 * 
 * Returns qualifying questions for both:
 * - Vendor workflows (book_movers, cleaning_service, etc.)
 * - Mini-assessment workflows (address_change_financial, etc.)
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
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
    
    throw new HttpsError('not-found', `Workflow not found: ${workflowId}`);
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
      
      // Determine if this is a mini-assessment or vendor workflow
      const isMiniAssessment = workflowId in MINI_ASSESSMENT_WORKFLOWS;
      
      if (isMiniAssessment) {
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
        
        // Update the user's task status
        await db.collection('users')
          .doc(userId)
          .collection('tasks')
          .doc(workflowId)
          .update({
            status: 'matching_in_progress',
            qualifyingAnswers: answers,
            qualifyingCompletedAt: admin.firestore.FieldValue.serverTimestamp()
          });
        
        // Send booking notification (non-blocking)
        const webhookUrl = process.env.NOTIFICATION_WEBHOOK_URL;
        if (webhookUrl) {
          fetch(webhookUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              type: 'vendor_workflow_submitted',
              userId,
              workflowId,
              answers,
              submittedAt: new Date().toISOString(),
              status: 'pending_matching'
            })
          }).catch(err => console.error('Notification webhook failed:', err.message));
        } else {
          console.warn('NOTIFICATION_WEBHOOK_URL not configured — vendor submission not notified');
        }

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

module.exports = {
  getWorkflowQualifying,
  submitWorkflowAnswers,
  getMiniAssessmentTypes
};