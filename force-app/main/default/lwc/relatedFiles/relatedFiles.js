import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFiles from '@salesforce/apex/RelatedFilesController.getFiles';
import getImageAsBase64 from '@salesforce/apex/RelatedFilesController.getImageAsBase64';

export default class RelatedFiles extends LightningElement {
    @api recordId;
    @api listTitle = '';
    @api initialLoadAmount = 6;
    @api relatedListIcon = '';
    
    @track allFiles = [];
    @track displayedFiles = [];
    @track isLoading = false;
    @track error = '';

    pageSize = 6;
    currentPage = 0;

    @track showImageModal = false;
    @track modalImageUrl = '';
    @track modalDownloadUrl = '';
    @track modalImageName = '';
    @track modalImageSize = '';
    @track modalImageLoadError = '';
    @track isLoadingModalImage = false;

    connectedCallback() {
        this.pageSize = this.effectiveInitialLoadAmount;
        this.loadFiles();
    }

    get computedListTitle() {
        return this.listTitle || 'Files';
    }

    get listTitleWithCount() {
        return `${this.computedListTitle} (${this.allFiles.length})`;
    }

    get hasError() {
        return !!this.error;
    }

    get hasFiles() {
        return !this.isLoading && !this.hasError && this.displayedFiles.length > 0;
    }

    get hasMoreItems() {
        const totalDisplayed = (this.currentPage + 1) * this.pageSize;
        return totalDisplayed < this.allFiles.length;
    }

    get remainingItemsCount() {
        const totalDisplayed = (this.currentPage + 1) * this.pageSize;
        const remaining = this.allFiles.length - totalDisplayed;
        return Math.min(remaining, this.pageSize);
    }

    get viewMoreButtonLabel() {
        return this.remainingItemsCount > 0 ? 
            `View More (${this.remainingItemsCount})` : 'View More';
    }

    get hasModalImageError() {
        return !!this.modalImageLoadError;
    }

    get effectiveInitialLoadAmount() {
        const amount = parseInt(this.initialLoadAmount, 10);
        return Math.min(Math.max(amount || 6, 1), 15);
    }

    // Simple check - only show icon if it's provided and properly formatted
    get shouldShowIcon() {
        return this.relatedListIcon && this.relatedListIcon.includes(':');
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await this.loadFiles();
            this.showToast('Success', 'Files refreshed', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to refresh files: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleViewMore() {
        this.currentPage++;
        this.updateDisplayedItems();
    }

    async loadFiles() {
        if (!this.recordId) {
            this.error = 'No record ID provided';
            return;
        }

        this.isLoading = true;
        this.error = '';

        try {
            const result = await getFiles({
                recordId: this.recordId,
                sortField: 'CreatedDate',
                sortDirection: 'DESC',
                limitCount: 50
            });
            
            this.allFiles = result || [];
            this.currentPage = 0;
            this.updateDisplayedItems();
            
            if (this.allFiles.length === 0) {
                this.error = 'No files found for this case';
            }
            
        } catch (error) {
            this.error = 'Error loading files: ' + (error.body?.message || error.message);
            this.allFiles = [];
            this.displayedFiles = [];
        } finally {
            this.isLoading = false;
        }
    }

    updateDisplayedItems() {
        if (this.currentPage === 0) {
            const initialAmount = this.effectiveInitialLoadAmount;
            this.displayedFiles = this.allFiles.slice(0, initialAmount);
            this.currentPage = Math.ceil(initialAmount / this.pageSize) - 1;
        } else {
            const endIndex = (this.currentPage + 1) * this.pageSize;
            this.displayedFiles = this.allFiles.slice(0, endIndex);
        }
    }

    async handleAttachmentClick(event) {
        event.preventDefault();
        const target = event.currentTarget;
        const fileName = target.dataset.name;
        const fileSize = target.dataset.size;
        const contentDocumentId = target.dataset.id;
        const isImage = target.dataset.isImage === 'true';
        const downloadUrl = target.dataset.downloadUrl;
        
        if (isImage) {
            this.modalImageName = fileName;
            this.modalImageSize = fileSize;
            this.modalImageLoadError = '';
            this.modalImageUrl = '';
            this.isLoadingModalImage = true;
            this.showImageModal = true;
            
            try {
                const base64Url = await getImageAsBase64({ contentDocumentId });
                
                if (base64Url) {
                    this.modalImageUrl = base64Url;
                    this.modalDownloadUrl = downloadUrl;
                    this.isLoadingModalImage = false;
                } else {
                    throw new Error('No image data returned');
                }
            } catch (error) {
                this.modalImageLoadError = 'Failed to load image: ' + (error.body?.message || error.message);
                this.isLoadingModalImage = false;
            }
        } else {
            this.handleDirectDownload(downloadUrl, fileName);
        }
    }

    handleDirectDownload(downloadUrl, fileName) {
        if (downloadUrl) {
            const link = document.createElement('a');
            link.href = downloadUrl;
            link.download = fileName || 'download';
            
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Download Started',
                    message: `Downloading ${fileName}`,
                    variant: 'success'
                })
            );
        } else {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Download Error',
                    message: 'Unable to download file - no URL available',
                    variant: 'error'
                })
            );
        }
    }

    handleModalImageError(event) {
        const img = event.target;
        const failedUrl = img.src;
        
        this.modalImageLoadError = `Failed to load image: ${failedUrl}`;
        
        if (failedUrl === this.modalImageUrl && this.modalDownloadUrl && failedUrl !== this.modalDownloadUrl) {
            this.modalImageUrl = this.modalDownloadUrl;
        }
    }

    handleModalImageLoad(event) {
        this.modalImageLoadError = '';
    }

    handleCloseModal() {
        this.showImageModal = false;
        this.isLoadingModalImage = false;
        this.modalImageUrl = '';
        this.modalDownloadUrl = '';
        this.modalImageName = '';
        this.modalImageSize = '';
        this.modalImageLoadError = '';
    }

    handleModalBackdropClick(event) {
        if (event.target.classList.contains('slds-backdrop')) {
            this.handleCloseModal();
        }
    }

    handleDownloadFromModal() {
        if (this.modalDownloadUrl) {
            this.handleDirectDownload(this.modalDownloadUrl, this.modalImageName);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}