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
    
    @AuraEnabled(cacheable=true)
    public static List<ArticleData> getArticles(String recordId) {
        List<ArticleData> articles = new List<ArticleData>();
        
        try {            
            // Validate input
            if (String.isBlank(recordId)) {
                return articles;
            }
            
            List<Knowledge__DataCategorySelection> dataCategories = [SELECT DataCategoryName, DataCategoryGroupName, ParentId FROM Knowledge__DataCategorySelection WHERE ParentId = :recordId];

            List<Knowledge__DataCategorySelection> filteredCategories = new List<Knowledge__DataCategorySelection>();

            for(Knowledge__DataCategorySelection category : dataCategories) {
                if(category.DataCategoryGroupName != 'Audience') {
                    filteredCategories.add(category);
                }
            }

            String dataCategoryName = filteredCategories[0].DataCategoryName;

            String dataCategoryGroupName = filteredCategories[0].DataCategoryGroupName;
            
            String query = 'SELECT Id, Title, UrlName ' +
                'FROM KnowledgeArticleVersion ' +
                'WHERE Id != \'' + recordId + '\' ' +
                'AND LastPublishedDate >= LAST_N_MONTHS:18 AND PublishStatus = \'Online\' ' +
                'WITH DATA CATEGORY ' + dataCategoryGroupName + '__c' + ' AT ' + dataCategoryName + '__c ' +
                'ORDER BY ArticleCaseAttachCount DESC, LastPublishedDate DESC LIMIT 6';

            List<KnowledgeArticleVersion> relatedArticles;
            if(!Test.isRunningTest()) {
                relatedArticles = Database.query(query);
            } else {
                //Can't query by data category in test class
                relatedArticles = [SELECT Id, Title, UrlName FROM KnowledgeArticleVersion WHERE Id = :recordId LIMIT 1];
            }
                        
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