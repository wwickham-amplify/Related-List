/**
 * RelatedListController - Apex controller for Related List LWC
 * Handles dynamic object queries and layout retrieval
 */
public with sharing class RelatedListController {
    
    /**
     * Wrapper class for object options
     */
    public class ObjectOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public Boolean isSpecial { get; set; }
        
        public ObjectOption(String label, String apiName, Boolean isSpecial) {
            this.label = label;
            this.value = apiName;
            this.apiName = apiName;
            this.isSpecial = isSpecial;
        }
    }
    
    /**
     * Wrapper class for field metadata
     */
    public class FieldMetadata {
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public Boolean sortable { get; set; }
        @AuraEnabled public Boolean isLookup { get; set; }
        @AuraEnabled public String referenceTo { get; set; }
        
        public FieldMetadata() {}
    }
    
    /**
     * Wrapper class for related list configuration
     */
    public class RelatedListConfig {
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String objectLabel { get; set; }
        @AuraEnabled public String relationshipField { get; set; }
        @AuraEnabled public List<FieldMetadata> columns { get; set; }
        @AuraEnabled public String icon { get; set; }
        @AuraEnabled public Boolean isSpecialObject { get; set; }
        
        public RelatedListConfig() {
            this.columns = new List<FieldMetadata>();
        }
    }
    
    /**
     * Wrapper class for record data
     */
    public class RelatedRecord {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public Map<String, Object> fields { get; set; }
        @AuraEnabled public String displayName { get; set; }
        
        public RelatedRecord() {
            this.fields = new Map<String, Object>();
        }
    }
    
    /**
     * Get configuration for a specific object type using Field Sets
     */
    @AuraEnabled(cacheable=false)
    public static RelatedListConfig getObjectConfiguration(String objectApiName, String parentRecordId, String fieldSetName) {
        RelatedListConfig config = new RelatedListConfig();
        
        try {
            config.objectApiName = objectApiName;
            config.isSpecialObject = objectApiName == 'Files';
            
            if (config.isSpecialObject) {
                return getFilesConfiguration();
            }
            
            // Get object metadata
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
            if (objType == null) {
                throw new AuraHandledException('Object ' + objectApiName + ' not found or not accessible');
            }
            
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            config.objectLabel = objDescribe.getLabelPlural();
            
            // Try to auto-detect relationship field
            config.relationshipField = detectRelationshipField(objDescribe, parentRecordId);
            
            // Get Field Set columns
            config.columns = getFieldSetColumns(objectApiName, fieldSetName);
            
            // Get icon
            config.icon = getObjectIcon(objectApiName);
            
        } catch (Exception e) {
            System.debug('Error getting object configuration: ' + e.getMessage());
            throw new AuraHandledException('Unable to configure object: ' + e.getMessage());
        }
        
        return config;
    }
    
    /**
     * Get Files configuration (special case)
     */
    private static RelatedListConfig getFilesConfiguration() {
        RelatedListConfig config = new RelatedListConfig();
        config.objectApiName = 'Files';
        config.objectLabel = 'Files';
        config.isSpecialObject = true;
        config.relationshipField = 'LinkedEntityId';
        config.icon = 'doctype:attachment';
        
        // Files use a different layout - no columns needed for card view
        return config;
    }
    
    /**
     * Auto-detect the relationship field to the parent record
     */
    private static String detectRelationshipField(Schema.DescribeSObjectResult objDescribe, String parentRecordId) {
        if (String.isBlank(parentRecordId)) {
            return null;
        }
        
        // Get the parent object type from the record ID
        Id parentId = Id.valueOf(parentRecordId);
        String parentObjectType = parentId.getSObjectType().getDescribe().getName();
        System.debug('Parent object type: ' + parentObjectType + ', Target object: ' + objDescribe.getName());
        
        // Special handling for Knowledge Articles - they use junction objects
        if (objDescribe.getName() == 'Knowledge__kav') {
            System.debug('Knowledge Article detected - this requires junction object handling');
            return null; // Will need special query logic
        }
        
        // Look for fields that reference the parent object
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
        List<String> possibleFields = new List<String>();
        
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                List<Schema.sObjectType> referenceTo = fieldDescribe.getReferenceTo();
                
                for (Schema.sObjectType refType : referenceTo) {
                    if (refType.getDescribe().getName() == parentObjectType) {
                        possibleFields.add(fieldName);
                        System.debug('Found possible relationship field: ' + fieldName);
                    }
                }
            }
        }
        
        // Return the first match (could be enhanced to prefer certain field names)
        if (!possibleFields.isEmpty()) {
            String selectedField = possibleFields[0];
            System.debug('Selected relationship field: ' + selectedField);
            return selectedField;
        }
        
        System.debug('No relationship field found for ' + objDescribe.getName() + ' to ' + parentObjectType);
        return null;
    }
    
    /**
     * Get field set columns for an object
     */
    private static List<FieldMetadata> getFieldSetColumns(String objectApiName, String fieldSetName) {
        List<FieldMetadata> columns = new List<FieldMetadata>();
        
        try {
            System.debug('Getting Field Set columns for object: ' + objectApiName + ', fieldSet: ' + fieldSetName);
            
            // Get object metadata
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            
            // Get field sets for this object
            Map<String, Schema.FieldSet> fieldSets = objDescribe.fieldSets.getMap();
            System.debug('Available field sets: ' + fieldSets.keySet());
            
            if (String.isBlank(fieldSetName)) {
                System.debug('No field set name provided, using fallback');
                return getFallbackColumns(objectApiName, objDescribe);
            }
            
            if (!fieldSets.containsKey(fieldSetName)) {
                System.debug('Field set "' + fieldSetName + '" not found, using fallback');
                return getFallbackColumns(objectApiName, objDescribe);
            }
            
            Schema.FieldSet fieldSet = fieldSets.get(fieldSetName);
            System.debug('Found field set with ' + fieldSet.getFields().size() + ' fields');
            
            for (Schema.FieldSetMember field : fieldSet.getFields()) {
                try {
                    String fieldPath = field.getFieldPath();
                    System.debug('Processing field: ' + fieldPath);
                    
                    // Get field describe from the object's field map
                    Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
                    
                    if (fieldMap.containsKey(fieldPath)) {
                        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldPath).getDescribe();
                        
                        // Check if user has access to this field
                        if (fieldDescribe.isAccessible()) {
                            FieldMetadata fieldMeta = new FieldMetadata();
                            fieldMeta.apiName = fieldPath;
                            fieldMeta.label = field.getLabel();
                            fieldMeta.type = String.valueOf(field.getType());
                            fieldMeta.sortable = fieldDescribe.isSortable();
                            fieldMeta.isLookup = field.getType() == Schema.DisplayType.REFERENCE;
                            
                            if (fieldMeta.isLookup && !fieldDescribe.getReferenceTo().isEmpty()) {
                                fieldMeta.referenceTo = fieldDescribe.getReferenceTo()[0].getDescribe().getName();
                            }
                            
                            columns.add(fieldMeta);
                            System.debug('Added field: ' + fieldMeta.apiName + ' (' + fieldMeta.label + ')');
                        } else {
                            System.debug('Field not accessible: ' + fieldPath);
                        }
                    } else {
                        System.debug('Field not found in field map: ' + fieldPath);
                    }
                } catch (Exception fieldError) {
                    System.debug('Error processing field ' + field.getFieldPath() + ': ' + fieldError.getMessage());
                }
            }
            
        } catch (Exception e) {
            System.debug('Error getting field set: ' + e.getMessage());
            return getFallbackColumns(objectApiName, null);
        }
        
        if (columns.isEmpty()) {
            System.debug('No columns found in field set, using fallback');
            return getFallbackColumns(objectApiName, null);
        }
        
        System.debug('Returning ' + columns.size() + ' columns from field set');
        return columns;
    }
    
    /**
     * Fallback columns when field set is not available
     */
    private static List<FieldMetadata> getFallbackColumns(String objectApiName, Schema.DescribeSObjectResult objDescribe) {
        List<FieldMetadata> columns = new List<FieldMetadata>();
        
        try {
            // Get object describe if not provided
            if (objDescribe == null) {
                Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
                objDescribe = objType.getDescribe();
            }
            
            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
            
            // Try common field names in order of preference
            List<String> fallbackFields = new List<String>();
            
            // Primary identifier field
            if (fieldMap.containsKey('Name')) {
                fallbackFields.add('Name');
            } else if (fieldMap.containsKey('Title')) {
                fallbackFields.add('Title');
            } else if (fieldMap.containsKey('Subject')) {
                fallbackFields.add('Subject');
            }
            
            // Status field
            if (fieldMap.containsKey('Status')) {
                fallbackFields.add('Status');
            } else if (fieldMap.containsKey('Status__c')) {
                fallbackFields.add('Status__c');
            }
            
            // Date field
            if (fieldMap.containsKey('CreatedDate')) {
                fallbackFields.add('CreatedDate');
            }
            
            // Ensure we have at least one field
            if (fallbackFields.isEmpty()) {
                fallbackFields.add('Id');
            }
            
            // Convert to FieldMetadata
            for (String fieldName : fallbackFields) {
                if (fieldMap.containsKey(fieldName)) {
                    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                    
                    if (fieldDescribe.isAccessible()) {
                        FieldMetadata field = new FieldMetadata();
                        field.apiName = fieldName;
                        field.label = fieldDescribe.getLabel();
                        field.type = String.valueOf(fieldDescribe.getType());
                        field.sortable = fieldDescribe.isSortable();
                        field.isLookup = fieldDescribe.getType() == Schema.DisplayType.REFERENCE;
                        
                        if (field.isLookup && !fieldDescribe.getReferenceTo().isEmpty()) {
                            field.referenceTo = fieldDescribe.getReferenceTo()[0].getDescribe().getName();
                        }
                        
                        columns.add(field);
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug('Error in fallback columns: ' + e.getMessage());
            // Final fallback - just ID
            FieldMetadata idField = new FieldMetadata();
            idField.apiName = 'Id';
            idField.label = 'Record ID';
            idField.type = 'ID';
            idField.sortable = true;
            idField.isLookup = false;
            columns.add(idField);
        }
        
        return columns;
    }
    
    /**
     * Get the actual Salesforce icon for an object type using the new icon method
     */
    private static String getObjectIcon(String objectApiName) {
        try {
            return getIconName(objectApiName);
        } catch (Exception e) {
            System.debug('Error getting icon for ' + objectApiName + ': ' + e.getMessage());
            // Fallback
            if (objectApiName.endsWith('__c')) {
                return 'standard:custom';
            }
            return 'standard:' + objectApiName.toLowerCase();
        }
    }
    
    /**
     * Get the actual Salesforce icon name for an object using describeTabs
     */
    @AuraEnabled(cacheable=false)
    public static String getIconName(String sObjectName) {
        System.debug('Getting icon for sObjectName: ' + sObjectName);
        
        // Handle special "Files" case
        if (sObjectName == 'Files') {
            return 'doctype:attachment';
        }
        
        String iconName;
        List<Schema.DescribeTabSetResult> tabSetDesc = Schema.describeTabs();
        List<Schema.DescribeTabResult> tabDesc = new List<Schema.DescribeTabResult>();
        List<Schema.DescribeIconResult> iconDesc = new List<Schema.DescribeIconResult>();
        
        // Get all tabs
        for(Schema.DescribeTabSetResult tsr : tabSetDesc) { 
            tabDesc.addAll(tsr.getTabs()); 
        }
        
        System.debug('Total tabs found: ' + tabDesc.size());
        
        // Find the tab for our object
        Boolean tabFound = false;
        for(Schema.DescribeTabResult tr : tabDesc) {
            System.debug('Checking tab for object: ' + tr.getSobjectName() + ' (looking for: ' + sObjectName + ')');
            
            if(sObjectName == tr.getSobjectName()) {
                tabFound = true;
                System.debug('Found tab for ' + sObjectName + ', isCustom: ' + tr.isCustom());
                
                if(tr.isCustom() == true) {
                    // Custom object - get the custom icon
                    iconDesc.addAll(tr.getIcons());
                    System.debug('Custom object icons found: ' + iconDesc.size());
                } else {
                    // Standard object - use standard pattern
                    iconName = 'standard:' + sObjectName.toLowerCase();
                    System.debug('Standard object icon: ' + iconName);
                }
                break;
            }
        }
        
        if (!tabFound) {
            System.debug('No tab found for ' + sObjectName);
        }
        
        // Process custom object icons - handle both SVG and PNG formats
        for (Schema.DescribeIconResult ir : iconDesc) {
            System.debug('Processing icon - ContentType: ' + ir.getContentType() + ', URL: ' + ir.getUrl());
            
            String url = ir.getUrl();
            if (String.isNotBlank(url) && url.contains('custom/')) {
                String customIconPart = '';
                
                // Handle SVG format
                if (ir.getContentType() == 'image/svg+xml' && url.contains('.svg')) {
                    customIconPart = url.substringBetween('custom/', '.svg');
                    System.debug('SVG format - extracted: ' + customIconPart);
                }
                // Handle PNG format  
                else if ((ir.getContentType() == 'image/png' || url.contains('.png')) && url.contains('custom/')) {
                    customIconPart = url.substringBetween('custom/', '_');
                    if (String.isBlank(customIconPart)) {
                        customIconPart = url.substringBetween('custom/', '.png');
                    }
                    System.debug('PNG format - extracted: ' + customIconPart);
                }
                
                if (String.isNotBlank(customIconPart)) {
                    // Remove any trailing parts after underscore if still present
                    if (customIconPart.contains('_')) {
                        String beforeUnderscore = customIconPart.substringBefore('_');
                        System.debug('Cleaned underscore part: ' + beforeUnderscore + ' (was: ' + customIconPart + ')');
                        customIconPart = beforeUnderscore;
                    }
                    
                    iconName = 'custom:' + customIconPart;
                    System.debug('Final extracted custom icon: ' + iconName);
                    break; // Found the icon, stop processing
                }
            }
        }
        
        // Enhanced fallback if no icon found
        if (String.isBlank(iconName)) {
            System.debug('No icon found through tabs, using fallback approach');
            
            if (sObjectName.endsWith('__c')) {
                // For custom objects, try a pattern-based approach
                iconName = getCustomObjectFallbackIcon(sObjectName);
            } else {
                // Standard object fallback
                iconName = 'standard:' + sObjectName.toLowerCase();
            }
        }
        
        System.debug('Final iconName: ' + iconName);
        return iconName;
    }
    
    /**
     * Enhanced fallback for custom objects when tab-based approach fails
     */
    private static String getCustomObjectFallbackIcon(String objectApiName) {
        String lowerName = objectApiName.toLowerCase();
        
        // Object name pattern matching for better icons
        if (lowerName.contains('asset')) {
            return 'custom:custom19'; // Asset-related icon (green)
        } else if (lowerName.contains('request')) {
            return 'custom:custom63'; // Request-related icon (green)
        } else if (lowerName.contains('product')) {
            return 'custom:custom54'; // Product-related icon
        } else {
            // Use hash-based approach for consistency
            Integer hash = Math.abs(objectApiName.hashCode());
            Integer iconNumber = Math.mod(hash, 100) + 1;
            return 'custom:custom' + iconNumber;
        }
    }
    
    /**
     * Get related records for display
     */
    @AuraEnabled(cacheable=false)
    public static List<RelatedRecord> getRelatedRecords(
        String objectApiName, 
        String parentRecordId, 
        String relationshipField,
        List<String> fieldNames,
        String sortField,
        String sortDirection,
        Integer limitCount
    ) {
        List<RelatedRecord> records = new List<RelatedRecord>();
        
        try {
            if (objectApiName == 'Files') {
                return getFileRecords(parentRecordId, limitCount);
            }
            
            // Special handling for Knowledge Articles
            if (objectApiName == 'Knowledge__kav') {
                return getKnowledgeArticleRecords(parentRecordId, fieldNames, sortField, sortDirection, limitCount);
            }
            
            if (String.isBlank(relationshipField)) {
                System.debug('No relationship field found for ' + objectApiName);
                return records;
            }
            
            // Build dynamic SOQL query
            String query = buildDynamicQuery(objectApiName, fieldNames, relationshipField, sortField, sortDirection, limitCount);
            System.debug('Executing query: ' + query);
            
            // Execute query with parent record ID
            List<SObject> sObjects = Database.query(query);
            
            // Convert to wrapper objects
            for (SObject obj : sObjects) {
                RelatedRecord record = new RelatedRecord();
                record.id = obj.Id;
                
                for (String fieldName : fieldNames) {
                    try {
                        // Get field metadata to determine if it's a lookup
                        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
                        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
                        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
                        
                        if (fieldMap.containsKey(fieldName)) {
                            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                            Object fieldValue = obj.get(fieldName);
                            
                            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE && fieldValue != null) {
                                // This is a lookup field - try to get the Name from the related record
                                String relationshipName = fieldDescribe.getRelationshipName();
                                Object relatedName = null;
                                
                                if (String.isNotBlank(relationshipName)) {
                                    try {
                                        // Try to get Name first
                                        SObject relatedRecord = obj.getSObject(relationshipName);
                                        if (relatedRecord != null) {
                                            if (relatedRecord.get('Name') != null) {
                                                relatedName = relatedRecord.get('Name');
                                            } else if (relatedRecord.get('Title') != null) {
                                                relatedName = relatedRecord.get('Title');
                                            } else if (relatedRecord.get('Subject') != null) {
                                                relatedName = relatedRecord.get('Subject');
                                            }
                                        }
                                    } catch (Exception e) {
                                        System.debug('Could not get related record name for ' + fieldName + ': ' + e.getMessage());
                                    }
                                }
                                
                                // Use the related record's name if available, otherwise the ID
                                record.fields.put(fieldName, relatedName != null ? relatedName : fieldValue);
                            } else {
                                // Regular field
                                record.fields.put(fieldName, fieldValue);
                            }
                        } else {
                            // Field not found in describe
                            record.fields.put(fieldName, obj.get(fieldName));
                        }
                    } catch (Exception e) {
                        System.debug('Error processing field ' + fieldName + ': ' + e.getMessage());
                        record.fields.put(fieldName, obj.get(fieldName));
                    }
                    
                    // Set display name from first field
                    if (record.displayName == null && record.fields.get(fieldName) != null) {
                        record.displayName = String.valueOf(record.fields.get(fieldName));
                    }
                }
                
                records.add(record);
            }
            
        } catch (Exception e) {
            System.debug('Error getting related records: ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve records: ' + e.getMessage());
        }
        
        return records;
    }
    
    /**
     * Get Knowledge Article records related to a Case through CaseArticle junction
     */
    private static List<RelatedRecord> getKnowledgeArticleRecords(
        String parentRecordId, 
        List<String> fieldNames,
        String sortField,
        String sortDirection,
        Integer limitCount
    ) {
        List<RelatedRecord> records = new List<RelatedRecord>();
        
        try {
            System.debug('Getting Knowledge Articles for Case: ' + parentRecordId);
            
            // Get the KnowledgeArticleVersionId from CaseArticle junction
            List<CaseArticle> caseArticles = [
                SELECT KnowledgeArticleVersionId 
                FROM CaseArticle 
                WHERE CaseId = :parentRecordId
            ];
            
            System.debug('Found ' + caseArticles.size() + ' CaseArticle records');
            
            if (caseArticles.isEmpty()) {
                return records;
            }
            
            // Extract Knowledge Article Version IDs
            Set<Id> knowledgeArticleVersionIds = new Set<Id>();
            for (CaseArticle ca : caseArticles) {
                if (ca.KnowledgeArticleVersionId != null) {
                    knowledgeArticleVersionIds.add(ca.KnowledgeArticleVersionId);
                }
            }
            
            if (knowledgeArticleVersionIds.isEmpty()) {
                System.debug('No KnowledgeArticleVersionIds found');
                return records;
            }
            
            // Build SOQL for Knowledge__kav using the specific version IDs
            List<String> selectFields = new List<String>{'Id'};
            selectFields.addAll(fieldNames);
            
            String selectClause = 'SELECT ' + String.join(selectFields, ', ');
            String fromClause = ' FROM Knowledge__kav';
            String whereClause = ' WHERE Id IN :knowledgeArticleVersionIds';
            
            String orderByClause = '';
            if (String.isNotBlank(sortField)) {
                orderByClause = ' ORDER BY ' + sortField;
                if (String.isNotBlank(sortDirection) && 
                    (sortDirection.toUpperCase() == 'ASC' || sortDirection.toUpperCase() == 'DESC')) {
                    orderByClause += ' ' + sortDirection.toUpperCase();
                }
            }
            
            String limitClause = '';
            if (limitCount != null && limitCount > 0) {
                limitClause = ' LIMIT ' + limitCount;
            }
            
            String query = selectClause + fromClause + whereClause + orderByClause + limitClause;
            System.debug('Knowledge Article query: ' + query);
            
            List<Knowledge__kav> articles = Database.query(query);
            System.debug('Found ' + articles.size() + ' Knowledge Articles');
            
            // Convert to RelatedRecord format
            for (Knowledge__kav article : articles) {
                RelatedRecord record = new RelatedRecord();
                record.id = article.Id;
                
                for (String fieldName : fieldNames) {
                    Object fieldValue = article.get(fieldName);
                    record.fields.put(fieldName, fieldValue);
                    
                    // Set display name from first field
                    if (record.displayName == null && fieldValue != null) {
                        record.displayName = String.valueOf(fieldValue);
                    }
                }
                
                records.add(record);
            }
            
        } catch (Exception e) {
            System.debug('Error getting Knowledge Article records: ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve Knowledge Articles: ' + e.getMessage());
        }
        
        return records;
    }
    
    /**
     * Build dynamic SOQL query with proper lookup field handling
     */
    private static String buildDynamicQuery(
        String objectApiName,
        List<String> fieldNames, 
        String relationshipField,
        String sortField,
        String sortDirection,
        Integer limitCount
    ) {
        // Validate inputs
        if (String.isBlank(objectApiName) || fieldNames == null || fieldNames.isEmpty()) {
            throw new AuraHandledException('Invalid query parameters');
        }
        
        // Get object metadata for field types
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
        
        // Build SELECT clause with lookup field handling
        List<String> selectFields = new List<String>{'Id'};
        
        for (String fieldName : fieldNames) {
            if (fieldMap.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                    // For lookup fields, query both the ID and the Name from the related object
                    selectFields.add(fieldName); // Add the ID field
                    
                    // Try to add the Name field from the related object
                    List<Schema.sObjectType> referenceTo = fieldDescribe.getReferenceTo();
                    if (!referenceTo.isEmpty()) {
                        String relationshipName = fieldDescribe.getRelationshipName();
                        if (String.isNotBlank(relationshipName)) {
                            // Add related object's Name field
                            selectFields.add(relationshipName + '.Name');
                            
                            // For some objects, also try Title, Subject, etc.
                            Schema.DescribeSObjectResult relatedObjDescribe = referenceTo[0].getDescribe();
                            Map<String, Schema.SObjectField> relatedFieldMap = relatedObjDescribe.fields.getMap();
                            
                            if (relatedFieldMap.containsKey('Title')) {
                                selectFields.add(relationshipName + '.Title');
                            }
                            if (relatedFieldMap.containsKey('Subject')) {
                                selectFields.add(relationshipName + '.Subject');
                            }
                        }
                    }
                } else {
                    // Regular field
                    selectFields.add(fieldName);
                }
            }
        }
        
        String selectClause = 'SELECT ' + String.join(selectFields, ', ');
        
        // Build FROM clause
        String fromClause = ' FROM ' + objectApiName;
        
        // Build WHERE clause
        String whereClause = ' WHERE ' + relationshipField + ' = :parentRecordId';
        
        // Build ORDER BY clause
        String orderByClause = '';
        if (String.isNotBlank(sortField)) {
            orderByClause = ' ORDER BY ' + sortField;
            if (String.isNotBlank(sortDirection) && 
                (sortDirection.toUpperCase() == 'ASC' || sortDirection.toUpperCase() == 'DESC')) {
                orderByClause += ' ' + sortDirection.toUpperCase();
            }
        }
        
        // Build LIMIT clause
        String limitClause = '';
        if (limitCount != null && limitCount > 0) {
            limitClause = ' LIMIT ' + limitCount;
        }
        
        String finalQuery = selectClause + fromClause + whereClause + orderByClause + limitClause;
        System.debug('Final SOQL Query: ' + finalQuery);
        
        return finalQuery;
    }
    
    /**
     * Get file records (special handling for ContentDocumentLink)
     */
    private static List<RelatedRecord> getFileRecords(String parentRecordId, Integer limitCount) {
        List<RelatedRecord> records = new List<RelatedRecord>();
        
        try {
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension,
                       ContentDocument.ContentSize, ContentDocument.CreatedDate
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :parentRecordId
                ORDER BY ContentDocument.CreatedDate DESC
                LIMIT :limitCount
            ];
            
            for (ContentDocumentLink link : links) {
                RelatedRecord record = new RelatedRecord();
                record.id = link.ContentDocumentId;
                record.displayName = link.ContentDocument.Title;
                
                record.fields.put('Title', link.ContentDocument.Title);
                record.fields.put('FileExtension', link.ContentDocument.FileExtension);
                record.fields.put('ContentSize', link.ContentDocument.ContentSize);
                record.fields.put('CreatedDate', link.ContentDocument.CreatedDate);
                
                records.add(record);
            }
            
        } catch (Exception e) {
            System.debug('Error getting file records: ' + e.getMessage());
        }
        
        return records;
    }
}