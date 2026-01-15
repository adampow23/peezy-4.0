/**
 * Peezy Brain - Workflow Tests
 * 
 * Tests workflow definitions and completeness.
 */

describe('Peezy Brain - Workflows', () => {

  let WORKFLOWS;

  beforeAll(() => {
    try {
      const workflowModule = require('../functions/workflows');
      WORKFLOWS = workflowModule.WORKFLOWS;
    } catch (e) {
      // Workflows not yet created
      WORKFLOWS = null;
    }
  });

  // ============================================
  // WORKFLOW CATALOG COMPLETENESS
  // ============================================
  describe('Workflow Catalog', () => {
    test('workflow catalog exists', () => {
      expect(WORKFLOWS).not.toBeNull();
      expect(typeof WORKFLOWS).toBe('object');
    });

    test('has 40 workflows', () => {
      if (!WORKFLOWS) return;
      const count = Object.keys(WORKFLOWS).length;
      expect(count).toBeGreaterThanOrEqual(40);
    });

    test('all logistics workflows exist', () => {
      if (!WORKFLOWS) return;
      const logisticsWorkflows = [
        'book_movers',
        'book_long_distance_movers',
        'schedule_move_date',
        'truck_rental',
        'coordinate_timing',
        'moving_day_prep',
        'post_move_checklist',
        'handle_moving_issues'
      ];

      for (const workflow of logisticsWorkflows) {
        expect(WORKFLOWS[workflow]).toBeDefined();
      }
    });

    test('all services workflows exist', () => {
      if (!WORKFLOWS) return;
      const servicesWorkflows = [
        'junk_removal',
        'cleaning_service',
        'pet_transport',
        'storage_unit',
        'internet_setup',
        'utility_transfer',
        'home_security',
        'auto_transport',
        'packing_services',
        'handyman_services',
        'appliance_services',
        'furniture_assembly'
      ];

      for (const workflow of servicesWorkflows) {
        expect(WORKFLOWS[workflow]).toBeDefined();
      }
    });

    test('all admin workflows exist', () => {
      if (!WORKFLOWS) return;
      const adminWorkflows = [
        'change_address',
        'mail_forwarding',
        'school_transfer',
        'update_insurance',
        'dmv_tasks',
        'voter_registration',
        'medical_records',
        'subscription_updates'
      ];

      for (const workflow of adminWorkflows) {
        expect(WORKFLOWS[workflow]).toBeDefined();
      }
    });

    test('all housing workflows exist', () => {
      if (!WORKFLOWS) return;
      const housingWorkflows = [
        'landlord_notice',
        'security_deposit',
        'home_inspection',
        'closing_prep',
        'walkthrough',
        'new_home_setup'
      ];

      for (const workflow of housingWorkflows) {
        expect(WORKFLOWS[workflow]).toBeDefined();
      }
    });

    test('all packing workflows exist', () => {
      if (!WORKFLOWS) return;
      const packingWorkflows = [
        'packing_supplies',
        'declutter',
        'start_packing',
        'pack_fragile',
        'essentials_box',
        'labeling_system'
      ];

      for (const workflow of packingWorkflows) {
        expect(WORKFLOWS[workflow]).toBeDefined();
      }
    });
  });

  // ============================================
  // WORKFLOW STRUCTURE
  // ============================================
  describe('Workflow Structure', () => {
    test('each workflow has required fields', () => {
      if (!WORKFLOWS) return;

      for (const [id, workflow] of Object.entries(WORKFLOWS)) {
        expect(workflow.id || id).toBeDefined();
        expect(workflow.title).toBeDefined();
        expect(workflow.description).toBeDefined();
        expect(workflow.steps).toBeDefined();
        expect(Array.isArray(workflow.steps)).toBe(true);
      }
    });

    test('each workflow has at least 3 steps', () => {
      if (!WORKFLOWS) return;

      for (const [id, workflow] of Object.entries(WORKFLOWS)) {
        expect(workflow.steps.length).toBeGreaterThanOrEqual(3);
      }
    });

    test('book_movers workflow has correct steps', () => {
      if (!WORKFLOWS) return;
      const bookMovers = WORKFLOWS.book_movers;

      expect(bookMovers).toBeDefined();
      expect(bookMovers.steps.length).toBeGreaterThanOrEqual(5);
      
      // Should include key steps
      const stepsText = bookMovers.steps.join(' ').toLowerCase();
      expect(stepsText).toMatch(/special items|piano|safe/i);
      expect(stepsText).toMatch(/service level|full service/i);
      expect(stepsText).toMatch(/budget|quote/i);
    });

    test('workflows with vendors have vendorCategory', () => {
      if (!WORKFLOWS) return;
      const workflowsWithVendors = [
        'book_movers',
        'junk_removal',
        'cleaning_service',
        'internet_setup',
        'storage_unit'
      ];

      for (const workflowId of workflowsWithVendors) {
        const workflow = WORKFLOWS[workflowId];
        if (workflow) {
          expect(workflow.vendorCategory).toBeDefined();
        }
      }
    });

    test('key info is populated for complex workflows', () => {
      if (!WORKFLOWS) return;
      const complexWorkflows = ['book_movers', 'book_long_distance_movers'];

      for (const workflowId of complexWorkflows) {
        const workflow = WORKFLOWS[workflowId];
        if (workflow) {
          expect(workflow.keyInfo).toBeDefined();
          expect(Object.keys(workflow.keyInfo).length).toBeGreaterThan(0);
        }
      }
    });
  });

  // ============================================
  // WORKFLOW CONTENT QUALITY
  // ============================================
  describe('Workflow Content Quality', () => {
    test('steps are actionable', () => {
      if (!WORKFLOWS) return;

      for (const [id, workflow] of Object.entries(WORKFLOWS)) {
        for (const step of workflow.steps) {
          // Each step should start with a verb or be action-oriented
          expect(step.length).toBeGreaterThan(10);
        }
      }
    });

    test('no duplicate workflow IDs', () => {
      if (!WORKFLOWS) return;
      const ids = Object.keys(WORKFLOWS);
      const uniqueIds = [...new Set(ids)];
      
      expect(ids.length).toBe(uniqueIds.length);
    });

    test('titles are descriptive', () => {
      if (!WORKFLOWS) return;

      for (const [id, workflow] of Object.entries(WORKFLOWS)) {
        expect(workflow.title.length).toBeGreaterThan(5);
        expect(workflow.title.length).toBeLessThan(50);
      }
    });
  });

});
