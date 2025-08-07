import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
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
        console.log('=== RelatedList Connected ===');
        console.log('Record ID:', this.recordId);
        console.log('Selected Object:', this.selectedObject);
        console.log('Target Site Page:', this.targetSitePage);
        console.log('=== Smart Defaults Applied ===');
        console.log('Related List Label:', `"${this.relatedListLabel}" → "${this.computedRelatedListLabel}"`);
        console.log('Field Set Name:', `"${this.fieldSetName}" → "${this.computedFieldSetName}"`);
        console.log('Record Limit:', `${this.recordLimit} → ${this.computedRecordLimit}`);
        
        // Set page size from record limit
        this.pageSize = this.computedRecordLimit;
        
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

    // Navigation helper methods
    get hasTargetPage() {
        return this.targetSitePage && this.targetSitePage.trim() !== '';
    }

    getSiteBaseUrl() {
        // Get the current site's base URL
        const currentUrl = window.location.href;
        const url = new URL(currentUrl);
        
        console.log('Current URL for site base extraction:', currentUrl);
        console.log('URL pathname:', url.pathname);
        
        // For Experience Cloud sites, we need to capture the full site path
        // Examples:
        // Sandbox: https://amplify--dev.sandbox.my.site.com/internalsupportlwr/
        // Production: https://amplify.my.site.com/customerportal/
        // Custom domain: https://portal.company.com/
        
        if (url.hostname.includes('.my.site.com') || 
            url.hostname.includes('.force.com') ||
            url.hostname.includes('salesforce-experience.com')) {
            
            // Salesforce-hosted site (including sandbox URLs)
            const pathParts = url.pathname.split('/').filter(part => part !== '');
            console.log('Path parts:', pathParts);
            
            if (pathParts.length > 0) {
                // Include the full site path
                // For sandbox: /internalsupportlwr/
                // For production: /customerportal/
                const sitePath = pathParts[0];
                const siteBaseUrl = `${url.origin}/${sitePath}`;
                console.log('Detected site base URL:', siteBaseUrl);
                return siteBaseUrl;
            }
            
            console.log('No path parts found, using origin only');
            return url.origin;
        } else {
            // Custom domain - might still have a path
            const pathParts = url.pathname.split('/').filter(part => part !== '');
            if (pathParts.length > 0) {
                // Check if we're in a subpath (like /portal/)
                const potentialSitePath = pathParts[0];
                const siteBaseUrl = `${url.origin}/${potentialSitePath}`;
                console.log('Custom domain with path detected:', siteBaseUrl);
                return siteBaseUrl;
            }
            
            console.log('Custom domain root detected:', url.origin);
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
            console.log('Constructed URL:', fullUrl, 'from base:', siteBaseUrl, 'and path:', pagePath);
            
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
        console.log('View More clicked - loading next page');
        this.currentPage++;
        this.updateDisplayedRecords();
    }
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

    handleRecordNavigation(event) {
        event.preventDefault();
        const recordUrl = event.currentTarget.dataset.recordUrl;
        
        if (recordUrl) {
            console.log('Navigating to record:', recordUrl);
            // Use window.location for Experience Cloud navigation
            window.location.href = recordUrl;
        }
    }

    handleRowAction(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const action = event.currentTarget.dataset.action;
        console.log('Row action:', action, 'for record:', recordId);

        if (action === 'preview') {
            this.showToast('Info', 'Preview functionality coming in future phases', 'info');
        } else if (action === 'navigate') {
            // This is now handled by handleRecordNavigation for clickable record links
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
        this.currentPage = 0;
        this.loadRecords();
    }

    @api
    changeObject(newObjectApiName) {
        console.log('Changing object to:', newObjectApiName);
        this.selectedObject = newObjectApiName;
        this.currentPage = 0;
        this.displayedRecords = [];
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
            recordLimit: this.getRecordLimitHelp(),
            navigation: this.getNavigationHelp()
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

    getNavigationHelp() {
        return `Current target page: "${this.targetSitePage || 'None selected'}". When a page is selected, the first field in your Field Set becomes a clickable link. The component automatically handles :recordId parameter replacement in the URL.`;
    }
}