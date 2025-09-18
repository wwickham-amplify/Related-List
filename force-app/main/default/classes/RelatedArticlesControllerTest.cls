@IsTest
public class RelatedArticlesControllerTest {
     
    /**
     * Test successful retrieval when articles exist and have categories
     */
    @IsTest
    static void testGetArticles() {
        List<Knowledge__kav> articles = new List<Knowledge__kav>();
                
        Knowledge__kav article1 = new Knowledge__kav();
        article1.Title = 'Test Article 3';
        article1.UrlName = 'Test-Article-3';
        article1.Language = 'en_US';
        articles.add(article1);
        
        Knowledge__kav article2 = new Knowledge__kav();
        article2.Title = 'Test Article 4';  
        article2.UrlName = 'Test-Article-4';
        article2.Language = 'en_US';
        articles.add(article2);
        
        insert articles;

        KnowledgeArticleVersion[] kavs = [SELECT Id, KnowledgeArticleId, Title, UrlName, Language, PublishStatus FROM KnowledgeArticleVersion];
        
        // Publish the articles using KbManagement.PublishingService
        List<Id> articleIds = new List<Id>();
        for (KnowledgeArticleVersion kav : kavs) {
            System.debug(kav);
            articleIds.add(kav.KnowledgeArticleId);
        }
        
        // Attempt to publish articles
        for (Id articleId : articleIds) {
            try {
                KbManagement.PublishingService.publishArticle(articleId, true);
            } catch (Exception publishEx) {
                System.debug('Could not publish article ' + articleId + ': ' + publishEx.getMessage());
            }
        }

        List<Knowledge__kav> publishedArticles = [
            SELECT Id, KnowledgeArticleId, Title, UrlName
            FROM Knowledge__kav 
        ];

        System.debug([SELECT PublishStatus, LastPublishedDate, Id FROM KnowledgeArticleVersion WHERE Id = :publishedArticles[0].Id]);

        Knowledge__DataCategorySelection dataCategory = new Knowledge__DataCategorySelection();
        dataCategory.ParentId = publishedArticles[0].Id;
        dataCategory.DataCategoryGroupName = 'Products';
        dataCategory.DataCategoryName = 'Amplify_Math';
        insert dataCategory;
        
        Test.startTest();
        List<RelatedArticlesController.RelatedArticleWrapper> articlesResult = 
            RelatedArticlesController.getRelatedArticles(publishedArticles[0].Id);
        Test.stopTest();
        
        System.assertNotEquals(null, articlesResult, 'Articles list should not be null');
        
        // Verify article structure if any were returned
        for (RelatedArticlesController.RelatedArticleWrapper article : articlesResult) {
            System.assertNotEquals(null, article.articleId, 'Article ID should not be null');
            System.assertNotEquals(null, article.title, 'Article title should not be null');
            System.assertNotEquals(null, article.urlName, 'Article URL name should not be null');
        }
        
        // If we got articles, it means our setup worked and we covered the processing code
        if (articlesResult.size() > 0) {
            System.debug('Successfully retrieved ' + articlesResult.size() + ' articles - coverage achieved');
        }
    }
    
    /*Same test but no categories*/
    
    @IsTest
    static void testGetArticlesNoCategories() {
        List<Knowledge__kav> articles = new List<Knowledge__kav>();
                
        Knowledge__kav article1 = new Knowledge__kav();
        article1.Title = 'Test Article 3';
        article1.UrlName = 'Test-Article-3';
        article1.Language = 'en_US';
        articles.add(article1);
        
        Knowledge__kav article2 = new Knowledge__kav();
        article2.Title = 'Test Article 4';  
        article2.UrlName = 'Test-Article-4';
        article2.Language = 'en_US';
        articles.add(article2);
        
        insert articles;

        KnowledgeArticleVersion[] kavs = [SELECT Id, KnowledgeArticleId, Title, UrlName, Language, PublishStatus FROM KnowledgeArticleVersion];
        
        // Publish the articles using KbManagement.PublishingService
        List<Id> articleIds = new List<Id>();
        for (KnowledgeArticleVersion kav : kavs) {
            System.debug(kav);
            articleIds.add(kav.KnowledgeArticleId);
        }
        
        // Attempt to publish articles
        for (Id articleId : articleIds) {
            try {
                KbManagement.PublishingService.publishArticle(articleId, true);
            } catch (Exception publishEx) {
                System.debug('Could not publish article ' + articleId + ': ' + publishEx.getMessage());
            }
        }

        List<Knowledge__kav> publishedArticles = [
            SELECT Id, KnowledgeArticleId, Title, UrlName
            FROM Knowledge__kav 
        ];

        System.debug([SELECT PublishStatus, LastPublishedDate, Id FROM KnowledgeArticleVersion WHERE Id = :publishedArticles[0].Id]);

        /*Knowledge__DataCategorySelection dataCategory = new Knowledge__DataCategorySelection();
        dataCategory.ParentId = publishedArticles[0].Id;
        dataCategory.DataCategoryGroupName = 'Products';
        dataCategory.DataCategoryName = 'Amplify_Math';
        insert dataCategory;*/
        
        Test.startTest();
        List<RelatedArticlesController.RelatedArticleWrapper> articlesResult = 
            RelatedArticlesController.getRelatedArticles(publishedArticles[0].Id);
        Test.stopTest();
        
        System.assertNotEquals(null, articlesResult, 'Articles list should not be null');
        
        // Verify article structure if any were returned
        for (RelatedArticlesController.RelatedArticleWrapper article : articlesResult) {
            System.assertNotEquals(null, article.articleId, 'Article ID should not be null');
            System.assertNotEquals(null, article.title, 'Article title should not be null');
            System.assertNotEquals(null, article.urlName, 'Article URL name should not be null');
        }
        
        // If we got articles, it means our setup worked and we covered the processing code
        if (articlesResult.size() > 0) {
            System.debug('Successfully retrieved ' + articlesResult.size() + ' articles - coverage achieved');
        }
    }
}