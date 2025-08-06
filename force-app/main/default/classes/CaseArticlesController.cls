/**
 * CaseArticlesController - Apex controller for Case Articles LWC
 * Retrieves Knowledge articles associated with a case through CaseArticle relationships
 */
public with sharing class CaseArticlesController {
    
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
    public static List<ArticleData> getCaseArticles(String caseId) {
        List<ArticleData> articles = new List<ArticleData>();
        
        try {            
            // Validate input
            if (String.isBlank(caseId)) {
                return articles;
            }
            
            // Verify the case exists and user has access
            List<Case> cases = [SELECT Id FROM Case WHERE Id = :caseId LIMIT 1];
            if (cases.isEmpty()) {
                return articles;
            }
            
            // Get the Knowledge Article Version IDs from CaseArticle junction
            List<CaseArticle> caseArticles = [
                SELECT KnowledgeArticleVersionId 
                FROM CaseArticle 
                WHERE CaseId = :caseId
                AND KnowledgeArticleVersionId != NULL
            ];
                        
            if (caseArticles.isEmpty()) {
                return articles;
            }
            
            // Extract Knowledge Article Version IDs
            Set<Id> knowledgeArticleVersionIds = new Set<Id>();
            for (CaseArticle ca : caseArticles) {
                knowledgeArticleVersionIds.add(ca.KnowledgeArticleVersionId);
            }
                        
            // Query Knowledge articles with required fields
            // Note: Only published articles that the user has access to will be returned
            List<Knowledge__kav> knowledgeArticles = [
                SELECT Id, Title, UrlName, 
                       PublishStatus, VersionNumber
                FROM Knowledge__kav 
                WHERE Id IN :knowledgeArticleVersionIds
                AND PublishStatus = 'Online'
                ORDER BY LastModifiedDate DESC
            ];
                        
            // Convert to wrapper objects
            for (Knowledge__kav article : knowledgeArticles) {
                ArticleData articleData = new ArticleData(
                    article.Id,
                    article.Title,
                    article.UrlName
                );
                articles.add(articleData);
                            }
            
        } catch (Exception e) {
            System.debug('Error getting case articles: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            
            // Log the error but don't throw it to avoid breaking the UI
            // Instead, return empty list
            throw new AuraHandledException('Unable to load case articles: ' + e.getMessage());
        }
        
        return articles;
    }
    
    /**
     * Refresh case articles (for manual refresh functionality)
     * This method is not cacheable to force fresh data
     * @param caseId The case record ID
     * @return List of ArticleData objects representing the associated knowledge articles
     */
    @AuraEnabled(cacheable=false)
    public static List<ArticleData> refreshCaseArticles(String caseId) {
        return getCaseArticles(caseId);
    }
}