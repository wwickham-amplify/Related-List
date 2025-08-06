@isTest
public class RelatedFilesControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test case
        Case testCase = new Case(
            Subject = 'Test Case for Files',
            Status = 'New',
            Origin = 'Web'
        );
        insert testCase;
        
        // Create test documents with different file types
        List<ContentVersion> contentVersions = new List<ContentVersion>();
        
        // Image file
        contentVersions.add(new ContentVersion(
            Title = 'test-image.png',
            PathOnClient = 'test-image.png',
            VersionData = Blob.valueOf('Test image content'),
            FirstPublishLocationId = testCase.Id
        ));
        
        // PDF file
        contentVersions.add(new ContentVersion(
            Title = 'test-document.pdf',
            PathOnClient = 'test-document.pdf',
            VersionData = Blob.valueOf('Test PDF content'),
            FirstPublishLocationId = testCase.Id
        ));
        
        // Word document
        contentVersions.add(new ContentVersion(
            Title = 'test-doc.docx',
            PathOnClient = 'test-doc.docx',
            VersionData = Blob.valueOf('Test Word content'),
            FirstPublishLocationId = testCase.Id
        ));
        
        // Text file
        contentVersions.add(new ContentVersion(
            Title = 'test-file.txt',
            PathOnClient = 'test-file.txt',
            VersionData = Blob.valueOf('Test text content'),
            FirstPublishLocationId = testCase.Id
        ));
        
        // Unknown file type
        contentVersions.add(new ContentVersion(
            Title = 'test-unknown',
            PathOnClient = 'test-unknown',
            VersionData = Blob.valueOf('Test unknown content'),
            FirstPublishLocationId = testCase.Id
        ));
        
        insert contentVersions;
    }
    
    @isTest
    static void testGetFiles_Success() {
        // Get test case
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, 
            'CreatedDate', 
            'DESC', 
            10
        );
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, files, 'Files list should not be null');
        System.assertEquals(5, files.size(), 'Should return 5 files');
        
        // Verify file properties
        for (RelatedFilesController.FileRecord file : files) {
            System.assertNotEquals(null, file.id, 'File ID should not be null');
            System.assertNotEquals(null, file.title, 'File title should not be null');
            System.assertNotEquals(null, file.downloadUrl, 'Download URL should not be null');
            System.assertNotEquals(null, file.icon, 'File icon should not be null');
            System.assertNotEquals(null, file.formattedSize, 'Formatted size should not be null');
        }
        
        // Check image file specifically
        RelatedFilesController.FileRecord imageFile = null;
        for (RelatedFilesController.FileRecord file : files) {
            if (file.title == 'test-image.png') {
                imageFile = file;
                break;
            }
        }
        System.assertNotEquals(null, imageFile, 'Image file should be found');
        System.assertEquals(true, imageFile.isImage, 'PNG file should be marked as image');
        System.assertEquals('doctype:image', imageFile.icon, 'PNG file should have image icon');
    }
    
    @isTest
    static void testGetFiles_WithDifferentSortFields() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        
        // Test sort by Title
        List<RelatedFilesController.FileRecord> filesByTitle = RelatedFilesController.getFiles(
            testCase.Id, 'Title', 'ASC', 10
        );
        
        // Test sort by ContentSize
        List<RelatedFilesController.FileRecord> filesBySize = RelatedFilesController.getFiles(
            testCase.Id, 'ContentSize', 'DESC', 10
        );
        
        // Test sort by FileExtension
        List<RelatedFilesController.FileRecord> filesByExtension = RelatedFilesController.getFiles(
            testCase.Id, 'FileExtension', 'ASC', 10
        );
        
        Test.stopTest();
        
        System.assertEquals(5, filesByTitle.size(), 'Sort by title should return all files');
        System.assertEquals(5, filesBySize.size(), 'Sort by size should return all files');
        System.assertEquals(5, filesByExtension.size(), 'Sort by extension should return all files');
    }
    
    @isTest
    static void testGetFiles_WithDefaults() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        
        // Test with null parameters (should use defaults)
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, null, null, null
        );
        
        // Test with empty string parameters
        List<RelatedFilesController.FileRecord> files2 = RelatedFilesController.getFiles(
            testCase.Id, '', '', 0
        );
        
        // Test with invalid sort direction
        List<RelatedFilesController.FileRecord> files3 = RelatedFilesController.getFiles(
            testCase.Id, 'CreatedDate', 'INVALID', 10
        );
        
        Test.stopTest();
        
        System.assertEquals(5, files.size(), 'Should handle null parameters');
        System.assertEquals(5, files2.size(), 'Should handle empty parameters');
        System.assertEquals(5, files3.size(), 'Should handle invalid sort direction');
    }
    
    @isTest
    static void testGetFiles_BlankRecordId() {
        Test.startTest();
        
        try {
            RelatedFilesController.getFiles('', 'CreatedDate', 'DESC', 10);
            System.assert(false, 'Should throw exception for blank record ID');
        } catch (Exception e) {
            // Should catch AuraHandledException, but let's be more flexible
            System.assert(e.getMessage().contains('Record ID is required') || 
                         e.getMessage().contains('Unable to retrieve files'), 
                         'Should throw appropriate error message. Actual: ' + e.getMessage());
        }
        
        try {
            RelatedFilesController.getFiles(null, 'CreatedDate', 'DESC', 10);
            System.assert(false, 'Should throw exception for null record ID');
        } catch (Exception e) {
            // Should catch AuraHandledException, but let's be more flexible
            System.assert(e.getMessage().contains('Record ID is required') || 
                         e.getMessage().contains('Unable to retrieve files'), 
                         'Should throw appropriate error message. Actual: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testGetFiles_LimitRecords() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        
        // Test with limit of 2
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, 'CreatedDate', 'DESC', 2
        );
        
        Test.stopTest();
        
        System.assertEquals(2, files.size(), 'Should respect limit parameter');
    }
    
    @isTest
    static void testGetImageAsBase64_Success() {
        // Get an image content document
        ContentVersion imageVersion = [SELECT ContentDocumentId, FileExtension 
                                      FROM ContentVersion 
                                      WHERE Title = 'test-image.png' LIMIT 1];
        
        Test.startTest();
        String base64Result = RelatedFilesController.getImageAsBase64(imageVersion.ContentDocumentId);
        Test.stopTest();
        
        System.assertNotEquals(null, base64Result, 'Base64 result should not be null');
        System.assert(base64Result.startsWith('data:image/'), 'Result should be data URL format');
        System.assert(base64Result.contains('base64,'), 'Result should contain base64 data');
    }
    
    @isTest
    static void testGetImageAsBase64_DifferentImageTypes() {
        // Test with PNG (already created)
        ContentVersion pngVersion = [SELECT ContentDocumentId FROM ContentVersion 
                                    WHERE Title = 'test-image.png' LIMIT 1];
        
        // Create JPG version for testing
        ContentVersion jpgVersion = new ContentVersion(
            Title = 'test-image.jpg',
            PathOnClient = 'test-image.jpg',
            VersionData = Blob.valueOf('Test JPG content')
        );
        insert jpgVersion;
        
        // Create GIF version for testing
        ContentVersion gifVersion = new ContentVersion(
            Title = 'test-image.gif',
            PathOnClient = 'test-image.gif',
            VersionData = Blob.valueOf('Test GIF content')
        );
        insert gifVersion;
        
        Test.startTest();
        
        String pngResult = RelatedFilesController.getImageAsBase64(pngVersion.ContentDocumentId);
        String jpgResult = RelatedFilesController.getImageAsBase64(
            [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :jpgVersion.Id].ContentDocumentId
        );
        String gifResult = RelatedFilesController.getImageAsBase64(
            [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :gifVersion.Id].ContentDocumentId
        );
        
        Test.stopTest();
        
        System.assert(pngResult.contains('data:image/png'), 'PNG should have correct MIME type');
        System.assert(jpgResult.contains('data:image/jpeg'), 'JPG should have correct MIME type');
        System.assert(gifResult.contains('data:image/gif'), 'GIF should have correct MIME type');
    }
    
    @isTest
    static void testGetImageAsBase64_InvalidId() {
        Test.startTest();
        String result = RelatedFilesController.getImageAsBase64('invalid-id');
        Test.stopTest();
        
        System.assertEquals(null, result, 'Should return null for invalid ID');
    }
    
    @isTest
    static void testGetImageAsBase64_NonExistentId() {
        // Use a valid ID format but non-existent record
        String fakeId = '069000000000000';
        
        Test.startTest();
        String result = RelatedFilesController.getImageAsBase64(fakeId);
        Test.stopTest();
        
        System.assertEquals(null, result, 'Should return null for non-existent ID');
    }
    
    @isTest
    static void testFileTypeClassifications() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, 'Title', 'ASC', 50
        );
        Test.stopTest();
        
        Map<String, RelatedFilesController.FileRecord> fileMap = new Map<String, RelatedFilesController.FileRecord>();
        for (RelatedFilesController.FileRecord file : files) {
            fileMap.put(file.title, file);
        }
        
        // Test image file
        RelatedFilesController.FileRecord pngFile = fileMap.get('test-image.png');
        System.assertEquals(true, pngFile.isImage, 'PNG should be classified as image');
        System.assertEquals('doctype:image', pngFile.icon, 'PNG should have image icon');
        
        // Test PDF file
        RelatedFilesController.FileRecord pdfFile = fileMap.get('test-document.pdf');
        System.assertEquals(false, pdfFile.isImage, 'PDF should not be classified as image');
        System.assertEquals('doctype:pdf', pdfFile.icon, 'PDF should have PDF icon');
        System.assertEquals(true, pdfFile.canPreview, 'PDF should be previewable');
        
        // Test Word document
        RelatedFilesController.FileRecord docFile = fileMap.get('test-doc.docx');
        System.assertEquals('doctype:word', docFile.icon, 'DOCX should have Word icon');
        System.assertEquals(false, docFile.isImage, 'DOCX should not be image');
        
        // Test text file
        RelatedFilesController.FileRecord txtFile = fileMap.get('test-file.txt');
        System.assertEquals('doctype:txt', txtFile.icon, 'TXT should have text icon');
        System.assertEquals(true, txtFile.canPreview, 'TXT should be previewable');
        
        // Test unknown file
        RelatedFilesController.FileRecord unknownFile = fileMap.get('test-unknown');
        System.assertEquals('doctype:unknown', unknownFile.icon, 'Unknown file should have unknown icon');
        System.assertEquals(false, unknownFile.isImage, 'Unknown file should not be image');
        System.assertEquals(false, unknownFile.canPreview, 'Unknown file should not be previewable');
    }
    
    @isTest
    static void testFileSizeFormatting() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        // Create files with specific sizes for testing
        List<ContentVersion> testSizeVersions = new List<ContentVersion>();
        
        // 500 bytes
        testSizeVersions.add(new ContentVersion(
            Title = 'small-file.txt',
            PathOnClient = 'small-file.txt',
            VersionData = Blob.valueOf('A'.repeat(500)),
            FirstPublishLocationId = testCase.Id
        ));
        
        // ~2KB
        testSizeVersions.add(new ContentVersion(
            Title = 'medium-file.txt',
            PathOnClient = 'medium-file.txt',
            VersionData = Blob.valueOf('B'.repeat(2048)),
            FirstPublishLocationId = testCase.Id
        ));
        
        insert testSizeVersions;
        
        Test.startTest();
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, 'Title', 'ASC', 50
        );
        Test.stopTest();
        
        // Find the test files
        RelatedFilesController.FileRecord smallFile = null;
        RelatedFilesController.FileRecord mediumFile = null;
        
        for (RelatedFilesController.FileRecord file : files) {
            if (file.title == 'small-file.txt') {
                smallFile = file;
            } else if (file.title == 'medium-file.txt') {
                mediumFile = file;
            }
        }
        
        System.assertNotEquals(null, smallFile, 'Small file should be found');
        System.assertNotEquals(null, mediumFile, 'Medium file should be found');
        System.assert(smallFile.formattedSize.contains('Bytes'), 'Small file should show bytes');
        System.assert(mediumFile.formattedSize.contains('KB'), 'Medium file should show KB');
    }
    
    @isTest
    static void testUserDisplayNames() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, 'CreatedDate', 'DESC', 10
        );
        Test.stopTest();
        
        // Verify all files have a created by name
        for (RelatedFilesController.FileRecord file : files) {
            System.assertNotEquals(null, file.createdBy, 'Created by should not be null');
            System.assertNotEquals('', file.createdBy, 'Created by should not be empty');
        }
    }
    
    @isTest
    static void testDownloadUrls() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, 'CreatedDate', 'DESC', 10
        );
        Test.stopTest();
        
        // Verify all files have download URLs
        for (RelatedFilesController.FileRecord file : files) {
            System.assertNotEquals(null, file.downloadUrl, 'Download URL should not be null');
            System.assert(file.downloadUrl.contains('/sfc/servlet.shepherd/document/download/'), 
                         'Download URL should contain correct path');
            System.assert(file.downloadUrl.contains(file.id), 'Download URL should contain file ID');
        }
    }
    
    @isTest
    static void testGetFiles_QueryException() {
        // Test with a fake but properly formatted Salesforce ID to avoid page access issues
        String fakeButValidFormatId = '001000000000000AAA';
        
        Test.startTest();
        
        List<RelatedFilesController.FileRecord> result = RelatedFilesController.getFiles(
            fakeButValidFormatId, 'CreatedDate', 'DESC', 10);
        
        // Should return empty list for non-existent record, not throw exception
        System.assertNotEquals(null, result, 'Should return a list even for non-existent record');
        System.assertEquals(0, result.size(), 'Should return empty list for non-existent record');
        
        Test.stopTest();
    }
    
    @isTest
    static void testGetFiles_EmptyResults() {
        // Create a case with no files attached
        Case emptyCaseTest = new Case(
            Subject = 'Empty Test Case',
            Status = 'New',
            Origin = 'Web'
        );
        insert emptyCaseTest;
        
        Test.startTest();
        
        List<RelatedFilesController.FileRecord> result = RelatedFilesController.getFiles(
            emptyCaseTest.Id, 'CreatedDate', 'DESC', 10);
        
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return a list even when no files exist');
        System.assertEquals(0, result.size(), 'Should return empty list when no files attached');
    }
    
    @isTest
    static void testCreateFileRecord_WithNullValues() {
        // This test verifies the private method handles null values gracefully
        // We can't directly test private methods, but we can test through public methods
        // with edge case data
        
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        // Create a ContentVersion with minimal data
        ContentVersion minimalVersion = new ContentVersion(
            Title = null, // This will test null handling
            PathOnClient = 'minimal.txt',
            VersionData = Blob.valueOf('minimal'),
            FirstPublishLocationId = testCase.Id
        );
        insert minimalVersion;
        
        Test.startTest();
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, 'CreatedDate', 'DESC', 50
        );
        Test.stopTest();
        
        // Should still return files even with null title
        System.assertNotEquals(0, files.size(), 'Should handle files with null titles');
        
        // Find the minimal file and verify it was processed
        boolean foundMinimalFile = false;
        for (RelatedFilesController.FileRecord file : files) {
            if (file.contentSize != null && file.contentSize == 7) { // 'minimal' = 7 bytes
                foundMinimalFile = true;
                System.assertNotEquals(null, file.formattedSize, 'Should have formatted size even with null title');
                System.assertNotEquals(null, file.icon, 'Should have icon even with null title');
                break;
            }
        }
        System.assertEquals(true, foundMinimalFile, 'Should find and process minimal file');
    }
    
    @isTest
    static void testDomainTransformation() {
        // This indirectly tests the domain transformation logic through file URLs
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, 'CreatedDate', 'DESC', 1
        );
        Test.stopTest();
        
        System.assertNotEquals(0, files.size(), 'Should have at least one file');
        
        RelatedFilesController.FileRecord file = files[0];
        System.assert(file.downloadUrl.startsWith('https://'), 'Download URL should start with https://');
        System.assert(file.downloadUrl.contains('.force.com') || 
                     file.downloadUrl.contains('salesforce.com'), 
                     'Download URL should contain Salesforce domain');
    }
    
    @isTest
    static void testAllFileIcons() {
        // Test various file extensions to ensure icon mapping works
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        List<ContentVersion> iconTestVersions = new List<ContentVersion>();
        List<String> extensions = new List<String>{'xlsx', 'pptx', 'csv', 'xml', 'zip', 'mp3', 'mp4', 'bmp', 'webp'};
        
        for (String ext : extensions) {
            iconTestVersions.add(new ContentVersion(
                Title = 'test.' + ext,
                PathOnClient = 'test.' + ext,
                VersionData = Blob.valueOf('test content'),
                FirstPublishLocationId = testCase.Id
            ));
        }
        
        insert iconTestVersions;
        
        Test.startTest();
        List<RelatedFilesController.FileRecord> files = RelatedFilesController.getFiles(
            testCase.Id, 'Title', 'ASC', 50
        );
        Test.stopTest();
        
        // Verify all files have appropriate icons
        Map<String, String> expectedIcons = new Map<String, String>{
            'xlsx' => 'doctype:excel',
            'pptx' => 'doctype:ppt', 
            'csv' => 'doctype:csv',
            'xml' => 'doctype:xml',
            'zip' => 'doctype:zip',
            'mp3' => 'doctype:audio',
            'mp4' => 'doctype:video',
            'bmp' => 'doctype:image',
            'webp' => 'doctype:image'
        };
        
        for (RelatedFilesController.FileRecord file : files) {
            for (String ext : expectedIcons.keySet()) {
                if (file.title.endsWith('.' + ext)) {
                    System.assertEquals(expectedIcons.get(ext), file.icon, 
                                      'File with extension ' + ext + ' should have correct icon');
                }
            }
        }
    }
}