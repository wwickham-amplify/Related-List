import { LightningElement, api, track } from 'lwc';
import getObjectConfiguration from '@salesforce/apex/RelatedListControllerLWR.getObjectConfiguration';
import getRelatedRecords from '@salesforce/apex/RelatedListControllerLWR.getRelatedRecords';
import getIconName from '@salesforce/apex/RelatedListControllerLWR.getIconName';

export default class RelatedListLWR extends LightningElement {
    // Public properties with smart defaults
    @api recordId; // The parent record ID
    @api selectedObject = 'Case'; // The object API name to display
    @api relatedListLabel = ''; // The display label for the list (auto-generated if blank)
    @api fieldSetName = ''; // The field set API name to use for columns (smart defaults if blank)
    @api recordLimit = 0; // Number of records to show (smart defaults if 0)
    @api targetSitePage = ''; // Site page selection from admin
    @api titleTextStyle = 'Heading 3'; // Title typography level

    
    // Private reactive properties
    @track records = [];
    @track displayedRecords = [];
    @track isLoading = false;
    @track errorMessage = '';
    @track hasError = false;
    @track objectConfig = null;
    @track sortField = '';
    @track sortDirection = 'ASC';
    @track actualIconName = 'standard:record'; // Will be populated by loadIconName
    
    // Pagination properties
    @track currentPage = 0;
    pageSize = 6;

    // Lifecycle hooks
    connectedCallback() {
        // Set page size from record limit
        this.pageSize = this.computedRecordLimit;
        
        // Validate configuration
        const configErrors = this.validateConfiguration();
        if (configErrors) {
            console.warn('Configuration Issues:', configErrors);
        }
        
        this.loadIconName();
        this.loadConfiguration();
    }

    // Load icon name directly (not cached)
    async loadIconName() {
        try {
            const iconName = await getIconName({ sObjectName: this.selectedObject });
            this.actualIconName = iconName;
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

    // Navigation helper methods
    get hasTargetPage() {
        return this.targetSitePage && this.targetSitePage.trim() !== '';
    }

    getSiteBaseUrl() {
        // Get the current site's base URL
        const currentUrl = window.location.href;
        const url = new URL(currentUrl);
        
        if (url.hostname.includes('.my.site.com') || 
            url.hostname.includes('.force.com') ||
            url.hostname.includes('salesforce-experience.com')) {
            
            // Salesforce-hosted site (including sandbox URLs)
            const pathParts = url.pathname.split('/').filter(part => part !== '');
            
            if (pathParts.length > 0) {
                const sitePath = pathParts[0];
                const siteBaseUrl = `${url.origin}/${sitePath}`;
                return siteBaseUrl;
            }
            
            return url.origin;
        } else {
            // Custom domain - might still have a path
            const pathParts = url.pathname.split('/').filter(part => part !== '');
            if (pathParts.length > 0) {
                const potentialSitePath = pathParts[0];
                const siteBaseUrl = `${url.origin}/${potentialSitePath}`;
                return siteBaseUrl;
            }
            
            return url.origin;
        }
    }

    constructRecordUrl(recordId) {
        if (!this.hasTargetPage || !recordId) {
            return null;
        }

        try {
            const siteBaseUrl = this.getSiteBaseUrl();
            let pagePath = this.targetSitePage.trim();
            
            // Remove leading slash if present
            if (pagePath.startsWith('/')) {
                pagePath = pagePath.substring(1);
            }
            
            // Replace :recordId parameter with actual record ID
            // Handle various URL parameter patterns
            pagePath = pagePath.replace(/:recordId/g, recordId);
            pagePath = pagePath.replace(/\{!recordId\}/g, recordId); // Handle merge field syntax too
            
            // If the path contains :recordName, remove it since we're not using it
            pagePath = pagePath.replace(/\/:recordName\)?/g, ''); // Remove optional recordName parameter
            pagePath = pagePath.replace(/:recordName/g, ''); // Remove any remaining recordName references
            
            const fullUrl = `${siteBaseUrl}/${pagePath}`;
            
            return fullUrl;
        } catch (error) {
            console.error('Error constructing record URL:', error);
            return null;
        }
    }

    // Computed properties
    get listTitle() {
        const count = this.records.length;
        return `${this.computedRelatedListLabel} (${count})`;
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

    get listIcon() {
        return this.actualIconName || this.objectConfig?.icon || 'standard:record';
    }

    get emptyStateMessage() {
        return `No ${this.computedRelatedListLabel.toLowerCase()} found.`;
    }

    get displayedRecords() {
        return this.displayedRecords || [];
    }

    get hasRecords() {
        return !this.isLoading && !this.hasError && this.records.length > 0;
    }

    get hasNoRecords() {
        return !this.isLoading && !this.hasError && this.records.length === 0;
    }

    get hasMoreRecords() {
        const totalDisplayed = (this.currentPage + 1) * this.pageSize;
        return totalDisplayed < this.records.length;
    }

    get remainingRecordsCount() {
        const totalDisplayed = (this.currentPage + 1) * this.pageSize;
        const remaining = this.records.length - totalDisplayed;
        return Math.min(remaining, this.pageSize);
    }

    get viewMoreButtonLabel() {
        return this.remainingRecordsCount > 0 ? 
            `View More (${this.remainingRecordsCount})` : 'View More';
    }

    get showCardView() {
        // Generic related lists use table view only
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
                this.objectConfig.columns.forEach((col, index) => {
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
                    
                    // Determine if this is the first field (primary field for linking)
                    const isFirstField = index === 0;
                    const shouldBeClickable = isFirstField && this.hasTargetPage;
                    const recordUrl = shouldBeClickable ? this.constructRecordUrl(record.id) : null;
                    
                    rowData.cells.push({
                        fieldName: col.apiName,
                        value: displayValue,
                        isLookup: col.isLookup && !isFirstField, // Only non-first-field lookups get lookup styling
                        isClickableRecord: shouldBeClickable && recordUrl, // First field with valid URL
                        recordUrl: recordUrl,
                        label: col.label
                    });
                });
            }
            
            return rowData;
        });
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

            this.records = records;
            this.currentPage = 0;
            this.updateDisplayedRecords();

        } catch (error) {
            console.error('Error loading records:', error);
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // Pagination methods
    updateDisplayedRecords() {
        if (this.currentPage === 0) {
            // Initial load - show the configured limit
            this.displayedRecords = this.records.slice(0, this.pageSize);
        } else {
            // Load more - show cumulative records
            const endIndex = (this.currentPage + 1) * this.pageSize;
            this.displayedRecords = this.records.slice(0, endIndex);
        }
        console.log(`Displaying ${this.displayedRecords.length} of ${this.records.length} records (page ${this.currentPage})`);
    }

    handleViewMore() {
        this.currentPage++;
        this.updateDisplayedRecords();
    }

    handleRefresh() {
        this.refreshRecords();
    }

    handleSort(event) {
        const fieldName = event.currentTarget.dataset.fieldName;

        // Toggle sort direction if same field, otherwise default to ASC
        if (this.sortField === fieldName) {
            this.sortDirection = this.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        } else {
            this.sortField = fieldName;
            this.sortDirection = 'ASC';
        }

        this.loadRecords();
    }

    handleRecordNavigation(event) {
        event.preventDefault();
        const recordUrl = event.currentTarget.dataset.recordUrl;
        
        if (recordUrl) {
            window.location.href = recordUrl;
        }
    }

    handleError(error) {
        this.hasError = true;
        this.errorMessage = error.body?.message || error.message || 'An unexpected error occurred';
        console.error('Component error:', this.errorMessage);
    }

    handleErrorNavigation() {
        window.location.href = '/error';
    }

    // Utility methods

    // Public methods for parent components
    @api
    refreshRecords() {
        this.currentPage = 0;
        this.loadRecords();
    }

    @api
    changeObject(newObjectApiName) {
        this.selectedObject = newObjectApiName;
        this.currentPage = 0;
        this.displayedRecords = [];
        this.loadIconName();
        this.loadConfiguration();
    }
    
    // Configuration validation
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
}