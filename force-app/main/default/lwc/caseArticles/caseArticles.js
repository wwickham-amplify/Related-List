import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCaseArticles from '@salesforce/apex/CaseArticlesController.getCaseArticles';

export default class CaseArticles extends LightningElement {
    @api recordId; // Current case record ID
    @api componentTitle = 'Case Articles'; // Configurable title
    @api iconName = ''; // Static SLDS icon name (e.g., 'standard:knowledge')
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
            // Add articleUrl to each article for proper href display
            this.allArticles = data.map(article => ({
                ...article,
                articleUrl: this.constructArticleUrl(article.urlName) || '#'
            }));
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
        return !this.isLoading && !this.error && this.displayedArticles && this.displayedArticles.length > 0;
    }

    get hasNoArticles() {
        return !this.isLoading && !this.error && this.allArticles.length === 0;
    }

    get hasError() {
        return !!this.error;
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

    // Simple check - only show icon if it's provided and properly formatted
    get shouldShowIcon() {
        return this.iconName && this.iconName.includes(':');
    }

    // Handle refresh button click
    async handleRefresh() {
        console.log('Manual refresh requested for case articles');
        this.isLoading = true;
        this.error = null; // Clear any existing errors
        
        try {
            await this.refresh();
            this.showToast('Success', 'Articles refreshed', 'success');
        } catch (error) {
            console.error('Error during refresh:', error);
            this.showToast('Error', 'Failed to refresh articles: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Navigation helper methods
    getSiteBaseUrl() {
        // Get the current site's base URL
        const currentUrl = window.location.href;
        const url = new URL(currentUrl);
        
        console.log('Current URL for site base extraction:', currentUrl);
        console.log('URL pathname:', url.pathname);
        
        // For Experience Cloud sites, we need to capture the full site path
        if (url.hostname.includes('.my.site.com') || 
            url.hostname.includes('.force.com') ||
            url.hostname.includes('salesforce-experience.com')) {
            
            // Salesforce-hosted site (including sandbox URLs)
            const pathParts = url.pathname.split('/').filter(part => part !== '');
            console.log('Path parts:', pathParts);
            
            if (pathParts.length > 0) {
                // Include the full site path
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

    constructArticleUrl(urlName) {
        if (!urlName) {
            return null;
        }

        try {
            const siteBaseUrl = this.getSiteBaseUrl();
            const fullUrl = `${siteBaseUrl}/article/${urlName}`;
            console.log('Constructed article URL:', fullUrl, 'from urlName:', urlName);
            return fullUrl;
        } catch (error) {
            console.error('Error constructing article URL:', error);
            return null;
        }
    }

    // Handle article link click
    handleRecordNavigation(event) {
        event.preventDefault();
        
        const urlName = event.currentTarget.dataset.urlName;
        const articleId = event.currentTarget.dataset.articleId;
        
        console.log('Article navigation clicked:', { urlName, articleId });
        
        if (!urlName) {
            console.error('No urlName found for article:', articleId);
            this.showToast('Error', 'Unable to navigate to article', 'error');
            return;
        }

        const articleUrl = this.constructArticleUrl(urlName);
        if (articleUrl) {
            console.log('Navigating to article URL:', articleUrl);
            window.location.href = articleUrl;
        } else {
            console.error('Failed to construct article URL for:', urlName);
            this.showToast('Error', 'Unable to navigate to article', 'error');
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
                // Add articleUrl to each article for proper href display
                this.allArticles = result.map(article => ({
                    ...article,
                    articleUrl: this.constructArticleUrl(article.urlName) || '#'
                }));
                this.displayedArticles = this.allArticles.slice(0, this.initialLoadCount);
                this.error = null;
                this.isLoading = false;
            })
            .catch(error => {
                this.error = error;
                this.allArticles = [];
                this.displayedArticles = [];
                this.isLoading = false;
                throw error; // Re-throw for handleRefresh to catch
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