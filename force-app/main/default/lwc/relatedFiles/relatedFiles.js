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
    @api titleTextStyle = 'Heading 3';
    @api addFilesButtonStyle = 'Secondary';
    @api viewAllButtonStyle = 'Secondary';
    @api closeButtonStyle = 'Secondary';
    
    @track files = [];
    @track isLoading = false;
    @track errorMessage = '';
    @track hasError = false;

    // Pagination properties
    @track currentDisplayCount = 0;
    @track totalFileCount = 0;
    @track hasMoreFilesToLoad = false;

    // Enhanced modal properties
    @track showImageModal = false;
    @track modalImageUrl = '';
    @track modalDownloadUrl = '';
    @track modalImageName = '';
    @track modalImageSize = '';

    // File upload properties
    @track isUploading = false;
    @track uploadError = '';
    @track showUploadError = false;

    connectedCallback() {
        console.log('=== RelatedFiles Connected ===');
        console.log('Record ID:', this.recordId);
        this.loadFiles();
    }

    get computedListTitle() {
        return this.listTitle || 'Files';
    }

    get listTitleWithCount() {
        return `${this.computedListTitle} (${this.files.length})`;
    }

    get titleClasses() {
        const lwrFontMap = {
            'Heading 1': 'slds-text-heading_large',
            'Heading 2': 'slds-text-heading_medium',
            'Heading 3': 'slds-text-heading_small',
            'Heading 4': 'slds-text-title_caps',
            'Heading 5': 'slds-text-title_bold',
            'Heading 6': 'slds-text-title',
            'Paragraph 1': 'slds-text-body_regular',
            'Paragraph 2': 'slds-text-body_small'
        };
        
        return lwrFontMap[this.titleTextStyle] || lwrFontMap['Heading 3'];
    }

    get addFilesButtonVariant() {
        const styleMap = {
            'Primary': 'brand',
            'Secondary': 'brand-outline',
            'Tertiary': 'bare'
        };
        return styleMap[this.addFilesButtonStyle] || 'brand-outline';
    }

    get viewAllButtonVariant() {
        const styleMap = {
            'Primary': 'brand',
            'Secondary': 'brand-outline', 
            'Tertiary': 'base'
        };
        return styleMap[this.viewAllButtonStyle] || 'brand-outline';
    }

    get closeButtonVariant() {
        const styleMap = {
            'Primary': 'brand',
            'Secondary': 'brand-outline', 
            'Tertiary': 'base'
        };
        return styleMap[this.closeButtonStyle] || 'brand-outline';
    }

    get computedRecordLimit() {
        const limit = parseInt(this.recordLimit, 10);
        return !isNaN(limit) && limit > 0 ? limit : 8;
    }

    get displayedFiles() {
        return this.files.slice(0, this.currentDisplayCount);
    }

    get hasFiles() {
        return !this.isLoading && !this.hasError && this.files.length > 0;
    }

    get hasNoFiles() {
        return !this.isLoading && !this.hasError && this.files.length === 0;
    }

    get hasMoreFiles() {
        // Show "View More" if we have more files to display OR more files to load from server
        return this.files.length > this.currentDisplayCount || this.hasMoreFilesToLoad;
    }

    get viewAllButtonLabel() {
        if (this.hasMoreFilesToLoad) {
            return `Load More Files`;
        } else {
            const remaining = this.files.length - this.currentDisplayCount;
            return `Show ${Math.min(remaining, this.computedRecordLimit)} More`;
        }
    }

    get showAddFilesButton() {
        return !this.disableFileUpload;
    }

    get computedMaxFileSize() {
        const sizeInMB = parseInt(this.maxFileSize, 10);
        return !isNaN(sizeInMB) && sizeInMB > 0 ? sizeInMB : 25;
    }

    get maxFileSizeBytes() {
        return this.computedMaxFileSize * 1024 * 1024;
    }

    get computedAcceptedFileTypes() {
        if (!this.acceptedFileTypes || this.acceptedFileTypes.trim() === '') {
            return null;
        }
        
        return this.acceptedFileTypes
            .split(',')
            .map(type => type.trim())
            .filter(type => type.length > 0)
            .map(type => type.startsWith('.') ? type : '.' + type)
            .join(',');
    }

    async loadFiles(loadMore = false) {
        if (!this.recordId) {
            console.warn('No recordId provided');
            return;
        }

        console.log('=== Loading Files ===');
        console.log('Load more:', loadMore);
        console.log('Current display count:', this.currentDisplayCount);
        
        this.isLoading = true;
        this.hasError = false;

        try {
            // Calculate how many files to request
            const currentFileCount = this.files.length;
            const requestLimit = loadMore ? 
                currentFileCount + this.computedRecordLimit : // Load more files
                Math.max(this.computedRecordLimit * 2, 20); // Initial load with buffer

            console.log('Requesting limit:', requestLimit);

            const rawFiles = await getFiles({
                recordId: this.recordId,
                sortField: 'CreatedDate',
                sortDirection: 'DESC',
                limitCount: requestLimit
            });

            console.log('Raw response from Apex:', rawFiles?.length || 0, 'files');
            
            if (!rawFiles || !Array.isArray(rawFiles)) {
                throw new Error('Invalid response from getFiles');
            }

            // Process the files
            this.files = rawFiles.map((file, index) => {
                return {
                    id: file.id || 'unknown-id',
                    title: file.title || 'Unknown File',
                    fileExtension: file.fileExtension || '',
                    fileType: file.fileType || 'Unknown',
                    formattedSize: file.formattedSize || '0 Bytes',
                    icon: this.getFileIcon(file.fileExtension || ''),
                    downloadUrl: file.downloadUrl || `/sfc/servlet.shepherd/document/download/${file.id}`,
                    previewUrl: file.previewUrl || this.generatePreviewUrl(file),
                    isImage: this.isImageFile(file.fileExtension || ''),
                    canPreview: this.canPreviewFile(file.fileExtension || ''),
                    createdDate: file.createdDate
                };
            });

            // Update display count
            if (loadMore) {
                // When loading more, increase display count by the record limit
                this.currentDisplayCount = Math.min(
                    this.currentDisplayCount + this.computedRecordLimit,
                    this.files.length
                );
            } else {
                // Initial load - show the record limit number of files
                this.currentDisplayCount = Math.min(this.computedRecordLimit, this.files.length);
            }

            // Check if there might be more files on the server
            // If we got exactly what we requested, there might be more
            this.hasMoreFilesToLoad = rawFiles.length === requestLimit;

            console.log('Processed files:', this.files.length);
            console.log('Currently displaying:', this.currentDisplayCount);
            console.log('Has more to load from server:', this.hasMoreFilesToLoad);

        } catch (error) {
            console.error('Error in loadFiles:', error);
            this.hasError = true;
            this.errorMessage = error.message || 'Unknown error';
        } finally {
            this.isLoading = false;
        }
    }

    // Handle View More button click
    handleViewMore() {
        console.log('=== View More Clicked ===');
        console.log('Current displayed:', this.currentDisplayCount);
        console.log('Total files loaded:', this.files.length);
        console.log('Has more to load from server:', this.hasMoreFilesToLoad);

        // If we have more files already loaded, just show more of them
        if (this.files.length > this.currentDisplayCount) {
            this.currentDisplayCount = Math.min(
                this.currentDisplayCount + this.computedRecordLimit,
                this.files.length
            );
            console.log('Showing more loaded files. New display count:', this.currentDisplayCount);
        } 
        // If we need to load more files from the server
        else if (this.hasMoreFilesToLoad) {
            console.log('Loading more files from server...');
            // Use Promise.resolve to handle async safely
            Promise.resolve().then(() => {
                return this.loadFiles(true);
            }).catch(error => {
                console.error('Error loading more files:', error);
                this.showToast('Error', 'Failed to load more files: ' + (error.body?.message || error.message), 'error');
            });
        }
    }

    // Handle Add Files button click
    handleAddFiles() {
        console.log('=== Add Files Clicked ===');
        
        if (this.disableFileUpload) {
            this.showToast('Info', 'File upload is disabled', 'info');
            return;
        }

        const fileInput = document.createElement('input');
        fileInput.type = 'file';
        fileInput.multiple = true;
        
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
        
        this.showUploadError = false;
        this.uploadError = '';
        
        if (files.length === 0) {
            return;
        }

        const validFiles = [];
        const errors = [];

        for (const file of files) {
            if (file.size > this.maxFileSizeBytes) {
                errors.push(`File size must be under ${this.computedMaxFileSize}MB. "${file.name}" is too large.`);
                continue;
            }

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

        if (errors.length > 0) {
            this.uploadError = errors.join('\n');
            this.showUploadError = true;
            return;
        }

        if (validFiles.length > 0) {
            this.uploadFiles(validFiles);
        }
    }

    // Upload files to Salesforce
    async uploadFiles(files) {
        console.log('=== Uploading Files ===');
        
        this.showUploadError = false;
        this.uploadError = '';
        this.isUploading = true;

        try {
            const fileUploadData = [];
            
            for (const file of files) {
                const base64 = await this.fileToBase64(file);
                fileUploadData.push({
                    filename: file.name,
                    base64: base64,
                    contentType: file.type || 'application/octet-stream'
                });
            }

            const uploadedFileIds = await uploadFiles({
                recordId: this.recordId,
                files: fileUploadData
            });

            const fileCount = uploadedFileIds.length;
            const message = fileCount === 1 ? 
                `1 file uploaded successfully` : 
                `${fileCount} files uploaded successfully`;
            
            this.showToast('Success', message, 'success');
            
            // Refresh the file list after successful upload
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
                const base64 = reader.result.split(',')[1];
                resolve(base64);
            };
            reader.onerror = () => reject(new Error('Failed to read file'));
            reader.readAsDataURL(file);
        });
    }

    // Handle Close button click (dismiss error)
    handleCloseError() {
        this.showUploadError = false;
        this.uploadError = '';
    }

    // Enhanced file and modal handling
    handleImageError(event) {
        console.log('Image load error, falling back to file icon');
        const target = event.target;
        const container = target.parentElement;
        
        // Hide the broken image
        target.style.display = 'none';
        
        // Update the file to be treated as non-image
        const fileId = target.closest('[data-file-id]')?.dataset?.fileId;
        if (fileId) {
            this.updateFileAsNonImage(fileId);
        }
    }

    updateFileAsNonImage(fileId) {
        this.files = this.files.map(file => {
            if (file.id === fileId) {
                return { ...file, isImage: false };
            }
            return file;
        });
    }

    handleFileClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const target = event.currentTarget;
        const fileId = target.dataset.fileId;
        const file = this.files.find(f => f.id === fileId);
        
        if (file) {
            // For images, open modal. For other files, download directly
            if (file.isImage) {
                this.openFileModal(file);
            } else {
                console.log('Direct download for non-image file:', file.title);
                this.downloadFile(file.downloadUrl, file.title);
                this.showToast('Success', `Downloading ${file.title}...`, 'success');
            }
        }
    }

    handleImageClick(event) {
        // Same as handleFileClick since we unified the logic
        this.handleFileClick(event);
    }

    openFileModal(file) {
        console.log('Opening modal for image:', file.title);
        
        // Only open modal for images
        if (!file.isImage) {
            return;
        }
        
        // Set modal properties for image display
        this.modalImageName = file.title || 'Unknown File';
        this.modalImageSize = file.formattedSize || '';
        this.modalDownloadUrl = file.downloadUrl;
        this.modalImageUrl = file.previewUrl || file.downloadUrl;
        
        this.showImageModal = true;
    }

    handleCloseModal() {
        this.showImageModal = false;
        this.modalImageUrl = '';
        this.modalDownloadUrl = '';
        this.modalImageName = '';
        this.modalImageSize = '';
    }

    handleModalBackdropClick(event) {
        if (event.target.classList.contains('slds-backdrop')) {
            this.handleCloseModal();
        }
    }

    handleModalImageError(event) {
        console.log('Modal image failed to load');
        // Close modal if image fails to load
        this.handleCloseModal();
        this.showToast('Error', 'Unable to preview this image', 'error');
    }

    handleDownloadFromModal() {
        const downloadUrl = this.modalDownloadUrl || this.modalImageUrl;
        if (downloadUrl) {
            this.downloadFile(downloadUrl, this.modalImageName);
            this.showToast('Success', `Downloading ${this.modalImageName}...`, 'success');
        }
    }

    // Download method
    downloadFile(url, filename) {
        try {
            const downloadWindow = window.open(url, '_blank');
            
            if (!downloadWindow || downloadWindow.closed || typeof downloadWindow.closed === 'undefined') {
                const link = document.createElement('a');
                link.href = url;
                link.target = '_blank';
                link.rel = 'noopener noreferrer';
                
                if (url.startsWith('blob:') || url.startsWith('data:')) {
                    link.download = filename || 'download';
                }
                
                link.style.display = 'none';
                document.body.appendChild(link);
                link.click();
                
                setTimeout(() => {
                    document.body.removeChild(link);
                }, 100);
            }
            
        } catch (error) {
            try {
                window.location.href = url;
            } catch (navError) {
                this.showToast('Error', 'Unable to download file. Please try right-clicking and selecting "Save As"', 'error');
            }
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(event);
    }

    // File type helper methods
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

    isImageFile(fileExtension) {
        if (!fileExtension) return false;
        const imageExtensions = new Set(['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg']);
        return imageExtensions.has(fileExtension.toLowerCase());
    }

    isPDFFile(fileExtension) {
        if (!fileExtension) return false;
        return fileExtension.toLowerCase() === 'pdf';
    }

    canPreviewFile(fileExtension) {
        if (!fileExtension) return false;
        const previewableExtensions = new Set(['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg', 'pdf']);
        return previewableExtensions.has(fileExtension.toLowerCase());
    }

    generatePreviewUrl(file) {
        const fileExt = (file.fileExtension || '').toLowerCase();
        
        if (this.isImageFile(file.fileExtension)) {
            let rendition = 'PNG';
            if (fileExt === 'jpg' || fileExt === 'jpeg') {
                rendition = 'JPEG';
            } else if (fileExt === 'gif') {
                rendition = 'GIF';
            }
            
            const versionId = file.latestPublishedVersionId || file.id;
            const contentId = file.contentDocumentId || file.id;
            
            return `/sfsites/c/sfc/servlet.shepherd/version/renditionDownload?rendition=${rendition}&versionId=${versionId}&operationContext=CHATTER&contentId=${contentId}&page=1`;
        }
        
        return `/sfc/servlet.shepherd/document/download/${file.id}`;
    }
}