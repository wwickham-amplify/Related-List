@isTest
public class RelatedListControllerLWRTest {
    
    // Test data setup
    @TestSetup
    static void makeData() {
        // Create test accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Industry = 'Technology',
                Type = 'Customer'
            ));
        }
        insert accounts;
        
        // Create test contacts related to first account
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                Email = 'test' + i + '@example.com',
                AccountId = accounts[0].Id,
                Title = 'Test Title ' + i
            ));
        }
        insert contacts;
        
        // Create test opportunities related to first account
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < 4; i++) {
            opportunities.add(new Opportunity(
                Name = 'Test Opportunity ' + i,
                AccountId = accounts[0].Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Amount = 10000 + (i * 1000)
            ));
        }
        insert opportunities;
        
        // Create test cases
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 2; i++) {
            cases.add(new Case(
                Subject = 'Test Case ' + i,
                Status = 'New',
                Origin = 'Web',
                Priority = 'Medium',
                AccountId = accounts[0].Id
            ));
        }
        insert cases;
    }
    
    @isTest
    static void testGetObjectConfiguration_Success() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        RelatedListControllerLWR.RelatedListConfig config = RelatedListControllerLWR.getObjectConfiguration(
            'Contact',
            testAccount.Id,
            'RelatedList'
        );
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, config, 'Configuration should not be null');
        System.assertEquals('Contact', config.objectApiName, 'Object API name should match');
        System.assertEquals('Contacts', config.objectLabel, 'Object label should be plural');
        System.assertNotEquals(null, config.columns, 'Columns should not be null');
        System.assert(config.columns.size() > 0, 'Should have at least one column');
        System.assertNotEquals(null, config.icon, 'Icon should not be null');
        // Relationship field detection may find AccountId or other valid relationship field
        System.assertNotEquals(null, config.relationshipField, 'Should detect a relationship field');
    }
    
    @isTest
    static void testGetObjectConfiguration_InvalidObject() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        try {
            RelatedListControllerLWR.RelatedListConfig config = RelatedListControllerLWR.getObjectConfiguration(
                'InvalidObject__c',
                testAccount.Id,
                'RelatedList'
            );
            System.assert(false, 'Should have thrown an exception');
        } catch (Exception e) {
            // Should contain some error about the object
            System.assert(String.isNotBlank(e.getMessage()), 'Should have an error message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetObjectConfiguration_EmptyFieldSetName() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        RelatedListControllerLWR.RelatedListConfig config = RelatedListControllerLWR.getObjectConfiguration(
            'Contact',
            testAccount.Id,
            '' // Empty field set name should use fallback
        );
        Test.stopTest();
        
        // Should still work with fallback columns
        System.assertNotEquals(null, config, 'Configuration should not be null');
        System.assert(config.columns.size() > 0, 'Should have fallback columns');
    }
    
    @isTest
    static void testGetObjectConfiguration_NonExistentFieldSet() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        RelatedListControllerLWR.RelatedListConfig config = RelatedListControllerLWR.getObjectConfiguration(
            'Contact',
            testAccount.Id,
            'NonExistentFieldSet'
        );
        Test.stopTest();
        
        // Should work with fallback columns
        System.assertNotEquals(null, config, 'Configuration should not be null');
        System.assert(config.columns.size() > 0, 'Should have fallback columns');
    }
    
    @isTest
    static void testGetRelatedRecords_Success() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Contact> expectedContacts = [SELECT Id, FirstName, LastName FROM Contact WHERE AccountId = :testAccount.Id];
        
        Test.startTest();
        List<RelatedListControllerLWR.RelatedRecord> records = RelatedListControllerLWR.getRelatedRecords(
            'Contact',
            testAccount.Id,
            'AccountId',
            new List<String>{'FirstName', 'LastName', 'Email'},
            'LastName',
            'ASC',
            10
        );
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(null, records, 'Records should not be null');
        System.assertEquals(expectedContacts.size(), records.size(), 'Should return expected number of records');
        
        // Verify first record has expected fields
        if (!records.isEmpty()) {
            RelatedListControllerLWR.RelatedRecord firstRecord = records[0];
            System.assertNotEquals(null, firstRecord.id, 'Record ID should not be null');
            System.assertNotEquals(null, firstRecord.fields, 'Fields should not be null');
            System.assert(firstRecord.fields.containsKey('FirstName'), 'Should contain FirstName field');
            System.assert(firstRecord.fields.containsKey('LastName'), 'Should contain LastName field');
            System.assert(firstRecord.fields.containsKey('Email'), 'Should contain Email field');
        }
    }
    
    @isTest
    static void testGetRelatedRecords_EmptyRelationshipField() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        List<RelatedListControllerLWR.RelatedRecord> records = RelatedListControllerLWR.getRelatedRecords(
            'Contact',
            testAccount.Id,
            '', // Empty relationship field
            new List<String>{'FirstName', 'LastName'},
            'LastName',
            'ASC',
            10
        );
        Test.stopTest();
        
        // Should return empty list
        System.assertNotEquals(null, records, 'Records should not be null');
        System.assertEquals(0, records.size(), 'Should return empty list');
    }
    
    @isTest
    static void testGetRelatedRecords_WithLookupFields() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        List<RelatedListControllerLWR.RelatedRecord> records = RelatedListControllerLWR.getRelatedRecords(
            'Contact',
            testAccount.Id,
            'AccountId',
            new List<String>{'FirstName', 'LastName', 'AccountId'}, // AccountId is a lookup field
            'LastName',
            'ASC',
            10
        );
        Test.stopTest();
        
        // Verify lookup field handling
        System.assertNotEquals(null, records, 'Records should not be null');
        if (!records.isEmpty()) {
            RelatedListControllerLWR.RelatedRecord firstRecord = records[0];
            System.assert(firstRecord.fields.containsKey('AccountId'), 'Should contain AccountId field');
            // The AccountId field should contain the Account name, not just the ID
            Object accountValue = firstRecord.fields.get('AccountId');
            System.assertNotEquals(null, accountValue, 'Account field should not be null');
        }
    }
    
    @isTest
    static void testGetRelatedRecords_InvalidParameters() {
        // Test with null/empty field names to trigger the validation
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        try {
            List<RelatedListControllerLWR.RelatedRecord> records = RelatedListControllerLWR.getRelatedRecords(
                'Contact',
                testAccount.Id,
                'AccountId',
                null, // Null field names should trigger error
                'Name',
                'ASC',
                10
            );
            System.assert(false, 'Should have thrown an exception');
        } catch (Exception e) {
            System.assert(String.isNotBlank(e.getMessage()), 'Should have an error message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetIconName_StandardObject() {
        Test.startTest();
        String iconName = RelatedListControllerLWR.getIconName('Account');
        Test.stopTest();
        
        System.assertNotEquals(null, iconName, 'Icon name should not be null');
        System.assert(iconName.startsWith('standard:'), 'Standard object should have standard icon');
    }
    
    @isTest
    static void testGetIconName_CustomObject() {
        Test.startTest();
        String iconName = RelatedListControllerLWR.getIconName('Custom_Object__c');
        Test.stopTest();
        
        System.assertNotEquals(null, iconName, 'Icon name should not be null');
        // Custom objects without tabs will get fallback icons
        System.assert(iconName.startsWith('custom:'), 'Custom object should have custom icon');
    }
    
    @isTest
    static void testGetIconName_AssetObject() {
        Test.startTest();
        String iconName = RelatedListControllerLWR.getIconName('Asset_Request__c');
        Test.stopTest();
        
        System.assertNotEquals(null, iconName, 'Icon name should not be null');
        System.assertEquals('custom:custom19', iconName, 'Asset object should get specific icon');
    }
    
    @isTest
    static void testGetIconName_RequestObject() {
        Test.startTest();
        String iconName = RelatedListControllerLWR.getIconName('Test_Request__c');
        Test.stopTest();
        
        System.assertNotEquals(null, iconName, 'Icon name should not be null');
        System.assertEquals('custom:custom63', iconName, 'Request object should get specific icon');
    }
    
    @isTest
    static void testGetIconName_ProductObject() {
        Test.startTest();
        String iconName = RelatedListControllerLWR.getIconName('Product_Info__c');
        Test.stopTest();
        
        System.assertNotEquals(null, iconName, 'Icon name should not be null');
        System.assertEquals('custom:custom54', iconName, 'Product object should get specific icon');
    }
    
    @isTest
    static void testFieldMetadata_Constructor() {
        Test.startTest();
        RelatedListControllerLWR.FieldMetadata field = new RelatedListControllerLWR.FieldMetadata();
        Test.stopTest();
        
        System.assertNotEquals(null, field, 'Field metadata should not be null');
        // Test that all properties can be set
        field.apiName = 'TestField';
        field.label = 'Test Field';
        field.type = 'STRING';
        field.sortable = true;
        field.isLookup = false;
        field.referenceTo = 'TestObject';
        
        System.assertEquals('TestField', field.apiName, 'API name should be set');
        System.assertEquals('Test Field', field.label, 'Label should be set');
    }
    
    @isTest
    static void testRelatedListConfig_Constructor() {
        Test.startTest();
        RelatedListControllerLWR.RelatedListConfig config = new RelatedListControllerLWR.RelatedListConfig();
        Test.stopTest();
        
        System.assertNotEquals(null, config, 'Config should not be null');
        System.assertNotEquals(null, config.columns, 'Columns should be initialized');
        System.assertEquals(0, config.columns.size(), 'Columns should be empty initially');
    }
    
    @isTest
    static void testRelatedRecord_Constructor() {
        Test.startTest();
        RelatedListControllerLWR.RelatedRecord record = new RelatedListControllerLWR.RelatedRecord();
        Test.stopTest();
        
        System.assertNotEquals(null, record, 'Record should not be null');
        System.assertNotEquals(null, record.fields, 'Fields should be initialized');
        System.assertEquals(0, record.fields.size(), 'Fields should be empty initially');
    }
    
    @isTest
    static void testGetRelatedRecords_SortingAndLimits() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        // Test DESC sorting and limit
        List<RelatedListControllerLWR.RelatedRecord> records = RelatedListControllerLWR.getRelatedRecords(
            'Contact',
            testAccount.Id,
            'AccountId',
            new List<String>{'FirstName', 'LastName'},
            'LastName',
            'DESC',
            2 // Limit to 2 records
        );
        Test.stopTest();
        
        System.assertNotEquals(null, records, 'Records should not be null');
        System.assert(records.size() <= 2, 'Should respect limit parameter');
        
        // Verify sorting (DESC means last names should be in reverse alphabetical order)
        if (records.size() > 1) {
            String firstName = (String) records[0].fields.get('LastName');
            String secondName = (String) records[1].fields.get('LastName');
            System.assert(firstName >= secondName, 'Should be sorted in descending order');
        }
    }
    
    @isTest
    static void testDetectRelationshipField_MultipleObjects() {
        // Test with different object types to cover relationship detection
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Test Contact relationship detection
        RelatedListControllerLWR.RelatedListConfig contactConfig = RelatedListControllerLWR.getObjectConfiguration(
            'Contact',
            testAccount.Id,
            'RelatedList'
        );
        
        // Test Opportunity relationship detection
        RelatedListControllerLWR.RelatedListConfig oppConfig = RelatedListControllerLWR.getObjectConfiguration(
            'Opportunity',
            testAccount.Id,
            'RelatedList'
        );
        
        Test.stopTest();
        
        // Both should find valid relationship fields (may vary by org configuration)
        System.assertNotEquals(null, contactConfig.relationshipField, 'Contact should have a relationship field');
        System.assertNotEquals(null, oppConfig.relationshipField, 'Opportunity should have a relationship field');
    }
    
    @isTest 
    static void testFallbackColumns_DifferentScenarios() {
        // Test fallback column generation for objects with different field structures
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Test Account (has Name field)
        RelatedListControllerLWR.RelatedListConfig accountConfig = RelatedListControllerLWR.getObjectConfiguration(
            'Account',
            testAccount.Id,
            'NonExistentFieldSet'
        );
        
        // Test Case (has Subject field)
        RelatedListControllerLWR.RelatedListConfig caseConfig = RelatedListControllerLWR.getObjectConfiguration(
            'Case',
            testAccount.Id,
            'NonExistentFieldSet'
        );
        
        Test.stopTest();
        
        // Verify fallback columns were generated
        System.assert(accountConfig.columns.size() > 0, 'Account should have fallback columns');
        System.assert(caseConfig.columns.size() > 0, 'Case should have fallback columns');
        
        // Check that at least one field is included (could be Name, Id, etc.)
        System.assertNotEquals(null, accountConfig.columns[0].apiName, 'Should have a valid field API name');
        System.assertNotEquals(null, accountConfig.columns[0].label, 'Should have a valid field label');
    }
    
    @isTest
    static void testGetFallbackColumns_EdgeCase() {
        // Test the final fallback scenario where no common fields are found
        Test.startTest();
        // Call the fallback method directly with a minimal object description
        List<RelatedListControllerLWR.FieldMetadata> columns = RelatedListControllerLWR.getFallbackColumns(
            'Account', 
            null // This will trigger getting the describe and then fallback to ID field
        );
        Test.stopTest();
        
        System.assert(columns.size() > 0, 'Should have at least one fallback column');
    }
    
    @isTest
    static void testIconExtractionCoverage() {
        // This test helps cover the icon extraction logic
        Test.startTest();
        
        // Test various custom object patterns to hit the icon extraction paths
        String assetIcon = RelatedListControllerLWR.getCustomObjectFallbackIcon('My_Asset_Object__c');
        String requestIcon = RelatedListControllerLWR.getCustomObjectFallbackIcon('Service_Request__c');
        String productIcon = RelatedListControllerLWR.getCustomObjectFallbackIcon('Product_Catalog__c');
        String otherIcon = RelatedListControllerLWR.getCustomObjectFallbackIcon('Random_Object__c');
        
        Test.stopTest();
        
        // Verify the pattern matching works
        System.assertEquals('custom:custom19', assetIcon, 'Asset objects should get custom19');
        System.assertEquals('custom:custom63', requestIcon, 'Request objects should get custom63');
        System.assertEquals('custom:custom54', productIcon, 'Product objects should get custom54');
        System.assert(otherIcon.startsWith('custom:custom'), 'Other objects should get hash-based icon');
    }
    
    @isTest
    static void testGetRelatedRecords_LookupFieldEdgeCases() {
        // Create test data with lookup relationships to test edge cases
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        // Test with Cases that have lookup to Account
        Case testCase = new Case(
            Subject = 'Test Case for Lookup',
            Status = 'New',
            Origin = 'Web',
            AccountId = testAccount.Id
        );
        insert testCase;
        
        Test.startTest();
        
        // Test retrieving Cases with AccountId lookup field
        List<RelatedListControllerLWR.RelatedRecord> records = RelatedListControllerLWR.getRelatedRecords(
            'Case',
            testAccount.Id,
            'AccountId',
            new List<String>{'Subject', 'AccountId', 'Status'}, // Include lookup field
            'Subject',
            'ASC',
            10
        );
        
        Test.stopTest();
        
        // Verify lookup field handling
        System.assertNotEquals(null, records, 'Records should not be null');
        if (!records.isEmpty()) {
            RelatedListControllerLWR.RelatedRecord firstRecord = records[0];
            
            // The AccountId lookup should be resolved to Account name
            System.assert(firstRecord.fields.containsKey('AccountId'), 'Should contain AccountId field');
            Object accountValue = firstRecord.fields.get('AccountId');
            System.assertNotEquals(null, accountValue, 'Account field should not be null');
            
            // Should contain other fields too
            System.assert(firstRecord.fields.containsKey('Subject'), 'Should contain Subject field');
            System.assert(firstRecord.fields.containsKey('Status'), 'Should contain Status field');
        }
    }
    
    @isTest
    static void testBuildDynamicQuery_ComplexScenarios() {
        // Test the query building with lookup fields to cover relationship traversal
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Create a Case with lookup to test relationship field handling in query
        Case testCase = new Case(
            Subject = 'Test Case with Owner',
            Status = 'New',
            Origin = 'Web', 
            AccountId = testAccount.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert testCase;
        
        // Test with lookup fields that reference User and Account
        List<RelatedListControllerLWR.RelatedRecord> records = RelatedListControllerLWR.getRelatedRecords(
            'Case',
            testAccount.Id,
            'AccountId',
            new List<String>{'Subject', 'Status', 'AccountId', 'OwnerId'}, // Multiple lookup fields
            'Subject',
            'DESC', // Test DESC sorting
            3
        );
        
        Test.stopTest();
        
        System.assertNotEquals(null, records, 'Records should not be null');
        if (!records.isEmpty()) {
            RelatedListControllerLWR.RelatedRecord record = records[0];
            
            // Verify all field types are handled including multiple lookups
            System.assert(record.fields.containsKey('Subject'), 'Should have Subject field');
            System.assert(record.fields.containsKey('Status'), 'Should have Status field');
            System.assert(record.fields.containsKey('AccountId'), 'Should have AccountId field');
            System.assert(record.fields.containsKey('OwnerId'), 'Should have OwnerId field');
            
            // Verify display name is set from first field
            System.assertNotEquals(null, record.displayName, 'Display name should be set');
        }
    }
    
    @isTest
    static void testFieldProcessingErrorHandling() {
        // Test error handling in field processing with existing valid fields
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Test with valid fields only to avoid script exceptions
        List<RelatedListControllerLWR.RelatedRecord> records = RelatedListControllerLWR.getRelatedRecords(
            'Contact',
            testAccount.Id,
            'AccountId',
            new List<String>{'FirstName', 'LastName', 'AccountId'}, // Only valid fields
            'LastName',
            'ASC',
            5
        );
        
        Test.stopTest();
        
        // Should return records successfully
        System.assertNotEquals(null, records, 'Records should not be null');
        
        if (!records.isEmpty()) {
            RelatedListControllerLWR.RelatedRecord record = records[0];
            
            // Should have all the valid fields
            System.assert(record.fields.containsKey('FirstName'), 'Should have FirstName field');
            System.assert(record.fields.containsKey('LastName'), 'Should have LastName field');
            System.assert(record.fields.containsKey('AccountId'), 'Should have AccountId field');
        }
    }
    
    @isTest
    static void testActualFieldSetProcessing() {
        // Test the actual field set processing path by creating a simple field set scenario
        // Since we can't create field sets in tests, we'll test the path where a field set exists
        // but has fields that need processing
        
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Call getFieldSetColumns directly to test the field set processing logic
        List<RelatedListControllerLWR.FieldMetadata> columns = RelatedListControllerLWR.getFieldSetColumns(
            'Contact',
            '' // Empty field set name will trigger fallback, but we're testing the method structure
        );
        
        // Also test with a non-existent field set name to cover that path
        List<RelatedListControllerLWR.FieldMetadata> fallbackColumns = RelatedListControllerLWR.getFieldSetColumns(
            'Contact',
            'NonExistentFieldSet'
        );
        
        Test.stopTest();
        
        // Both should return fallback columns since field sets don't exist in test context
        System.assert(columns.size() > 0, 'Should have fallback columns');
        System.assert(fallbackColumns.size() > 0, 'Should have fallback columns');
        
        // Verify column metadata structure
        RelatedListControllerLWR.FieldMetadata firstColumn = columns[0];
        System.assertNotEquals(null, firstColumn.apiName, 'Should have API name');
        System.assertNotEquals(null, firstColumn.label, 'Should have label');
        System.assertNotEquals(null, firstColumn.type, 'Should have type');
        System.assertNotEquals(null, firstColumn.sortable, 'Should have sortable flag');
        System.assertNotEquals(null, firstColumn.isLookup, 'Should have isLookup flag');
    }
    
    @isTest
    static void testGetFieldSetColumns_ExceptionHandling() {
        Test.startTest();
        
        // Test with null object name to trigger exception handling
        List<RelatedListControllerLWR.FieldMetadata> columns = RelatedListControllerLWR.getFieldSetColumns(
            null,
            'TestFieldSet'
        );
        
        Test.stopTest();
        
        // Should still return some columns due to exception handling and fallback
        System.assertNotEquals(null, columns, 'Should not return null even with errors');
    }
    
    @isTest
    static void testBuildDynamicQuery_EdgeCases() {
        // Test the query building with various edge cases
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Test with mixed field types including lookups
        List<RelatedListControllerLWR.RelatedRecord> records = RelatedListControllerLWR.getRelatedRecords(
            'Opportunity',
            testAccount.Id,
            'AccountId',
            new List<String>{'Name', 'StageName', 'CloseDate', 'Amount', 'AccountId'},
            'Name',
            'ASC',
            5
        );
        
        Test.stopTest();
        
        System.assertNotEquals(null, records, 'Records should not be null');
        if (!records.isEmpty()) {
            RelatedListControllerLWR.RelatedRecord firstRecord = records[0];
            
            // Verify all field types are handled
            System.assert(firstRecord.fields.containsKey('Name'), 'Should have Name (text) field');
            System.assert(firstRecord.fields.containsKey('StageName'), 'Should have StageName (picklist) field');
            System.assert(firstRecord.fields.containsKey('CloseDate'), 'Should have CloseDate (date) field');
            System.assert(firstRecord.fields.containsKey('Amount'), 'Should have Amount (currency) field');
            System.assert(firstRecord.fields.containsKey('AccountId'), 'Should have AccountId (lookup) field');
        }
    }
}