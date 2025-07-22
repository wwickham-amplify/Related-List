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
        @AuraEnabled public Boolean isSpecial { get; set; } // For Files, which isn't a real object
        
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
     * Get available objects for the related list dropdown
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAvailableObjects() {
        List<ObjectOption> options = new List<ObjectOption>();
        
        try {
            // Add special "Files" option first
            options.add(new ObjectOption('Files', 'Files', true));
            
            // Get all objects the user has access to
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            List<String> objectNames = new List<String>();
            
            for (String objName : globalDescribe.keySet()) {
                Schema.SObjectType objType = globalDescribe.get(objName);
                Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
                
                // Only include objects that:
                // 1. User can access
                // 2. Are queryable
                // 3. Are not system objects (no __ suffix for standard, allow custom)
                // 4. Have a Name field or similar
                if (objDescribe.isAccessible() && 
                    objDescribe.isQueryable() && 
                    !objDescribe.getName().endsWith('__Share') &&
                    !objDescribe.getName().endsWith('__History') &&
                    !objDescribe.getName().endsWith('__Feed') &&
                    !objDescribe.getName().contains('ChangeEvent')) {
                    
                    objectNames.add(objName);
                }
            }
            
            // Sort alphabetically
            objectNames.sort();
            
            // Convert to options
            for (String objName : objectNames) {
                Schema.SObjectType objType = globalDescribe.get(objName);
                Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
                
                String label = objDescribe.getLabelPlural();
                options.add(new ObjectOption(label, objName, false));
            }
            
        } catch (Exception e) {
            System.debug('Error getting available objects: ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve available objects: ' + e.getMessage());
        }
        
        return options;
    }
    
    /**
     * Get configuration for a specific object type
     */
    @AuraEnabled(cacheable=false)
    public static RelatedListConfig getObjectConfiguration(String objectApiName, String parentRecordId) {
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
            
            // Get search layout columns
            config.columns = getSearchLayoutColumns(objectApiName);
            
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
        
        // Look for fields that reference the parent object
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
        
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                List<Schema.sObjectType> referenceTo = fieldDescribe.getReferenceTo();
                
                for (Schema.sObjectType refType : referenceTo) {
                    if (refType.getDescribe().getName() == parentObjectType) {
                        return fieldName;
                    }
                }
            }
        }
        
        return null;
    }
    
    /**
     * Get search layout columns for an object
     */
    private static List<FieldMetadata> getSearchLayoutColumns(String objectApiName) {
        List<FieldMetadata> columns = new List<FieldMetadata>();
        
        try {
            // Get object metadata
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
            
            // For now, use a default set of common fields since search layouts are hard to query dynamically
            // TODO: In a future enhancement, we could use the Tooling API to get actual search layouts
            List<String> defaultFields = getDefaultLayoutFields(objectApiName, fieldMap);
            
            for (String fieldName : defaultFields) {
                if (fieldMap.containsKey(fieldName)) {
                    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                    
                    // Check if user has access to this field
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
            System.debug('Error getting search layout: ' + e.getMessage());
            // Fallback to just Name field
            columns.add(createNameFieldMetadata(objectApiName));
        }
        
        return columns;
    }
    
    /**
     * Get default layout fields for common objects
     */
    private static List<String> getDefaultLayoutFields(String objectApiName, Map<String, Schema.SObjectField> fieldMap) {
        // Object-specific layouts
        if (objectApiName == 'Internal_Asset_Request__c') {
            return new List<String>{'Name', 'Internal_Asset_Product__c', 'Status__c'};
        }
        
        if (objectApiName == 'Knowledge__kav') {
            return new List<String>{'Title', 'ArticleType', 'PublishStatus'};
        }
        
        // Generic fallback - look for common field patterns
        List<String> fields = new List<String>();
        
        // Always try Name first
        if (fieldMap.containsKey('Name')) {
            fields.add('Name');
        } else if (fieldMap.containsKey('Title')) {
            fields.add('Title');
        } else if (fieldMap.containsKey('Subject')) {
            fields.add('Subject');
        }
        
        // Add status-type fields
        if (fieldMap.containsKey('Status')) {
            fields.add('Status');
        } else if (fieldMap.containsKey('Status__c')) {
            fields.add('Status__c');
        }
        
        // Add date fields
        if (fieldMap.containsKey('CreatedDate')) {
            fields.add('CreatedDate');
        }
        
        // Ensure we have at least one field
        if (fields.isEmpty()) {
            fields.add('Id');
        }
        
        return fields;
    }
    
    /**
     * Create a basic Name field metadata as fallback
     */
    private static FieldMetadata createNameFieldMetadata(String objectApiName) {
        FieldMetadata field = new FieldMetadata();
        field.apiName = 'Name';
        field.label = 'Name';
        field.type = 'STRING';
        field.sortable = true;
        field.isLookup = false;
        return field;
    }
    
    /**
     * Get appropriate icon for object type
     */
    private static String getObjectIcon(String objectApiName) {
        // Standard object icons
        Map<String, String> iconMap = new Map<String, String>{
            'Account' => 'standard:account',
            'Contact' => 'standard:contact',
            'Case' => 'standard:case',
            'Opportunity' => 'standard:opportunity',
            'Lead' => 'standard:lead',
            'Task' => 'standard:task',
            'Event' => 'standard:event',
            'Knowledge__kav' => 'standard:knowledge',
            'Internal_Asset_Request__c' => 'standard:asset_relationship'
        };
        
        if (iconMap.containsKey(objectApiName)) {
            return iconMap.get(objectApiName);
        }
        
        // Custom object default icon
        if (objectApiName.endsWith('__c')) {
            return 'standard:custom';
        }
        
        return 'standard:record';
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
                    Object fieldValue = obj.get(fieldName);
                    record.fields.put(fieldName, fieldValue);
                    
                    // Set display name from first field
                    if (record.displayName == null && fieldValue != null) {
                        record.displayName = String.valueOf(fieldValue);
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
     * Build dynamic SOQL query
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
        
        // Build SELECT clause
        String selectClause = 'SELECT Id, ' + String.join(fieldNames, ', ');
        
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
        
        return selectClause + fromClause + whereClause + orderByClause + limitClause;
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