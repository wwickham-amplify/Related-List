import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFiles from '@salesforce/apex/RelatedFilesController.getFiles';
import uploadFiles from '@salesforce/apex/RelatedFilesController.uploadFiles';

export default class RelatedFiles extends LightningElement {
    @api recordId;
    @api listTitle = '';
    @api recordLimit = 8;
    @api disableFileUpload = false;
    @api maxFileSize = 25;
    @api acceptedFileTypes = '';
    
    @track files = [];
    @track isLoading = false;
    @track errorMessage = '';
    @track hasError = false;

    // Modal properties
    @track showImageModal = false;
    @track modalImageUrl = '';
    @track modalDownloadUrl = '';
    @track modalImageName = '';
    @track modalImageSize = '';
    @track modalIsImage = false;
    @track modalFileIcon = 'doctype:unknown';

    // File upload properties
    @track showFileUpload = false;
    @track isUploading = false;
    @track selectedFiles = [];
    @track uploadError = '';
    @track showUploadError = false;

    connectedCallback() {
        console.log('=== RelatedFiles Connected ===');
        console.log('Record ID:', this.recordId);
        console.log('List Title:', this.listTitle);
        console.log('Record Limit:', this.recordLimit);
        console.log('Disable File Upload:', this.disableFileUpload);
        console.log('Max File Size:', this.maxFileSize);
        console.log('Accepted File Types:', this.acceptedFileTypes);
        this.loadFiles();
    }

    get computedListTitle() {
        return this.listTitle || 'Files';
    }

    get listTitleWithCount() {
        return `${this.computedListTitle} (${this.files.length})`;
    }

    get computedRecordLimit() {
        // Ensure recordLimit is treated as a number and has a sensible default
        const limit = parseInt(this.recordLimit, 10);
        return !isNaN(limit) && limit > 0 ? limit : 8;
    }

    get displayedFiles() {
        // Apply the record limit properly
        return this.files.slice(0, this.computedRecordLimit);
    }

    get hasFiles() {
        return !this.isLoading && !this.hasError && this.files.length > 0;
    }

    get hasNoFiles() {
        return !this.isLoading && !this.hasError && this.files.length === 0;
    }

    get hasMoreFiles() {
        return this.files.length > this.computedRecordLimit;
    }

    get viewAllButtonLabel() {
        const remaining = this.files.length - this.computedRecordLimit;
        return `View All (${remaining} more)`;
    }

    get showAddFilesButton() {
        // Hide the button when uploads are disabled
        return !this.disableFileUpload;
    }

    get computedMaxFileSize() {
        // Convert MB to bytes for validation
        const sizeInMB = parseInt(this.maxFileSize, 10);
        return !isNaN(sizeInMB) && sizeInMB > 0 ? sizeInMB : 25;
    }

    get maxFileSizeBytes() {
        return this.computedMaxFileSize * 1024 * 1024;
    }

    get computedAcceptedFileTypes() {
        // Process accepted file types
        if (!this.acceptedFileTypes || this.acceptedFileTypes.trim() === '') {
            return null; // Accept all types
        }
        
        // Clean up the input - remove spaces and ensure proper format
        return this.acceptedFileTypes
            .split(',')
            .map(type => type.trim())
            .filter(type => type.length > 0)
            .map(type => type.startsWith('.') ? type : '.' + type)
            .join(',');
    }

    async loadFiles() {
        if (!this.recordId) {
            console.warn('No recordId provided');
            return;
        }

        console.log('=== Loading Files ===');
        console.log('Using record limit:', this.computedRecordLimit);
        this.isLoading = true;
        this.hasError = false;

        try {
            const rawFiles = await getFiles({
                recordId: this.recordId,
                sortField: 'CreatedDate',
                sortDirection: 'DESC',
                limitCount: 50 // Get more than display limit for proper limiting
            });

            console.log('Raw response from Apex:', rawFiles);
            
            if (!rawFiles || !Array.isArray(rawFiles)) {
                throw new Error('Invalid response from getFiles');
            }

            // Process the files
            this.files = rawFiles.map((file, index) => {
                console.log(`File ${index}:`, {
                    id: file.id,
                    title: file.title,
                    fileExtension: file.fileExtension
                });

                return {
                    id: file.id || 'unknown-id',
                    title: file.title || 'Unknown File',
                    fileExtension: file.fileExtension || '',
                    formattedSize: file.formattedSize || '0 Bytes',
                    icon: this.getFileIcon(file.fileExtension || ''),
                    downloadUrl: file.downloadUrl || `/sfc/servlet.shepherd/document/download/${file.id}`,
                    previewUrl: file.previewUrl || this.generatePreviewUrl(file),
                    isImage: this.isImageFile(file.fileExtension || '')
                };
            });

            console.log('Processed files:', this.files.length);
            console.log('Will display:', this.displayedFiles.length);

        } catch (error) {
            console.error('Error in loadFiles:', error);
            this.hasError = true;
            this.errorMessage = error.message || 'Unknown error';
        } finally {
            this.isLoading = false;
        }
    }

    // Handle Add Files button click
    handleAddFiles() {
        console.log('=== Add Files Clicked ===');
        console.log('Disabled:', this.disableFileUpload);
        console.log('Max Size (MB):', this.computedMaxFileSize);
        console.log('Accepted Types:', this.computedAcceptedFileTypes);
        
        if (this.disableFileUpload) {
            this.showToast('Info', 'File upload is disabled', 'info');
            return;
        }

        // Create file input element dynamically
        const fileInput = document.createElement('input');
        fileInput.type = 'file';
        fileInput.multiple = true;
        
        // Set accepted file types if specified
        if (this.computedAcceptedFileTypes) {
            fileInput.accept = this.computedAcceptedFileTypes;
        }

        fileInput.addEventListener('change', (event) => {
            this.handleFileSelection(event);
        });

        fileInput.click();
    }

    // Handle file selection from input
    handleFileSelection(event) {
        const files = Array.from(event.target.files);
        console.log('Files selected:', files.length);
        
        // Clear any previous errors
        this.showUploadError = false;
        this.uploadError = '';
        
        if (files.length === 0) {
            return;
        }

        // Validate files
        const validFiles = [];
        const errors = [];

        for (const file of files) {
            console.log(`Validating file: ${file.name}, Size: ${file.size} bytes`);
            
            // Check file size
            if (file.size > this.maxFileSizeBytes) {
                errors.push(`File size must be under ${this.computedMaxFileSize}MB. "${file.name}" is too large.`);
                continue;
            }

            // Check file type if restrictions are set
            if (this.computedAcceptedFileTypes) {
                const fileExtension = '.' + file.name.split('.').pop().toLowerCase();
                const acceptedTypes = this.computedAcceptedFileTypes.toLowerCase().split(',');
                
                if (!acceptedTypes.includes(fileExtension)) {
                    errors.push(`"${file.name}" is not an accepted file type`);
                    continue;
                }
            }

            validFiles.push(file);
        }

        // Show errors if any
        if (errors.length > 0) {
            this.uploadError = errors.join('\n');
            this.showUploadError = true;
            return; // Don't proceed with upload if there are validation errors
        }

        // Upload valid files
        if (validFiles.length > 0) {
            this.uploadFiles(validFiles);
        }
    }

    // Upload files to Salesforce
    async uploadFiles(files) {
        console.log('=== Uploading Files ===');
        console.log('Files to upload:', files.length);
        
        // Clear any previous errors
        this.showUploadError = false;
        this.uploadError = '';
        this.isUploading = true;

        try {
            // Convert files to base64
            const fileUploadData = [];
            
            for (const file of files) {
                console.log(`Converting file to base64: ${file.name}`);
                
                const base64 = await this.fileToBase64(file);
                
                fileUploadData.push({
                    filename: file.name,
                    base64: base64,
                    contentType: file.type || 'application/octet-stream'
                });
            }

            // Call Apex method
            console.log('Calling Apex uploadFiles method...');
            const uploadedFileIds = await uploadFiles({
                recordId: this.recordId,
                files: fileUploadData
            });

            console.log('Files uploaded successfully:', uploadedFileIds);
            
            // Show success message
            const fileCount = uploadedFileIds.length;
            const message = fileCount === 1 ? 
                `1 file uploaded successfully` : 
                `${fileCount} files uploaded successfully`;
            
            this.showToast('Success', message, 'success');
            
            // Refresh the file list
            await this.loadFiles();

        } catch (error) {
            console.error('Error uploading files:', error);
            this.uploadError = 'Failed to upload files: ' + (error.body?.message || error.message);
            this.showUploadError = true;
        } finally {
            this.isUploading = false;
        }
    }

    // Convert file to base64
    fileToBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                // Remove the data URL prefix (data:mime/type;base64,)
                const base64 = reader.result.split(',')[1];
                resolve(base64);
            };
            reader.onerror = () => reject(new Error('Failed to read file'));
            reader.readAsDataURL(file);
        });
    }

    // Handle View All button click
    handleViewAll() {
        console.log('View All clicked - will implement navigation later');
        this.showToast('Info', 'View All functionality coming soon', 'info');
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(event);
    }

    // Get appropriate doctype icon based on file extension
    getFileIcon(fileExtension) {
        if (!fileExtension) return 'doctype:unknown';
        
        const ext = fileExtension.toLowerCase();
        const iconMap = {
            'pdf': 'doctype:pdf',
            'doc': 'doctype:word', 'docx': 'doctype:word',
            'xls': 'doctype:excel', 'xlsx': 'doctype:excel',
            'ppt': 'doctype:ppt', 'pptx': 'doctype:ppt',
            'txt': 'doctype:txt',
            'csv': 'doctype:csv',
            'xml': 'doctype:xml',
            'zip': 'doctype:zip', 'rar': 'doctype:zip',
            'png': 'doctype:image', 'jpg': 'doctype:image', 'jpeg': 'doctype:image', 
            'gif': 'doctype:image', 'svg': 'doctype:image', 'bmp': 'doctype:image',
            'mp3': 'doctype:audio', 'wav': 'doctype:audio',
            'mp4': 'doctype:video', 'mov': 'doctype:video', 'avi': 'doctype:video'
        };
        
        return iconMap[ext] || 'doctype:unknown';
    }

    // Check if file extension represents an image
    isImageFile(fileExtension) {
        if (!fileExtension) return false;
        const imageExtensions = new Set(['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg']);
        return imageExtensions.has(fileExtension.toLowerCase());
    }

    // Generate appropriate preview URL for file
    generatePreviewUrl(file) {
        const fileExt = (file.fileExtension || '').toLowerCase();
        
        // For images, use rendition download for better preview
        if (this.isImageFile(file.fileExtension)) {
            let rendition = 'PNG';
            if (fileExt === 'jpg' || fileExt === 'jpeg') {
                rendition = 'JPEG';
            } else if (fileExt === 'gif') {
                rendition = 'GIF';
            }
            
            // Try to get the version ID from the file data, or use the file ID
            const versionId = file.latestPublishedVersionId || file.id;
            const contentId = file.contentDocumentId || file.id;
            
            return `/sfsites/c/sfc/servlet.shepherd/version/renditionDownload?rendition=${rendition}&versionId=${versionId}&operationContext=CHATTER&contentId=${contentId}&page=1`;
        }
        
        // For non-images, use download URL
        return `/sfc/servlet.shepherd/document/download/${file.id}`;
    }

    // Modal event handlers
    handleFileClick(event) {
        const fileId = event.currentTarget.dataset.fileId;
        const file = this.files.find(f => f.id === fileId);
        
        console.log('File clicked:', file?.title);

        if (file) {
            // Set modal properties
            this.modalImageUrl = file.previewUrl;
            this.modalDownloadUrl = file.downloadUrl;
            this.modalImageName = file.title || 'Unknown File';
            this.modalImageSize = file.formattedSize || '';
            this.modalIsImage = file.isImage || false;
            this.modalFileIcon = file.icon || 'doctype:unknown';
            this.showImageModal = true;
        }
    }

    handleCloseModal() {
        this.showImageModal = false;
        this.modalImageUrl = '';
        this.modalDownloadUrl = '';
        this.modalImageName = '';
        this.modalImageSize = '';
        this.modalIsImage = false;
        this.modalFileIcon = 'doctype:unknown';
    }

    handleModalBackdropClick(event) {
        if (event.target.classList.contains('slds-backdrop')) {
            this.handleCloseModal();
        }
    }

    handleDownloadFromModal() {
        console.log('Download from modal:', this.modalImageName);
        const downloadUrl = this.modalDownloadUrl || this.modalImageUrl;
        
        if (downloadUrl) {
            // Create temporary download link
            const link = document.createElement('a');
            link.href = downloadUrl;
            link.download = this.modalImageName;
            link.style.display = 'none';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            
            this.showToast('Success', `Downloaded ${this.modalImageName}`, 'success');
        }
    }
}