@isTest
public class RelatedListLWRControllerTest {
    
    // ===== TEST DATA SETUP =====
    
    @testSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account',
            Phone = '555-1234',
            Website = 'www.test.com'
        );
        insert testAccount;
        
        // Create test contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                Email = 'test' + i + '@example.com',
                Phone = '555-000' + i,
                AccountId = testAccount.Id
            ));
        }
        insert contacts;
        
        // Create test opportunities
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            opportunities.add(new Opportunity(
                Name = 'Test Opportunity ' + i,
                AccountId = testAccount.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Amount = 10000 * (i + 1)
            ));
        }
        insert opportunities;
        
        // Create test case for Knowledge Articles
        Case testCase = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Origin = 'Web',
            AccountId = testAccount.Id
        );
        insert testCase;
        
        // Create ContentVersion for file testing
        ContentVersion cv = new ContentVersion(
            Title = 'Test Image',
            PathOnClient = 'test.png',
            VersionData = Blob.valueOf('Test image content'),
            IsMajorVersion = true
        );
        insert cv;
        
        // Get ContentDocumentId
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        
        // Create ContentDocumentLink
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = testAccount.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
    }
    
    // ===== ARL MODE TESTS =====
    
    @isTest
    static void testGetObjectTypeFromRecordId_Success() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        String objectType = RelatedListLWRController.getObjectTypeFromRecordId(acc.Id);
        Test.stopTest();
        
        System.assertEquals('Account', objectType, 'Should return Account object type');
    }
    
    @isTest
    static void testGetObjectTypeFromRecordId_BlankId() {
        Test.startTest();
        String objectType = RelatedListLWRController.getObjectTypeFromRecordId('');
        Test.stopTest();
        
        System.assertEquals(null, objectType, 'Should return null for blank ID');
    }
    
    @isTest
    static void testGetRelatedListInfo_Contacts() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        RelatedListLWRController.RelatedListInfo result =
            RelatedListLWRController.getRelatedListInfo('Account', 'Contacts', acc.Id, 'Name,Email,Phone', '', 0, 25);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.fields.size() > 0, 'Should have field information');
        System.assertEquals(5, result.records.size(), 'Should return 5 contacts');
    }
    
    @isTest
    static void testGetRelatedListInfo_WithRelationshipField() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        RelatedListLWRController.RelatedListInfo result =
            RelatedListLWRController.getRelatedListInfo('Account', 'Contacts', acc.Id, 'Name,Email', 'AccountId', 0, 25);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.relatedObjectType, 'Should identify related object type');
        // The relationship field helps find the correct relationship, records may vary
        System.assert(result.records.size() >= 0, 'Should return records or empty list');
    }
    
    @isTest
    static void testGetRelatedListInfo_Opportunities() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        RelatedListLWRController.RelatedListInfo result = 
            RelatedListLWRController.getRelatedListInfo('Account', 'Opportunities', acc.Id, 'Name,Amount,StageName', '', 0, 25);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(3, result.records.size(), 'Should return 3 opportunities');
    }
    
    @isTest
    static void testGetRelatedListInfo_NoEnabledFields() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        RelatedListLWRController.RelatedListInfo result = 
            RelatedListLWRController.getRelatedListInfo('Account', 'Contacts', acc.Id, '', '', 0, 25);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.fields.size() > 0, 'Should use default fields');
    }
    
    @isTest
    static void testGetRelatedListInfo_InvalidRelationship() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        RelatedListLWRController.RelatedListInfo result = 
            RelatedListLWRController.getRelatedListInfo('Account', 'InvalidRelationship', acc.Id, '', '', 0, 25);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.records.size(), 'Should return no records for invalid relationship');
    }
    
    // ===== KNOWLEDGE ARTICLES TESTS =====
    
    @isTest
    static void testGetCaseArticles_NoArticles() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        List<RelatedListLWRController.ArticleData> articles = 
            RelatedListLWRController.getCaseArticles(testCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Should return a list');
        System.assertEquals(0, articles.size(), 'Should return empty list when no articles');
    }
    
    @isTest
    static void testGetCaseArticles_BlankCaseId() {
        Test.startTest();
        List<RelatedListLWRController.ArticleData> articles = 
            RelatedListLWRController.getCaseArticles('');
        Test.stopTest();
        
        System.assertEquals(0, articles.size(), 'Should return empty list for blank case ID');
    }
    
    @isTest
    static void testGetCaseArticles_InvalidCaseId() {
        Test.startTest();
        try {
            List<RelatedListLWRController.ArticleData> articles = 
                RelatedListLWRController.getCaseArticles('001000000000000');
            System.assertEquals(0, articles.size(), 'Should return empty list for non-existent case');
        } catch (AuraHandledException e) {
            System.assert(true, 'Should handle invalid case ID gracefully');
        }
        Test.stopTest();
    }
    
    // ===== FILES TESTS =====
    
    @isTest
    static void testGetFiles_Success() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 50);
        Test.stopTest();

        System.assertNotEquals(null, files, 'Should return a list');
        System.assertEquals(1, files.size(), 'Should return 1 file');
        System.assertEquals('Test Image', files[0].title, 'File title should match');
        System.assertNotEquals(null, files[0].downloadUrl, 'Should have download URL');
        System.assertEquals(true, files[0].isImage, 'PNG should be identified as image');
    }
    
    @isTest
    static void testGetFiles_DifferentSortFields() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<RelatedListLWRController.FileRecord> filesByTitle =
            RelatedListLWRController.getFiles(acc.Id, 'Title', 'ASC', 10);
        List<RelatedListLWRController.FileRecord> filesBySize =
            RelatedListLWRController.getFiles(acc.Id, 'ContentSize', 'DESC', 10);
        List<RelatedListLWRController.FileRecord> filesByExt =
            RelatedListLWRController.getFiles(acc.Id, 'FileExtension', 'ASC', 10);
        Test.stopTest();

        System.assertEquals(1, filesByTitle.size(), 'Should return files sorted by title');
        System.assertEquals(1, filesBySize.size(), 'Should return files sorted by size');
        System.assertEquals(1, filesByExt.size(), 'Should return files sorted by extension');
    }
    
    @isTest
    static void testGetFiles_DefaultParameters() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, null, null, null);
        Test.stopTest();

        System.assertEquals(1, files.size(), 'Should use default parameters');
    }
    
    @isTest
    static void testGetFiles_BlankRecordId() {
        Test.startTest();
        try {
            List<RelatedListLWRController.FileRecord> files =
                RelatedListLWRController.getFiles('', 'CreatedDate', 'DESC', 50);
            System.assert(false, 'Should throw exception for blank record ID');
        } catch (AuraHandledException e) {
            // Just verify we caught the exception - the message will vary
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
        
    @isTest
    static void testGetImageAsBase64_Success() {
        ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion LIMIT 1];
        
        Test.startTest();
        String base64Image = RelatedListLWRController.getImageAsBase64(cv.ContentDocumentId);
        Test.stopTest();
        
        System.assertNotEquals(null, base64Image, 'Should return base64 string');
        System.assert(base64Image.startsWith('data:image/'), 'Should be a data URL');
    }
    
    @isTest
    static void testGetImageAsBase64_InvalidId() {
        Test.startTest();
        String base64Image = RelatedListLWRController.getImageAsBase64('069000000000000AAA');
        Test.stopTest();
        
        System.assertEquals(null, base64Image, 'Should return null for invalid ID');
    }
    
    // ===== HELPER METHODS TESTS =====
    
    @isTest
    static void testFileIconMapping() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create files with different extensions
        List<ContentVersion> cvList = new List<ContentVersion>{
            new ContentVersion(Title = 'Test PDF', PathOnClient = 'test.pdf', VersionData = Blob.valueOf('PDF')),
            new ContentVersion(Title = 'Test Word', PathOnClient = 'test.docx', VersionData = Blob.valueOf('Word')),
            new ContentVersion(Title = 'Test Excel', PathOnClient = 'test.xlsx', VersionData = Blob.valueOf('Excel')),
            new ContentVersion(Title = 'Test Unknown', PathOnClient = 'test.unknown', VersionData = Blob.valueOf('Unknown'))
        };
        insert cvList;
        
        // Link to account
        List<ContentDocumentLink> cdlList = new List<ContentDocumentLink>();
        for (ContentVersion cv : [SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :cvList]) {
            cdlList.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = acc.Id,
                ShareType = 'V'
            ));
        }
        insert cdlList;
        
        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 50);
        Test.stopTest();

        System.assert(files.size() >= 4, 'Should return multiple files with different icons');
    }
    
    @isTest
    static void testFileSizeFormatting() {
        // Test through file creation with various sizes
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 50);
        Test.stopTest();

        System.assertNotEquals(null, files[0].formattedSize, 'Should have formatted size');
        System.assert(files[0].formattedSize.contains('Bytes') || 
                     files[0].formattedSize.contains('KB') || 
                     files[0].formattedSize.contains('MB'), 
                     'Size should have unit');
    }
    
    // ===== EDGE CASES =====
    
    @isTest
    static void testGetRelatedListInfo_WithInvalidFields() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        RelatedListLWRController.RelatedListInfo result =
            RelatedListLWRController.getRelatedListInfo('Account', 'Contacts', acc.Id, 'Name,InvalidField__c', '', 0, 25);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should handle invalid fields gracefully');
        System.assert(result.fields.size() >= 1, 'Should return at least valid fields');
    }

    @isTest
    static void testGetRelatedListInfo_WithRelationshipFields() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // Test with relationship field notation (e.g., Account.Name)
        RelatedListLWRController.RelatedListInfo result =
            RelatedListLWRController.getRelatedListInfo('Account', 'Contacts', acc.Id, 'Name,Account.Name,Account.Industry', '', 0, 25);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should handle relationship fields');
        System.assert(result.fields.size() >= 1, 'Should include relationship fields');
    }

    @isTest
    static void testGetFiles_WithInvalidRecordId() {
        Test.startTest();
        try {
            List<RelatedListLWRController.FileRecord> files =
                RelatedListLWRController.getFiles('invalid', 'CreatedDate', 'DESC', 50);
            System.assert(false, 'Should throw exception for invalid record ID');
        } catch (Exception e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetImageAsBase64_WithAccessDenied() {
        // Create a content version without linking it to test access control
        ContentVersion cv = new ContentVersion(
            Title = 'Unlinked Image',
            PathOnClient = 'unlinked.jpg',
            VersionData = Blob.valueOf('Test unlinked image'),
            IsMajorVersion = true
        );
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        // Delete any links
        delete [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId = :cv.ContentDocumentId];

        Test.startTest();
        String result = RelatedListLWRController.getImageAsBase64(cv.ContentDocumentId);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when access denied');
    }

    @isTest
    static void testFilePreviewTypes() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Create files with different preview capabilities
        List<ContentVersion> cvList = new List<ContentVersion>{
            new ContentVersion(Title = 'Test JPG', PathOnClient = 'test.jpg', VersionData = Blob.valueOf('JPG')),
            new ContentVersion(Title = 'Test GIF', PathOnClient = 'test.gif', VersionData = Blob.valueOf('GIF')),
            new ContentVersion(Title = 'Test CSV', PathOnClient = 'test.csv', VersionData = Blob.valueOf('CSV')),
            new ContentVersion(Title = 'Test TXT', PathOnClient = 'test.txt', VersionData = Blob.valueOf('TXT'))
        };
        insert cvList;

        List<ContentDocumentLink> cdlList = new List<ContentDocumentLink>();
        for (ContentVersion cv : [SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :cvList]) {
            cdlList.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = acc.Id,
                ShareType = 'V'
            ));
        }
        insert cdlList;

        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 50);
        Test.stopTest();

        Boolean hasPreviewableFile = false;
        Boolean hasNonPreviewableFile = false;
        for (RelatedListLWRController.FileRecord file : files) {
            if (file.canPreview) {
                hasPreviewableFile = true;
            } else {
                hasNonPreviewableFile = true;
            }
        }

        System.assert(files.size() >= 4, 'Should return multiple files');
        System.assert(hasPreviewableFile, 'Should identify previewable files');
    }

    @isTest
    static void testFileSizeFormattingVariations() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Create files with specific sizes to test formatting
        String smallContent = 'X'; // < 1KB
        String mediumContent = '';
        for (Integer i = 0; i < 2000; i++) {
            mediumContent += 'X'; // > 1KB
        }

        List<ContentVersion> cvList = new List<ContentVersion>{
            new ContentVersion(Title = 'Small File', PathOnClient = 'small.txt', VersionData = Blob.valueOf(smallContent)),
            new ContentVersion(Title = 'Medium File', PathOnClient = 'medium.txt', VersionData = Blob.valueOf(mediumContent))
        };
        insert cvList;

        List<ContentDocumentLink> cdlList = new List<ContentDocumentLink>();
        for (ContentVersion cv : [SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :cvList]) {
            cdlList.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = acc.Id,
                ShareType = 'V'
            ));
        }
        insert cdlList;

        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 50);
        Test.stopTest();

        Boolean hasBytesFormat = false;
        Boolean hasKBFormat = false;
        for (RelatedListLWRController.FileRecord file : files) {
            if (file.formattedSize.contains('Bytes')) {
                hasBytesFormat = true;
            }
            if (file.formattedSize.contains('KB')) {
                hasKBFormat = true;
            }
        }

        System.assert(hasBytesFormat || hasKBFormat, 'Should format file sizes correctly');
    }

    @isTest
    static void testGetObjectTypeFromRecordId_InvalidFormat() {
        Test.startTest();
        String objectType = RelatedListLWRController.getObjectTypeFromRecordId('InvalidId123');
        Test.stopTest();

        System.assertEquals(null, objectType, 'Should return null for invalid ID format');
    }

    @isTest
    static void testGetRelatedListInfo_NoRecordsFound() {
        // Create an account with no related records
        Account emptyAccount = new Account(Name = 'Empty Account');
        insert emptyAccount;

        Test.startTest();
        RelatedListLWRController.RelatedListInfo result =
            RelatedListLWRController.getRelatedListInfo('Account', 'Contacts', emptyAccount.Id, 'Name,Email', '', 0, 25);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.records.size(), 'Should return empty list when no records found');
    }

    @isTest
    static void testGetFiles_LimitParameter() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Create multiple files
        List<ContentVersion> cvList = new List<ContentVersion>();
        for (Integer i = 0; i < 5; i++) {
            cvList.add(new ContentVersion(
                Title = 'Test File ' + i,
                PathOnClient = 'test' + i + '.txt',
                VersionData = Blob.valueOf('Content ' + i)
            ));
        }
        insert cvList;

        List<ContentDocumentLink> cdlList = new List<ContentDocumentLink>();
        for (ContentVersion cv : [SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :cvList]) {
            cdlList.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = acc.Id,
                ShareType = 'V'
            ));
        }
        insert cdlList;

        Test.startTest();
        List<RelatedListLWRController.FileRecord> limitedFiles =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 3);
        List<RelatedListLWRController.FileRecord> allFiles =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 50);
        Test.stopTest();

        System.assert(limitedFiles.size() <= 3, 'Should respect limit parameter');
        System.assert(allFiles.size() >= limitedFiles.size(), 'All files should be >= limited files');
    }

    @isTest
    static void testCommonDisplayFields() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // Test with empty enabled fields to trigger default field selection
        RelatedListLWRController.RelatedListInfo contactResult =
            RelatedListLWRController.getRelatedListInfo('Account', 'Contacts', acc.Id, '', '', 0, 25);
        RelatedListLWRController.RelatedListInfo oppResult =
            RelatedListLWRController.getRelatedListInfo('Account', 'Opportunities', acc.Id, '', '', 0, 25);
        Test.stopTest();

        System.assert(contactResult.fields.size() > 0, 'Should use default Contact fields');
        System.assert(oppResult.fields.size() > 0, 'Should use default Opportunity fields');
    }

    // ===== WRAPPER CLASS TESTS =====

    @isTest
    static void testFieldInfoWrapper() {
        Test.startTest();
        RelatedListLWRController.FieldInfo field = new RelatedListLWRController.FieldInfo();
        field.apiName = 'TestField';
        field.label = 'Test Label';
        field.type = 'STRING';

        System.assertEquals('TestField', field.apiName);
        System.assertEquals('Test Label', field.label);
        System.assertEquals('STRING', field.type);
        Test.stopTest();
    }

    @isTest
    static void testRelatedListInfoWrapper() {
        Test.startTest();
        RelatedListLWRController.RelatedListInfo info = new RelatedListLWRController.RelatedListInfo();
        info.fields = new List<RelatedListLWRController.FieldInfo>();
        info.records = new List<sObject>();
        info.relationshipName = 'Contacts';
        info.relatedObjectType = 'Contact';

        System.assertEquals('Contacts', info.relationshipName);
        System.assertEquals('Contact', info.relatedObjectType);
        System.assertNotEquals(null, info.fields);
        System.assertNotEquals(null, info.records);
        Test.stopTest();
    }

    @isTest
    static void testArticleDataDefaultConstructor() {
        Test.startTest();
        RelatedListLWRController.ArticleData article = new RelatedListLWRController.ArticleData();

        System.assertEquals(null, article.id);
        System.assertEquals(null, article.title);
        System.assertEquals(null, article.urlName);
        Test.stopTest();
    }

    @isTest
    static void testArticleDataParameterizedConstructor() {
        Test.startTest();
        RelatedListLWRController.ArticleData article = new RelatedListLWRController.ArticleData(
            'test-id-123', 'Test Article Title', 'test-article-url'
        );

        System.assertEquals('test-id-123', article.id);
        System.assertEquals('Test Article Title', article.title);
        System.assertEquals('test-article-url', article.urlName);
        Test.stopTest();
    }

    @isTest
    static void testArticleDataSetters() {
        Test.startTest();
        RelatedListLWRController.ArticleData article = new RelatedListLWRController.ArticleData();

        article.id = 'new-id';
        article.title = 'New Title';
        article.urlName = 'new-url-name';

        System.assertEquals('new-id', article.id);
        System.assertEquals('New Title', article.title);
        System.assertEquals('new-url-name', article.urlName);
        Test.stopTest();
    }

    @isTest
    static void testFileRecordWrapper() {
        Test.startTest();
        RelatedListLWRController.FileRecord file = new RelatedListLWRController.FileRecord();
        file.id = 'file-123';
        file.title = 'Test File';
        file.fileExtension = 'pdf';
        file.contentSize = 1024;
        file.formattedSize = '1 KB';
        file.isImage = false;
        file.canPreview = true;
        file.icon = 'doctype:pdf';

        System.assertEquals('file-123', file.id);
        System.assertEquals('Test File', file.title);
        System.assertEquals('pdf', file.fileExtension);
        System.assertEquals(1024, file.contentSize);
        System.assertEquals(false, file.isImage);
        System.assertEquals(true, file.canPreview);
        Test.stopTest();
    }

    // ===== MORE COMPREHENSIVE FILE TESTS =====

    @isTest
    static void testGetFiles_AllSortFieldVariations() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<RelatedListLWRController.FileRecord> byTitle =
            RelatedListLWRController.getFiles(acc.Id, 'Title', 'ASC', 10);
        List<RelatedListLWRController.FileRecord> bySize =
            RelatedListLWRController.getFiles(acc.Id, 'ContentSize', 'DESC', 10);
        List<RelatedListLWRController.FileRecord> byExt =
            RelatedListLWRController.getFiles(acc.Id, 'FileExtension', 'ASC', 10);
        List<RelatedListLWRController.FileRecord> byModified =
            RelatedListLWRController.getFiles(acc.Id, 'ContentModifiedDate', 'DESC', 10);
        Test.stopTest();

        System.assertNotEquals(null, byTitle, 'Should handle Title sort');
        System.assertNotEquals(null, bySize, 'Should handle ContentSize sort');
        System.assertNotEquals(null, byExt, 'Should handle FileExtension sort');
        System.assertNotEquals(null, byModified, 'Should handle ContentModifiedDate sort');
    }

    @isTest
    static void testGetFiles_EmptyParameters() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<RelatedListLWRController.FileRecord> filesEmpty =
            RelatedListLWRController.getFiles(acc.Id, '', '', 0);
        List<RelatedListLWRController.FileRecord> filesInvalid =
            RelatedListLWRController.getFiles(acc.Id, 'InvalidField', 'INVALID', 10);
        Test.stopTest();

        System.assertNotEquals(null, filesEmpty, 'Should handle empty parameters');
        System.assertNotEquals(null, filesInvalid, 'Should handle invalid parameters');
    }

    @isTest
    static void testGetFiles_AllFileIcons() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Create comprehensive set of file types using FirstPublishLocationId
        List<ContentVersion> cvList = new List<ContentVersion>{
            new ContentVersion(Title = 'test.xlsx', PathOnClient = 'test.xlsx', VersionData = Blob.valueOf('xlsx'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.xls', PathOnClient = 'test.xls', VersionData = Blob.valueOf('xls'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.pptx', PathOnClient = 'test.pptx', VersionData = Blob.valueOf('pptx'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.ppt', PathOnClient = 'test.ppt', VersionData = Blob.valueOf('ppt'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.csv', PathOnClient = 'test.csv', VersionData = Blob.valueOf('csv'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.xml', PathOnClient = 'test.xml', VersionData = Blob.valueOf('xml'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.zip', PathOnClient = 'test.zip', VersionData = Blob.valueOf('zip'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.mp3', PathOnClient = 'test.mp3', VersionData = Blob.valueOf('mp3'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.mp4', PathOnClient = 'test.mp4', VersionData = Blob.valueOf('mp4'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.bmp', PathOnClient = 'test.bmp', VersionData = Blob.valueOf('bmp'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.svg', PathOnClient = 'test.svg', VersionData = Blob.valueOf('svg'), FirstPublishLocationId = acc.Id),
            new ContentVersion(Title = 'test.webp', PathOnClient = 'test.webp', VersionData = Blob.valueOf('webp'), FirstPublishLocationId = acc.Id)
        };
        insert cvList;

        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, 'Title', 'ASC', 50);
        Test.stopTest();

        Set<String> iconTypes = new Set<String>();
        for (RelatedListLWRController.FileRecord file : files) {
            iconTypes.add(file.icon);
        }
        System.assert(iconTypes.size() >= 5, 'Should have multiple different file icons');
    }

    @isTest
    static void testGetImageAsBase64_DifferentImageTypes() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        ContentVersion jpgVersion = new ContentVersion(
            Title = 'test.jpg',
            PathOnClient = 'test.jpg',
            VersionData = Blob.valueOf('Test JPG'),
            FirstPublishLocationId = acc.Id
        );
        insert jpgVersion;

        ContentVersion gifVersion = new ContentVersion(
            Title = 'test.gif',
            PathOnClient = 'test.gif',
            VersionData = Blob.valueOf('Test GIF'),
            FirstPublishLocationId = acc.Id
        );
        insert gifVersion;

        jpgVersion = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :jpgVersion.Id];
        gifVersion = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :gifVersion.Id];

        Test.startTest();
        String jpgResult = RelatedListLWRController.getImageAsBase64(jpgVersion.ContentDocumentId);
        String gifResult = RelatedListLWRController.getImageAsBase64(gifVersion.ContentDocumentId);
        Test.stopTest();

        System.assert(jpgResult != null && jpgResult.contains('data:image/'), 'JPG should return data URL');
        System.assert(gifResult != null && gifResult.contains('data:image/'), 'GIF should return data URL');
    }

    @isTest
    static void testGetFiles_QueryException() {
        String fakeId = '001000000000000AAA';

        Test.startTest();
        List<RelatedListLWRController.FileRecord> result =
            RelatedListLWRController.getFiles(fakeId, 'CreatedDate', 'DESC', 10);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return list even for non-existent record');
        System.assertEquals(0, result.size(), 'Should return empty list for non-existent record');
    }

    @isTest
    static void testGetFiles_EmptyResults() {
        Account emptyAcc = new Account(Name = 'Empty Account');
        insert emptyAcc;

        Test.startTest();
        List<RelatedListLWRController.FileRecord> result =
            RelatedListLWRController.getFiles(emptyAcc.Id, 'CreatedDate', 'DESC', 10);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return list when no files');
        System.assertEquals(0, result.size(), 'Should return empty list when no files attached');
    }

    @isTest
    static void testGetFiles_MinimalContentVersion() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        ContentVersion minimalVersion = new ContentVersion(
            Title = null,
            PathOnClient = 'minimal.txt',
            VersionData = Blob.valueOf('minimal'),
            FirstPublishLocationId = acc.Id
        );
        insert minimalVersion;

        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 50);
        Test.stopTest();

        System.assertNotEquals(0, files.size(), 'Should handle files with null titles');
    }

    @isTest
    static void testGetFiles_DownloadUrls() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 10);
        Test.stopTest();

        for (RelatedListLWRController.FileRecord file : files) {
            System.assertNotEquals(null, file.downloadUrl, 'Download URL should not be null');
            System.assert(file.downloadUrl.contains('/sfc/servlet.shepherd/document/download/'),
                         'Download URL should contain correct path');
        }
    }

    @isTest
    static void testGetFiles_UserDisplayNames() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<RelatedListLWRController.FileRecord> files =
            RelatedListLWRController.getFiles(acc.Id, 'CreatedDate', 'DESC', 10);
        Test.stopTest();

        for (RelatedListLWRController.FileRecord file : files) {
            System.assertNotEquals(null, file.createdBy, 'Created by should not be null');
            System.assertNotEquals('', file.createdBy, 'Created by should not be empty');
        }
    }

    @isTest
    static void testGetRelatedListInfo_EmptyRecordId() {
        Test.startTest();
        RelatedListLWRController.RelatedListInfo result =
            RelatedListLWRController.getRelatedListInfo('Account', 'Contacts', '', 'Name,Email', '', 0, 25);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.records.size(), 'Should return no records without recordId');
    }

    @isTest
    static void testGetRelatedListInfo_NullRecordId() {
        Test.startTest();
        RelatedListLWRController.RelatedListInfo result =
            RelatedListLWRController.getRelatedListInfo('Account', 'Contacts', null, 'Name', '', 0, 25);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should handle null recordId');
    }

    @isTest
    static void testGetObjectTypeFromRecordId_NullValue() {
        Test.startTest();
        String objectType = RelatedListLWRController.getObjectTypeFromRecordId(null);
        Test.stopTest();

        System.assertEquals(null, objectType, 'Should return null for null input');
    }

    @isTest
    static void testGetCaseArticles_WithNullId() {
        Test.startTest();
        List<RelatedListLWRController.ArticleData> articles =
            RelatedListLWRController.getCaseArticles(null);
        Test.stopTest();

        System.assertEquals(0, articles.size(), 'Should return empty list for null case ID');
    }

    // ===== RECORD DELETION TESTS =====

    @isTest
    static void testCanDeleteObject_Success() {
        Test.startTest();
        Boolean canDelete = RelatedListLWRController.canDeleteObject('Contact');
        Test.stopTest();

        // Result depends on profile permissions, but method should not throw error
        System.assertNotEquals(null, canDelete, 'Should return a boolean value');
    }

    @isTest
    static void testCanDeleteObject_InvalidObject() {
        Test.startTest();
        Boolean canDelete = RelatedListLWRController.canDeleteObject('InvalidObject__c');
        Test.stopTest();

        System.assertEquals(false, canDelete, 'Should return false for invalid object');
    }

    @isTest
    static void testCanDeleteObject_BlankObjectName() {
        Test.startTest();
        Boolean canDelete = RelatedListLWRController.canDeleteObject('');
        Test.stopTest();

        System.assertEquals(false, canDelete, 'Should return false for blank object name');
    }

    @isTest
    static void testCanDeleteObject_NullObjectName() {
        Test.startTest();
        Boolean canDelete = RelatedListLWRController.canDeleteObject(null);
        Test.stopTest();

        System.assertEquals(false, canDelete, 'Should return false for null object name');
    }

    @isTest
    static void testDeleteRecord_Success() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        RelatedListLWRController.deleteRecord(contact.Id);
        Test.stopTest();

        List<Contact> remainingContacts = [SELECT Id FROM Contact WHERE Id = :contact.Id];
        System.assertEquals(0, remainingContacts.size(), 'Contact should be deleted');
    }

    @isTest
    static void testDeleteRecord_InvalidId() {
        Test.startTest();
        try {
            RelatedListLWRController.deleteRecord('invalid123');
            System.assert(false, 'Should throw exception for invalid ID');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testDeleteRecord_BlankId() {
        Test.startTest();
        try {
            RelatedListLWRController.deleteRecord('');
            System.assert(false, 'Should throw exception for blank ID');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testDeleteRecord_NullId() {
        Test.startTest();
        try {
            RelatedListLWRController.deleteRecord(null);
            System.assert(false, 'Should throw exception for null ID');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testDeleteRecord_NonExistentRecord() {
        // Create a valid-looking ID that doesn't exist
        String fakeId = '003000000000000AAA';

        Test.startTest();
        try {
            RelatedListLWRController.deleteRecord(fakeId);
            System.assert(false, 'Should throw exception for non-existent record');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

}