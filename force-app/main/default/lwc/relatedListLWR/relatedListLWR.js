import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRelatedListInfo from '@salesforce/apex/RelatedListLWRController.getRelatedListInfo';
import getObjectTypeFromRecordId from '@salesforce/apex/RelatedListLWRController.getObjectTypeFromRecordId';
import getCaseArticles from '@salesforce/apex/RelatedListLWRController.getCaseArticles';
import getFiles from '@salesforce/apex/RelatedListLWRController.getFiles';
import getImageAsBase64 from '@salesforce/apex/RelatedListLWRController.getImageAsBase64';
import canDeleteObject from '@salesforce/apex/RelatedListLWRController.canDeleteObject';
import deleteRecord from '@salesforce/apex/RelatedListLWRController.deleteRecord';
import getActivity from '@salesforce/apex/RelatedListLWRController.getEmailActivity';

/**
 * @slot iconSlot
 * @slot slot1
 * @slot slot2
 * @slot slot3
 * @slot slot4
 */
export default class SlotTest extends NavigationMixin(LightningElement) {
    
    // ===== API PROPERTIES =====
    
    // Configuration and context
    @api configJSONString = '{}';
    @api recordId;
    
    // ===== PRIVATE TRACKED PROPERTIES =====

    // Keep @track only for arrays that are mutated internally
    @track allRecords = [];
    @track displayedRecords = [];
    @track columns = [];

    // Fix #2: Remove @track from primitives - they're still reactive without it
    isLoading = false;
    isLoadingMore = false;
    error = null;
    hasData = false;
    hasMoreRecords = false;
    serverHasMoreRecords = false; // Track if server told us there are more records
    currentOffset = 0;
    detectedObjectType = null;
    sortedBy = '';
    sortDirection = 'asc';

    // File-specific state (primitives - no @track needed)
    showImageModal = false;
    modalImageUrl = '';
    modalDownloadUrl = '';
    modalImageName = '';
    modalImageSize = '';
    modalImageLoadError = '';
    isLoadingModalImage = false;

    // Delete permission tracking
    canDeleteRecords = false;
    
    // Performance and state tracking
    lastDataSignature = '';
    lastUISignature = '';
    isInitialized = false;
    lastLoadTime = 0;
    _scrollDebounceTimeout = null;
    _cachedRelationshipFieldMap = null;

    // Performance metrics tracking
    _perfMetrics = {
        // Batch 1 metrics (already optimized)
        relatedListLabelAccessCount: 0,
        relatedListLabelCacheHits: 0,
        customFieldNamesListAccessCount: 0,
        customFieldNamesListCacheHits: 0,
        sortOperationCount: 0,
        sortOptimizationSavings: 0,

        // Batch 2 metrics
        configGetterAccessCount: 0,  // Fix #9: Track accesses to config-only getters
        configGetterCacheHits: 0,     // Fix #9: Track cache hits
        flattenARLCallCount: 0,       // Fix #10: Track ARL field flattening calls
        flattenARLFieldsProcessed: 0, // Fix #10: Track total fields processed
        infiniteScrollTriggerCount: 0, // Fix #11: Track scroll handler triggers
        cardDataGenerationCount: 0,    // Fix #12: Track card data generation
        cardDataWastedCount: 0,        // Fix #12: Track wasted card data (when not in cards mode)

        // General metrics
        renderCallbackCount: 0,
        lastRenderTime: 0
    };

    // Cached config object (Fix #1: Cache JSON.parse result)
    _cachedConfigObj = null;
    _lastConfigString = '';

    // Cached signatures (Fix #3: Cache JSON.stringify results)
    _cachedDataSignature = null;
    _cachedUiSignature = null;
    _lastSignatureInputs = {
        recordId: null,
        relatedListName: null,
        relationshipField: null,
        enabledFields: null,
        detectedObjectType: null,
        relatedListType: null,
        numberOfSlots: null,
        iconType: null,
        relatedListIcon: null,
        fieldNames: null
    };

    // Fix #6: Cache relatedListLabel
    _cachedRelatedListLabel = null;
    _lastLabelInputs = {
        baseLabel: null,
        recordCount: null,
        hasMoreRecords: null
    };

    // Fix #7: Cache customFieldNamesList
    _cachedCustomFieldNamesList = [];
    _lastFieldNamesString = '';

    // Fix #9: Cache config-only getters
    _cachedConfigGetters = {
        showViewMore: null,
        showViewAll: null,
        viewAllUrl: null,
        hideCheckboxColumn: null,
        showRowNumberColumn: null,
        resizeColumnDisabled: null,
        columnSortingDisabled: null,
        enableInfiniteLoading: null,
        initialRecordsToLoad: null,
        defaultColumnWidth: null,
        maxRecordsToFetch: null
    };
    _lastConfigJSONForGetters = '';
    
    // ===== UTILITY METHODS FOR DEBUGGING =====
    
    debugLog(message, ...args) {
        if (this.showDebugInfo) {
            console.log(`[Related List LWR Debug] ${message}`, ...args);
        }
    }

    debugWarn(message, ...args) {
        if (this.showDebugInfo) {
            console.warn(`[Related List LWR Debug] ${message}`, ...args);
        }
    }

    debugError(message, ...args) {
        if (this.showDebugInfo) {
            console.error(`[Related List LWR Debug] ${message}`, ...args);
        }
    }

    // Always log errors regardless of debug mode
    logError(message, ...args) {
        console.error(`[Related List LWR Error] ${message}`, ...args);
    }
    
    // ===== COMPUTED CONFIGURATION PROPERTIES =====
    
    get configObj() {
        this._perfMetrics.configObjAccessCount++;

        // Fix #1: Only parse JSON when the string actually changes
        if (this.configJSONString !== this._lastConfigString) {
            try {
                this._cachedConfigObj = JSON.parse(this.configJSONString);
                this._lastConfigString = this.configJSONString;
            } catch (e) {
                this.logError('Invalid JSON in configJSONString:', e);
                this._cachedConfigObj = {};
            }
        }

        return this._cachedConfigObj;
    }
    
    // Get the current record
    get currentRecordId() {
        // Priority 1: Use configured recordId from CPE
        const configuredRecordId = this.configObj.recordId;
        if (configuredRecordId && 
            configuredRecordId.trim() !== '' &&
            configuredRecordId !== '{!recordId}' && 
            configuredRecordId !== 'undefined') {
            this.debugLog('Using configured record ID:', configuredRecordId);
            return configuredRecordId;
        }
        
        // Priority 2: Use API recordId (from Experience Cloud automatic injection)
        if (this.recordId && 
            this.recordId !== '{!recordId}' && 
            this.recordId !== 'undefined' && 
            this.recordId.trim() !== '') {
            this.debugLog('Using Experience Cloud record ID:', this.recordId);
            return this.recordId;
        }
        
        this.debugLog('No valid record ID available');
        return null;
    }

    // UI Configuration - instant response
    get numberOfSlots() {
        return this.configObj.numberOfSlots || 'None';
    }
    
    get relatedListIcon() {
        return this.configObj.relatedListIcon || '';
    }

    get iconType() {
    return this.configObj.iconType || 'slds';
}

    get useIconSlot() {
        return this.iconType === 'slot';
    }
    
    get relatedListLabel() {
        this._perfMetrics.relatedListLabelAccessCount++;

        // Fix #6: Only recalculate when label or count changes
        const baseLabel = this.configObj.relatedListLabel || 'Related Records';
        const recordCount = this.hasData ? this.allRecords.length : 0;

        // Check if inputs changed (including hasMoreRecords for "20+" logic)
        if (this._lastLabelInputs.baseLabel !== baseLabel ||
            this._lastLabelInputs.recordCount !== recordCount ||
            this._lastLabelInputs.hasMoreRecords !== this.hasMoreRecords) {

            // Update cache
            this._lastLabelInputs.baseLabel = baseLabel;
            this._lastLabelInputs.recordCount = recordCount;
            this._lastLabelInputs.hasMoreRecords = this.hasMoreRecords;

            // Recalculate label - show initialRecordsToLoad+ when there are more records
            if (this.hasData && recordCount > 0) {
                if (this.hasMoreRecords && recordCount >= this.initialRecordsToLoad) {
                    // Show "6+" (or whatever the initial load size is) when there are more records
                    this._cachedRelatedListLabel = `${baseLabel} (${this.initialRecordsToLoad}+)`;
                } else {
                    // Show exact count when all records are loaded or count is below initial load size
                    this._cachedRelatedListLabel = `${baseLabel} (${recordCount})`;
                }
            } else {
                this._cachedRelatedListLabel = baseLabel;
            }
        } else {
            this._perfMetrics.relatedListLabelCacheHits++;
        }

        return this._cachedRelatedListLabel;
    }
    
    get showViewMore() {
        this._perfMetrics.configGetterAccessCount++;

        // Fix #9: Cache config-only getter - update all caches when config changes
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        } else {
            this._perfMetrics.configGetterCacheHits++;
        }
        return this._cachedConfigGetters.showViewMore;
    }

    get showViewAll() {
        this._perfMetrics.configGetterAccessCount++;

        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        } else {
            this._perfMetrics.configGetterCacheHits++;
        }
        return this._cachedConfigGetters.showViewAll;
    }

    get viewAllUrl() {
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        }
        return this._cachedConfigGetters.viewAllUrl;
    }

    // Fix #9: Helper to update all config getter caches at once
    _updateAllConfigGetterCaches() {
        this._cachedConfigGetters.showViewMore = this.configObj.showViewMore || false;
        this._cachedConfigGetters.showViewAll = this.configObj.showViewAll || false;
        this._cachedConfigGetters.viewAllUrl = this.configObj.viewAllUrl || '';
        this._cachedConfigGetters.hideCheckboxColumn = this.configObj.hideCheckboxColumn !== undefined ? this.configObj.hideCheckboxColumn : true;
        this._cachedConfigGetters.showRowNumberColumn = this.configObj.showRowNumberColumn !== undefined ? this.configObj.showRowNumberColumn : false;
        this._cachedConfigGetters.resizeColumnDisabled = this.configObj.resizeColumnDisabled || false;
        this._cachedConfigGetters.columnSortingDisabled = this.configObj.columnSortingDisabled || false;
        this._cachedConfigGetters.enableInfiniteLoading = this.configObj.enableInfiniteLoading || false;
        this._cachedConfigGetters.initialRecordsToLoad = this.configObj.initialRecordsToLoad || 6;
        this._cachedConfigGetters.defaultColumnWidth = this.configObj.defaultColumnWidth || null;
        this._cachedConfigGetters.maxRecordsToFetch = this.configObj.maxRecordsToFetch || 50;

        // Mark caches as updated
        this._lastConfigJSONForGetters = this.configJSONString;
    }
    
    // ARL Mode Properties
    get relatedListName() {
        return this.configObj.relatedListName || '';
    }
    
    get fieldNames() {
        return this.configObj.fieldNames || '';
    }

    get relationshipField() {
        return this.configObj.relationshipField || '';
    }
    
    get enabledFields() {
        return this.configObj.enabledFields || '';
    }

    get customFieldNamesList() {
        this._perfMetrics.customFieldNamesListAccessCount++;

        // Fix #7: Only recalculate when fieldNames string changes
        if (this.fieldNames !== this._lastFieldNamesString) {
            this._lastFieldNamesString = this.fieldNames;

            if (!this.fieldNames || this.fieldNames.trim() === '') {
                this._cachedCustomFieldNamesList = [];
            } else {
                this._cachedCustomFieldNamesList = this.fieldNames
                    .split(',')
                    .map(name => name.trim())
                    .filter(name => name.length > 0);
            }
        } else {
            this._perfMetrics.customFieldNamesListCacheHits++;
        }

        return this._cachedCustomFieldNamesList;
    }

    getCustomFieldLabel(fieldInfo, index) {
        const customNames = this.customFieldNamesList;
        
        // If we have a custom name for this index, use it
        if (customNames.length > index) {
            this.debugLog(`Using custom name for field ${index}: "${customNames[index]}" instead of "${fieldInfo.label}"`);
            return customNames[index];
        }
        
        // Otherwise, use the original field label
        return fieldInfo.label;
    }
    
    // Record Linking
    get recordPageUrl() {
        return this.configObj.recordPageUrl || '';
    }
    
    get enableRecordLinking() {
        return this.configObj.enableRecordLinking || false;
    }
    
    // Table Configuration
    get initialRecordsToLoad() {
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        }
        return this._cachedConfigGetters.initialRecordsToLoad;
    }

    get defaultColumnWidth() {
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        }
        return this._cachedConfigGetters.defaultColumnWidth;
    }

    get hideCheckboxColumn() {
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        }
        return this._cachedConfigGetters.hideCheckboxColumn;
    }

    get showRowNumberColumn() {
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        }
        return this._cachedConfigGetters.showRowNumberColumn;
    }

    get resizeColumnDisabled() {
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        }
        return this._cachedConfigGetters.resizeColumnDisabled;
    }

    get columnSortingDisabled() {
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        }
        return this._cachedConfigGetters.columnSortingDisabled;
    }

    get enableInfiniteLoading() {
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        }
        return this._cachedConfigGetters.enableInfiniteLoading;
    }

    get maxRecordsToFetch() {
        if (this.configJSONString !== this._lastConfigJSONForGetters) {
            this._updateAllConfigGetterCaches();
        }
        return this._cachedConfigGetters.maxRecordsToFetch;
    }

    get enableRecordDeletion() {
        return this.configObj.enableRecordDeletion || false;
    }

    get relatedListType() {
        return this.configObj.relatedListType || 'standard';
    }

    get isStandardType() {
        return this.relatedListType === 'standard';
    }

    get isFilesType() {
        return this.relatedListType === 'files';
    }

    get isArticlesType() {
        return this.relatedListType === 'articles';
    }

    get isEmailType() {
        console.log('relatedlisttype: ' + this.relatedListType);
        return this.relatedListType === 'emails';
    }

    get showArticles() {
        // Articles now use the regular table display
        return false;
    }

    get shouldShowDeleteAction() {
        return this.enableRecordDeletion &&
               this.canDeleteRecords &&
               this.displayMode === 'table' &&
               this.isStandardType;
    }

    // ===== SMART CHANGE DETECTION =====
    
    get dataSignature() {
        this._perfMetrics.dataSignatureAccessCount++;

        // Fix #3: Only regenerate signature if relevant properties changed
        const currentInputs = {
            recordId: this.currentRecordId,
            relatedListName: this.relatedListName,
            relationshipField: this.relationshipField,
            enabledFields: this.enabledFields,
            detectedObjectType: this.detectedObjectType,
            relatedListType: this.relatedListType
        };

        // Check if any relevant input changed
        const hasChanged = Object.keys(currentInputs).some(
            key => currentInputs[key] !== this._lastSignatureInputs[key]
        );

        if (hasChanged || !this._cachedDataSignature) {
            // Update cache
            Object.assign(this._lastSignatureInputs, currentInputs);

            // Create signature for data-affecting properties based on mode
            if (this.isArticlesType) {
                this._cachedDataSignature = JSON.stringify({
                    mode: 'articles',
                    recordId: this.currentRecordId
                });
            } else if (this.isFilesType) {
                this._cachedDataSignature = JSON.stringify({
                    mode: 'files',
                    recordId: this.currentRecordId
                });
            } else {
                // ARL mode signature
                this._cachedDataSignature = JSON.stringify({
                    mode: 'arl',
                    recordId: this.currentRecordId,
                    relatedListName: this.relatedListName,
                    relationshipField: this.relationshipField,
                    enabledFields: this.enabledFields,
                    detectedObjectType: this.detectedObjectType
                });
            }
        }

        return this._cachedDataSignature;
    }
    
    get uiSignature() {
        this._perfMetrics.uiSignatureAccessCount++;

        // Fix #3: Only regenerate signature if UI properties changed
        const currentUiInputs = {
            numberOfSlots: this.numberOfSlots,
            iconType: this.iconType,
            relatedListIcon: this.relatedListIcon,
            fieldNames: this.fieldNames,
            defaultColumnWidth: this.defaultColumnWidth,
            hideCheckboxColumn: this.hideCheckboxColumn,
            showRowNumberColumn: this.showRowNumberColumn,
            resizeColumnDisabled: this.resizeColumnDisabled,
            columnSortingDisabled: this.columnSortingDisabled
        };

        // Check if any UI input changed
        const hasChanged = Object.keys(currentUiInputs).some(
            key => currentUiInputs[key] !== this._lastSignatureInputs[key]
        );

        if (hasChanged || !this._cachedUiSignature) {
            // Update cache
            Object.assign(this._lastSignatureInputs, currentUiInputs);

            this._cachedUiSignature = JSON.stringify({
                numberOfSlots: this.numberOfSlots,
                iconType: this.iconType,
                relatedListIcon: this.relatedListIcon,
                relatedListLabel: this.relatedListLabel,
                showViewMore: this.showViewMore,
                showViewAll: this.showViewAll,
                viewAllUrl: this.viewAllUrl,
                enableRecordLinking: this.enableRecordLinking,
                recordPageUrl: this.recordPageUrl,
                fieldNames: this.fieldNames,
                defaultColumnWidth: this.defaultColumnWidth,
                hideCheckboxColumn: this.hideCheckboxColumn,
                showRowNumberColumn: this.showRowNumberColumn,
                resizeColumnDisabled: this.resizeColumnDisabled,
                columnSortingDisabled: this.columnSortingDisabled,
                enableInfiniteLoading: this.enableInfiniteLoading,
                displayMode: this.displayMode,
            });
        }

        return this._cachedUiSignature;
    }
    
    get shouldReloadData() {
        return this.dataSignature !== this.lastDataSignature;
    }
    
    get shouldRebuildColumns() {
        return this.uiSignature !== this.lastUISignature;
    }
    
    get dataSourceMode() {
        return 'Related List API';
    }
    
    // ===== UI STATE GETTERS =====
    
    // Slot visibility getters - instant response
    get showSlot1() {
        return this.numberOfSlots !== 'None';
    }
    
    get showSlot2() {
        return ['Two', 'Three', 'Four'].includes(this.numberOfSlots);
    }
    
    get showSlot3() {
        return ['Three', 'Four'].includes(this.numberOfSlots);
    }
    
    get showSlot4() {
        return this.numberOfSlots === 'Four';
    }
    
    // Icon display logic
    get showStandardIcon() {
        return this.iconType === 'slds' && this.hasIcon;
    }

    get showIconSlot() {
        return this.iconType === 'slot';
    }

    // UI state getters
    get hasIcon() {
        return this.relatedListIcon && this.relatedListIcon.includes(':');
    }
    
    get showActionButtonContainer() {
        // Only show if there's actually something to display AND there are records
        const hasContent = this.showTable || this.showArticles || this.showFilesGrid || this.showCards;
        const hasLoadMore = this.showLoadMoreButton && this.hasMoreRecords;
        const hasViewAll = this.showViewAll && hasContent;
        return hasLoadMore || hasViewAll;
    }
    
    get actionButtonContainerClass() {
        const base = 'slds-text-align_center slds-m-top_medium compact-action-buttons';
        if (this.showViewMore && this.showViewAll) {
            return `${base} action-button-container-dual`;
        }
        return `${base} action-button-container-single`;
    }
    
    get showEmptyState() {
        //console.log('loading ' + this.isLoading + ' error ' + this.error + ' has data ' + this.hasData);
        return !this.isLoading && !this.error && !this.hasData;
    }
    
    get displayMode() {
        return this.configObj.displayMode || 'table';
    }

    get showTable() {
        //console.log('display mode: ' + this.displayMode);
        return ((this.displayMode === 'table' && this.isStandardType) || 
                this.isArticlesType || this.isEmailType) &&  // Removed Files reference
            !this.isLoading && 
            !this.error && 
            this.hasData && 
            this.displayedRecords.length > 0;
    }

    get showCards() {
        return this.displayMode === 'cards' &&
            !this.isLoading &&
            !this.error &&
            this.hasData &&
            this.displayedRecords.length > 0 &&
            !this.isArticlesType && // Don't show cards for articles
            !this.isFilesType; // Don't show cards for files - they have their own grid
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        this.debugLog('Row action:', actionName, row);

        if (actionName === 'viewFile') {
            // Handle file view action
            if (row.isImage) {
                this.handleImagePreview(row.contentDocumentId, row.title, row.formattedSize, row.downloadUrl);
            } else {
                this.handleDirectDownload(row.downloadUrl, row.title);
            }
        } else if (actionName === 'delete') {
            // Handle delete action
            this.handleDeleteRecord(row.Id);
        }
    }

    get firstFieldName() {
        if (this.columns.length === 0) return null;
        const firstCol = this.columns[0];
        // If linking is enabled, the fieldName becomes 'recordUrl', so get the original field name
        if (firstCol.fieldName === 'recordUrl' && firstCol.typeAttributes?.label?.fieldName) {
            return firstCol.typeAttributes.label.fieldName;
        }
        return firstCol.fieldName;
    }

    get cardFields() {
        // Return all fields except the first (which is shown as title)
        return this.columns.slice(1).map((col, index) => {
            // Get the actual field name, not 'recordUrl'
            let fieldName = col.fieldName;
            if (fieldName === 'recordUrl' && col.typeAttributes?.label?.fieldName) {
                fieldName = col.typeAttributes.label.fieldName;
            }
            
            return {
                fieldName: fieldName,
                label: col.label,
                // Add unique key for iteration
                key: `card-field-${index}`
            };
        });
    }

    get showLoadMoreButton() {
        const hasContent = this.showTable || this.showArticles || this.showFilesGrid || this.showCards;
        const result = hasContent && this.hasMoreRecords && this.showViewMore && !this.enableInfiniteLoading;

        // Debug logging
        this.debugLog('showLoadMoreButton calculation:', {
            hasContent,
            hasMoreRecords: this.hasMoreRecords,
            showViewMore: this.showViewMore,
            enableInfiniteLoading: this.enableInfiniteLoading,
            result
        });

        // Hide Load More button when infinite loading is enabled (it replaces the button)
        return result;
    }
    
    get loadMoreButtonLabel() {
        const remainingRecords = this.allRecords.length - this.displayedRecords.length;
        const nextBatchSize = Math.min(remainingRecords, this.initialRecordsToLoad);
        return `Load More (${nextBatchSize} more)`;
    }

    get showBothButtons() {
        return this.showLoadMoreButton && this.showViewAll;
    }
    
    // For template boolean properties
    get hideCheckboxColumnValue() {
        return this.hideCheckboxColumn;
    }
    
    get showRowNumberColumnValue() {
        return this.showRowNumberColumn;
    }

    get tableContainerClass() {
        // Only use fixed-header-table for cards view
        // Standard table display uses regular responsive container
        if (this.showCards) {
            return 'responsive-table-container fixed-header-table';
        }
        return 'responsive-table-container';
    }
    
    // Validation
    get hasValidConfiguration() {
        if (this.isArticlesType || this.isEmailType) {
            // Articles mode validation - just needs recordId
            const hasRecordId = !!(this.currentRecordId);
            this.debugLog('Articles Validation:', { hasRecordId });
            return hasRecordId;
        } else if (this.isFilesType) {
            // Files mode validation - just needs recordId
            const hasRecordId = !!(this.currentRecordId);
            this.debugLog('Files Validation:', { hasRecordId });
            return hasRecordId;
        } else {
            // ARL mode validation (existing logic)
            const hasRelatedListName = !!(this.relatedListName);
            const hasRecordId = !!(this.currentRecordId);
            const hasDetectedObjectType = !!(this.detectedObjectType);
            
            this.debugLog('ARL Validation:', {
                hasRelatedListName,
                hasRecordId,
                hasDetectedObjectType,
                relatedListName: this.relatedListName,
                recordId: this.currentRecordId,
                detectedObjectType: this.detectedObjectType,
                enabledFields: this.enabledFields,
                relationshipField: this.relationshipField,
                canProceed: hasRelatedListName && hasRecordId && hasDetectedObjectType
            });
            
            return hasRelatedListName && hasRecordId && hasDetectedObjectType;
        }
    }
    
    get showFilesGrid() {
        return this.isFilesType && 
            !this.isLoading && 
            !this.error && 
            this.hasData && 
            this.displayedRecords.length > 0;
    }

    get filesGridColumns() {
        return this.configObj.filesGridColumns || '2';
    }

    get filesGridClass() {
        return `files-grid-container files-grid-columns-${this.filesGridColumns}`;
    }

    get cardGridColumns() {
        return this.configObj.cardGridColumns || '1';
    }

    get cardGridClass() {
        return `card-container card-grid-columns-${this.cardGridColumns}`;
    }

    get hasModalImageError() {
        return !!this.modalImageLoadError;
    }

    // Debug properties
    get showDebugInfo() {
        return this.configObj.showDebugInfo || false;
    }
    
    // ===== DEBUG METHODS =====
    
    debugConfiguration() {
        if (!this.showDebugInfo) return;
        
        this.debugLog('=== SlotTest Configuration Debug ===');
        this.debugLog('configured recordId:', this.configObj.recordId);
        this.debugLog('API recordId (from Experience Cloud):', this.recordId);
        this.debugLog('currentRecordId (final resolved):', this.currentRecordId);
        this.debugLog('detectedObjectType:', this.detectedObjectType);
        this.debugLog('hasValidConfiguration:', this.hasValidConfiguration);
        this.debugLog('shouldReloadData:', this.shouldReloadData);
        this.debugLog('dataSignature:', this.dataSignature);
        this.debugLog('lastDataSignature:', this.lastDataSignature);
        this.debugLog('configJSONString:', this.configJSONString);
        this.debugLog('====================================');
    }
    
    // ===== LIFECYCLE HOOKS =====
    
    connectedCallback() {
        this.debugLog(`SlotTest connected with CPE integration - Mode: ${this.dataSourceMode}`);
        this.debugLog('Configuration:', this.configObj);
        this.isInitialized = true;
        this.detectObjectTypeAndLoadData();
    }
    
    renderedCallback() {
        const renderStart = performance.now();
        this._perfMetrics.renderCallbackCount++;

        if (!this.isInitialized) {
            return;
        }

        // Don't interfere with manual refresh
        if (this.isRefreshing) {
            return;
        }

        // Smart change detection - only reload what's necessary
        if (this.shouldReloadData) {
            this.debugLog('Data signature changed, reloading data');
            this.debugLog('Previous signature:', this.lastDataSignature);
            this.debugLog('Current signature:', this.dataSignature);
            this.loadData();
        } else if (this.shouldRebuildColumns && this.hasData) {
            this.debugLog('UI signature changed, rebuilding columns only');
            this.rebuildColumnsOnly();
        }

        const renderEnd = performance.now();
        this._perfMetrics.lastRenderTime = renderEnd - renderStart;
    }
    
    // ===== DATA LOADING ORCHESTRATION =====
    
    async detectObjectTypeAndLoadData() {
        this.debugLog('detectObjectTypeAndLoadData called with recordId:', this.currentRecordId);

        if (!this.currentRecordId) {
            this.debugLog('No valid record ID for processing');
            this.clearData();
            return;
        }

        
        try {
            // Always detect object type (needed for both modes)
            this.detectedObjectType = await getObjectTypeFromRecordId({ recordId: this.currentRecordId });
            this.debugLog('Detected object type:', this.detectedObjectType);
            
            if (this.detectedObjectType) {
                // Force a signature update to trigger reload
                this.lastDataSignature = '';
                this.loadData();
            } else {
                this.error = 'Could not determine object type from record ID';
            }
        } catch (error) {
            this.logError('Error detecting object type:', error);
            this.error = 'Could not determine object type from record ID';
        }
    }
    
    async loadData() {
        // Debug configuration first
        this.debugConfiguration();

        if (!this.hasValidConfiguration) {
            this.debugLog(`Invalid configuration, skipping data load`);
            this.clearData();
            return;
        }

        const startTime = performance.now();
        this.debugLog(`Loading data for type: ${this.relatedListType}`);

        this.isLoading = true;
        this.error = null;

        try {
            // Route to appropriate data loading method based on type
            if (this.isArticlesType) {
                await this.loadArticles();
            } else if (this.isFilesType) {
                await this.loadFiles();
            } else if (this.isEmailType) {
                await this.loadRelatedActivity('08pEi000001JIofIAG');
            } else {
                await this.loadDataWithARL();
            }

            // Update signatures to prevent unnecessary reloads
            this.lastDataSignature = this.dataSignature;
            this.lastUISignature = this.uiSignature;

            const endTime = performance.now();
            this.lastLoadTime = Math.round(endTime - startTime);
            this.debugLog(`Data loading took ${this.lastLoadTime}ms`);

        } catch (error) {
            this.logError(`Error loading data:`, error);
            this.error = error.body?.message || error.message || 'Unknown error occurred';
            this.clearData();
        } finally {
            this.isLoading = false;
        }
    }
    
    // Fast column rebuild for UI-only changes (no data reload)
    async rebuildColumnsOnly() {
        this.debugLog('Rebuilding columns only (no data reload)');
        
        if (!this.hasData || this.allRecords.length === 0) {
            return;
        }
        
        try {
            // For ARL mode, we'd need to call the API again
            // For now, just reprocess existing records
            this.debugLog('ARL column rebuild requires data reload');
            this.loadData();
            return;
            
        } catch (error) {
            this.logError('Error rebuilding columns:', error);
            // Fall back to full data reload
            this.loadData();
        }
    }
    
    reprocessRecordsForLinking(records) {
        return records.map(record => {
            const processedRecord = { ...record };
            
            // Remove old recordUrl if it exists
            delete processedRecord.recordUrl;
            
            // Add new recordUrl if linking is enabled
            if (this.enableRecordLinking && this.recordPageUrl && record.Id) {
                processedRecord.recordUrl = this.buildRecordUrl(record.Id);
            }
            
            // Re-flatten relationship fields for ARL mode
            this.flattenRelationshipFieldsForARL(processedRecord, records.length > 0 ? records[0] : {});
            
            return processedRecord;
        });
    }

    async loadRelatedActivity(recordId) {
        if (!recordId) {
            //console.log('oh no fail' + recordId);
            this.showToast('Error', 'No record ID provided', 'error');
            return;
        }

        try {
            this.currentOffset = 0;
            const response = await getActivity({ recordId: recordId });

            let modifiedResponse = [...response];
            modifiedResponse.forEach(rec => {
                rec.url = '/internalsupportlwr/emailmessage/' + rec.Id;
                if(rec.Status === 0 || rec.Status === 1) {
                    rec.statusText = 'Read';
                } else if (rec.Status === 2) {
                    rec.statusText = 'Replied';
                } else {
                    rec.statusText = 'Sent';
                }
            });

            //console.log('126467: ');
            //console.log(modifiedResponse);

            this.columns = [
                {
                    label: 'Subject', fieldName: 'url', type: 'url',
                    typeAttributes: {label: { fieldName: 'Subject' }, 
                    target: '_blank'}, hideDefaultActions: true
                },
                {
                    label: 'Status', fieldName: 'statusText', hideDefaultActions: true
                },
                {
                    label: 'Opened?', fieldName: 'IsOpened', type: 'boolean', hideDefaultActions: true
                },
                {
                    label: 'Message Date', fieldName: 'MessageDate', type: 'date', hideDefaultActions: true
                }

            ];
            this.allRecords = modifiedResponse;

            this.hasData = this.allRecords.length > 0;
            this.displayedRecords = this.allRecords;

        } catch (error) {
            this.logError('Error loading activity:', error);
            const errorMessage = error.body?.message || error.message || 'Unknown error occurred';
            this.showToast('Error', 'Failed to load related email activity: ' + errorMessage, 'error');
        }
    }
    
    // ===== ARL MODE DATA LOADING =====
    
    async loadDataWithARL(appendRecords = false) {
        this.debugLog('Using Related List API data loading method', appendRecords ? '(appending)' : '(initial)');

        if (!this.relatedListName || !this.detectedObjectType) {
            throw new Error('Related List Name and Object Type are required for ARL mode');
        }

        // Load up to maxRecordsToFetch records total (no pagination - simplified approach)
        const offset = 0;
        const limit = this.maxRecordsToFetch;

        this.debugLog('ARL Parameters:', {
            objectApiName: this.detectedObjectType,
            relatedListName: this.relatedListName,
            recordId: this.currentRecordId,
            enabledFields: this.enabledFields,
            relationshipField: this.relationshipField,
            offset: offset,
            limit: limit
        });

        const response = await getRelatedListInfo({
            objectApiName: this.detectedObjectType,
            relatedListName: this.relatedListName,
            recordId: this.currentRecordId,
            enabledFields: this.enabledFields || '',
            relationshipField: this.relationshipField || '',
            offsetParam: offset,
            limitParam: limit
        });

        this.debugLog('ARL Response:', response);

        if (response?.fields) {
            // Check delete permissions before building columns
            await this.checkDeletePermission();

            // Load all records up front (up to 50), paginate client-side only
            this.columns = this.buildColumnsFromARL(response.fields);
            this.allRecords = this.processARLRecords(response.records || []);

            // Store server's hasMoreRecords flag - if true, there are more than 50 total
            this.serverHasMoreRecords = response.hasMoreRecords || false;

            this.currentOffset = 0;
            this.updateDisplayedRecords();
            this.hasData = this.allRecords.length > 0;

            this.debugLog(`ARL Success: ${this.columns.length} columns, ${this.allRecords.length} records, serverHasMore: ${this.serverHasMoreRecords}`);
        } else {
            throw new Error('No field information returned from Related List API');
        }
    }
    
    buildColumnsFromARL(fields) {
        const columns = fields.map((field, index) => {
            const fieldType = this.mapFieldTypeToDataTableType(field.type);
            const column = {
                label: this.getCustomFieldLabel(field, index),
                fieldName: this.getDisplayFieldNameForARL(field.apiName),
                type: (field.type === 'DATETIME' || field.type === 'DATE') ? 'text' : fieldType,
                isDateTime: field.type === 'DATETIME',
                isDate: field.type === 'DATE',
                sortable: !this.columnSortingDisabled,
                wrapText: true
            };

            if (this.defaultColumnWidth && this.defaultColumnWidth > 0) {
                column.fixedWidth = this.defaultColumnWidth;
            }

            // Enable linking on first column if configured
            if (index === 0 && this.enableRecordLinking && this.recordPageUrl) {
                column.type = 'url';
                column.typeAttributes = {
                    label: { fieldName: this.getDisplayFieldNameForARL(field.apiName) },
                    target: '_blank'
                };
                column.fieldName = 'recordUrl';
            }

            return column;
        });

        // Add delete action column if appropriate
        if (this.shouldShowDeleteAction) {
            columns.push({
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        {
                            label: 'Delete',
                            name: 'delete',
                            iconName: 'utility:delete'
                        }
                    ]
                },
                fixedWidth: 60
            });
        }

        return columns;
    }
    
    processARLRecords(records) {
        return records.map(record => {
            const processedRecord = { ...record };
            
            // Format datetime and date fields
            this.columns.forEach(col => {
                const fieldName = col.fieldName === 'recordUrl' ? 
                    (col.typeAttributes?.label?.fieldName || this.columns[0].fieldName) : 
                    col.fieldName;
                    
                if (col.isDateTime && processedRecord[fieldName]) {
                    processedRecord[fieldName] = this.formatDateTime(processedRecord[fieldName]);
                } else if (col.isDate && processedRecord[fieldName]) {
                    processedRecord[fieldName] = this.formatDate(processedRecord[fieldName]);
                }
            });

            // Add record URL for linking
            if (this.enableRecordLinking && this.recordPageUrl && record.Id) {
                processedRecord.recordUrl = this.buildRecordUrl(record.Id);
            }
            
            // Flatten relationship fields for ARL mode
            this.flattenRelationshipFieldsForARL(processedRecord, records.length > 0 ? records[0] : {});

            // Add card display data - only when in cards mode
            if (this.displayMode === 'cards') {
                processedRecord.cardData = this.buildCardData(processedRecord);
            }

            return processedRecord;
        });
    }
    
    getDisplayFieldNameForARL(fieldApiName) {
        // Use the consistent flattening method for ARL fields
        return this.getFlattenedFieldName(fieldApiName);
    }

    getFlattenedFieldName(fieldApiName) {
        if (fieldApiName.includes('.')) {
            return fieldApiName.replace('.', '_');
        }
        return fieldApiName;
    }

    flattenRelationshipFieldsForARL(record, sampleRecord) {
        this._perfMetrics.flattenARLCallCount++;

        // Cache the relationship field mapping to avoid repeated processing
        if (!this._cachedRelationshipFieldMap && sampleRecord) {
            this._cachedRelationshipFieldMap = [];
            const keysToProcess = Object.keys(sampleRecord);
            this._perfMetrics.flattenARLFieldsProcessed += keysToProcess.length;

            keysToProcess.forEach(key => {
                if (key.includes('.')) {
                    const parts = key.split('.');
                    this._cachedRelationshipFieldMap.push({
                        originalKey: key,
                        relationshipName: parts[0],
                        fieldName: parts[1],
                        flattenedFieldName: this.getFlattenedFieldName(key)
                    });
                }
            });
        }

        // Use cached mapping to process record
        if (this._cachedRelationshipFieldMap) {
            this._cachedRelationshipFieldMap.forEach(mapping => {
                // Extract the value from the nested relationship
                if (record[mapping.relationshipName] && record[mapping.relationshipName][mapping.fieldName] !== undefined) {
                    record[mapping.flattenedFieldName] = record[mapping.relationshipName][mapping.fieldName];
                    this.debugLog(`Flattened ARL field ${mapping.originalKey} -> ${mapping.flattenedFieldName}: ${record[mapping.flattenedFieldName]}`);
                } else {
                    record[mapping.flattenedFieldName] = null;
                    this.debugLog(`Flattened ARL field ${mapping.originalKey} -> ${mapping.flattenedFieldName}: null (no data)`);
                }
            });
        }
    }

    // ===== SHARED DATA PROCESSING METHODS =====

    flattenRecords(records) {
        this.debugLog('Flattening records:', records);

        return records.map(record => {
            const flatRecord = { ...record };

            // Format datetime and date fields
            this.columns.forEach(col => {
                if (col.isDateTime && flatRecord[col.fieldName]) {
                    flatRecord[col.fieldName] = this.formatDateTime(flatRecord[col.fieldName]);
                } else if (col.isDate && flatRecord[col.fieldName]) {
                    flatRecord[col.fieldName] = this.formatDate(flatRecord[col.fieldName]);
                }
            });
            
            // Add record URL for linking
            if (this.enableRecordLinking && this.recordPageUrl && record.Id) {
                flatRecord.recordUrl = this.buildRecordUrl(record.Id);
            }

            // Add card display data - only when in cards mode
            if (this.displayMode === 'cards') {
                flatRecord.cardData = this.buildCardData(flatRecord);
            }

            return flatRecord;
        });
    }
    
    buildCardData(record) {
        this._perfMetrics.cardDataGenerationCount++;

        // Track if we're wasting effort (not in cards mode)
        if (this.displayMode !== 'cards') {
            this._perfMetrics.cardDataWastedCount++;
        }

        if (!this.columns || this.columns.length === 0) {
            return { title: '', fields: [] };
        }

        // Get first field value for title
        const firstCol = this.columns[0];
        let titleFieldName = firstCol.fieldName;
        if (titleFieldName === 'recordUrl' && firstCol.typeAttributes?.label?.fieldName) {
            titleFieldName = firstCol.typeAttributes.label.fieldName;
        }
        
        const cardData = {
            title: record[titleFieldName] || '',
            fields: []
        };
        
        // Get remaining fields with their values
        for (let i = 1; i < this.columns.length; i++) {
            const col = this.columns[i];
            let fieldName = col.fieldName;
            if (fieldName === 'recordUrl' && col.typeAttributes?.label?.fieldName) {
                fieldName = col.typeAttributes.label.fieldName;
            }
            
            cardData.fields.push({
                key: `field-${i}`,
                label: col.label,
                value: record[fieldName] || ''
            });
        }
        
        return cardData;
    }

    async loadArticles() {
        this.debugLog('Loading Knowledge Articles for case:', this.currentRecordId);
        
        if (!this.currentRecordId) {
            throw new Error('Record ID is required for Knowledge Articles');
        }
        
        try {
            const articles = await getCaseArticles({ caseId: this.currentRecordId });
            
            this.debugLog(`Retrieved ${articles.length} articles`);
            
            // Build columns for articles - single "Title" column
            this.columns = [{
                label: 'Title',
                fieldName: this.enableRecordLinking && this.recordPageUrl ? 'recordUrl' : 'title',
                type: this.enableRecordLinking && this.recordPageUrl ? 'url' : 'text',
                typeAttributes: this.enableRecordLinking && this.recordPageUrl ? {
                    label: { fieldName: 'title' },
                    target: '_blank'
                } : undefined,
                sortable: !this.columnSortingDisabled,
                wrapText: true
            }];
            
            // Transform articles to match the datatable structure
            this.allRecords = articles.map(article => {
                const articleRecord = {
                    Id: article.id,
                    title: article.title,
                    urlName: article.urlName,
                    recordUrl: this.enableRecordLinking && this.recordPageUrl ?
                        this.buildArticleUrl(article.urlName, article.id) : undefined
                };

                // Add cardData for cards display mode
                if (this.displayMode === 'cards') {
                    articleRecord.cardData = this.buildCardData(articleRecord);
                }

                return articleRecord;
            });

            // Reset pagination
            this.currentOffset = 0;
            this.updateDisplayedRecords();
            
            this.debugLog(`Loaded ${this.allRecords.length} articles, displaying ${this.displayedRecords.length}`);
            
        } catch (error) {
            this.logError('Error loading articles:', error);
            throw error;
        }
    }

    async loadFiles() {
        this.debugLog('Loading Files for record:', this.currentRecordId);

        if (!this.currentRecordId) {
            throw new Error('Record ID is required for Files');
        }

        try {
            const files = await getFiles({
                recordId: this.currentRecordId,
                sortField: 'CreatedDate',
                sortDirection: 'DESC',
                limitCount: this.maxRecordsToFetch
            });
            
            this.debugLog(`Retrieved ${files.length} files`);
            
            // Build columns for table view
            this.columns = [
                {
                    label: 'Name',
                    fieldName: 'title',
                    type: 'button',
                    typeAttributes: {
                        label: { fieldName: 'title' },
                        name: 'viewFile',
                        variant: 'base'
                    },
                    sortable: !this.columnSortingDisabled,
                    wrapText: true
                },
                {
                    label: 'Type',
                    fieldName: 'fileExtension',
                    type: 'text',
                    fixedWidth: 80,
                    sortable: !this.columnSortingDisabled
                },
                {
                    label: 'Size',
                    fieldName: 'formattedSize',
                    type: 'text',
                    fixedWidth: 100,
                    sortable: !this.columnSortingDisabled
                },
                {
                    label: 'Modified',
                    fieldName: 'createdDate',
                    type: 'date',
                    typeAttributes: {
                        year: 'numeric',
                        month: 'short',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit'
                    },
                    fixedWidth: 180,
                    sortable: !this.columnSortingDisabled
                }
            ];
            
            // Store files directly - files use their own grid view, not cards
            this.allRecords = files || [];

            // Reset pagination
            this.currentOffset = 0;
            this.updateDisplayedRecords();
            
            this.debugLog(`Loaded ${this.allRecords.length} files, displaying ${this.displayedRecords.length}`);
            
        } catch (error) {
            this.logError('Error loading files:', error);
            throw error;
        }
    }

    buildArticleUrl(urlName, articleId) {
        // If recordPageUrl is NOT configured, return null (no linking)
        if (!this.recordPageUrl || this.recordPageUrl.trim() === '') {
            this.debugLog('No recordPageUrl configured - articles will not link');
            return null;
        }
        
        const siteBaseUrl = this.getSiteBaseUrl();
        let articlePath = this.recordPageUrl;
        
        // Replace placeholders
        if (articlePath.includes(':urlName')) {
            articlePath = articlePath.replace(':urlName', urlName);
        } else if (articlePath.includes('{urlName}')) {
            articlePath = articlePath.replace('{urlName}', urlName);
        }
        
        if (articlePath.includes(':recordId')) {
            articlePath = articlePath.replace(':recordId', articleId);
        } else if (articlePath.includes('{recordId}')) {
            articlePath = articlePath.replace('{recordId}', articleId);
        }
        
        // Ensure path starts with /
        const cleanPath = articlePath.startsWith('/') ? articlePath : '/' + articlePath;
        const fullUrl = siteBaseUrl + cleanPath;
        
        this.debugLog('Built article URL from recordPageUrl:', fullUrl);
        return fullUrl;
    }

    getSiteBaseUrl() {
        const url = new URL(window.location.href);

        this.debugLog('Getting site base URL from:', window.location.href);
        this.debugLog('URL hostname:', url.hostname);
        this.debugLog('URL pathname:', url.pathname);
        this.debugLog('URL origin:', url.origin);

        // For Experience Cloud sites, capture the full site path
        if (url.hostname.includes('.my.site.com') ||
            url.hostname.includes('.force.com') ||
            url.hostname.includes('salesforce-experience.com')) {

            const pathParts = url.pathname.split('/').filter(part => part !== '');
            this.debugLog('Path parts:', pathParts);

            if (pathParts.length > 0) {
                const sitePath = pathParts[0];
                const siteBaseUrl = `${url.origin}/${sitePath}`;
                this.debugLog('Experience Cloud site base URL:', siteBaseUrl);
                return siteBaseUrl;
            }

            this.debugLog('No path parts found, returning origin:', url.origin);
            return url.origin;
        } else {
            // Custom domain
            const pathParts = url.pathname.split('/').filter(part => part !== '');
            this.debugLog('Custom domain path parts:', pathParts);

            if (pathParts.length > 0) {
                const siteBaseUrl = `${url.origin}/${pathParts[0]}`;
                this.debugLog('Custom domain site base URL:', siteBaseUrl);
                return siteBaseUrl;
            }

            this.debugLog('No path parts found, returning origin:', url.origin);
            return url.origin;
        }
    }

    // ===== SHARED UTILITY METHODS =====
    
    clearData() {
        this.allRecords = [];
        this.displayedRecords = [];
        this.columns = [];
        this.hasData = false;
        this.hasMoreRecords = false;
        this.serverHasMoreRecords = false;
        this.currentOffset = 0;
        this.clearSort();
        // Clear cached field mapping for performance optimization
        this._cachedRelationshipFieldMap = null;
    }
    
    buildRecordUrl(recordId) {
        if (!this.recordPageUrl || !recordId) {
            return null;
        }

        const siteBaseUrl = this.getSiteBaseUrl();
        let recordPath = this.recordPageUrl;

        // Replace placeholders
        if (recordPath.includes(':recordId')) {
            recordPath = recordPath.replace(':recordId', recordId);
        } else if (recordPath.includes('{recordId}')) {
            recordPath = recordPath.replace('{recordId}', recordId);
        } else {
            recordPath = recordPath.endsWith('/') ? recordPath + recordId : recordPath + '/' + recordId;
        }

        // Ensure path starts with /
        const cleanPath = recordPath.startsWith('/') ? recordPath : '/' + recordPath;
        const fullUrl = siteBaseUrl + cleanPath;

        this.debugLog('Built record URL:', fullUrl);
        return fullUrl;
    }
    
    updateDisplayedRecords() {
        const pageSize = this.initialRecordsToLoad;
        const endIndex = this.currentOffset + pageSize;

        this.displayedRecords = this.allRecords.slice(0, endIndex);
        this.hasData = this.displayedRecords.length > 0;

        // Calculate hasMoreRecords based on both client-side and server-side state
        const hasMoreClientRecords = endIndex < this.allRecords.length;

        // hasMoreRecords is true when:
        // 1. We have more client-side records to display (not yet shown), OR
        // 2. We've shown all client-side records AND the server told us there are more on the server
        if (hasMoreClientRecords) {
            // Still have more records to show from what we already loaded
            this.hasMoreRecords = true;
        } else if (this.serverHasMoreRecords) {
            // Shown all client records, but server says there are more
            this.hasMoreRecords = true;
        } else {
            // Shown all records and server has no more
            this.hasMoreRecords = false;
        }

        this.debugLog(`Showing ${this.displayedRecords.length} of ${this.allRecords.length} records, serverHasMore: ${this.serverHasMoreRecords}, hasMore: ${this.hasMoreRecords}`);
    }
    
    mapFieldTypeToDataTableType(fieldType) {
        const typeMap = {
            'STRING': 'text',
            'TEXTAREA': 'text',
            'EMAIL': 'email',
            'PHONE': 'phone',
            'URL': 'url',
            'CURRENCY': 'currency',
            'PERCENT': 'percent',
            'NUMBER': 'text',
            'DOUBLE': 'number',
            'INTEGER': 'number',
            'DATE': 'text',
            'DATETIME': 'text',
            'TIME': 'text',
            'BOOLEAN': 'boolean',
            'PICKLIST': 'text',
            'MULTIPICKLIST': 'text',
            'REFERENCE': 'text'
        };
        
        return typeMap[fieldType?.toUpperCase()] || 'text';
    }

    formatDate(dateString) {
        if (!dateString) return '';
        
        try {
            const date = new Date(dateString);
            // Format as M/D/YYYY
            return date.toLocaleDateString('en-US', {
                month: 'numeric',
                day: 'numeric',
                year: 'numeric'
            });
        } catch (error) {
            return dateString;
        }
    }

    formatDateTime(dateTimeString) {
        if (!dateTimeString) return '';
        
        try {
            const date = new Date(dateTimeString);
            return date.toLocaleString('en-US', {
                month: 'numeric',
                day: 'numeric',
                year: 'numeric',
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            });
        } catch (error) {
            return dateTimeString;
        }
    }
    
    // ===== EVENT HANDLERS =====
    
    handleRefresh() {
        this.debugLog(`Refresh clicked - Mode: ${this.dataSourceMode}`);

        // Log performance metrics before refresh
        this.logPerformanceMetrics('BEFORE REFRESH');

        // Set a flag to prevent renderedCallback from interfering
        this.isRefreshing = true;

        this.clearData();

        // Force reload by resetting signatures
        this.lastDataSignature = '';
        this.lastUISignature = '';

        // Reset metrics for this refresh cycle
        this._perfMetrics.relatedListLabelAccessCount = 0;
        this._perfMetrics.relatedListLabelCacheHits = 0;
        this._perfMetrics.customFieldNamesListAccessCount = 0;
        this._perfMetrics.customFieldNamesListCacheHits = 0;
        this._perfMetrics.sortOperationCount = 0;
        this._perfMetrics.sortOptimizationSavings = 0;
        this._perfMetrics.configGetterAccessCount = 0;
        this._perfMetrics.configGetterCacheHits = 0;
        this._perfMetrics.flattenARLCallCount = 0;
        this._perfMetrics.flattenARLFieldsProcessed = 0;
        this._perfMetrics.infiniteScrollTriggerCount = 0;
        this._perfMetrics.cardDataGenerationCount = 0;
        this._perfMetrics.cardDataWastedCount = 0;

        // Invalidate signature caches to force fresh comparison
        this._cachedDataSignature = null;
        this._cachedUiSignature = null;

        this.loadData().finally(() => {
            this.isRefreshing = false;
            // Log performance metrics after refresh completes
            setTimeout(() => {
                this.logPerformanceMetrics('AFTER REFRESH');
            }, 100);
        });
    }

    logPerformanceMetrics(label) {
        if (!this.showDebugInfo) return;

        console.log(`\n========== PERFORMANCE METRICS ${label} ==========`);

        console.log(`\n📊 BATCH 1 - Optimizations Applied:`);
        console.log(`✓ FIX #6: Cached relatedListLabel getter`);
        console.log(`  - Label accesses: ${this._perfMetrics.relatedListLabelAccessCount}`);
        console.log(`  - Cache hits: ${this._perfMetrics.relatedListLabelCacheHits}`);
        const labelHitRate = this._perfMetrics.relatedListLabelAccessCount > 0
            ? ((this._perfMetrics.relatedListLabelCacheHits / this._perfMetrics.relatedListLabelAccessCount) * 100).toFixed(1)
            : '0.0';
        console.log(`  - Cache hit rate: ${labelHitRate}%`);

        console.log(`\n✓ FIX #7: Cached customFieldNamesList`);
        console.log(`  - List accesses: ${this._perfMetrics.customFieldNamesListAccessCount}`);
        console.log(`  - Cache hits: ${this._perfMetrics.customFieldNamesListCacheHits}`);
        const listHitRate = this._perfMetrics.customFieldNamesListAccessCount > 0
            ? ((this._perfMetrics.customFieldNamesListCacheHits / this._perfMetrics.customFieldNamesListAccessCount) * 100).toFixed(1)
            : '0.0';
        console.log(`  - Cache hit rate: ${listHitRate}%`);

        console.log(`\n✓ FIX #8: Optimized sorting algorithm`);
        console.log(`  - Sort operations: ${this._perfMetrics.sortOperationCount}`);
        console.log(`  - Value extractions saved: ${this._perfMetrics.sortOptimizationSavings}`);

        console.log(`\n📋 BATCH 2 - Additional Optimizations:`);
        console.log(`✓ FIX #9: Cached config-only getters`);
        console.log(`  - Getter accesses: ${this._perfMetrics.configGetterAccessCount}`);
        console.log(`  - Cache hits: ${this._perfMetrics.configGetterCacheHits}`);
        const configHitRate = this._perfMetrics.configGetterAccessCount > 0
            ? ((this._perfMetrics.configGetterCacheHits / this._perfMetrics.configGetterAccessCount) * 100).toFixed(1)
            : '0.0';
        console.log(`  - Cache hit rate: ${configHitRate}%`);

        console.log(`\n🔍 FIX #10 BASELINE: ARL field flattening`);
        console.log(`  - Flatten calls: ${this._perfMetrics.flattenARLCallCount}`);
        console.log(`  - Fields processed: ${this._perfMetrics.flattenARLFieldsProcessed}`);
        const avgFieldsPerCall = this._perfMetrics.flattenARLCallCount > 0
            ? (this._perfMetrics.flattenARLFieldsProcessed / this._perfMetrics.flattenARLCallCount).toFixed(1)
            : '0';
        console.log(`  - Avg fields per call: ${avgFieldsPerCall}`);
        console.log(`  - Opportunity: Cache field mapping logic`);

        console.log(`\n🔍 FIX #11 BASELINE: Infinite scroll triggers`);
        console.log(`  - Scroll handler triggers: ${this._perfMetrics.infiniteScrollTriggerCount}`);
        console.log(`  - Opportunity: Debounce to reduce redundant calls`);

        console.log(`\n🔍 FIX #12 BASELINE: Card data generation`);
        console.log(`  - Card data generated: ${this._perfMetrics.cardDataGenerationCount}`);
        console.log(`  - Wasted (not in cards mode): ${this._perfMetrics.cardDataWastedCount}`);
        const wasteRate = this._perfMetrics.cardDataGenerationCount > 0
            ? ((this._perfMetrics.cardDataWastedCount / this._perfMetrics.cardDataGenerationCount) * 100).toFixed(1)
            : '0.0';
        console.log(`  - Waste rate: ${wasteRate}%`);
        console.log(`  - Opportunity: Only generate when displayMode === 'cards'`);

        console.log(`\n🎯 General Metrics:`);
        console.log(`  - renderedCallback calls: ${this._perfMetrics.renderCallbackCount}`);
        console.log(`  - Last render time: ${this._perfMetrics.lastRenderTime.toFixed(2)}ms`);
        console.log(`================================================\n`);
    }
    
    async handleViewMore() {
        this.debugLog('=== View More/Load More Button Clicked ===');
        this.debugLog('Current state:', {
            displayedRecordsLength: this.displayedRecords.length,
            allRecordsLength: this.allRecords.length,
            hasMoreRecords: this.hasMoreRecords,
            serverHasMoreRecords: this.serverHasMoreRecords,
            isStandardType: this.isStandardType,
            currentOffset: this.currentOffset
        });

        this.isLoadingMore = true;

        try {
            // Simple client-side pagination - all records already loaded (up to 50)
            this.debugLog('>>> Displaying more client-side records');
            this.currentOffset += this.initialRecordsToLoad;
            this.updateDisplayedRecords();
        } catch (error) {
            this.logError('Error loading more records:', error);
        } finally {
            this.isLoadingMore = false;
        }
    }
    
    handleViewAll() {
        this.debugLog('View All clicked');
        
        // If viewAllUrl is configured, navigate to it
        if (this.viewAllUrl && this.viewAllUrl.trim() !== '') {
            this.debugLog('Navigating to View All URL:', this.viewAllUrl);
            this.navigateToViewAllUrl();
        } else {
            // Fall back to showing all records in current table
            this.debugLog('No View All URL configured, showing all records in table');
            if (this.allRecords.length > 0) {
                this.displayedRecords = [...this.allRecords];
                this.hasMoreRecords = false;
                this.debugLog('Showing all', this.displayedRecords.length, 'records');
            }
        }
    }

    handleSort(event) {
        try {
            const { fieldName: sortedBy, sortDirection } = event.detail;
            this.debugLog('Column sort requested:', sortedBy, sortDirection);

            this.sortedBy = sortedBy;
            this.sortDirection = sortDirection;

            // Preserve the number of records currently displayed
            const currentlyDisplayedCount = this.displayedRecords.length;

            // Sort the allRecords array
            this.sortData(sortedBy, sortDirection);

            // Calculate offset to maintain the same number of visible records
            // currentOffset represents how many additional pages have been loaded beyond the first
            this.currentOffset = Math.max(0, currentlyDisplayedCount - this.initialRecordsToLoad);
            this.updateDisplayedRecords();

        } catch (error) {
            this.logError('Error handling sort:', error);
        }
    }

    sortData(fieldName, direction) {
        try {
            this._perfMetrics.sortOperationCount++;
            this.debugLog('Sorting data by field:', fieldName, 'direction:', direction);

            // Fix #8: Pre-extract and normalize all values ONCE before sorting
            // This avoids calling getFieldValue() N*log(N) times during sort comparisons
            const recordsWithValues = this.allRecords.map(record => {
                let value = this.getFieldValue(record, fieldName);

                // Normalize the value once
                if (value != null && typeof value !== 'string' && typeof value !== 'number') {
                    value = String(value);
                }

                return { record, value };
            });

            // Track optimization savings
            const comparisonCount = Math.ceil(this.allRecords.length * Math.log2(this.allRecords.length));
            const savedExtractions = comparisonCount * 2 - this.allRecords.length;
            this._perfMetrics.sortOptimizationSavings += savedExtractions;

            // Now sort using the pre-extracted values
            recordsWithValues.sort((a, b) => {
                const aVal = a.value;
                const bVal = b.value;

                // Handle null/undefined values
                if (aVal == null && bVal == null) return 0;
                if (aVal == null) return direction === 'asc' ? -1 : 1;
                if (bVal == null) return direction === 'asc' ? 1 : -1;

                // Perform comparison
                let result = 0;
                if (aVal < bVal) {
                    result = -1;
                } else if (aVal > bVal) {
                    result = 1;
                }

                return direction === 'asc' ? result : -result;
            });

            // Extract sorted records
            this.allRecords = recordsWithValues.map(item => item.record);
            this.debugLog('Data sorted successfully');

        } catch (error) {
            this.logError('Error sorting data:', error);
        }
    }

    getFieldValue(record, fieldName) {
        try {
            // Handle direct field access
            if (record.hasOwnProperty(fieldName)) {
                return record[fieldName];
            }
            
            // Handle relationship fields (e.g., Account.Name)
            if (fieldName.includes('.')) {
                const [relationshipName, targetField] = fieldName.split('.');
                if (record[relationshipName] && record[relationshipName][targetField]) {
                    return record[relationshipName][targetField];
                }
            }
            
            // For URL columns, use the original field value for sorting
            if (fieldName === 'recordUrl' && this.columns.length > 0) {
                // Get the first column's field name
                const firstField = this.columns[0].fieldName;
                if (firstField && record[firstField]) {
                    return record[firstField];
                }
            }
            
            return null;
        } catch (error) {
            this.logError('Error getting field value:', error);
            return null;
        }
    }
    
    clearSort() {
        this.sortedBy = '';
        this.sortDirection = 'asc';
    }

    handleLoadMore(event) {
        try {
            this._perfMetrics.infiniteScrollTriggerCount++;
            this.debugLog('Infinite scroll load more triggered');

            if (this.isLoadingMore || !this.hasMoreRecords) {
                return;
            }

            // Debounce scroll handler to prevent redundant calls during fast scrolling
            if (this._scrollDebounceTimeout) {
                clearTimeout(this._scrollDebounceTimeout);
            }

            this._scrollDebounceTimeout = setTimeout(async () => {
                if (this.isLoadingMore || !this.hasMoreRecords) {
                    this.debugLog('Infinite scroll aborted:', {
                        isLoadingMore: this.isLoadingMore,
                        hasMoreRecords: this.hasMoreRecords
                    });
                    return;
                }

                this.debugLog('=== Infinite Scroll Triggered ===');
                this.debugLog('Scroll state:', {
                    displayedRecordsLength: this.displayedRecords.length,
                    allRecordsLength: this.allRecords.length,
                    hasMoreRecords: this.hasMoreRecords,
                    serverHasMoreRecords: this.serverHasMoreRecords,
                    isStandardType: this.isStandardType
                });

                this.isLoadingMore = true;

                try {
                    // Simple client-side pagination - all records already loaded (up to 50)
                    this.debugLog('>>> Infinite scroll displaying client-side records');
                    this.currentOffset += this.initialRecordsToLoad;
                    this.updateDisplayedRecords();
                } catch (error) {
                    this.logError('Error loading more records:', error);
                } finally {
                    setTimeout(() => {
                        this.isLoadingMore = false;
                    }, 300);
                }
            }, 250); // 250ms debounce delay

        } catch (error) {
            this.logError('Error in load more:', error);
            this.isLoadingMore = false;
        }
    }

    navigateToViewAllUrl() {
        const siteBaseUrl = this.getSiteBaseUrl();
        const cleanUrl = this.viewAllUrl.startsWith('/') ? this.viewAllUrl : '/' + this.viewAllUrl;
        const fullUrl = siteBaseUrl + cleanUrl;
        
        this.debugLog('View All URL:', fullUrl);
        
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: fullUrl
            }
        });
    }
    
    handleFileClick(event) {
        event.preventDefault();
        const target = event.currentTarget;
        const fileName = target.dataset.name;
        const fileSize = target.dataset.size;
        const contentDocumentId = target.dataset.id;
        const isImage = target.dataset.isImage === 'true';
        const downloadUrl = target.dataset.downloadUrl;
        
        this.debugLog('File clicked:', { fileName, isImage, contentDocumentId });
        
        if (isImage) {
            this.handleImagePreview(contentDocumentId, fileName, fileSize, downloadUrl);
        } else {
            this.handleDirectDownload(downloadUrl, fileName);
        }
    }

    async handleImagePreview(contentDocumentId, fileName, fileSize, downloadUrl) {
        this.modalImageName = fileName;
        this.modalImageSize = fileSize;
        this.modalImageLoadError = '';
        this.modalImageUrl = '';
        this.modalDownloadUrl = downloadUrl;
        this.isLoadingModalImage = true;
        this.showImageModal = true;
        
        try {
            const base64Url = await getImageAsBase64({ contentDocumentId });
            
            if (base64Url) {
                this.modalImageUrl = base64Url;
                this.isLoadingModalImage = false;
                this.debugLog('Image loaded successfully');
            } else {
                throw new Error('No image data returned');
            }
        } catch (error) {
            this.logError('Error loading image:', error);
            this.modalImageLoadError = 'Failed to load image: ' + (error.body?.message || error.message);
            this.isLoadingModalImage = false;
        }
    }

    handleDirectDownload(downloadUrl, fileName) {
        if (!downloadUrl) {
            this.logError('No download URL available for file:', fileName);
            return;
        }

        this.debugLog('Initiating download:', fileName);

        // Use window.open for Experience Cloud compatibility
        // This works better with Locker Service than programmatic link clicks
        try {
            // Open in new window/tab - browser will handle as download if content-disposition is set
            window.open(downloadUrl, '_blank');
        } catch (error) {
            this.logError('Error opening download URL:', error);
            // Fallback: try to navigate to the URL directly
            window.location.href = downloadUrl;
        }
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

    handleModalImageError(event) {
        const img = event.target;
        const failedUrl = img.src;
        
        this.modalImageLoadError = `Failed to load image: ${failedUrl}`;
        
        // Try fallback to download URL if different
        if (failedUrl === this.modalImageUrl && this.modalDownloadUrl && failedUrl !== this.modalDownloadUrl) {
            this.modalImageUrl = this.modalDownloadUrl;
        }
    }

    handleModalImageLoad() {
        this.modalImageLoadError = '';
    }

    // ===== DELETE FUNCTIONALITY =====

    async checkDeletePermission() {
        try {
            if (!this.detectedObjectType || !this.enableRecordDeletion) {
                this.canDeleteRecords = false;
                return;
            }

            this.canDeleteRecords = await canDeleteObject({
                objectApiName: this.detectedObjectType
            });

            this.debugLog('Delete permission check:', {
                objectType: this.detectedObjectType,
                canDelete: this.canDeleteRecords
            });

        } catch (error) {
            this.logError('Error checking delete permission:', error);
            this.canDeleteRecords = false;
        }
    }

    async handleDeleteRecord(recordId) {
        if (!recordId) {
            this.showToast('Error', 'No record ID provided', 'error');
            return;
        }

        this.debugLog('Deleting record:', recordId);

        try {
            await deleteRecord({ recordId: recordId });

            // Remove from allRecords array
            this.allRecords = this.allRecords.filter(record => record.Id !== recordId);

            // Update displayed records
            this.updateDisplayedRecords();

            this.showToast('Success', 'Record deleted successfully', 'success');

            this.debugLog('Record deleted successfully:', recordId);

        } catch (error) {
            this.logError('Error deleting record:', error);
            const errorMessage = error.body?.message || error.message || 'Unknown error occurred';
            this.showToast('Error', 'Failed to delete record: ' + errorMessage, 'error');
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}