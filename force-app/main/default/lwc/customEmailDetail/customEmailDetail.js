import { LightningElement, api, wire } from 'lwc';
import getEmailDetail from '@salesforce/apex/CalendarController.getEmailDetail';

export default class CustomEmailDetail extends LightningElement {
    @api recordId;
    extractedRecordId;
    emailData;
    error;

    connectedCallback() {
        console.log('connectedCallback - recordId from @api:', this.recordId);
        console.log('Current URL:', window.location.pathname);
        // Extract recordId from URL if not provided via @api
        if (!this.recordId || this.recordId === '{!recordId}' || this.recordId === 'undefined') {
            this.extractedRecordId = this.extractRecordIdFromUrl();
            console.log('Extracted recordId from URL:', this.extractedRecordId);
        }
        console.log('Final currentRecordId:', this.currentRecordId);
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
        console.log('Wire fired - eventId:', this.currentRecordId);
        if (data) {
            console.log('Email data received:', data);
            this.emailData = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.emailData = undefined;
            console.error('Error loading email:', error);
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