import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCaseArticles from '@salesforce/apex/CaseArticlesController.getCaseArticles';

export default class CaseArticles extends LightningElement {
    @api recordId; // Current case record ID
    @api componentTitle = 'Case Articles'; // Configurable title
    @api titleLevel = 'Heading 3'; // LWR typography level
    @api iconName = 'standard:knowledge'; // SLDS icon name
    @api initialLoadCount = 3; // Number of articles to show initially
    @api loadMoreCount = 3; // Number of articles to load each time "Load More" is clicked
    
    @track allArticles = []; // All articles from server
    @track displayedArticles = []; // Currently displayed articles
    @track isLoading = true;
    @track error = null;

    // Wire method to get case articles
    @wire(getCaseArticles, { caseId: '$recordId' })
    wiredArticles({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.allArticles = data;
            this.displayedArticles = this.allArticles.slice(0, this.initialLoadCount);
            this.error = null;
        } else if (error) {
            this.error = error;
            this.allArticles = [];
            this.displayedArticles = [];
            console.error('Error loading case articles:', error);
        }
    }

    // Computed properties
    get hasArticles() {
        return this.displayedArticles && this.displayedArticles.length > 0;
    }

    get hasNoArticles() {
        return !this.isLoading && !this.error && this.allArticles.length === 0;
    }

    get hasError() {
        return this.error != null;
    }

    get errorMessage() {
        return this.error?.body?.message || this.error?.message || 'An error occurred loading articles';
    }

    get totalArticleCount() {
        return this.allArticles ? this.allArticles.length : 0;
    }

    get displayedArticleCount() {
        return this.displayedArticles ? this.displayedArticles.length : 0;
    }

    get listTitle() {
        return `${this.componentTitle} (${this.displayedArticleCount}${this.hasMoreToLoad ? ` of ${this.totalArticleCount}` : ''})`;
    }

    get hasMoreToLoad() {
        return this.displayedArticleCount < this.totalArticleCount;
    }

    get loadMoreButtonLabel() {
        const remaining = this.totalArticleCount - this.displayedArticleCount;
        const toLoad = Math.min(remaining, this.loadMoreCount);
        return `Load ${toLoad} More`;
    }

    get titleClass() {
        // Map LWR typography levels to SLDS classes
        const typographyMap = {
            'Heading 1': 'slds-text-heading_large',
            'Heading 2': 'slds-text-heading_medium',
            'Heading 3': 'slds-text-heading_small',
            'Heading 4': 'slds-text-title_caps',
            'Heading 5': 'slds-text-title',
            'Heading 6': 'slds-text-body_regular',
            'Paragraph 1': 'slds-text-body_regular',
            'Paragraph 2': 'slds-text-body_small'
        };
        return typographyMap[this.titleLevel] || 'slds-text-heading_small';
    }

    // Handle article link clicks
    handleArticleClick(event) {
        event.preventDefault();
        const urlName = event.currentTarget.dataset.urlName;
        const articleId = event.currentTarget.dataset.articleId;
        
        if (urlName) {
            // Navigate to the article using the URL name
            const articleUrl = `/article/${urlName}`;
            window.open(articleUrl, '_blank');
        } else {
            console.warn('No URL name found for article:', articleId);
        }
    }

    // Handle load more button click
    handleLoadMore() {
        const currentCount = this.displayedArticleCount;
        const newCount = Math.min(currentCount + this.loadMoreCount, this.totalArticleCount);
        this.displayedArticles = this.allArticles.slice(0, newCount);
    }

    // Public method to refresh the list
    @api
    refresh() {
        this.isLoading = true;
        // Re-execute the wire by clearing and resetting
        return getCaseArticles({ caseId: this.recordId })
            .then(result => {
                this.allArticles = result;
                this.displayedArticles = this.allArticles.slice(0, this.initialLoadCount);
                this.error = null;
                this.isLoading = false;
            })
            .catch(error => {
                this.error = error;
                this.allArticles = [];
                this.displayedArticles = [];
                this.isLoading = false;
                this.showToast('Error', 'Failed to refresh articles', 'error');
            });
    }

    // Utility method to show toast messages
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}