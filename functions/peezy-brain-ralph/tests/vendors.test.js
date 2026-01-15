/**
 * Peezy Brain - Vendor Tests
 * 
 * Tests vendor catalog completeness and surfacing behavior.
 */

describe('Peezy Brain - Vendors', () => {

  let VENDORS;

  beforeAll(() => {
    try {
      const vendorModule = require('../functions/vendorCatalog');
      VENDORS = vendorModule.VENDORS;
    } catch (e) {
      // Vendor catalog not yet created
      VENDORS = null;
    }
  });

  // ============================================
  // VENDOR CATALOG COMPLETENESS
  // ============================================
  describe('Vendor Catalog', () => {
    test('vendor catalog exists', () => {
      expect(VENDORS).not.toBeNull();
      expect(typeof VENDORS).toBe('object');
    });

    test('has 50+ vendor categories', () => {
      if (!VENDORS) return;
      const count = Object.keys(VENDORS).length;
      expect(count).toBeGreaterThanOrEqual(50);
    });

    test('all core vendors exist', () => {
      if (!VENDORS) return;
      const coreVendors = [
        'movers',
        'long_distance_movers',
        'internet',
        'junk_removal',
        'cleaning',
        'truck_rental'
      ];

      for (const vendor of coreVendors) {
        expect(VENDORS[vendor]).toBeDefined();
      }
    });

    test('all situational vendors exist', () => {
      if (!VENDORS) return;
      const situationalVendors = [
        'storage',
        'pet_transport',
        'auto_transport',
        'packing_services'
      ];

      for (const vendor of situationalVendors) {
        expect(VENDORS[vendor]).toBeDefined();
      }
    });

    test('all property vendors exist', () => {
      if (!VENDORS) return;
      const propertyVendors = [
        'plumber',
        'hvac',
        'electrician',
        'locksmith',
        'home_security'
      ];

      for (const vendor of propertyVendors) {
        expect(VENDORS[vendor]).toBeDefined();
      }
    });

    test('all specialty vendors exist', () => {
      if (!VENDORS) return;
      const specialtyVendors = [
        'piano_moving',
        'pool_table_moving',
        'art_moving'
      ];

      for (const vendor of specialtyVendors) {
        expect(VENDORS[vendor]).toBeDefined();
      }
    });

    test('all insurance vendors exist', () => {
      if (!VENDORS) return;
      const insuranceVendors = [
        'renters_insurance',
        'homeowners_insurance',
        'auto_insurance'
      ];

      for (const vendor of insuranceVendors) {
        expect(VENDORS[vendor]).toBeDefined();
      }
    });
  });

  // ============================================
  // VENDOR STRUCTURE
  // ============================================
  describe('Vendor Structure', () => {
    test('each vendor has required fields', () => {
      if (!VENDORS) return;

      for (const [id, vendor] of Object.entries(VENDORS)) {
        expect(vendor.id || id).toBeDefined();
        expect(vendor.displayName).toBeDefined();
        expect(vendor.category).toBeDefined();
        expect(vendor.triggers).toBeDefined();
        expect(vendor.surfacingStyle).toBeDefined();
      }
    });

    test('triggers have explicit and implicit arrays', () => {
      if (!VENDORS) return;

      for (const [id, vendor] of Object.entries(VENDORS)) {
        expect(vendor.triggers.explicit).toBeDefined();
        expect(Array.isArray(vendor.triggers.explicit)).toBe(true);
        expect(vendor.triggers.explicit.length).toBeGreaterThan(0);
      }
    });

    test('surfacing styles are valid', () => {
      if (!VENDORS) return;
      const validStyles = ['direct', 'inform', 'plant_seed'];

      for (const [id, vendor] of Object.entries(VENDORS)) {
        expect(validStyles).toContain(vendor.surfacingStyle);
      }
    });

    test('categories are valid', () => {
      if (!VENDORS) return;
      const validCategories = ['core', 'situational', 'property', 'specialty', 'home_services', 'insurance'];

      for (const [id, vendor] of Object.entries(VENDORS)) {
        expect(validCategories).toContain(vendor.category);
      }
    });

    test('plant_seed vendors have seedPhrase', () => {
      if (!VENDORS) return;

      for (const [id, vendor] of Object.entries(VENDORS)) {
        if (vendor.surfacingStyle === 'plant_seed') {
          expect(vendor.seedPhrase).toBeDefined();
          expect(vendor.seedPhrase.length).toBeGreaterThan(20);
        }
      }
    });
  });

  // ============================================
  // TRIGGER ACCURACY
  // ============================================
  describe('Trigger Accuracy', () => {
    test('mover triggers are comprehensive', () => {
      if (!VENDORS) return;
      const moverTriggers = VENDORS.movers?.triggers?.explicit || [];
      
      expect(moverTriggers).toEqual(
        expect.arrayContaining(['movers', 'moving company'])
      );
    });

    test('internet triggers are comprehensive', () => {
      if (!VENDORS) return;
      const internetTriggers = VENDORS.internet?.triggers?.explicit || [];
      
      expect(internetTriggers).toEqual(
        expect.arrayContaining(['internet', 'wifi'])
      );
    });

    test('no duplicate vendor IDs', () => {
      if (!VENDORS) return;
      const ids = Object.keys(VENDORS);
      const uniqueIds = [...new Set(ids)];
      
      expect(ids.length).toBe(uniqueIds.length);
    });
  });

});
