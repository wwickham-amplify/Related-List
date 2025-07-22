/**
 * RelatedFilesController - Apex controller specifically for Related Files LWC
 * Handles file queries, uploads, and file operations
 */
public with sharing class RelatedFilesController {
    
    /**
     * Wrapper class for file data
     */
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
    
    /**
     * Wrapper class for file upload data
     */
    public class FileUploadData {
        @AuraEnabled public String filename { get; set; }
        @AuraEnabled public String base64 { get; set; }
        @AuraEnabled public String contentType { get; set; }
        
        public FileUploadData() {}
    }
    
    /**
     * Get files related to a specific record
     * @param recordId The parent record ID
     * @param sortField Field to sort by (Title, CreatedDate, ContentSize)
     * @param sortDirection Sort direction (ASC or DESC)
     * @param limitCount Maximum number of files to return
     * @return List of FileRecord objects
     */
    @AuraEnabled(cacheable=false)
    public static List<FileRecord> getFiles(String recordId, String sortField, String sortDirection, Integer limitCount) {
        List<FileRecord> files = new List<FileRecord>();
        
        System.debug('=== Getting Files ===');
        System.debug('Record ID: ' + recordId);
        System.debug('Sort Field: ' + sortField);
        System.debug('Sort Direction: ' + sortDirection);
        System.debug('Limit: ' + limitCount);
        
        try {
            // Validate inputs
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }
            
            // Set defaults
            String actualSortField = String.isNotBlank(sortField) ? sortField : 'CreatedDate';
            String actualSortDirection = String.isNotBlank(sortDirection) ? sortDirection.toUpperCase() : 'DESC';
            Integer actualLimit = limitCount != null && limitCount > 0 ? limitCount : 50;
            
            // Validate sort direction
            if (actualSortDirection != 'ASC' && actualSortDirection != 'DESC') {
                actualSortDirection = 'DESC';
            }
            
            // Build dynamic query
            String query = buildFileQuery(actualSortField, actualSortDirection, actualLimit);
            System.debug('Executing query: ' + query);
            
            // Execute query
            List<ContentDocumentLink> links = Database.query(query);
            System.debug('Found ' + links.size() + ' ContentDocumentLinks');
            
            // Convert to FileRecord objects
            for (ContentDocumentLink link : links) {
                try {
                    FileRecord fileRecord = createFileRecord(link);
                    files.add(fileRecord);
                } catch (Exception e) {
                    System.debug('Error processing file: ' + link.ContentDocumentId + ' - ' + e.getMessage());
                    // Continue processing other files
                }
            }
            
            System.debug('Returning ' + files.size() + ' file records');
            
        } catch (Exception e) {
            System.debug('Error in getFiles: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Unable to retrieve files: ' + e.getMessage());
        }
        
        return files;
    }
    
    /**
     * Upload files and attach them to a parent record
     * @param recordId The parent record ID
     * @param files List of file upload data
     * @return List of created file IDs
     */
    @AuraEnabled
    public static List<String> uploadFiles(String recordId, List<FileUploadData> files) {
        List<String> createdFileIds = new List<String>();
        
        System.debug('=== Uploading Files ===');
        System.debug('Record ID: ' + recordId);
        System.debug('Files count: ' + (files != null ? files.size() : 0));
        
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Validate inputs
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }
            
            if (files == null || files.isEmpty()) {
                throw new AuraHandledException('No files provided for upload');
            }
            
            // Check permissions
            if (!Schema.sObjectType.ContentVersion.isCreateable()) {
                throw new AuraHandledException('Insufficient permissions to upload files');
            }
            
            // Create ContentVersion records
            List<ContentVersion> contentVersions = new List<ContentVersion>();
            
            for (FileUploadData fileData : files) {
                if (String.isBlank(fileData.filename) || String.isBlank(fileData.base64)) {
                    System.debug('Skipping invalid file data: ' + fileData.filename);
                    continue;
                }
                
                ContentVersion cv = new ContentVersion();
                cv.Title = fileData.filename;
                cv.PathOnClient = fileData.filename;
                cv.VersionData = EncodingUtil.base64Decode(fileData.base64);
                cv.FirstPublishLocationId = recordId;
                cv.IsMajorVersion = true;
                
                contentVersions.add(cv);
                System.debug('Prepared file for upload: ' + fileData.filename);
            }
            
            if (contentVersions.isEmpty()) {
                throw new AuraHandledException('No valid files to upload');
            }
            
            // Insert ContentVersions
            insert contentVersions;
            System.debug('Successfully uploaded ' + contentVersions.size() + ' files');
            
            // Collect the created IDs
            for (ContentVersion cv : contentVersions) {
                createdFileIds.add(cv.Id);
            }
            
        } catch (Exception e) {
            System.debug('Error uploading files: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            Database.rollback(sp);
            throw new AuraHandledException('Failed to upload files: ' + e.getMessage());
        }
        
        return createdFileIds;
    }
    
    /**
     * Delete a file
     * @param contentDocumentId The ContentDocument ID to delete
     * @return Boolean indicating success
     */
    @AuraEnabled
    public static Boolean deleteFile(String contentDocumentId) {
        System.debug('=== Deleting File ===');
        System.debug('ContentDocument ID: ' + contentDocumentId);
        
        try {
            // Validate input
            if (String.isBlank(contentDocumentId)) {
                throw new AuraHandledException('ContentDocument ID is required');
            }
            
            // Check permissions
            if (!Schema.sObjectType.ContentDocument.isDeletable()) {
                throw new AuraHandledException('Insufficient permissions to delete files');
            }
            
            // Delete the ContentDocument (this will cascade delete ContentVersions and ContentDocumentLinks)
            ContentDocument doc = new ContentDocument(Id = contentDocumentId);
            delete doc;
            
            System.debug('Successfully deleted file: ' + contentDocumentId);
            return true;
            
        } catch (Exception e) {
            System.debug('Error deleting file: ' + e.getMessage());
            throw new AuraHandledException('Failed to delete file: ' + e.getMessage());
        }
    }
    
    /**
     * Get file statistics for a record
     * @param recordId The parent record ID
     * @return Map containing file statistics
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFileStatistics(String recordId) {
        Map<String, Object> stats = new Map<String, Object>();
        
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }
            
            // Get basic counts
            List<AggregateResult> results = [
                SELECT COUNT(Id) fileCount, SUM(ContentDocument.ContentSize) totalSize
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :recordId
                AND IsDeleted = false
            ];
            
            if (!results.isEmpty()) {
                AggregateResult result = results[0];
                stats.put('fileCount', result.get('fileCount'));
                stats.put('totalSize', result.get('totalSize'));
                stats.put('formattedTotalSize', formatFileSize((Long)result.get('totalSize')));
            } else {
                stats.put('fileCount', 0);
                stats.put('totalSize', 0);
                stats.put('formattedTotalSize', '0 Bytes');
            }
            
            System.debug('File statistics: ' + stats);
            
        } catch (Exception e) {
            System.debug('Error getting file statistics: ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve file statistics: ' + e.getMessage());
        }
        
        return stats;
    }
    
    // Private helper methods
    
    /**
     * Build dynamic SOQL query for files
     */
    private static String buildFileQuery(String sortField, String sortDirection, Integer limitCount) {
        String selectClause = 'SELECT Id, ContentDocumentId, LinkedEntityId, ' +
                             'ContentDocument.Id, ContentDocument.Title, ContentDocument.LatestPublishedVersionId, ' +
                             'ContentDocument.ContentSize, ContentDocument.FileType, ContentDocument.FileExtension, ' +
                             'ContentDocument.CreatedDate, ContentDocument.CreatedById, ' +
                             'ContentDocument.CreatedBy.Name, ContentDocument.CreatedBy.FirstName, ContentDocument.CreatedBy.LastName';
        
        String fromClause = ' FROM ContentDocumentLink';
        String whereClause = ' WHERE LinkedEntityId = :recordId AND IsDeleted = false';
        
        // Map sort field to actual field names
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
    
    /**
     * Create a FileRecord from ContentDocumentLink
     */
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
            link.ContentDocument.CreatedBy.FirstName,
            link.ContentDocument.CreatedBy.LastName,
            link.ContentDocument.CreatedBy.Name
        );
        
        // Generate URLs
        record.downloadUrl = '/sfc/servlet.shepherd/document/download/' + link.ContentDocument.Id;
        record.previewUrl = generatePreviewUrl(link.ContentDocument);
        
        // Determine file characteristics
        record.isImage = isImageFile(record.fileExtension);
        record.canPreview = canPreviewFile(record.fileExtension);
        record.icon = getFileIcon(record.fileExtension);
        
        return record;
    }
    
    /**
     * Generate appropriate preview URL for file
     */
    private static String generatePreviewUrl(ContentDocument doc) {
        String fileExt = String.isNotBlank(doc.FileExtension) ? doc.FileExtension.toLowerCase() : 'png';
        
        // For images, use rendition download
        if (isImageFile(doc.FileExtension)) {
            String rendition = 'PNG';
            if (fileExt == 'jpg' || fileExt == 'jpeg') {
                rendition = 'JPEG';
            } else if (fileExt == 'gif') {
                rendition = 'GIF';
            }
            
            return '/sfsites/c/sfc/servlet.shepherd/version/renditionDownload?rendition=' + rendition + 
                   '&versionId=' + doc.LatestPublishedVersionId + 
                   '&operationContext=CHATTER&contentId=' + doc.Id + '&page=1';
        }
        
        // For other files, use download URL
        return '/sfc/servlet.shepherd/document/download/' + doc.Id;
    }
    
    /**
     * Check if file extension represents an image
     */
    private static Boolean isImageFile(String fileExtension) {
        if (String.isBlank(fileExtension)) {
            return false;
        }
        
        Set<String> imageExtensions = new Set<String>{
            'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg'
        };
        
        return imageExtensions.contains(fileExtension.toLowerCase());
    }
    
    /**
     * Check if file can be previewed inline
     */
    private static Boolean canPreviewFile(String fileExtension) {
        if (String.isBlank(fileExtension)) {
            return false;
        }
        
        Set<String> previewableExtensions = new Set<String>{
            'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'pdf', 'txt'
        };
        
        return previewableExtensions.contains(fileExtension.toLowerCase());
    }
    
    /**
     * Get appropriate icon for file type
     */
    private static String getFileIcon(String fileExtension) {
        if (String.isBlank(fileExtension)) {
            return 'doctype:unknown';
        }
        
        String ext = fileExtension.toLowerCase();
        Map<String, String> iconMap = new Map<String, String>{
            'pdf' => 'doctype:pdf',
            'doc' => 'doctype:word', 'docx' => 'doctype:word',
            'xls' => 'doctype:excel', 'xlsx' => 'doctype:excel',
            'ppt' => 'doctype:ppt', 'pptx' => 'doctype:ppt',
            'txt' => 'doctype:txt',
            'csv' => 'doctype:csv',
            'xml' => 'doctype:xml',
            'zip' => 'doctype:zip', 'rar' => 'doctype:zip',
            'png' => 'doctype:image', 'jpg' => 'doctype:image', 'jpeg' => 'doctype:image',
            'gif' => 'doctype:image', 'svg' => 'doctype:image', 'bmp' => 'doctype:image',
            'mp3' => 'doctype:audio', 'wav' => 'doctype:audio',
            'mp4' => 'doctype:video', 'mov' => 'doctype:video', 'avi' => 'doctype:video'
        };
        
        return iconMap.get(ext) != null ? iconMap.get(ext) : 'doctype:unknown';
    }
    
    /**
     * Format file size for display
     */
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
    
    /**
     * Get user display name from individual name fields
     */
    private static String getDisplayNameFromUser(String firstName, String lastName, String fullName) {
        if (String.isNotBlank(firstName) && String.isNotBlank(lastName)) {
            return firstName + ' ' + lastName;
        }
        
        if (String.isNotBlank(fullName)) {
            return fullName;
        }
        
        return 'Unknown User';
    }
}