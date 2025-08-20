public with sharing class RelatedArticlesController {
    
    /**
     * Wrapper class for Knowledge Article data
     */
    public class ArticleData {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String urlName { get; set; }
        
        public ArticleData() {}
        
        public ArticleData(String id, String title, String urlName) {
            this.id = id;
            this.title = title;
            this.urlName = urlName;
        }
    }
    
    /**
     * Get Knowledge articles associated with a case
     * @param caseId The case record ID
     * @return List of ArticleData objects representing the associated knowledge articles
     */
    @AuraEnabled(cacheable=true)
    public static List<ArticleData> getArticles(String recordId) {
        List<ArticleData> articles = new List<ArticleData>();
        
        try {            
            // Validate input
            if (String.isBlank(recordId)) {
                return articles;
            }
            
            Knowledge__DataCategorySelection dataCategory = [SELECT DataCategoryName, DataCategoryGroupName, ParentId FROM Knowledge__DataCategorySelection WHERE ParentId = :recordId LIMIT 1];

            String dataCategoryName = dataCategory.DataCategoryName;

            String dataCategoryGroupName = dataCategory.DataCategoryGroupName;
            
            String query = 'SELECT Id, Title, UrlName ' +
              'FROM KnowledgeArticleVersion ' +
              'WHERE Id != \'' + recordId + '\' ' +
              'AND LastPublishedDate >= LAST_N_MONTHS:18 ' +
              'WITH DATA CATEGORY ' + dataCategoryGroupName + '__c' + ' AT ' + dataCategoryName + '__c ' +
              'ORDER BY ArticleCaseAttachCount DESC, LastPublishedDate DESC LIMIT 6';

            List<KnowledgeArticleVersion> relatedArticles = Database.query(query);
                        
            if (relatedArticles.isEmpty()) {
                return articles;
            }
                        
            // Convert to wrapper objects
            for (KnowledgeArticleVersion article : relatedArticles) {
                ArticleData articleData = new ArticleData(
                    article.Id,
                    article.Title,
                    article.UrlName
                );
                articles.add(articleData);
            }
            
        } catch (Exception e) {
            System.debug('Error getting related articles: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            
            // Log the error but don't throw it to avoid breaking the UI
            // Instead, return empty list
            throw new AuraHandledException('Unable to load related articles: ' + e.getMessage());
        }
        
        return articles;
    }
}