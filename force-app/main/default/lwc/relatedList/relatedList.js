import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getObjectConfiguration from '@salesforce/apex/RelatedListController.getObjectConfiguration';
import getRelatedRecords from '@salesforce/apex/RelatedListController.getRelatedRecords';
import getIconName from '@salesforce/apex/RelatedListController.getIconName';

export default class RelatedList extends LightningElement {
    // Public properties
    @api recordId; // The parent record ID
    @api selectedObject = 'Files'; // The object API name to display
    @api relatedListLabel = 'Related Records'; // The display label for the list
    @api fieldSetName = 'RelatedList'; // The field set API name to use for columns
    @api recordLimit = 6; // Number of records to show
    
    // Private reactive properties
    @track records = [];
    @track isLoading = false;
    @track errorMessage = '';
    @track hasError = false;
    @track objectConfig = null;
    @track sortField = '';
    @track sortDirection = 'ASC';
    @track wrapText = false;
    @track actualIconName = 'standard:record'; // Will be populated by loadIconName

    // Lifecycle hooks
    connectedCallback() {
        console.log('=== RelatedList Connected ===');
        console.log('Record ID:', this.recordId);
        console.log('Selected Object:', this.selectedObject);
        
        this.loadIconName();
        this.loadConfiguration();
    }

    // Load icon name directly (not cached)
    async loadIconName() {
        try {
            console.log('Loading icon name for:', this.selectedObject);
            const iconName = await getIconName({ sObjectName: this.selectedObject });
            this.actualIconName = iconName;
            console.log('Icon loaded for ' + this.selectedObject + ': ' + iconName);
        } catch (error) {
            console.error('Error loading icon:', error);
            this.actualIconName = this.selectedObject.endsWith('__c') ? 'standard:custom' : 'standard:record';
        }
    }

    // Computed properties
    get listTitle() {
        const count = this.records.length;
        return `${this.relatedListLabel} (${count})`;
    }

    get listIcon() {
        return this.actualIconName || this.objectConfig?.icon || 'standard:record';
    }

    get emptyStateMessage() {
        return `No ${this.relatedListLabel.toLowerCase()} found.`;
    }

    get showActionButton() {
        return this.selectedObject === 'Files' || this.objectConfig?.isSpecialObject;
    }

    get actionButtonLabel() {
        return this.selectedObject === 'Files' ? 'Add Files' : 'Add Record';
    }

    get actionButtonIcon() {
        return this.selectedObject === 'Files' ? 'utility:attach' : 'utility:add';
    }

    get displayedRecords() {
        return this.records.slice(0, this.recordLimit);
    }

    get hasRecords() {
        return !this.isLoading && !this.hasError && this.records.length > 0;
    }

    get hasNoRecords() {
        return !this.isLoading && !this.hasError && this.records.length === 0;
    }

    get hasMoreRecords() {
        return this.records.length > this.recordLimit;
    }

    get showCardView() {
        return this.selectedObject === 'Files' || this.objectConfig?.isSpecialObject;
    }

    get showListView() {
        return !this.showCardView && this.objectConfig?.columns?.length > 0;
    }

    get tableColumns() {
        if (!this.objectConfig?.columns) return [];
        
        return this.objectConfig.columns.map(col => ({
            ...col,
            sortedBy: col.apiName,
            sortedDirection: this.sortField === col.apiName ? this.sortDirection : null,
            sortedDirectionAsc: this.sortField === col.apiName && this.sortDirection === 'ASC'
        }));
    }

    get tableData() {
        return this.displayedRecords.map(record => {
            const rowData = { 
                id: record.id,
                cells: []
            };
            
            if (this.objectConfig?.columns) {
                this.objectConfig.columns.forEach(col => {
                    let value = record.fields[col.apiName];
                    let displayValue = '';
                    
                    // Format different field types
                    if (value !== null && value !== undefined) {
                        if (col.type === 'DATETIME' || col.type === 'DATE') {
                            displayValue = new Date(value).toLocaleDateString();
                        } else if (col.isLookup && typeof value === 'object') {
                            // Handle lookup field display
                            displayValue = value.Name || value.Id;
                        } else {
                            displayValue = String(value);
                        }
                    }
                    
                    rowData.cells.push({
                        fieldName: col.apiName,
                        value: displayValue,
                        isLookup: col.isLookup,
                        label: col.label
                    });
                });
            }
            
            return rowData;
        });
    }

    get textDisplayClass() {
        return this.wrapText ? 'slds-truncate' : 'slds-line-clamp_x-small';
    }

    // Methods
    async loadConfiguration() {
        if (!this.recordId) {
            console.warn('No recordId provided');
            return;
        }

        console.log('=== Loading Configuration ===');
        this.isLoading = true;
        this.hasError = false;

        try {
            const config = await getObjectConfiguration({
                objectApiName: this.selectedObject,
                parentRecordId: this.recordId,
                fieldSetName: this.fieldSetName
            });

            console.log('Object configuration:', config);
            this.objectConfig = config;

            // Set default sort field
            if (config.columns && config.columns.length > 0) {
                this.sortField = config.columns[0].apiName;
            }

            await this.loadRecords();

        } catch (error) {
            console.error('Error loading configuration:', error);
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadRecords() {
        if (!this.objectConfig) {
            console.warn('No object configuration available');
            return;
        }

        console.log('=== Loading Records ===');
        this.isLoading = true;

        try {
            const fieldNames = this.objectConfig.columns?.map(col => col.apiName) || ['Name'];

            const records = await getRelatedRecords({
                objectApiName: this.selectedObject,
                parentRecordId: this.recordId,
                relationshipField: this.objectConfig.relationshipField,
                fieldNames: fieldNames,
                sortField: this.sortField,
                sortDirection: this.sortDirection,
                limitCount: 50 // Get more than display limit for sorting
            });

            console.log('Records loaded:', records.length);
            this.records = records;

        } catch (error) {
            console.error('Error loading records:', error);
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // Event handlers
    handleActionClick() {
        console.log('Action button clicked for:', this.selectedObject);
        
        if (this.selectedObject === 'Files') {
            // TODO: Implement file upload in Phase 2
            this.showToast('Info', 'File upload functionality coming in Phase 2', 'info');
        } else {
            // TODO: Implement record creation for other objects
            this.showToast('Info', 'Record creation functionality coming in later phases', 'info');
        }
    }

    handleSort(event) {
        const fieldName = event.currentTarget.dataset.fieldName;
        console.log('Sort requested for field:', fieldName);

        // Toggle sort direction if same field, otherwise default to ASC
        if (this.sortField === fieldName) {
            this.sortDirection = this.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        } else {
            this.sortField = fieldName;
            this.sortDirection = 'ASC';
        }

        console.log('New sort:', this.sortField, this.sortDirection);
        this.loadRecords();
    }

    handleTextDisplay(event) {
        const action = event.detail.value;
        console.log('Text display action:', action);
        
        if (action === 'wrap') {
            this.wrapText = true;
        } else if (action === 'clip') {
            this.wrapText = false;
        }
    }

    handleRowAction(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const action = event.currentTarget.dataset.action;
        console.log('Row action:', action, 'for record:', recordId);

        if (action === 'preview') {
            // TODO: Implement preview modal in Phase 2
            this.showToast('Info', 'Preview functionality coming in Phase 2', 'info');
        } else if (action === 'navigate') {
            // TODO: Implement record navigation
            this.showToast('Info', 'Record navigation functionality coming in later phases', 'info');
        }
    }

    handleViewAll() {
        console.log('View All clicked for:', this.selectedObject);
        
        try {
            let url = '';
            
            if (this.selectedObject === 'Internal_Asset_Request__c') {
                url = `/internal-asset-product/related/${this.recordId}/Case__c`;
            } else if (this.selectedObject === 'Knowledge__kav') {
                url = `/article/related/${this.recordId}/CaseArticle`;
            } else {
                url = `/related-list/${this.selectedObject}/${this.recordId}`;
            }
            
            console.log('Would navigate to:', url);
            this.showToast('Info', `Would navigate to: ${url}`, 'info');
            
            // TODO: Implement actual navigation in later phases
            // window.location.href = url;
            
        } catch (error) {
            console.error('Error navigating to View All:', error);
            this.handleError(error);
        }
    }

    handleError(error) {
        this.hasError = true;
        this.errorMessage = error.body?.message || error.message || 'An unexpected error occurred';
        console.error('Component error:', this.errorMessage);
    }

    handleErrorNavigation() {
        console.log('Navigating to error page');
        window.location.href = '/error';
    }

    // Utility methods
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    // Public methods for parent components
    @api
    refreshRecords() {
        console.log('Manual refresh requested');
        this.loadRecords();
    }

    @api
    changeObject(newObjectApiName) {
        console.log('Changing object to:', newObjectApiName);
        this.selectedObject = newObjectApiName;
        this.loadIconName();
        this.loadConfiguration();
    }
}