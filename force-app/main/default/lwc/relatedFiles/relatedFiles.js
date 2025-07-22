import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFiles from '@salesforce/apex/RelatedFilesController.getFiles';

export default class RelatedFiles extends LightningElement {
    @api recordId;
    @api listTitle = '';
    @api recordLimit = 8;
    @api disableFileUpload = false;
    @api maxFileSize = 25;
    @api acceptedFileTypes = '';
    @api showThumbnails = false;
    @api cardSize = 'medium';
    
    @track files = [];
    @track isLoading = false;
    @track errorMessage = '';
    @track hasError = false;

    connectedCallback() {
        console.log('=== RelatedFiles Connected (Simple Debug Version) ===');
        console.log('Record ID:', this.recordId);
        this.loadFiles();
    }

    get computedListTitle() {
        return this.listTitle || 'Files';
    }

    get listTitleWithCount() {
        return `${this.computedListTitle} (${this.files.length})`;
    }

    get hasFiles() {
        return !this.isLoading && !this.hasError && this.files.length > 0;
    }

    get hasNoFiles() {
        return !this.isLoading && !this.hasError && this.files.length === 0;
    }

    async loadFiles() {
        if (!this.recordId) {
            console.warn('No recordId provided');
            return;
        }

        console.log('=== Loading Files (Simple Version) ===');
        this.isLoading = true;
        this.hasError = false;

        try {
            const rawFiles = await getFiles({
                recordId: this.recordId,
                sortField: 'CreatedDate',
                sortDirection: 'DESC',
                limitCount: 10
            });

            console.log('Raw response from Apex:', rawFiles);
            
            if (!rawFiles || !Array.isArray(rawFiles)) {
                throw new Error('Invalid response from getFiles');
            }

            // Minimal processing - just log what we get
            this.files = rawFiles.map((file, index) => {
                console.log(`File ${index}:`, {
                    id: file.id,
                    title: file.title,
                    fileExtension: file.fileExtension,
                    hasFields: !!file.fields
                });

                // Return the file with computed icon
                return {
                    id: file.id || 'unknown-id',
                    title: file.title || 'Unknown File',
                    fileExtension: file.fileExtension || '',
                    formattedSize: file.formattedSize || '0 Bytes',
                    icon: this.getFileIcon(file.fileExtension || '')
                };
            });

            console.log('Processed files:', this.files);

        } catch (error) {
            console.error('Error in loadFiles:', error);
            this.hasError = true;
            this.errorMessage = error.message || 'Unknown error';
        } finally {
            this.isLoading = false;
        }
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
}