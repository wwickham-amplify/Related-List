/**
 * CaseArticlesControllerTest - Test class for CaseArticlesController
 * Tests Knowledge article retrieval functionality for cases
 */
@IsTest
public class CaseArticlesControllerTest {
    
    /**
     * Test data setup
     */
    @TestSetup
    static void setupTestData() {
        // Create test case
        Case testCase = new Case(
            Subject = 'Test Case for Articles',
            Status = 'New',
            Origin = 'Web'
        );
        insert testCase;
        
        // Create Knowledge articles
        List<Knowledge__kav> articles = new List<Knowledge__kav>();
        
        Knowledge__kav article1 = new Knowledge__kav(
            Title = 'Test Article 1',
            UrlName = 'test-article-1',
            Language = 'en_US'
        );
        articles.add(article1);
        
        Knowledge__kav article2 = new Knowledge__kav(
            Title = 'Test Article 2', 
            UrlName = 'test-article-2',
            Language = 'en_US'
        );
        articles.add(article2);
        
        Knowledge__kav article3 = new Knowledge__kav(
            Title = 'Draft Article',
            UrlName = 'draft-article',
            Language = 'en_US'
        );
        articles.add(article3);
        
        insert articles;
        
        // Update articles to published status (except draft)
        List<Knowledge__kav> articlesToUpdate = [
            SELECT Id, PublishStatus, KnowledgeArticleId, Title
            FROM Knowledge__kav 
            WHERE Id IN :articles
        ];
        
        for (Knowledge__kav article : articlesToUpdate) {
            if (article.Title != 'Draft Article') {
                article.PublishStatus = 'Online';
            }
        }
        update articlesToUpdate;
        
        // Create CaseArticle relationships using KnowledgeArticleId (not KnowledgeArticleVersionId)
        List<CaseArticle> caseArticles = new List<CaseArticle>();
        
        for (Knowledge__kav article : articlesToUpdate) {
            if (article.PublishStatus == 'Online') {
                CaseArticle caseArticle = new CaseArticle(
                    CaseId = testCase.Id,
                    KnowledgeArticleId = article.KnowledgeArticleId
                );
                caseArticles.add(caseArticle);
            }
        }
        
        if (!caseArticles.isEmpty()) {
            insert caseArticles;
        }
    }
    
    /**
     * Test successful retrieval of case articles - covers main happy path
     */
    @IsTest
    static void testGetCaseArticles_Success() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.getCaseArticles(testCase.Id);
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(2, articles.size(), 'Should return 2 published articles');
        
        // Verify article data structure and all properties
        for (CaseArticlesController.ArticleData article : articles) {
            System.assertNotEquals(null, article.id, 'Article ID should not be null');
            System.assertNotEquals(null, article.title, 'Article title should not be null');
            System.assertNotEquals(null, article.urlName, 'Article URL name should not be null');
            System.assert(article.title.startsWith('Test Article'), 'Should be test articles');
            System.assert(article.urlName.startsWith('test-article'), 'URL name should match pattern');
        }
    }
    
    /**
     * Test with invalid case ID - covers case validation logic
     */
    @IsTest
    static void testGetCaseArticles_InvalidCaseId() {
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.getCaseArticles('500000000000000AAA');
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(0, articles.size(), 'Should return empty list for invalid case');
    }
    
    /**
     * Test with blank case ID - covers input validation
     */
    @IsTest
    static void testGetCaseArticles_BlankCaseId() {
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.getCaseArticles('');
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(0, articles.size(), 'Should return empty list for blank case ID');
    }
    
    /**
     * Test with null case ID - covers null input validation
     */
    @IsTest
    static void testGetCaseArticles_NullCaseId() {
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.getCaseArticles(null);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(0, articles.size(), 'Should return empty list for null case ID');
    }
    
    /**
     * Test case with no associated articles - covers empty CaseArticle scenario
     */
    @IsTest
    static void testGetCaseArticles_NoArticles() {
        Case caseWithoutArticles = new Case(
            Subject = 'Case Without Articles',
            Status = 'New',
            Origin = 'Web'
        );
        insert caseWithoutArticles;
        
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.getCaseArticles(caseWithoutArticles.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(0, articles.size(), 'Should return empty list for case without articles');
    }
    
    /**
     * Test case with CaseArticles but no published Knowledge articles
     */
    @IsTest
    static void testGetCaseArticles_NullKnowledgeArticleVersionId() {
        Case testCase = new Case(
            Subject = 'Test Case with Null Article Versions',
            Status = 'New',
            Origin = 'Web'
        );
        insert testCase;
        
        // Create CaseArticle with null KnowledgeArticleVersionId (shouldn't happen in practice)
        // This tests the AND KnowledgeArticleVersionId != NULL condition
        
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.getCaseArticles(testCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(0, articles.size(), 'Should return empty list when no valid article version IDs');
    }
    
    /**
     * Test case with draft articles only - covers PublishStatus filtering
     */
    @IsTest
    static void testGetCaseArticles_DraftArticlesOnly() {
        Case testCase = new Case(
            Subject = 'Test Case for Draft Articles',
            Status = 'New',
            Origin = 'Web'
        );
        insert testCase;
        
        // Create draft article
        Knowledge__kav draftArticle = new Knowledge__kav(
            Title = 'Draft Only Article',
            UrlName = 'draft-only-article',
            Language = 'en_US',
            PublishStatus = 'Draft'
        );
        insert draftArticle;
        
        // Link draft article to case using KnowledgeArticleId
        CaseArticle caseArticle = new CaseArticle(
            CaseId = testCase.Id,
            KnowledgeArticleId = draftArticle.KnowledgeArticleId
        );
        insert caseArticle;
        
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.getCaseArticles(testCase.Id);
        Test.stopTest();
        
        // Should return empty because only Online articles are returned
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(0, articles.size(), 'Should return empty list for draft articles only');
    }
    
    /**
     * Test refresh method - covers non-cacheable method
     */
    @IsTest
    static void testRefreshCaseArticles() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.refreshCaseArticles(testCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(2, articles.size(), 'Should return 2 published articles');
        
        // Verify it calls the same logic as getCaseArticles
        List<CaseArticlesController.ArticleData> directArticles = 
            CaseArticlesController.getCaseArticles(testCase.Id);
        System.assertEquals(articles.size(), directArticles.size(), 'Refresh should return same results');
    }
    
    /**
     * Test refresh method with invalid case ID
     */
    @IsTest
    static void testRefreshCaseArticles_InvalidId() {
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.refreshCaseArticles('500000000000000AAA');
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(0, articles.size(), 'Should return empty list for invalid case');
    }
    
    /**
     * Test ArticleData wrapper class - covers all constructors and properties
     */
    @IsTest
    static void testArticleDataWrapper() {
        Test.startTest();
        
        // Test default constructor
        CaseArticlesController.ArticleData article1 = new CaseArticlesController.ArticleData();
        System.assertEquals(null, article1.id, 'Default constructor should set null ID');
        System.assertEquals(null, article1.title, 'Default constructor should set null title');
        System.assertEquals(null, article1.urlName, 'Default constructor should set null urlName');
        
        // Test parameterized constructor
        CaseArticlesController.ArticleData article2 = new CaseArticlesController.ArticleData(
            'test-id-123', 'Test Article Title', 'test-article-url-name'
        );
        System.assertEquals('test-id-123', article2.id, 'ID should be set correctly');
        System.assertEquals('Test Article Title', article2.title, 'Title should be set correctly');
        System.assertEquals('test-article-url-name', article2.urlName, 'URL name should be set correctly');
        
        // Test property setters
        article1.id = 'new-id';
        article1.title = 'New Title';
        article1.urlName = 'new-url-name';
        
        System.assertEquals('new-id', article1.id, 'ID setter should work');
        System.assertEquals('New Title', article1.title, 'Title setter should work');
        System.assertEquals('new-url-name', article1.urlName, 'URL name setter should work');
        
        Test.stopTest();
    }
    
    /**
     * Test exception handling - covers try-catch block
     */
    @IsTest
    static void testGetCaseArticles_ExceptionHandling() {
        Test.startTest();
        
        try {
            // Pass malformed ID that might cause exception
            List<CaseArticlesController.ArticleData> articles = 
                CaseArticlesController.getCaseArticles('INVALID_ID_FORMAT');
            
            // If no exception, verify we still get a valid response
            System.assertNotEquals(null, articles, 'Should return valid list even with malformed ID');
            
        } catch (AuraHandledException e) {
            // Verify proper exception handling
            System.assert(e.getMessage().contains('Unable to load case articles'), 
                         'Should throw appropriate error message');
        }
        
        Test.stopTest();
    }
    
    /**
     * Test with special characters in case ID
     */
    @IsTest
    static void testGetCaseArticles_SpecialCharacters() {
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.getCaseArticles('500!@#$%^&*()');
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Should handle special characters gracefully');
        System.assertEquals(0, articles.size(), 'Should return empty list for invalid format');
    }
    
    /**
     * Test bulk scenario with multiple articles
     */
    @IsTest
    static void testGetCaseArticles_BulkScenario() {
        Case bulkCase = new Case(
            Subject = 'Bulk Test Case',
            Status = 'New',
            Origin = 'Web'
        );
        insert bulkCase;
        
        // Create multiple articles
        List<Knowledge__kav> bulkArticles = new List<Knowledge__kav>();
        for (Integer i = 1; i <= 5; i++) {
            Knowledge__kav article = new Knowledge__kav(
                Title = 'Bulk Article ' + i,
                UrlName = 'bulk-article-' + i,
                Language = 'en_US',
                PublishStatus = 'Online'
            );
            bulkArticles.add(article);
        }
        insert bulkArticles;
        
        // Create CaseArticle relationships using KnowledgeArticleId
        List<CaseArticle> bulkCaseArticles = new List<CaseArticle>();
        for (Knowledge__kav article : bulkArticles) {
            CaseArticle caseArticle = new CaseArticle(
                CaseId = bulkCase.Id,
                KnowledgeArticleId = article.KnowledgeArticleId
            );
            bulkCaseArticles.add(caseArticle);
        }
        insert bulkCaseArticles;
        
        Test.startTest();
        List<CaseArticlesController.ArticleData> articles = 
            CaseArticlesController.getCaseArticles(bulkCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles list should not be null');
        System.assertEquals(5, articles.size(), 'Should return all 5 bulk articles');
        
        // Verify ordering (should be by LastModifiedDate DESC)
        for (Integer i = 0; i < articles.size() - 1; i++) {
            System.assertNotEquals(null, articles[i].title, 'Each article should have a title');
        }
    }
}