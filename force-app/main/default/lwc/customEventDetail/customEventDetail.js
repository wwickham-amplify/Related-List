import { LightningElement, api, wire } from 'lwc';
import getEventDetail from '@salesforce/apex/CalendarController.getEventDetail';
import Id from '@salesforce/user/Id';

export default class CustomEventDetail extends LightningElement {
    @api recordId;
    extractedRecordId;
    eventData;
    error;
    userId = Id;

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
            segment.toLowerCase() === 'event'
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
    @wire(getEventDetail, { eventId: '$currentRecordId', userId: '$userId' })
    wiredEvent({ error, data }) {
        console.log('Wire fired - eventId:', this.currentRecordId, 'userId:', this.userId);
        if (data) {
            console.log('Event data received:', data);
            this.eventData = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.eventData = undefined;
            console.error('Error loading event:', error);
        }
    }

    // Check if this is a Tutor user
    get isTutorUser() {
        return this.eventData?.UserTutorType === 'Tutor';
    }

    // Check if this is a ResourceAbsence event for Tutor
    get isTutorResourceAbsence() {
        return this.eventData?.WhatType === 'ResourceAbsence' && this.isTutorUser;
    }

    // Get display subject (without RA-# - now shown in Related To field)
    get displaySubject() {
        return this.eventData?.Subject || '';
    }

    get subject() {
        return this.eventData?.Subject || '';
    }

    get formattedStartDateTime() {
        if (!this.eventData?.StartDateTime) return '';
        return this.formatDateTime(this.eventData.StartDateTime);
    }

    get formattedEndDateTime() {
        if (!this.eventData?.EndDateTime) return '';
        return this.formatDateTime(this.eventData.EndDateTime);
    }

    get description() {
        return this.eventData?.Description || '';
    }

    get location() {
        return this.eventData?.Location || '';
    }

    get absenceType() {
        return this.eventData?.AbsenceType || '';
    }

    get relatedToValue() {
        return this.eventData?.AppointmentNumber || this.eventData?.AbsenceNumber || '';
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
    }
}