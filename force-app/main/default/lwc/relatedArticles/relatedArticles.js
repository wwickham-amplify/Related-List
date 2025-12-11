import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRelatedArticles from '@salesforce/apex/RelatedArticlesController.getRelatedArticles';

export default class RelatedArticles extends LightningElement {
    @api recordId; // Knowledge Article Version Id
    componentTitle = 'Related Articles';
    //@api iconName = ''; // Static SLDS icon name (e.g., 'standard:knowledge')
    //@api initialLoadCount = 3; // Number of articles to show initially
    //@api loadMoreCount = 3; // Number of articles to load each time "Load More" is clicked
    
    tempArticlesList = []; // All articles from server
    displayedArticles = []; // Currently displayed articles
    //@track isLoading = true;
    error = null;

    // Wire method to get related articles
    @wire(getRelatedArticles, { currentArticleId: '$recordId' })
    wiredArticles({ error, data }) {
        this.isLoading = false;
        if (data) {
            console.log("Data: " + data);
            this.tempArticlesList = data.map(article => ({
                ...article,
                articleUrl: this.constructArticleUrl(article.urlName) || '#'
            }));
            this.displayedArticles = this.tempArticlesList.slice(0, this.initialLoadCount);
            this.displayedArticles.forEach(article => {
                console.log(article.title + ' ' + article.articleId);
            });
            this.error = null;
        } else if (error) {
            this.error = error;
            this.displayedArticles = [];
            console.error('Error loading case articles:', error);
        }
    }

    // Computed properties
    get hasArticles() {
        return !this.error && this.displayedArticles && this.displayedArticles.length > 0;
    }

    get hasNoArticles() {
        return !this.error && this.tempArticlesList.length === 0;
    }

    get hasError() {
        return !!this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || this.error?.message || 'An error occurred loading articles';
    }

    get totalArticleCount() {
        return this.tempArticlesList ? this.tempArticlesList.length : 0;
    }

    get displayedArticleCount() {
        return this.displayedArticles ? this.displayedArticles.length : 0;
    }

    get listTitle() {
        return this.componentTitle;
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
            // Custom domain - ignore subpaths for Prod, just use custom domain
            /*const pathParts = url.pathname.split('/').filter(part => part !== '');
            if (pathParts.length > 0) {
                // Check if we're in a subpath (like /portal/)
                const potentialSitePath = pathParts[0];
                const siteBaseUrl = `${url.origin}/${potentialSitePath}`;
                console.log('Custom domain with path detected:', siteBaseUrl);
                return siteBaseUrl;
            }*/
            
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