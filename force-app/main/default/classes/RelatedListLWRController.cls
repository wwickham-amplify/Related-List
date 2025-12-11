public with sharing class RelatedListLWRController {
    
    // ===== ARL (RELATED LIST API) METHODS =====
    
    @AuraEnabled(cacheable=true)
    public static String getObjectTypeFromRecordId(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                return null;
            }
            
            // Get the object type from the record ID
            Id recordIdObj = Id.valueOf(recordId);
            Schema.SObjectType objectType = recordIdObj.getSObjectType();
            String objectApiName = objectType.getDescribe().getName();
            
            System.debug('RelatedListLWR: Detected object type: ' + objectApiName + ' from recordId: ' + recordId);
            return objectApiName;
            
        } catch (Exception e) {
            System.debug('RelatedListLWR: Error getting object type from recordId: ' + e.getMessage());
            return null;
        }
    }
    
    @AuraEnabled(cacheable=false)
    public static RelatedListInfo getRelatedListInfo(String objectApiName, String relatedListName, String recordId, String enabledFields, String relationshipField, Integer offsetParam, Integer limitParam) {
        try {
            System.debug('RelatedListLWR: Starting getRelatedListInfo with: objectApiName=' + objectApiName + ', relatedListName=' + relatedListName + ', recordId=' + recordId + ', relationshipField=' + relationshipField + ', offset=' + offsetParam + ', limit=' + limitParam);

            RelatedListInfo result = new RelatedListInfo();
            result.fields = new List<FieldInfo>();
            result.records = new List<sObject>();
            result.hasMoreRecords = false;

            // Enhanced relationship finding for custom objects
            RelationshipMapping relationshipInfo = findRelatedListMapping(objectApiName, relatedListName, relationshipField);
            System.debug('RelatedListLWR: Found relationship mapping: ' + relationshipInfo);

            if (relationshipInfo == null) {
                System.debug('RelatedListLWR: No relationship mapping found for: ' + relatedListName);
                result.relationshipName = relatedListName;
                return result;
            }

            // Set the relationship info
            result.relationshipName = relationshipInfo.relationshipName;
            result.relatedObjectType = relationshipInfo.childObjectType;

            System.debug('RelatedListLWR: Using relationship: ' + result.relationshipName + ' -> ' + result.relatedObjectType);

            // Get field information
            if (String.isNotBlank(result.relatedObjectType)) {
                result.fields = getRelatedListFields(result.relatedObjectType, enabledFields);
                System.debug('RelatedListLWR: Found ' + result.fields.size() + ' fields');

                // Get actual related records if we have a record ID
                if (String.isNotBlank(recordId)) {
                    result.records = getRelatedRecords(objectApiName, relationshipInfo, recordId, result.fields, offsetParam, limitParam);
                    System.debug('RelatedListLWR: Found ' + result.records.size() + ' records');

                    // Check if there are more records by querying one extra
                    Integer actualLimit = limitParam != null ? limitParam : 50;
                    System.debug('RelatedListLWR: actualLimit=' + actualLimit + ', recordsReturned=' + result.records.size());
                    result.hasMoreRecords = result.records.size() > actualLimit;
                    System.debug('RelatedListLWR: hasMoreRecords calculated as: ' + result.hasMoreRecords + ' (because ' + result.records.size() + ' > ' + actualLimit + ')');

                    // If we got more records than requested, trim to the exact limit
                    if (result.hasMoreRecords) {
                        System.debug('RelatedListLWR: Trimming from ' + result.records.size() + ' to ' + actualLimit + ' records');
                        List<sObject> trimmedRecords = new List<sObject>();
                        for (Integer i = 0; i < actualLimit; i++) {
                            trimmedRecords.add(result.records[i]);
                        }
                        result.records = trimmedRecords;
                        System.debug('RelatedListLWR: After trim: ' + result.records.size() + ' records');
                    }
                }
            }

            System.debug('RelatedListLWR: Final result: fields=' + result.fields.size() + ', records=' + result.records.size() + ', hasMore=' + result.hasMoreRecords);
            return result;

        } catch (Exception e) {
            System.debug('RelatedListLWR: Error in getRelatedListInfo: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving related list info: ' + e.getMessage());
        }
    }

    // ===== ARL-SPECIFIC METHODS =====

    private static RelationshipMapping findRelatedListMapping(String parentObjectType, String searchName, String relationshipField) {
        System.debug('RelatedListLWR: Finding relationship mapping for: ' + parentObjectType + ' -> ' + searchName + ' with relationshipField: ' + relationshipField);
        
        if (String.isBlank(searchName)) {
            return null;
        }
        
        try {
            Schema.SObjectType parentType = Schema.getGlobalDescribe().get(parentObjectType);
            if (parentType == null) {
                System.debug('RelatedListLWR: Parent object type not found: ' + parentObjectType);
                return null;
            }
            
            Schema.DescribeSObjectResult parentDescribe = parentType.getDescribe();
            List<Schema.ChildRelationship> childRelationships = parentDescribe.getChildRelationships();
            
            System.debug('RelatedListLWR: Found ' + childRelationships.size() + ' child relationships for ' + parentObjectType);
            
            // Priority Strategy: If relationshipField is specified, use it to find the exact relationship
            if (String.isNotBlank(relationshipField)) {
                System.debug('RelatedListLWR: Using specified relationship field: ' + relationshipField);
                for (Schema.ChildRelationship relationship : childRelationships) {
                    String fieldName = relationship.getField().getDescribe().getName();
                    if (fieldName.equalsIgnoreCase(relationshipField)) {
                        System.debug('RelatedListLWR: Found exact match for relationship field: ' + relationshipField + ' -> ' + relationship.getChildSObject().getDescribe().getName());
                        return createRelationshipMapping(relationship);
                    }
                }
                System.debug('RelatedListLWR: Specified relationship field not found: ' + relationshipField);
            }
            
            // Strategy 1: Exact match on relationship name (API name)
            for (Schema.ChildRelationship relationship : childRelationships) {
                if (relationship.getRelationshipName() == searchName) {
                    return createRelationshipMapping(relationship);
                }
            }
            
            // Strategy 2: Case-insensitive match on relationship name
            String searchNameLower = searchName.toLowerCase();
            for (Schema.ChildRelationship relationship : childRelationships) {
                if (relationship.getRelationshipName() != null && 
                    relationship.getRelationshipName().toLowerCase() == searchNameLower) {
                    return createRelationshipMapping(relationship);
                }
            }
            
            // Strategy 3: Match based on child object label/name patterns
            for (Schema.ChildRelationship relationship : childRelationships) {
                String childObjectName = relationship.getChildSObject().getDescribe().getName();
                String childObjectLabel = relationship.getChildSObject().getDescribe().getLabel();
                String childObjectLabelPlural = relationship.getChildSObject().getDescribe().getLabelPlural();
                
                // Check if searchName matches any of the child object identifiers
                if (searchName.equalsIgnoreCase(childObjectLabel) || 
                    searchName.equalsIgnoreCase(childObjectLabelPlural) ||
                    searchName.equalsIgnoreCase(childObjectName)) {
                    System.debug('RelatedListLWR: Found match by object label/name: ' + searchName + ' -> ' + childObjectName);
                    return createRelationshipMapping(relationship);
                }
            }
            
            System.debug('RelatedListLWR: Could not find relationship for: ' + searchName + ' on object: ' + parentObjectType);
            
        } catch (Exception e) {
            System.debug('RelatedListLWR: Error finding related list mapping: ' + e.getMessage());
        }
        
        return null;
    }
    
    private static RelationshipMapping createRelationshipMapping(Schema.ChildRelationship relationship) {
        RelationshipMapping mapping = new RelationshipMapping();
        mapping.relationshipName = relationship.getRelationshipName();
        mapping.childObjectType = relationship.getChildSObject().getDescribe().getName();
        mapping.relationshipField = relationship.getField().getDescribe().getName();
        return mapping;
    }
    
    private static List<sObject> getRelatedRecords(String parentObjectType, RelationshipMapping relationshipInfo, String recordId, List<FieldInfo> fields, Integer offsetParam, Integer limitParam) {
        List<sObject> records = new List<sObject>();

        try {
            if (String.isBlank(recordId) || fields.isEmpty()) {
                System.debug('RelatedListLWR: Missing recordId or fields for query');
                return records;
            }

            // Build field list for query, handling both direct and relationship fields
            Set<String> fieldNames = new Set<String>();
            fieldNames.add('Id'); // Always include Id

            for (FieldInfo field : fields) {
                fieldNames.add(field.apiName);
            }

            // Always include CreatedDate for sorting if the object has it (even if not displayed)
            // Check if the object type has a CreatedDate field
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(relationshipInfo.childObjectType);
            if (sObjectType != null) {
                Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
                if (fieldMap.containsKey('CreatedDate')) {
                    fieldNames.add('CreatedDate');
                    System.debug('RelatedListLWR: Added CreatedDate field for sorting');
                }
            }

            // Set default pagination parameters
            Integer offset = offsetParam != null ? offsetParam : 0;
            Integer limitCount = limitParam != null ? limitParam : 50;

            // Build the SOQL query using the relationship field
            // SECURITY NOTE: This string concatenation is SAFE because:
            // 1. fieldNames come from Schema.DescribeSObjectResult (validated by Salesforce)
            // 2. childObjectType comes from Schema.ChildRelationship (Salesforce metadata)
            // 3. relationshipField comes from Schema.ChildRelationship (Salesforce metadata)
            // 4. recordId uses bind variable (:recordId) for injection protection
            // 5. offset and limitCount are validated integers
            String soqlQuery = 'SELECT ' + String.join(new List<String>(fieldNames), ', ') +
                              ' FROM ' + relationshipInfo.childObjectType +
                              ' WHERE ' + relationshipInfo.relationshipField + ' = :recordId';

            // Add ORDER BY for consistent results - prioritize CreatedDate DESC over Name
            if (fieldNames.contains('CreatedDate')) {
                soqlQuery += ' ORDER BY CreatedDate DESC';
            } else if (fieldNames.contains('Name')) {
                soqlQuery += ' ORDER BY Name';
            }

            // Add pagination - query for one extra record to detect if there are more
            soqlQuery += ' LIMIT ' + (limitCount + 1);
            if (offset > 0) {
                soqlQuery += ' OFFSET ' + offset;
            }

            System.debug('RelatedListLWR: Executing SOQL with pagination: ' + soqlQuery);
            records = Database.query(soqlQuery);
            System.debug('RelatedListLWR: Query returned ' + records.size() + ' records');

            // Enforce field-level security - remove fields user doesn't have access to
            if (!records.isEmpty()) {
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.READABLE,
                    records
                );
                records = decision.getRecords();

                // Log if any fields were removed
                if (!decision.getRemovedFields().isEmpty()) {
                    System.debug('RelatedListLWR: Removed inaccessible fields: ' + decision.getRemovedFields());
                }
            }

        } catch (Exception e) {
            System.debug('RelatedListLWR: Error querying related records: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return records;
    }
    
    private static List<FieldInfo> getRelatedListFields(String objectType, String enabledFields) {
        List<FieldInfo> fields = new List<FieldInfo>();
        
        try {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectType);
            if (sObjectType == null) {
                System.debug('RelatedListLWR: Could not find object type: ' + objectType);
                return fields;
            }
            
            Schema.DescribeSObjectResult describe = sObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
            
            List<String> fieldsToShow = new List<String>();
            
            // If enabledFields is specified, use those fields
            if (String.isNotBlank(enabledFields)) {
                List<String> enabledList = enabledFields.split(',');
                for (String fieldName : enabledList) {
                    String trimmed = fieldName.trim();
                    if (String.isNotBlank(trimmed)) {
                        fieldsToShow.add(trimmed);
                    }
                }
            } else {
                // Otherwise, use common fields for the object type
                fieldsToShow = getCommonDisplayFields(objectType);
            }
            
            // Process each field
            for (String fieldName : fieldsToShow) {
                FieldInfo fieldInfo = processField(fieldName, fieldMap);
                if (fieldInfo != null) {
                    fields.add(fieldInfo);
                    System.debug('RelatedListLWR: Added field: ' + fieldInfo.apiName + ' (' + fieldInfo.label + ')');
                }
            }
            
        } catch (Exception e) {
            System.debug('RelatedListLWR: Error getting related list fields: ' + e.getMessage());
        }
        
        return fields;
    }
    
    private static List<String> getCommonDisplayFields(String objectType) {
        // Return common fields that are typically displayed in related lists
        Map<String, List<String>> commonFieldsByObject = new Map<String, List<String>>{
            'Contact' => new List<String>{'Name', 'Email', 'Phone', 'Title'},
            'Opportunity' => new List<String>{'Name', 'Amount', 'CloseDate', 'StageName'},
            'Case' => new List<String>{'CaseNumber', 'Subject', 'Status', 'Priority'},
            'Task' => new List<String>{'Subject', 'Status', 'Priority', 'ActivityDate'},
            'Event' => new List<String>{'Subject', 'ActivityDate', 'StartDateTime', 'EndDateTime'},
            'Lead' => new List<String>{'Name', 'Company', 'Email', 'Phone', 'Status'},
            'Account' => new List<String>{'Name', 'Type', 'Phone', 'Website'}
        };
        
        if (commonFieldsByObject.containsKey(objectType)) {
            return commonFieldsByObject.get(objectType);
        }
        
        // Default fields for any object (including custom objects)
        return new List<String>{'Name', 'CreatedDate', 'LastModifiedDate'};
    }

    // ===== FIELD PROCESSING METHODS =====

    private static FieldInfo processField(String fieldName, Map<String, Schema.SObjectField> fieldMap) {
        try {
            // Handle relationship fields (e.g., Account.Name)
            if (fieldName.contains('.')) {
                return processRelationshipField(fieldName, fieldMap);
            } else {
                return processDirectField(fieldName, fieldMap);
            }
        } catch (Exception e) {
            System.debug('RelatedListLWR: Error processing field ' + fieldName + ': ' + e.getMessage());
            return null;
        }
    }
    
    private static FieldInfo processDirectField(String fieldName, Map<String, Schema.SObjectField> fieldMap) {
        Schema.SObjectField field = findField(fieldMap, fieldName);
        if (field != null) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.isAccessible()) {
                FieldInfo fieldInfo = new FieldInfo();
                fieldInfo.apiName = fieldDescribe.getName();
                fieldInfo.label = fieldDescribe.getLabel();
                fieldInfo.type = String.valueOf(fieldDescribe.getType());
                return fieldInfo;
            }
        }
        return null;
    }
    
    private static FieldInfo processRelationshipField(String fieldName, Map<String, Schema.SObjectField> fieldMap) {
        List<String> parts = fieldName.split('\\.');
        if (parts.size() != 2) {
            return null;
        }
        
        String relationshipName = parts[0]; // e.g., "Account"
        String targetFieldName = parts[1];  // e.g., "Name"
        
        // For standard relationships, the field name is typically the relationship name + "Id"
        String lookupFieldName = relationshipName + 'Id'; // e.g., "AccountId"
        
        // If it's a custom relationship, try the __r to __c conversion
        if (relationshipName.endsWith('__r')) {
            lookupFieldName = relationshipName.substring(0, relationshipName.length() - 3) + '__c';
        }
        
        Schema.SObjectField lookupField = findField(fieldMap, lookupFieldName);
        if (lookupField == null) {
            return null;
        }
        
        Schema.DescribeFieldResult lookupFieldDescribe = lookupField.getDescribe();
        if (!lookupFieldDescribe.isAccessible() || lookupFieldDescribe.getType() != Schema.DisplayType.REFERENCE) {
            return null;
        }
        
        // Get the target object type from the lookup field
        List<Schema.sObjectType> referenceTo = lookupFieldDescribe.getReferenceTo();
        if (referenceTo.isEmpty()) {
            return null;
        }
        
        Schema.sObjectType targetObjectType = referenceTo[0];
        Schema.DescribeSObjectResult targetDescribe = targetObjectType.getDescribe();
        Map<String, Schema.SObjectField> targetFieldMap = targetDescribe.fields.getMap();
        
        // Find the target field on the related object
        Schema.SObjectField targetField = findField(targetFieldMap, targetFieldName);
        if (targetField == null) {
            return null;
        }
        
        Schema.DescribeFieldResult targetFieldDescribe = targetField.getDescribe();
        if (!targetFieldDescribe.isAccessible()) {
            return null;
        }
        
        // Create FieldInfo for the relationship field
        FieldInfo fieldInfo = new FieldInfo();
        fieldInfo.apiName = fieldName; // Keep the full relationship notation for SOQL
        fieldInfo.label = targetFieldDescribe.getLabel();
        fieldInfo.type = String.valueOf(targetFieldDescribe.getType());
        
        return fieldInfo;
    }
    
    private static Schema.SObjectField findField(Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        // Try exact match first
        if (fieldMap.containsKey(fieldName)) {
            return fieldMap.get(fieldName);
        }
        
        // Try case-insensitive match
        for (String key : fieldMap.keySet()) {
            if (key.equalsIgnoreCase(fieldName)) {
                return fieldMap.get(key);
            }
        }
        
        return null;
    }
    
    // ===== WRAPPER CLASSES =====

    // Wrapper classes for ARL mode
    public class FieldInfo {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
    }
    
    // ARL-specific wrapper classes
    public class RelatedListInfo {
        @AuraEnabled public List<FieldInfo> fields;
        @AuraEnabled public List<sObject> records;
        @AuraEnabled public String relationshipName;
        @AuraEnabled public String relatedObjectType;
        @AuraEnabled public Boolean hasMoreRecords;
    }
    
    // Helper class for relationship mapping
    private class RelationshipMapping {
        public String relationshipName;
        public String childObjectType;
        public String relationshipField;
    }

    // ===== KNOWLEDGE ARTICLES METHODS =====
    // Add these methods to your existing RelatedListLWRController.cls class

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
    @AuraEnabled(cacheable=false)
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
    // ===== FILES METHODS =====

    public class FileRecord {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String contentDocumentId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String fileExtension { get; set; }
        @AuraEnabled public String fileType { get; set; }
        @AuraEnabled public Long contentSize { get; set; }
        @AuraEnabled public String formattedSize { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public String createdBy { get; set; }
        @AuraEnabled public String downloadUrl { get; set; }
        @AuraEnabled public String previewUrl { get; set; }
        @AuraEnabled public String icon { get; set; }
        @AuraEnabled public Boolean isImage { get; set; }
        @AuraEnabled public Boolean canPreview { get; set; }
        
        public FileRecord() {}
    }

    @AuraEnabled(cacheable=false)
    public static List<FileRecord> getFiles(String recordId, String sortField, String sortDirection, Integer limitCount) {
        List<FileRecord> files = new List<FileRecord>();

        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            String actualSortField = String.isNotBlank(sortField) ? sortField : 'CreatedDate';
            String actualSortDirection = String.isNotBlank(sortDirection) ? sortDirection.toUpperCase() : 'DESC';
            Integer actualLimit = limitCount != null && limitCount > 0 ? limitCount : 50;

            if (actualSortDirection != 'ASC' && actualSortDirection != 'DESC') {
                actualSortDirection = 'DESC';
            }

            String query = buildFileQuery(actualSortField, actualSortDirection, actualLimit, recordId);
            List<ContentDocumentLink> links = Database.query(query);
            
            for (ContentDocumentLink link : links) {
                try {
                    FileRecord fileRecord = createFileRecord(link);
                    files.add(fileRecord);
                } catch (Exception e) {
                    System.debug('Error processing file: ' + e.getMessage());
                }
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Unable to retrieve files: ' + e.getMessage());
        }
        
        return files;
    }

    @AuraEnabled(cacheable=false)
    public static String getImageAsBase64(String contentDocumentId) {
        try {
            // Verify user has access to this file via ContentDocumentLink
            // This ensures users can only access files they have permission to view
            // With sharing enforces object-level security on the linked entity
            List<ContentDocumentLink> accessCheck = [
                SELECT Id, LinkedEntityId
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :contentDocumentId
                LIMIT 1
            ];

            // If no links exist or user doesn't have access to any linked records, deny access
            if (accessCheck.isEmpty()) {
                throw new AuraHandledException('Access denied: You do not have permission to access this file');
            }

            List<ContentVersion> versions = [
                SELECT VersionData, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];

            if (!versions.isEmpty()) {
                Blob imageBlob = versions[0].VersionData;
                String base64 = EncodingUtil.base64Encode(imageBlob);
                String fileExt = versions[0].FileExtension?.toLowerCase();
                
                String mimeType = 'image/png';
                if (fileExt == 'jpg' || fileExt == 'jpeg') mimeType = 'image/jpeg';
                else if (fileExt == 'gif') mimeType = 'image/gif';
                
                return 'data:' + mimeType + ';base64,' + base64;
            }
        } catch (Exception e) {
            System.debug('Error loading image as base64: ' + e.getMessage());
        }
        return null;
    }

    private static String buildFileQuery(String sortField, String sortDirection, Integer limitCount, String recordId) {
        // Validate recordId format to prevent SOQL injection
        try {
            Id validatedId = Id.valueOf(recordId);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid record ID format: ' + recordId);
        }

        String selectClause = 'SELECT Id, ContentDocumentId, LinkedEntityId, ' +
                            'ContentDocument.Id, ContentDocument.Title, ContentDocument.LatestPublishedVersionId, ' +
                            'ContentDocument.ContentSize, ContentDocument.FileType, ContentDocument.FileExtension, ' +
                            'ContentDocument.CreatedDate, ContentDocument.CreatedById, ' +
                            'ContentDocument.CreatedBy.Name, ContentDocument.CreatedBy.FirstName, ContentDocument.CreatedBy.LastName';

        String fromClause = ' FROM ContentDocumentLink';
        // SECURITY NOTE: Using String.escapeSingleQuotes as defense-in-depth
        // recordId is validated as valid Salesforce ID above
        String whereClause = ' WHERE LinkedEntityId = \'' + String.escapeSingleQuotes(recordId) + '\' AND IsDeleted = false';

        String actualSortField;
        if (sortField == 'Title') {
            actualSortField = 'ContentDocument.Title';
        } else if (sortField == 'ContentSize') {
            actualSortField = 'ContentDocument.ContentSize';
        } else if (sortField == 'FileExtension') {
            actualSortField = 'ContentDocument.FileExtension';
        } else {
            actualSortField = 'ContentDocument.CreatedDate';
        }

        String orderByClause = ' ORDER BY ' + actualSortField + ' ' + sortDirection;
        String limitClause = ' LIMIT ' + limitCount;

        return selectClause + fromClause + whereClause + orderByClause + limitClause;
    }

    private static FileRecord createFileRecord(ContentDocumentLink link) {
        FileRecord record = new FileRecord();
        
        record.id = link.ContentDocument.Id;
        record.contentDocumentId = link.ContentDocument.Id;
        record.title = link.ContentDocument.Title;
        record.fileExtension = link.ContentDocument.FileExtension;
        record.fileType = link.ContentDocument.FileType;
        record.contentSize = link.ContentDocument.ContentSize;
        record.formattedSize = formatFileSize(link.ContentDocument.ContentSize);
        record.createdDate = link.ContentDocument.CreatedDate;
        record.createdBy = getDisplayNameFromUser(
            link.ContentDocument.CreatedBy?.FirstName,
            link.ContentDocument.CreatedBy?.LastName,
            link.ContentDocument.CreatedBy?.Name
        );
        
        record.downloadUrl = getBaseDomain() + '/sfc/servlet.shepherd/document/download/' + link.ContentDocument.Id;
        record.previewUrl = record.downloadUrl;
        
        record.isImage = isImageFile(record.fileExtension);
        record.canPreview = canPreviewFile(record.fileExtension);
        record.icon = getFileIcon(record.fileExtension);
        
        return record;
    }

    private static String getBaseDomain() {
        String domain = '';
        
        try {
            domain = URL.getOrgDomainUrl().toExternalForm();
            if (String.isNotBlank(domain)) {
                domain = transformToFileDomain(domain);
            }
        } catch (Exception e) {
            // Continue to fallback
        }
        
        if (String.isBlank(domain)) {
            try {
                String currentDomain = ApexPages.currentPage()?.getHeaders()?.get('Host');
                if (String.isNotBlank(currentDomain)) {
                    domain = 'https://' + currentDomain;
                    domain = transformToFileDomain(domain);
                }
            } catch (Exception e) {
                // Continue to fallback
            }
        }
        
        if (String.isBlank(domain)) {
            try {
                String siteHost = Site.getBaseUrl();
                if (String.isNotBlank(siteHost)) {
                    domain = transformToFileDomain(siteHost);
                }
            } catch (Exception e) {
                // Continue to fallback
            }
        }
        
        if (String.isBlank(domain)) {
            domain = 'https://files.salesforce.com';
        }
        
        return domain;
    }

    private static String transformToFileDomain(String inputDomain) {
        if (String.isBlank(inputDomain)) {
            return inputDomain;
        }
        
        try {
            String domainOnly = inputDomain.replace('https://', '').replace('http://', '');
            if (domainOnly.contains('/')) {
                domainOnly = domainOnly.substring(0, domainOnly.indexOf('/'));
            }
            
            String fileDomain = '';
            
            if (domainOnly.contains('.sandbox.my.salesforce.com')) {
                String orgPart = domainOnly.substring(0, domainOnly.indexOf('.sandbox.my.salesforce.com'));
                fileDomain = 'https://' + orgPart + '.sandbox.file.force.com';
            } else if (domainOnly.contains('.my.salesforce.com')) {
                String orgPart = domainOnly.substring(0, domainOnly.indexOf('.my.salesforce.com'));
                fileDomain = 'https://' + orgPart + '.file.force.com';
            } else if (domainOnly.contains('.lightning.force.com')) {
                String orgPart = domainOnly.substring(0, domainOnly.indexOf('.lightning.force.com'));
                fileDomain = 'https://' + orgPart + '.file.force.com';
            } else if (domainOnly.contains('.')) {
                String orgPart = domainOnly.substring(0, domainOnly.indexOf('.'));
                fileDomain = 'https://' + orgPart + '.file.force.com';
            } else {
                fileDomain = 'https://' + domainOnly + '.file.force.com';
            }
            
            return fileDomain;
            
        } catch (Exception e) {
            return 'https://files.salesforce.com';
        }
    }

    private static Boolean isImageFile(String fileExtension) {
        if (String.isBlank(fileExtension)) {
            return false;
        }
        Set<String> imageExtensions = new Set<String>{'png', 'jpg', 'jpeg', 'bmp', 'webp'};
        return imageExtensions.contains(fileExtension.toLowerCase());
    }

    private static Boolean canPreviewFile(String fileExtension) {
        if (String.isBlank(fileExtension)) {
            return false;
        }
        Set<String> previewableExtensions = new Set<String>{'png', 'jpg', 'jpeg', 'bmp', 'webp', 'pdf', 'txt'};
        return previewableExtensions.contains(fileExtension.toLowerCase());
    }

    private static String getFileIcon(String fileExtension) {
        if (String.isBlank(fileExtension)) {
            return 'doctype:unknown';
        }
        
        Map<String, String> iconMap = new Map<String, String>{
            'pdf' => 'doctype:pdf',
            'doc' => 'doctype:word',
            'docx' => 'doctype:word',
            'xls' => 'doctype:excel',
            'xlsx' => 'doctype:excel',
            'ppt' => 'doctype:ppt',
            'pptx' => 'doctype:ppt',
            'txt' => 'doctype:txt',
            'csv' => 'doctype:csv',
            'xml' => 'doctype:xml',
            'zip' => 'doctype:zip',
            'png' => 'doctype:image',
            'jpg' => 'doctype:image',
            'jpeg' => 'doctype:image',
            'gif' => 'doctype:image',
            'svg' => 'doctype:image',
            'bmp' => 'doctype:image',
            'webp' => 'doctype:image',
            'mp3' => 'doctype:audio',
            'mp4' => 'doctype:video',
            'mov' => 'doctype:video'
        };
        
        String ext = fileExtension.toLowerCase();
        return iconMap.get(ext) != null ? iconMap.get(ext) : 'doctype:unknown';
    }

    private static String formatFileSize(Long bytes) {
        if (bytes == null || bytes == 0) return '0 Bytes';
        
        List<String> sizes = new List<String>{'Bytes', 'KB', 'MB', 'GB'};
        Integer i = 0;
        Double size = bytes;
        
        while (size >= 1024 && i < sizes.size() - 1) {
            size = size / 1024;
            i++;
        }
        
        return String.valueOf(Math.round(size * 10) / 10.0) + ' ' + sizes[i];
    }

    private static String getDisplayNameFromUser(String firstName, String lastName, String fullName) {
        if (String.isNotBlank(firstName) && String.isNotBlank(lastName)) {
            return firstName + ' ' + lastName;
        }

        if (String.isNotBlank(fullName)) {
            return fullName;
        }

        return 'Unknown User';
    }

    // ===== RECORD DELETION METHODS =====

    /**
     * Check if the current user has permission to delete records of a specific object type
     * @param objectApiName The API name of the object to check (e.g., 'Contact', 'Opportunity')
     * @return Boolean indicating whether the user can delete records of this object type
     */
    @AuraEnabled(cacheable=true)
    public static Boolean canDeleteObject(String objectApiName) {
        try {
            if (String.isBlank(objectApiName)) {
                return false;
            }

            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                System.debug('RelatedListLWR: Object type not found: ' + objectApiName);
                return false;
            }

            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
            Boolean isDeletable = describeResult.isDeletable();

            System.debug('RelatedListLWR: Delete permission check for ' + objectApiName + ': ' + isDeletable);
            return isDeletable;

        } catch (Exception e) {
            System.debug('RelatedListLWR: Error checking delete permission: ' + e.getMessage());
            return false;
        }
    }

    /**
     * Delete a record by ID
     * @param recordId The ID of the record to delete
     */
    @AuraEnabled(cacheable=false)
    public static void deleteRecord(String recordId) {
        try {
            // Validate input
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            // Validate recordId format and get object type
            Id recordIdObj;
            try {
                recordIdObj = Id.valueOf(recordId);
            } catch (Exception e) {
                throw new AuraHandledException('Invalid record ID format');
            }

            Schema.SObjectType sObjectType = recordIdObj.getSObjectType();
            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();

            // Check if user has delete permission (defense in depth)
            if (!describeResult.isDeletable()) {
                throw new AuraHandledException('You do not have permission to delete this record');
            }

            // Query the record
            String objectName = describeResult.getName();
            String query = 'SELECT Id FROM ' + objectName + ' WHERE Id = :recordId LIMIT 1';
            List<sObject> records = Database.query(query);

            if (records.isEmpty()) {
                throw new AuraHandledException('Record not found');
            }

            // Delete the record
            sObject recordToDelete = records[0];
            delete recordToDelete;

            System.debug('RelatedListLWR: Successfully deleted record: ' + recordId);

        } catch (DmlException e) {
            System.debug('RelatedListLWR: DML error deleting record: ' + e.getMessage());
            throw new AuraHandledException('Unable to delete record: ' + e.getDmlMessage(0));
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledExceptions as-is
            throw e;
        } catch (Exception e) {
            System.debug('RelatedListLWR: Error deleting record: ' + e.getMessage());
            throw new AuraHandledException('Error deleting record: ' + e.getMessage());
        }
    }

    /**
     * @param recordId The ID of the source record
     */
    @AuraEnabled(cacheable=false)
    public static List<EmailMessage> getEmailActivity(String recordId) {

        String query = 'SELECT Id, Name, IsOpened, MessageDate, Status, Subject FROM EmailMessage WHERE RelatedToId = :recordId';
        List<sObject> records = Database.query(query);

        return records;
    }
}