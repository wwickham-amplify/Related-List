import { LightningElement, api, wire } from 'lwc';
import getEmailDetail from '@salesforce/apex/CalendarController.getEmailDetail';

export default class CustomEmailDetail extends LightningElement {
    @api recordId;
    extractedRecordId;
    emailData;
    error;
    htmlRendered = false;

    connectedCallback() {
        // console.log('connectedCallback - recordId from @api:', this.recordId);
        // console.log('Current URL:', window.location.pathname);
        // Extract recordId from URL if not provided via @api
        if (!this.recordId || this.recordId === '{!recordId}' || this.recordId === 'undefined') {
            this.extractedRecordId = this.extractRecordIdFromUrl();
            // console.log('Extracted recordId from URL:', this.extractedRecordId);
        }
        // console.log('Final currentRecordId:', this.currentRecordId);
    }

    renderedCallback() {
        console.log('[DEBUG] renderedCallback called');
        console.log('[DEBUG] emailData exists:', !!this.emailData);
        console.log('[DEBUG] HtmlBody exists:', !!(this.emailData && this.emailData.HtmlBody));
        console.log('[DEBUG] htmlRendered flag:', this.htmlRendered);

        // Render HTML body once when data is available
        if (this.emailData && this.emailData.HtmlBody && !this.htmlRendered) {
            console.log('[DEBUG] Conditions met - calling renderHtmlBody()');
            this.renderHtmlBody();
            this.htmlRendered = true;
        } else {
            console.log('[DEBUG] Conditions NOT met for rendering');
        }
    }

    renderHtmlBody() {
        console.log('[DEBUG] === renderHtmlBody() START ===');
        try {
            const container = this.template.querySelector('[data-html-container]');
            console.log('[DEBUG] Container element found:', !!container);

            if (!container) {
                console.error('[DEBUG] Container not found!');
                return;
            }

            if (!this.emailData.HtmlBody) {
                console.error('[DEBUG] No HtmlBody data!');
                return;
            }

            console.log('[DEBUG] HtmlBody length:', this.emailData.HtmlBody.length);
            console.log('[DEBUG] HtmlBody preview (first 200 chars):', this.emailData.HtmlBody.substring(0, 200));

            // Clear any existing content
            console.log('[DEBUG] Clearing existing content...');
            while (container.firstChild) {
                container.removeChild(container.firstChild);
            }
            console.log('[DEBUG] Container cleared');

            // Parse the HTML string using DOMParser
            console.log('[DEBUG] Creating DOMParser...');
            const parser = new DOMParser();
            console.log('[DEBUG] Parsing HTML string...');
            const doc = parser.parseFromString(this.emailData.HtmlBody, 'text/html');
            console.log('[DEBUG] HTML parsed successfully');
            console.log('[DEBUG] Parsed doc.head exists:', !!doc.head);
            console.log('[DEBUG] Parsed doc.body exists:', !!doc.body);

            // First, append any style tags from the head
            if (doc.head) {
                const styleTags = doc.head.querySelectorAll('style');
                console.log('[DEBUG] Found', styleTags.length, 'style tags in head');
                styleTags.forEach((styleTag, index) => {
                    console.log(`[DEBUG] Appending style tag ${index + 1}/${styleTags.length}`);
                    console.log('[DEBUG] Style content length:', styleTag.textContent.length);
                    container.appendChild(styleTag.cloneNode(true));
                });
            }

            // Add custom override styles to fix email layout
            console.log('[DEBUG] Adding custom override styles...');
            const overrideStyle = document.createElement('style');
            overrideStyle.textContent = `
                /* Override fixed widths in email HTML */
                table, .section {
                    max-width: 100% !important;
                    width: 100% !important;
                }

                /* Ensure email content doesn't overflow */
                img {
                    max-width: 100% !important;
                    height: auto !important;
                }
            `;
            container.appendChild(overrideStyle);
            console.log('[DEBUG] Override styles added');

            // Then append all body children
            const bodyChildren = doc.body.childNodes;
            console.log('[DEBUG] Number of body childNodes:', bodyChildren.length);
            console.log('[DEBUG] Starting to append body nodes...');
            bodyChildren.forEach((node, index) => {
                console.log(`[DEBUG] Appending body node ${index + 1}/${bodyChildren.length}, type:`, node.nodeType, 'nodeName:', node.nodeName);
                const clonedNode = node.cloneNode(true);
                container.appendChild(clonedNode);
            });
            console.log('[DEBUG] All nodes appended successfully');
            console.log('[DEBUG] Container childNodes after append:', container.childNodes.length);

            // Fix inline styles that restrict width
            console.log('[DEBUG] Fixing inline styles...');
            const allElements = container.querySelectorAll('*');
            console.log('[DEBUG] Checking', allElements.length, 'total elements for max-width styles');

            let modifiedCount = 0;
            allElements.forEach((element) => {
                // Check if element has max-width style set
                if (element.style.maxWidth && element.style.maxWidth !== '100%') {
                    console.log(`[DEBUG] Element ${modifiedCount + 1}: ${element.tagName}, original max-width:`, element.style.maxWidth);

                    // Override max-width to 100%
                    element.style.maxWidth = '100%';
                    modifiedCount++;
                    console.log(`[DEBUG] Element ${modifiedCount}: max-width changed to 100%`);
                }
            });
            console.log('[DEBUG] Modified', modifiedCount, 'elements with max-width');

            // Also fix width attributes on tables
            const tablesWithWidth = container.querySelectorAll('table[width], .section[width]');
            console.log('[DEBUG] Found', tablesWithWidth.length, 'tables/sections with width attribute');
            tablesWithWidth.forEach((element, index) => {
                console.log(`[DEBUG] Table ${index + 1}: removing width attribute, was:`, element.getAttribute('width'));
                element.style.width = '100%';
                element.style.maxWidth = '100%';
            });

            console.log('[DEBUG] Inline styles fixed');
            console.log('[DEBUG] === renderHtmlBody() END ===');
        } catch (error) {
            console.error('[DEBUG] ERROR in renderHtmlBody():', error);
            console.error('[DEBUG] Error stack:', error.stack);
        }
    }

    extractRecordIdFromUrl() {
        const url = window.location.pathname;

        // Pattern: /event/{recordId}/...
        const pathSegments = url.split('/');
        const eventIndex = pathSegments.findIndex(segment =>
            segment.toLowerCase() === 'emailmessage'
        );

        if (eventIndex !== -1 && pathSegments.length > eventIndex + 1) {
            const potentialId = pathSegments[eventIndex + 1];
            // Validate it looks like a Salesforce ID (18 or 15 characters, alphanumeric)
            if (/^[a-zA-Z0-9]{15,18}$/.test(potentialId)) {
                return potentialId;
            }
        }

        return null;
    }

    get currentRecordId() {
        // Priority 1: Use @api recordId if valid
        if (this.recordId &&
            this.recordId !== '{!recordId}' &&
            this.recordId !== 'undefined' &&
            this.recordId !== 'null') {
            return this.recordId;
        }

        // Priority 2: Use extracted recordId from URL
        if (this.extractedRecordId) {
            return this.extractedRecordId;
        }

        return null;
    }

    // Wire to get Event record data from Apex using CalendarController
    @wire(getEmailDetail, { recordId: '$currentRecordId' })
    wiredEmail({ error, data }) {
        console.log('[DEBUG] === Wire Method Called ===');
        console.log('[DEBUG] currentRecordId:', this.currentRecordId);
        if (data) {
            console.log('[DEBUG] Email data received from Apex');
            console.log('[DEBUG] Data keys:', Object.keys(data));
            console.log('[DEBUG] HtmlBody exists in data:', !!data.HtmlBody);
            console.log('[DEBUG] HtmlBody length:', data.HtmlBody ? data.HtmlBody.length : 0);
            this.emailData = data;
            this.error = undefined;
            this.htmlRendered = false; // Reset flag to trigger re-render
            console.log('[DEBUG] htmlRendered flag reset to false');
        } else if (error) {
            this.error = error;
            this.emailData = undefined;
            this.htmlRendered = false;
            console.error('[DEBUG] Error loading email:', error);
        }
    }

    // Get display subject (without RA-# - now shown in Related To field)
    /*get displaySubject() {
        return this.emailData?.Subject || '';
    }

    get subject() {
        return this.emailData?.Subject || '';
    }

    get formattedStartDateTime() {
        if (!this.emailData?.StartDateTime) return '';
        return this.formatDateTime(this.emailData.StartDateTime);
    }

    get formattedEndDateTime() {
        if (!this.emailData?.EndDateTime) return '';
        return this.formatDateTime(this.emailData.EndDateTime);
    }

    get description() {
        return this.emailData?.Description || '';
    }

    get location() {
        return this.emailData?.Location || '';
    }

    get absenceType() {
        return this.emailData?.AbsenceType || '';
    }

    get relatedToValue() {
        return this.emailData?.AppointmentNumber || this.emailData?.AbsenceNumber || '';
    }

    formatDateTime(dateTimeString) {
        const date = new Date(dateTimeString);

        // Format: 11/18/2025 7:00 AM
        const options = {
            month: '2-digit',
            day: '2-digit',
            year: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        };

        return date.toLocaleString('en-US', options);
    }*/
}