import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { getRelatedListInfo, getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { getRecord } from 'lightning/uiRecordApi';

export default class RelatedListLWR extends NavigationMixin(LightningElement) {
    @api recordId; // Parent record ID
    @api relatedListId = 'Tasks'; // Related list API name
    @api relatedListLabel = ''; // Optional custom label
    @api recordLimit = 6; // Number of records to display
    
    // State management
    @track sortedBy = null;
    @track sortedDirection = 'asc';

    // Wire the parent record to get object type automatically
    @wire(getRecord, { recordId: '$recordId', fields: ['Id'] })
    parentRecord;

    // Wire related list metadata
    @wire(getRelatedListInfo, {
        parentObjectApiName: '$parentObjectApiName',
        relatedListId: '$relatedListId'
    })
    relatedListInfo;

    // Wire related list records
    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: '$relatedListId',
        fields: '$fieldNames',
        sortBy: '$sortBy',
        pageSize: '$pageSize'
    })
    relatedListRecords;

    // Computed properties for wire parameters
    get parentObjectApiName() {
        // Add error handling and debugging
        const apiName = this.parentRecord?.data?.apiName;
        console.log('Parent Object API Name:', apiName);
        return apiName;
    }

    get fieldNames() {
        // Get field names from columns, fallback to basic fields
        console.log('Related List Info:', this.relatedListInfo);
        if (this.relatedListInfo?.data?.displayColumns?.length > 0) {
            const fields = this.relatedListInfo.data.displayColumns.map(col => col.fieldApiName);
            console.log('Field Names from LDS:', fields);
            return fields;
        }
        console.log('No fields from LDS, using empty array');
        return []; // LDS will use default fields
    }

    get sortBy() {
        if (this.sortedBy) {
            return [{
                fieldApiName: this.sortedBy,
                sortDirection: this.sortedDirection.toUpperCase()
            }];
        }
        return [];
    }

    get pageSize() {
        return this.recordLimit + 10; // Get extra records to show "View All"
    }

    // Computed properties for display
    get isLoading() {
        return this.parentRecord?.loading || 
               this.relatedListInfo?.loading || 
               this.relatedListRecords?.loading;
    }

    get hasError() {
        const hasWireError = this.parentRecord?.error || 
                            this.relatedListInfo?.error || 
                            this.relatedListRecords?.error;
        
        // Log errors for debugging
        if (hasWireError) {
            console.error('LDS Wire Error:', {
                parentRecord: this.parentRecord?.error,
                relatedListInfo: this.relatedListInfo?.error,
                relatedListRecords: this.relatedListRecords?.error
            });
        }
        
        return hasWireError;
    }

    get errorMessage() {
        const error = this.parentRecord?.error || 
                     this.relatedListInfo?.error || 
                     this.relatedListRecords?.error;
        return error?.body?.message || error?.message || 'An unexpected error occurred';
    }

    get relatedListMetadata() {
        return this.relatedListInfo?.data;
    }

    get headerActions() {
        return this.relatedListMetadata?.actions || [];
    }

    get columns() {
        const cols = this.relatedListMetadata?.displayColumns || [];
        return cols.map(col => ({
            ...col,
            sortedBy: col.fieldApiName,
            sortedDirection: this.sortedBy === col.fieldApiName ? this.sortedDirection : null,
            sortedDirectionAsc: this.sortedBy === col.fieldApiName && this.sortedDirection === 'asc'
        }));
    }

    get recordActions() {
        return this.relatedListMetadata?.recordActions || [];
    }

    get records() {
        return this.relatedListRecords?.data?.records || [];
    }

    get listTitle() {
        const label = this.relatedListLabel || this.relatedListMetadata?.label || this.relatedListId;
        const count = this.records.length;
        return `${label} (${count})`;
    }

    get listIcon() {
        return this.relatedListMetadata?.icon || 'standard:record';
    }

    get hasRecords() {
        return !this.isLoading && !this.hasError && this.records.length > 0;
    }

    get hasNoRecords() {
        return !this.isLoading && !this.hasError && this.records.length === 0;
    }

    get displayedRecords() {
        return this.records.slice(0, this.recordLimit);
    }

    get hasMoreRecords() {
        return this.records.length > this.recordLimit;
    }

    get emptyStateMessage() {
        const label = this.relatedListLabel || this.relatedListMetadata?.label || 'records';
        return `No ${label.toLowerCase()} found.`;
    }

    get showHeaderActions() {
        return this.headerActions && this.headerActions.length > 0;
    }

    get primaryAction() {
        return this.headerActions.length > 0 ? this.headerActions[0] : null;
    }

    get secondaryActions() {
        return this.headerActions.length > 1 ? this.headerActions.slice(1) : [];
    }

    get showMultipleActions() {
        return this.headerActions.length > 1;
    }

    // Table data for display
    get tableData() {
        return this.displayedRecords.map(record => {
            const row = {
                id: record.id,
                cells: []
            };

            this.columns.forEach(column => {
                const fieldValue = this.getFieldValue(record, column.fieldApiName);
                row.cells.push({
                    fieldName: column.fieldApiName,
                    value: fieldValue,
                    label: column.label,
                    isLookup: column.dataType === 'Reference'
                });
            });

            return row;
        });
    }

    // Helper to get field value from record
    getFieldValue(record, fieldApiName) {
        try {
            // Handle nested field references (e.g., Account.Name)
            const fieldParts = fieldApiName.split('.');
            let value = record.fields;
            
            for (const part of fieldParts) {
                if (value && value[part]) {
                    value = value[part].value !== undefined ? value[part].value : value[part];
                } else {
                    return '';
                }
            }
            
            return value || '';
        } catch (error) {
            console.error('Error getting field value for', fieldApiName, error);
            return '';
        }
    }

    // Event handlers
    handleHeaderAction(event) {
        const actionApiName = event.currentTarget?.dataset?.actionApiName || 
                             event.detail?.value; // For lightning-menu-item
        
        const action = this.headerActions.find(a => a.apiName === actionApiName);
        
        console.log('Header action clicked:', action);
        
        if (action) {
            this.executeHeaderAction(action);
        }
    }

    executeHeaderAction(action) {
        console.log('Executing header action:', action);
        
        // Handle different action types
        if (action.type === 'StandardButton') {
            this.handleStandardAction(action);
        } else if (action.type === 'CustomButton') {
            this.handleCustomAction(action);
        } else {
            this.showToast('Info', `Action "${action.label}" clicked`, 'info');
        }
    }

    handleStandardAction(action) {
        // Parse the action to determine what to do
        if (action.label.toLowerCase().includes('new')) {
            const targetObject = this.extractTargetObject(action);
            this.navigateToNew(targetObject);
        } else if (action.label.toLowerCase().includes('email')) {
            this.openEmailComposer();
        }
    }

    extractTargetObject(action) {
        // Extract target object from action metadata
        return action.targetSObjectType || this.relatedListId;
    }

    navigateToNew(objectApiName) {
        console.log('Navigating to new record for:', objectApiName);
        
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: objectApiName,
                actionName: 'new'
            },
            state: {
                defaultFieldValues: this.getDefaultFieldValues(objectApiName)
            }
        });
    }

    getDefaultFieldValues(objectApiName) {
        // Build default field values to link to parent record
        if (objectApiName === 'Task' || objectApiName === 'Event') {
            return `WhatId=${this.recordId}`;
        } else {
            // For custom objects, try to detect relationship field
            const parentObjectName = this.parentObjectApiName;
            if (parentObjectName) {
                return `${parentObjectName}__c=${this.recordId}`;
            }
        }
        return '';
    }

    openEmailComposer() {
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: {
                apiName: 'Global.SendEmail'
            }
        });
    }

    handleCustomAction(action) {
        console.log('Custom action not yet implemented:', action);
        this.showToast('Info', `Custom action "${action.label}" not yet implemented`, 'info');
    }

    handleRowAction(event) {
        const recordId = event.currentTarget.dataset.recordId;
        console.log('Row clicked for record:', recordId);
        
        // Navigate to record detail
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    handleSort(event) {
        const fieldName = event.currentTarget.dataset.fieldName;
        console.log('Sort requested for field:', fieldName);

        // Toggle sort direction
        if (this.sortedBy === fieldName) {
            this.sortedDirection = this.sortedDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortedBy = fieldName;
            this.sortedDirection = 'asc';
        }

        // The wire will automatically refresh with new sort parameters
    }

    handleViewAll() {
        console.log('View All clicked');
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                relationshipApiName: this.relatedListId,
                actionName: 'view'
            }
        });
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

    // Public API methods
    @api
    refresh() {
        console.log('Manual refresh requested');
        // With @wire, we can use refreshApex or the wired data will refresh automatically
        // For now, we could reload the page or trigger a refresh of the wired data
        return Promise.resolve();
    }
}