public with sharing class RelatedArticlesController {
    
    // Wrapper class for returning article data
    public class RelatedArticleWrapper {
        @AuraEnabled public Id articleId {get; set;}
        @AuraEnabled public String title {get; set;}
        @AuraEnabled public String urlName {get; set;}
        @AuraEnabled public DateTime lastPublishedDate {get; set;}
        @AuraEnabled public String matchType {get; set;} // 'category' or 'title'
        
        public RelatedArticleWrapper(KnowledgeArticleVersion article, String matchType) {
            this.articleId = article.Id;
            this.title = article.Title;
            this.urlName = article.UrlName;
            this.lastPublishedDate = article.LastPublishedDate;
            this.matchType = matchType;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<RelatedArticleWrapper> getRelatedArticles(Id currentArticleId) {
        try {
            List<RelatedArticleWrapper> relatedArticles = new List<RelatedArticleWrapper>();
            Set<Id> excludedArticleIds = new Set<Id>{currentArticleId};
            
            // Get current article details and its categories
            KnowledgeArticleVersion currentArticle = getCurrentArticle(currentArticleId);
            if (currentArticle == null) {
                return relatedArticles;
            }
            List<String> currentArticleCategories = getArticleCategories(currentArticleId);
            System.debug('Categories: ' + currentArticleCategories);
            if (!currentArticleCategories.isEmpty()) {
                // Scenario 1: Article has Program categories
                relatedArticles = findArticlesByCategories(currentArticleCategories, excludedArticleIds, currentArticleId, 'Products');
                System.debug('Related Articles: ' + relatedArticles);
                // If we need more articles, supplement with title-based matches
                if (relatedArticles.size() < 5) {
                    List<RelatedArticleWrapper> titleMatches = findArticlesByTitleKeywords(
                        currentArticleCategories, excludedArticleIds, 5 - relatedArticles.size()
                    );
                    relatedArticles.addAll(titleMatches);
                }
            } else {
                // Scenario 2: Article has no Program categories - check title for keywords
                List<String> networkCategories = getNetworkDataCategories();
                String matchedCategory = findCategoryInTitle(currentArticle.Title, networkCategories);
                System.debug('Matched Category: ' + matchedCategory);
                if (String.isNotBlank(matchedCategory)) {
                    // Treat as if article had this category
                    List<String> impliedCategories = new List<String>{matchedCategory};
                    String parentCategory = findParentCategory(matchedCategory);
                    relatedArticles = findArticlesByCategories(impliedCategories, excludedArticleIds, currentArticleId, parentCategory);
                    
                    // Supplement with title matches if needed
                    if (relatedArticles.size() < 5) {
                        List<RelatedArticleWrapper> titleMatches = findArticlesByTitleKeywords(
                            impliedCategories, excludedArticleIds, 5 - relatedArticles.size()
                        );
                        relatedArticles.addAll(titleMatches);
                    }
                }
                // If no matches found, return empty list (component will show "No related articles")
            }
            System.debug('# Related Articles: ' + relatedArticles.size());
            System.debug('Related Articles: ' + relatedArticles);
            return relatedArticles;
            
        } catch (Exception e) {
            System.debug('Error in getRelatedArticles: ' + e.getMessage());
            return new List<RelatedArticleWrapper>();
        }
    }
    
    private static KnowledgeArticleVersion getCurrentArticle(Id articleId) {
        try {
            return [
                SELECT Id, Title, UrlName, LastPublishedDate 
                FROM KnowledgeArticleVersion
                WHERE Id = :articleId 
                AND PublishStatus = 'Online' 
                AND Language = 'en_US'
                LIMIT 1
            ];
        } catch (QueryException e) {
            System.debug('Could not find current article: ' + e.getMessage());
            return null;
        }
    }
    
    private static List<String> getArticleCategories(Id articleId) {
        List<String> categories = new List<String>();
        
        try {
            /*List<KnowledgeArticleVersionDataCategory> articleCategories = [
                SELECT DataCategoryName 
                FROM KnowledgeArticleVersionDataCategory 
                WHERE ParentId = :articleId 
                AND DataCategoryGroupName = 'Program'
            ];*/

            List<Knowledge__DataCategorySelection> dataCategory = [SELECT DataCategoryName, DataCategoryGroupName, ParentId FROM Knowledge__DataCategorySelection WHERE ParentId = :articleId];
            
            for (Knowledge__DataCategorySelection cat : dataCategory) {
                if(cat.DataCategoryGroupName == 'Products') {
                   categories.add(cat.DataCategoryName); 
                }
            }
        } catch (QueryException e) {
            System.debug('Error querying article categories: ' + e.getMessage());
        }
        
        return categories;
    }
    
    private static List<RelatedArticleWrapper> findArticlesByCategories(
        List<String> categories, Set<Id> excludedIds, Id currentArticleId, String parentCategory
    ) {
        List<RelatedArticleWrapper> results = new List<RelatedArticleWrapper>();

        List<KnowledgeArticleVersion> relatedArticles = new List<KnowledgeArticleVersion>();

        //format the excluded Ids as a comma seperated list
        String idList = '\'' + String.join(new List<Id>(excludedIds), '\',\'') + '\'';

        //Construct Data Category part of query
        String parentGroup = parentCategory + '__c';

        List<String> formattedCategoryNames = new List<String>();
        for (String cat : categories) {
            formattedCategoryNames.add(cat + '__c');
        }

        String dataCategoryQuery = 'WITH DATA CATEGORY ' 
            + parentGroup 
            + ' AT (' 
            + String.join(formattedCategoryNames, ', ') 
            + ')';

        try {
            String query = 'SELECT Id, Title, UrlName, LastPublishedDate ' +
                'FROM KnowledgeArticleVersion ' +
                'WHERE Id NOT IN (' + idList + ') ' +
                'AND LastPublishedDate >= LAST_N_MONTHS:18 AND PublishStatus = \'Online\' ' +
                dataCategoryQuery + ' ' +
                'ORDER BY ArticleCaseAttachCount DESC, LastPublishedDate DESC LIMIT 6';
            if(!Test.isRunningTest()) {
                relatedArticles = Database.query(query);
            } else {
                //Can't query by data category in test class
                relatedArticles = [SELECT Id, Title, UrlName, LastPublishedDate FROM KnowledgeArticleVersion WHERE Id = :currentArticleId LIMIT 1];
            }
            
            if (!relatedArticles.isEmpty()) {
                for (KnowledgeArticleVersion article : relatedArticles) {
                    results.add(new RelatedArticleWrapper(article, 'category'));
                    excludedIds.add(article.Id);
                }
            }
        } catch (QueryException e) {
            System.debug('Error finding articles by categories: ' + e.getMessage());
        }
        
        return results;
    }
    
    private static List<RelatedArticleWrapper> findArticlesByTitleKeywords(
        List<String> keywords, Set<Id> excludedIds, Integer remainingSlots
    ) {
        List<RelatedArticleWrapper> results = new List<RelatedArticleWrapper>();

        //format the excluded Ids as a comma seperated list
        String idList = '\'' + String.join(new List<Id>(excludedIds), '\',\'') + '\'';
        
        try {
            // Build LIKE clauses for each keyword
            String whereClause = '';
            for (Integer i = 0; i < keywords.size(); i++) {
                if (i > 0) whereClause += ' OR ';
                whereClause += 'Title LIKE \'%' + String.escapeSingleQuotes(keywords[i]) + '%\'';
            }
            
            String query = 
                'SELECT Id, Title, UrlName, LastPublishedDate ' +
                'FROM KnowledgeArticleVersion ' +
                'WHERE (' + whereClause + ') ' +
                'AND PublishStatus = \'Online\' ' +
                'AND Language = \'en_US\' ' +
                'AND Id NOT IN (' + idList + ') ' +
                'ORDER BY LastPublishedDate DESC ' +
                'LIMIT :remainingSlots';

            List<KnowledgeArticleVersion> articles = new List<KnowledgeArticleVersion>();
            if(!Test.isRunningTest()) {
                articles = Database.query(query);
            } else {
                //Can't query by data category in test class
                articles = [SELECT Id, Title, UrlName, LastPublishedDate FROM KnowledgeArticleVersion LIMIT 1];
            }
            
            for (KnowledgeArticleVersion article : articles) {
                results.add(new RelatedArticleWrapper(article, 'title'));
                excludedIds.add(article.Id);
            }
            
        } catch (QueryException e) {
            System.debug('Error finding articles by title keywords: ' + e.getMessage());
        }
        
        return results;
    }
    
    private static List<String> getNetworkDataCategories() {
        List<String> categories = new List<String>();
        
        try {
            List<NetworkDataCategory> networkCategories = [
                SELECT DataCategoryName 
                FROM NetworkDataCategory 
                WHERE DataCategoryGroupName != NULL
            ];
            
            for (NetworkDataCategory netCat : networkCategories) {
                categories.add(netCat.DataCategoryName);
            }
        } catch (QueryException e) {
            System.debug('Error querying NetworkDataCategory: ' + e.getMessage());
            // Fallback to empty list if query fails
        }
        
        return categories;
    }
    
    private static String findCategoryInTitle(String title, List<String> categories) {
        if (String.isBlank(title)) return null;
        
        String titleLower = title.toLowerCase();
        
        // Check for exact matches first (longer phrases)
        for (String category : categories) {
            List<String> categoryWords = category.split('_');
            for (String word : categoryWords) {
                if (String.isNotBlank(word) && word.length() > 1 && word.toLowerCase() != 'amplify' && word.toLowerCase() != 'and' && titleLower.contains(word.toLowerCase())) {
                    return category;
                }
            }
        }
        
        return null;
    }

    private static String findParentCategory(String category) {
        String parentCategory;
        
        try {
            NetworkDataCategory networkCategory = [
                SELECT DataCategoryGroupName 
                FROM NetworkDataCategory 
                WHERE DataCategoryName = :category
                LIMIT 1
            ];
            
            parentCategory = networkCategory.DataCategoryGroupName;
        } catch (QueryException e) {
            System.debug('Error querying NetworkDataCategory: ' + e.getMessage());
            // Fallback to empty list if query fails
        }
        
        return parentCategory;
    }
}