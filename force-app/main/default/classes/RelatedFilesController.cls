public with sharing class RelatedFilesController {
    
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
                    // Continue processing other files
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
            // Return null on any error
        }
        return null;
    }
    
    private static String buildFileQuery(String sortField, String sortDirection, Integer limitCount, String recordId) {
        String selectClause = 'SELECT Id, ContentDocumentId, LinkedEntityId, ' +
                             'ContentDocument.Id, ContentDocument.Title, ContentDocument.LatestPublishedVersionId, ' +
                             'ContentDocument.ContentSize, ContentDocument.FileType, ContentDocument.FileExtension, ' +
                             'ContentDocument.CreatedDate, ContentDocument.CreatedById, ' +
                             'ContentDocument.CreatedBy.Name, ContentDocument.CreatedBy.FirstName, ContentDocument.CreatedBy.LastName';
        
        String fromClause = ' FROM ContentDocumentLink';
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
            // Continue to fallback methods
        }
        
        if (String.isBlank(domain)) {
            try {
                String currentDomain = ApexPages.currentPage()?.getHeaders()?.get('Host');
                if (String.isNotBlank(currentDomain)) {
                    domain = 'https://' + currentDomain;
                    domain = transformToFileDomain(domain);
                }
            } catch (Exception e) {
                // Continue to next fallback
            }
        }
        
        if (String.isBlank(domain)) {
            try {
                String siteHost = Site.getBaseUrl();
                if (String.isNotBlank(siteHost)) {
                    domain = transformToFileDomain(siteHost);
                }
            } catch (Exception e) {
                // Continue to final fallback
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
}