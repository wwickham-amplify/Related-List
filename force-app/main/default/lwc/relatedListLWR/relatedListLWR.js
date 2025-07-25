import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getObjectConfiguration from '@salesforce/apex/RelatedListController.getObjectConfiguration';
import getRelatedRecords from '@salesforce/apex/RelatedListController.getRelatedRecords';
import getIconName from '@salesforce/apex/RelatedListController.getIconName';

export default class RelatedListLWR extends LightningElement {
    // Public properties with smart defaults
    @api recordId; // The parent record ID
    @api selectedObject = 'Case'; // The object API name to display
    @api relatedListLabel = ''; // The display label for the list (auto-generated if blank)
    @api fieldSetName = ''; // The field set API name to use for columns (smart defaults if blank)
    @api recordLimit = 0; // Number of records to show (smart defaults if 0)
    
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
        console.log('=== Smart Defaults Applied ===');
        console.log('Related List Label:', `"${this.relatedListLabel}" → "${this.computedRelatedListLabel}"`);
        console.log('Field Set Name:', `"${this.fieldSetName}" → "${this.computedFieldSetName}"`);
        console.log('Record Limit:', `${this.recordLimit} → ${this.computedRecordLimit}`);
        
        // Validate configuration
        const configErrors = this.validateConfiguration();
        if (configErrors) {
            console.warn('Configuration Issues:', configErrors);
        } else {
            console.log('Configuration validated successfully');
        }
        
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

    // Computed properties with smart defaults
    get computedRelatedListLabel() {
        if (this.relatedListLabel) {
            return this.relatedListLabel;
        }
        
        // Auto-generate labels based on object type
        const labelMap = {
            'Knowledge__kav': 'Knowledge Articles',
            'Internal_Asset_Request__c': 'Internal Asset Requests',
            'Case': 'Related Cases',
            'Account': 'Related Accounts',
            'Contact': 'Related Contacts',
            'Opportunity': 'Related Opportunities'
        };
        
        return labelMap[this.selectedObject] || 'Related Records';
    }
    
    get computedFieldSetName() {
        if (this.fieldSetName) {
            return this.fieldSetName;
        }
        
        // Smart defaults based on object type
        const fieldSetMap = {
            'Knowledge__kav': 'KnowledgeRelatedList',
            'Internal_Asset_Request__c': 'AssetRequestRelatedList',
            'Case': 'CaseRelatedList',
            'Account': 'AccountRelatedList',
            'Contact': 'ContactRelatedList',
            'Opportunity': 'OpportunityRelatedList'
        };
        
        return fieldSetMap[this.selectedObject] || 'RelatedList';
    }
    
    get computedRecordLimit() {
        if (this.recordLimit > 0) {
            return this.recordLimit;
        }
        
        // Smart defaults: Default 6 records for most objects
        return 6;
    }

    // Computed properties
    get listTitle() {
        const count = this.records.length;
        return `${this.computedRelatedListLabel} (${count})`;
    }

    get listIcon() {
        return this.actualIconName || this.objectConfig?.icon || 'standard:record';
    }

    get emptyStateMessage() {
        return `No ${this.computedRelatedListLabel.toLowerCase()} found.`;
    }

    get showActionButton() {
        // Hide action button for generic related lists - will be enhanced in future phases
        return false;
    }

    get actionButtonLabel() {
        return 'Add Record';
    }

    get actionButtonIcon() {
        return 'utility:add';
    }

    get displayedRecords() {
        return this.records.slice(0, this.computedRecordLimit);
    }

    get hasRecords() {
        return !this.isLoading && !this.hasError && this.records.length > 0;
    }

    get hasNoRecords() {
        return !this.isLoading && !this.hasError && this.records.length === 0;
    }

    get hasMoreRecords() {
        return this.records.length > this.computedRecordLimit;
    }

    get showCardView() {
        // Generic related lists use table view by default
        return false;
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
                fieldSetName: this.computedFieldSetName
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
        this.showToast('Info', 'Record creation functionality coming in later phases', 'info');
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
            this.showToast('Info', 'Preview functionality coming in future phases', 'info');
        } else if (action === 'navigate') {
            this.showToast('Info', 'Record navigation functionality coming in future phases', 'info');
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
    
    // Configuration validation and help methods
    validateConfiguration() {
        const errors = [];
        
        if (!this.recordId) {
            errors.push('Record ID is required');
        }
        
        if (!this.selectedObject) {
            errors.push('Object API Name is required');
        }
        
        return errors.length > 0 ? errors : null;
    }
    
    getConfigurationHelp() {
        const help = {
            objectSpecific: this.getObjectSpecificHelp(),
            fieldSet: this.getFieldSetHelp(),
            recordLimit: this.getRecordLimitHelp()
        };
        
        return help;
    }
    
    getObjectSpecificHelp() {
        const helpMap = {
            'Knowledge__kav': 'Displays Knowledge Articles linked via CaseArticle junction object. Recommended Field Set: KnowledgeRelatedList with Title, Summary, Article_Type.',
            'Internal_Asset_Request__c': 'Displays Internal Asset Request records. Recommended Field Set: AssetRequestRelatedList with Name, Status, Request_Type.',
            'Case': 'Displays related Case records. Create a Field Set with relevant fields like CaseNumber, Subject, Status, Priority.',
            'Account': 'Displays related Account records. Create a Field Set with relevant fields like Name, Type, Industry.',
            'Contact': 'Displays related Contact records. Create a Field Set with relevant fields like Name, Title, Email, Phone.',
            'Opportunity': 'Displays related Opportunity records. Create a Field Set with relevant fields like Name, Stage, Amount, Close_Date.'
        };
        
        return helpMap[this.selectedObject] || 'Generic object display. Create a Field Set in Setup → Object Manager → [Object] → Field Sets with the fields you want to show.';
    }
    
    getFieldSetHelp() {
        return `Current smart default: "${this.computedFieldSetName}". Override this by specifying a custom Field Set name, or create the recommended Field Set in Setup → Object Manager → ${this.selectedObject} → Field Sets.`;
    }
    
    getRecordLimitHelp() {
        return `Current smart default: ${this.computedRecordLimit} records. Adjust this based on your layout and user experience needs.`;
    }
}