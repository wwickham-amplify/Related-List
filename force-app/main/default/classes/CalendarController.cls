public with sharing class CalendarController {
    // Constants for object type names
    private static final String OBJECT_TYPE_SERVICE_APPOINTMENT = 'ServiceAppointment';
    private static final String OBJECT_TYPE_RESOURCE_ABSENCE = 'ResourceAbsence';

    @AuraEnabled(cacheable=true)
    public static List<EventWrapper> getEvents(String userId, Integer year, Integer month) {
        // Convert month from JavaScript (0-11) to Salesforce (1-12)
        Integer salesforceMonth = month + 1;

        // Calculate first and last day of the month
        Date firstDay = Date.newInstance(year, salesforceMonth, 1);
        Date lastDay = firstDay.addMonths(1).addDays(-1);

        // Expand range by ±45 days for better coverage and caching
        Date expandedStartDate = firstDay.addDays(-45);
        Date expandedEndDate = lastDay.addDays(45);

        // Convert to DateTime for querying
        DateTime startDateTime = DateTime.newInstance(expandedStartDate, Time.newInstance(0, 0, 0, 0));
        DateTime endDateTime = DateTime.newInstance(expandedEndDate, Time.newInstance(23, 59, 59, 0));

        try {
            // Query the User's Contact to get Tutor_PLS_or_Both__c field
            String userTutorType = null;
            List<User> users = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
            if (!users.isEmpty() && users[0].ContactId != null) {
                List<Contact> contacts = [SELECT Tutor_PLS_or_Both__c FROM Contact WHERE Id = :users[0].ContactId LIMIT 1];
                if (!contacts.isEmpty()) {
                    userTutorType = contacts[0].Tutor_PLS_or_Both__c;
                }
            }

            // Determine if user is a Tutor only
            // Only Tutors see ResourceAbsences as Events with Absence_Unavailable color
            // PLS and "PLS and Tutor" see ResourceAbsences as ResourceAbsence records
            Boolean isTutorUser = userTutorType == 'Tutor';

            // Query events
            // For Tutors only: include ResourceAbsence-related Events (use Event.Subject and link to Event with Absence_Unavailable color)
            // For PLS and "PLS and Tutor": exclude ResourceAbsence-related Events (we'll query ResourceAbsences directly)
            List<Event> events;
            if (isTutorUser) {
                // Include all events including ResourceAbsence-related events
                events = [
                    SELECT Id, Subject, StartDateTime, EndDateTime, IsAllDayEvent, Description, Location, WhatId, What.Type, CreatedDate, LastModifiedDate
                    FROM Event
                    WHERE OwnerId = :userId
                    AND StartDateTime <= :endDateTime
                    AND EndDateTime >= :startDateTime
                    ORDER BY StartDateTime ASC
                ];
            } else {
                // Exclude ResourceAbsence-related events
                events = [
                    SELECT Id, Subject, StartDateTime, EndDateTime, IsAllDayEvent, Description, Location, WhatId, What.Type, CreatedDate, LastModifiedDate
                    FROM Event
                    WHERE OwnerId = :userId
                    AND StartDateTime <= :endDateTime
                    AND EndDateTime >= :startDateTime
                    AND (What.Type != :OBJECT_TYPE_RESOURCE_ABSENCE OR What.Type = null)
                    ORDER BY StartDateTime ASC
                ];
            }

            // Query ResourceAbsences directly for PLS and "PLS and Tutor" users
            List<ResourceAbsence> resourceAbsences = new List<ResourceAbsence>();
            if (!isTutorUser) {
                resourceAbsences = [
                    SELECT Id, Type, AbsenceNumber, Resource_User_Id__c, Start, End, FSL__Duration_In_Minutes__c,
                           ResourceId, Resource.Name
                    FROM ResourceAbsence
                    WHERE Resource_User_Id__c = :userId
                    AND Start <= :endDateTime
                    AND End >= :startDateTime
                    ORDER BY Start ASC
                ];
            }

            // Deduplicate events: ServiceAppointments by WhatId only, others by WhatId + CreatedDate
            List<Event> deduplicatedEvents = deduplicateEvents(events);

            // Collect WhatIds for related ServiceAppointments and ResourceAbsences
            Set<Id> serviceAppointmentIds = new Set<Id>();
            Set<Id> resourceAbsenceIds = new Set<Id>();

            for (Event evt : deduplicatedEvents) {
                if (evt.WhatId != null && evt.What != null) {
                    String objectType = evt.What.Type;
                    if (objectType == OBJECT_TYPE_SERVICE_APPOINTMENT) {
                        serviceAppointmentIds.add(evt.WhatId);
                    } else if (objectType == OBJECT_TYPE_RESOURCE_ABSENCE) {
                        resourceAbsenceIds.add(evt.WhatId);
                    }
                }
            }

            // For non-Tutors, collect ResourceAbsence IDs to query their related Events for Subject
            Set<Id> resourceAbsenceIdsForSubjects = new Set<Id>();
            if (!isTutorUser) {
                for (ResourceAbsence ra : resourceAbsences) {
                    resourceAbsenceIdsForSubjects.add(ra.Id);
                }
            }

            // Query related ServiceAppointments with custom fields
            Map<Id, ServiceAppointment> serviceAppointmentMap = new Map<Id, ServiceAppointment>();
            if (!serviceAppointmentIds.isEmpty()) {
                for (ServiceAppointment sa : [
                    SELECT Id, Service_Type__c, Training_Type__c,
                           AppointmentNumber, Status__c, Subject,
                           Scheduled_Customer_Start__c, Duration,
                           Number_of_Attendees__c, Type_of_Attendees__c, PTR_Completed__c,
                           Training_Product_Delivered_Name__c, Trainer__c, Account_Name__c,
                           SchedStartTime, SchedEndTime, Customer_Status__c
                    FROM ServiceAppointment
                    WHERE Id IN :serviceAppointmentIds
                    AND Trainer__c = :userId
                ]) {
                    serviceAppointmentMap.put(sa.Id, sa);
                }
            }

            // Query completed PD Service Appointments (those without Event records)
            List<ServiceAppointment> completedSAs = [
                SELECT Id, Service_Type__c, Training_Type__c,
                       AppointmentNumber, Status__c, Subject,
                       Scheduled_Customer_Start__c, Duration,
                       Number_of_Attendees__c, Type_of_Attendees__c, PTR_Completed__c,
                       Training_Product_Delivered_Name__c, Trainer__c, Account_Name__c,
                       SchedStartTime, SchedEndTime, Customer_Status__c
                FROM ServiceAppointment
                WHERE Trainer__c = :userId
                AND Service_Type__c = 'PD'
                AND Customer_Status__c = 'Completed'
                AND SchedStartTime <= :endDateTime
                AND SchedEndTime >= :startDateTime
                AND Id NOT IN :serviceAppointmentIds
                ORDER BY SchedStartTime ASC
            ];

            // Query related ResourceAbsences for Tutor users
            Map<Id, ResourceAbsence> resourceAbsenceMap = new Map<Id, ResourceAbsence>();
            if (!resourceAbsenceIds.isEmpty()) {
                for (ResourceAbsence ra : [
                    SELECT Id, AbsenceNumber, Type, Resource.Name
                    FROM ResourceAbsence
                    WHERE Id IN :resourceAbsenceIds
                ]) {
                    resourceAbsenceMap.put(ra.Id, ra);
                }
            }

            // Query Events related to ResourceAbsences for non-Tutors to get Subject
            Map<Id, String> resourceAbsenceEventSubjects = new Map<Id, String>();
            if (!resourceAbsenceIdsForSubjects.isEmpty()) {
                for (Event evt : [
                    SELECT Id, Subject, WhatId
                    FROM Event
                    WHERE WhatId IN :resourceAbsenceIdsForSubjects
                    AND What.Type = :OBJECT_TYPE_RESOURCE_ABSENCE
                ]) {
                    if (evt.WhatId != null && String.isNotBlank(evt.Subject)) {
                        resourceAbsenceEventSubjects.put(evt.WhatId, evt.Subject);
                    }
                }
            }

            // Build wrapper list with enriched data from Events
            List<EventWrapper> wrappedEvents = new List<EventWrapper>();
            for (Event evt : deduplicatedEvents) {
                EventWrapper wrapper = new EventWrapper();
                wrapper.Id = evt.Id;
                wrapper.Subject = evt.Subject;
                wrapper.StartDateTime = evt.StartDateTime;
                wrapper.EndDateTime = evt.EndDateTime;
                wrapper.IsAllDayEvent = evt.IsAllDayEvent;
                wrapper.Description = evt.Description;
                wrapper.Location = evt.Location;
                wrapper.WhatId = evt.WhatId;
                wrapper.WhatType = evt.What != null ? evt.What.Type : null;
                wrapper.UserTutorType = userTutorType;

                // Add custom field data for ServiceAppointments
                if (evt.WhatId != null && serviceAppointmentMap.containsKey(evt.WhatId)) {
                    ServiceAppointment sa = serviceAppointmentMap.get(evt.WhatId);
                    wrapper.ServiceType = sa.Service_Type__c;
                    wrapper.TrainingType = sa.Training_Type__c;

                    // Populate ServiceAppointment-specific fields
                    wrapper.AppointmentNumber = sa.AppointmentNumber;
                    wrapper.TrainingProductDelivered = sa.Training_Product_Delivered_Name__c;
                    wrapper.SAStatus = sa.Status__c;
                    wrapper.SASubject = sa.Subject;
                    wrapper.ScheduledCustomerStart = sa.Scheduled_Customer_Start__c;
                    wrapper.Duration = sa.Duration;
                    wrapper.NumberOfAttendees = sa.Number_of_Attendees__c;
                    wrapper.TypeOfAttendees = sa.Type_of_Attendees__c;
                    wrapper.PTRCompleted = sa.PTR_Completed__c;
                    wrapper.AccountName = sa.Account_Name__c;
                }

                // Add custom field data for ResourceAbsence-related Events (Tutor users only)
                if (evt.WhatId != null && resourceAbsenceMap.containsKey(evt.WhatId)) {
                    ResourceAbsence ra = resourceAbsenceMap.get(evt.WhatId);

                    // Populate ResourceAbsence-specific fields
                    wrapper.AbsenceNumber = ra.AbsenceNumber;
                    wrapper.AbsenceType = ra.Type;
                    wrapper.ResourceName = ra.Resource != null ? ra.Resource.Name : null;
                }

                wrappedEvents.add(wrapper);
            }

            // Add ResourceAbsences as separate event wrappers
            for (ResourceAbsence ra : resourceAbsences) {
                EventWrapper wrapper = new EventWrapper();
                wrapper.Id = ra.Id;

                // Store the Event Subject if available for JS to use in formatting
                // JS will format as: "8:00 am <strong>Subject | RA-#</strong>"
                if (resourceAbsenceEventSubjects.containsKey(ra.Id)) {
                    wrapper.Subject = resourceAbsenceEventSubjects.get(ra.Id);
                } else {
                    wrapper.Subject = null;
                }

                wrapper.StartDateTime = ra.Start;
                wrapper.EndDateTime = ra.End;

                // If duration is longer than 24 hours (1440 minutes), treat as all-day event
                Decimal durationInMinutes = ra.FSL__Duration_In_Minutes__c != null ? ra.FSL__Duration_In_Minutes__c : 0;
                wrapper.IsAllDayEvent = durationInMinutes > 1440;

                wrapper.WhatId = ra.Id;
                wrapper.WhatType = OBJECT_TYPE_RESOURCE_ABSENCE;
                wrapper.UserTutorType = userTutorType;

                // Populate ResourceAbsence-specific fields
                wrapper.AbsenceType = ra.Type;
                wrapper.AbsenceNumber = ra.AbsenceNumber;
                wrapper.ResourceUserId = ra.Resource_User_Id__c;
                wrapper.ResourceName = ra.Resource != null ? ra.Resource.Name : null;
                wrapper.DurationInMinutes = durationInMinutes;

                wrappedEvents.add(wrapper);
            }

            // Add completed PD Service Appointments as separate event wrappers
            for (ServiceAppointment sa : completedSAs) {
                EventWrapper wrapper = new EventWrapper();
                wrapper.Id = sa.Id;
                wrapper.Subject = sa.Subject;
                wrapper.StartDateTime = sa.SchedStartTime;
                wrapper.EndDateTime = sa.SchedEndTime;
                wrapper.IsAllDayEvent = false; // SchedStartTime and SchedEndTime are datetime fields
                wrapper.WhatId = sa.Id;
                wrapper.WhatType = OBJECT_TYPE_SERVICE_APPOINTMENT;
                wrapper.UserTutorType = userTutorType;

                // Populate ServiceAppointment-specific fields
                wrapper.ServiceType = sa.Service_Type__c;
                wrapper.TrainingType = sa.Training_Type__c;
                wrapper.AppointmentNumber = sa.AppointmentNumber;
                wrapper.TrainingProductDelivered = sa.Training_Product_Delivered_Name__c;
                wrapper.SAStatus = sa.Status__c;
                wrapper.SASubject = sa.Subject;
                wrapper.ScheduledCustomerStart = sa.Scheduled_Customer_Start__c;
                wrapper.Duration = sa.Duration;
                wrapper.NumberOfAttendees = sa.Number_of_Attendees__c;
                wrapper.TypeOfAttendees = sa.Type_of_Attendees__c;
                wrapper.PTRCompleted = sa.PTR_Completed__c;
                wrapper.AccountName = sa.Account_Name__c;

                wrappedEvents.add(wrapper);
            }

            return wrappedEvents;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching events: ' + e.getMessage());
        }
    }

    // Get calendar event colors from Custom Metadata Type
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getEventColors() {
        Map<String, String> colorMap = new Map<String, String>();

        try {
            // Query all Calendar_Event_Color__mdt records
            List<Calendar_Event_Color__mdt> colorConfigs = [
                SELECT Event_Type__c, Color_Hex__c
                FROM Calendar_Event_Color__mdt
            ];

            // Build map of Event Type to Color Hex
            for (Calendar_Event_Color__mdt config : colorConfigs) {
                if (String.isNotBlank(config.Event_Type__c) && String.isNotBlank(config.Color_Hex__c)) {
                    colorMap.put(config.Event_Type__c, config.Color_Hex__c);
                }
            }

            return colorMap;
        } catch (Exception e) {
            // If there's an error (e.g., CMDT not deployed), return empty map
            // Component will fall back to CSS variables
            System.debug('Error fetching event colors: ' + e.getMessage());
            return new Map<String, String>();
        }
    }

    // Get single event detail with enriched data (for Tutor users)
    @AuraEnabled(cacheable=true)
    public static EventWrapper getEventDetail(String eventId, String userId) {
        try {
            // Query the User's Contact to get Tutor_PLS_or_Both__c field
            String userTutorType = null;
            List<User> users = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
            if (!users.isEmpty() && users[0].ContactId != null) {
                List<Contact> contacts = [SELECT Tutor_PLS_or_Both__c FROM Contact WHERE Id = :users[0].ContactId LIMIT 1];
                if (!contacts.isEmpty()) {
                    userTutorType = contacts[0].Tutor_PLS_or_Both__c;
                }
            }

            // Check if this is a ServiceAppointment ID (completed SA without Event)
            Id recordId = Id.valueOf(eventId);
            String sObjectType = recordId.getSObjectType().getDescribe().getName();

            if (sObjectType == OBJECT_TYPE_SERVICE_APPOINTMENT) {
                // Query the ServiceAppointment directly
                List<ServiceAppointment> serviceAppointments = [
                    SELECT Id, Service_Type__c, Training_Type__c,
                           AppointmentNumber, Status__c, Subject,
                           Scheduled_Customer_Start__c, Duration,
                           Number_of_Attendees__c, Type_of_Attendees__c, PTR_Completed__c,
                           Training_Product_Delivered_Name__c, Trainer__c, Account_Name__c,
                           SchedStartTime, SchedEndTime, Customer_Status__c
                    FROM ServiceAppointment
                    WHERE Id = :eventId
                    AND Trainer__c = :userId
                    LIMIT 1
                ];

                if (serviceAppointments.isEmpty()) {
                    throw new AuraHandledException('Service Appointment not found');
                }

                ServiceAppointment sa = serviceAppointments[0];

                // Build wrapper with SA data
                EventWrapper wrapper = new EventWrapper();
                wrapper.Id = sa.Id;
                wrapper.Subject = sa.Subject;
                wrapper.StartDateTime = sa.SchedStartTime;
                wrapper.EndDateTime = sa.SchedEndTime;
                wrapper.IsAllDayEvent = false;
                wrapper.WhatId = sa.Id;
                wrapper.WhatType = OBJECT_TYPE_SERVICE_APPOINTMENT;
                wrapper.UserTutorType = userTutorType;

                // Populate ServiceAppointment-specific fields
                wrapper.ServiceType = sa.Service_Type__c;
                wrapper.TrainingType = sa.Training_Type__c;
                wrapper.AppointmentNumber = sa.AppointmentNumber;
                wrapper.TrainingProductDelivered = sa.Training_Product_Delivered_Name__c;
                wrapper.SAStatus = sa.Status__c;
                wrapper.SASubject = sa.Subject;
                wrapper.ScheduledCustomerStart = sa.Scheduled_Customer_Start__c;
                wrapper.Duration = sa.Duration;
                wrapper.NumberOfAttendees = sa.Number_of_Attendees__c;
                wrapper.TypeOfAttendees = sa.Type_of_Attendees__c;
                wrapper.PTRCompleted = sa.PTR_Completed__c;
                wrapper.AccountName = sa.Account_Name__c;

                return wrapper;
            }

            // Query the Event
            List<Event> events = [
                SELECT Id, Subject, StartDateTime, EndDateTime, IsAllDayEvent, Description, Location,
                       WhatId, What.Type, OwnerId, Owner.Name, CreatedDate, LastModifiedDate
                FROM Event
                WHERE Id = :eventId
                LIMIT 1
            ];

            if (events.isEmpty()) {
                throw new AuraHandledException('Event not found');
            }

            Event evt = events[0];

            // Build wrapper with enriched data
            EventWrapper wrapper = new EventWrapper();
            wrapper.Id = evt.Id;
            wrapper.Subject = evt.Subject;
            wrapper.StartDateTime = evt.StartDateTime;
            wrapper.EndDateTime = evt.EndDateTime;
            wrapper.IsAllDayEvent = evt.IsAllDayEvent;
            wrapper.Description = evt.Description;
            wrapper.Location = evt.Location;
            wrapper.WhatId = evt.WhatId;
            wrapper.WhatType = evt.What != null ? evt.What.Type : null;
            wrapper.UserTutorType = userTutorType;

            // Get ServiceAppointment data if applicable
            if (evt.WhatId != null && evt.What != null && evt.What.Type == OBJECT_TYPE_SERVICE_APPOINTMENT) {
                List<ServiceAppointment> serviceAppointments = [
                    SELECT Id, Service_Type__c, Training_Type__c,
                           AppointmentNumber, Status__c, Subject,
                           Scheduled_Customer_Start__c, Duration,
                           Number_of_Attendees__c, Type_of_Attendees__c, PTR_Completed__c,
                           Training_Product_Delivered_Name__c, Trainer__c, Account_Name__c
                    FROM ServiceAppointment
                    WHERE Id = :evt.WhatId
                    AND Trainer__c = :userId
                    LIMIT 1
                ];

                if (!serviceAppointments.isEmpty()) {
                    ServiceAppointment sa = serviceAppointments[0];
                    wrapper.ServiceType = sa.Service_Type__c;
                    wrapper.TrainingType = sa.Training_Type__c;
                    wrapper.AppointmentNumber = sa.AppointmentNumber;
                    wrapper.TrainingProductDelivered = sa.Training_Product_Delivered_Name__c;
                    wrapper.SAStatus = sa.Status__c;
                    wrapper.SASubject = sa.Subject;
                    wrapper.ScheduledCustomerStart = sa.Scheduled_Customer_Start__c;
                    wrapper.Duration = sa.Duration;
                    wrapper.NumberOfAttendees = sa.Number_of_Attendees__c;
                    wrapper.TypeOfAttendees = sa.Type_of_Attendees__c;
                    wrapper.PTRCompleted = sa.PTR_Completed__c;
                    wrapper.AccountName = sa.Account_Name__c;
                }
            }

            // Get ResourceAbsence data if applicable (for Tutor users)
            if (evt.WhatId != null && evt.What != null && evt.What.Type == OBJECT_TYPE_RESOURCE_ABSENCE) {
                List<ResourceAbsence> resourceAbsences = [
                    SELECT Id, AbsenceNumber, Type, Resource.Name
                    FROM ResourceAbsence
                    WHERE Id = :evt.WhatId
                    LIMIT 1
                ];

                if (!resourceAbsences.isEmpty()) {
                    ResourceAbsence ra = resourceAbsences[0];
                    wrapper.AbsenceNumber = ra.AbsenceNumber;
                    wrapper.AbsenceType = ra.Type;
                    wrapper.ResourceName = ra.Resource != null ? ra.Resource.Name : null;
                }
            }

            return wrapper;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching event detail: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true scope = 'global')
    public static EmailMessage getEmailDetail(String recordId) {
        if (String.isBlank(recordId)) {
            return null;
        }

        List<EmailMessage> emails = [
            SELECT Id, Name, ActivityId, AttachmentIds, AutomationType, BccAddress,
                Case_Communication_Status__c, Case_Status__c, CcAddress, ClientThreadIdentifier, CreatedById, CreatedDate,
                CS_Case_Status__c, Einstein_Email_Summary__c, Email_Message_Process__c, EmailRoutingAddressId,
                EmailTemplateId, FirstOpenedDate, FromAddress, FromId, FromName, HasAttachment, Headers,
                HtmlBody, Incoming, IsBounced, IsClientManaged, IsDeleted, IsExternallyVisible, IsOpened,
                IsTracked, LastModifiedById, LastModifiedDate, LastOpenedDate, MessageDate,
                MessageIdentifier, ParentId, RelatedToId, ReplyToEmailMessageId, Source, Status, Subject,
                SystemModstamp, TextBody, ThreadIdentifier, ToAddress, ValidatedFromAddress
            FROM EmailMessage
            WHERE Id = :recordId
            LIMIT 1
        ];

        return emails.isEmpty() ? null : emails[0];
    }

    // Get event indicators for year view (returns dates with events)
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getEventIndicators(String userId, Integer year) {
        Map<String, Integer> eventCountsByDate = new Map<String, Integer>();

        try {
            // Query the User's Contact to get Tutor_PLS_or_Both__c field
            String userTutorType = null;
            List<User> users = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
            if (!users.isEmpty() && users[0].ContactId != null) {
                List<Contact> contacts = [SELECT Tutor_PLS_or_Both__c FROM Contact WHERE Id = :users[0].ContactId LIMIT 1];
                if (!contacts.isEmpty()) {
                    userTutorType = contacts[0].Tutor_PLS_or_Both__c;
                }
            }

            // Determine if user is a Tutor only
            // Only Tutors see ResourceAbsences as Events with Absence_Unavailable color
            // PLS and "PLS and Tutor" see ResourceAbsences as ResourceAbsence records
            Boolean isTutorUser = userTutorType == 'Tutor';

            // Query all events for the year
            // For Tutors only: include ResourceAbsence-related Events
            // For PLS and "PLS and Tutor": exclude ResourceAbsence-related Events (we'll query ResourceAbsences directly)
            DateTime startOfYear = DateTime.newInstance(year, 1, 1, 0, 0, 0);
            DateTime endOfYear = DateTime.newInstance(year, 12, 31, 23, 59, 59);

            List<Event> events;
            if (isTutorUser) {
                // Include all events including ResourceAbsence-related events
                events = [
                    SELECT Id, StartDateTime, EndDateTime, IsAllDayEvent, WhatId, What.Type, CreatedDate, LastModifiedDate
                    FROM Event
                    WHERE OwnerId = :userId
                    AND StartDateTime <= :endOfYear
                    AND EndDateTime >= :startOfYear
                    ORDER BY StartDateTime ASC
                ];
            } else {
                // Exclude ResourceAbsence-related events
                events = [
                    SELECT Id, StartDateTime, EndDateTime, IsAllDayEvent, WhatId, What.Type, CreatedDate, LastModifiedDate
                    FROM Event
                    WHERE OwnerId = :userId
                    AND StartDateTime <= :endOfYear
                    AND EndDateTime >= :startOfYear
                    AND (What.Type != :OBJECT_TYPE_RESOURCE_ABSENCE OR What.Type = null)
                    ORDER BY StartDateTime ASC
                ];
            }

            // Query ResourceAbsences directly for PLS and "PLS and Tutor" users
            List<ResourceAbsence> resourceAbsences = new List<ResourceAbsence>();
            if (!isTutorUser) {
                resourceAbsences = [
                    SELECT Id, Start, End
                    FROM ResourceAbsence
                    WHERE Resource_User_Id__c = :userId
                    AND Start <= :endOfYear
                    AND End >= :startOfYear
                    ORDER BY Start ASC
                ];
            }

            // Deduplicate events: ServiceAppointments by WhatId only, others by WhatId + CreatedDate
            List<Event> deduplicatedEvents = deduplicateEvents(events);

            // Collect ServiceAppointment IDs from Events to avoid counting them twice
            Set<Id> serviceAppointmentIdsFromEvents = new Set<Id>();
            for (Event evt : deduplicatedEvents) {
                if (evt.WhatId != null && evt.What != null && evt.What.Type == OBJECT_TYPE_SERVICE_APPOINTMENT) {
                    serviceAppointmentIdsFromEvents.add(evt.WhatId);
                }
            }

            // Query completed PD Service Appointments for the year
            List<ServiceAppointment> completedSAs = [
                SELECT Id, SchedStartTime, SchedEndTime
                FROM ServiceAppointment
                WHERE Trainer__c = :userId
                AND Service_Type__c = 'PD'
                AND Customer_Status__c = 'Completed'
                AND SchedStartTime <= :endOfYear
                AND SchedEndTime >= :startOfYear
                AND Id NOT IN :serviceAppointmentIdsFromEvents
                ORDER BY SchedStartTime ASC
            ];

            // Process each event and count events per day
            for (Event evt : deduplicatedEvents) {
                // For all-day events, use dateGMT() to avoid timezone conversion issues
                // For timed events, use date() to get the local date
                Date startDate = evt.IsAllDayEvent ? evt.StartDateTime.dateGMT() : evt.StartDateTime.date();
                Date endDate = evt.IsAllDayEvent ? evt.EndDateTime.dateGMT() : evt.EndDateTime.date();

                // For all-day events, if EndDateTime is exactly midnight, include the previous day
                if (evt.IsAllDayEvent && evt.EndDateTime.time() == Time.newInstance(0, 0, 0, 0)) {
                    endDate = endDate.addDays(-1);
                }

                // Add event to all days it spans
                Date currentDate = startDate;
                while (currentDate <= endDate) {
                    // Format as YYYY-MM-DD
                    String dateKey = String.valueOf(currentDate.year()) + '-' +
                                   String.valueOf(currentDate.month()).leftPad(2, '0') + '-' +
                                   String.valueOf(currentDate.day()).leftPad(2, '0');

                    // Increment count for this date
                    if (eventCountsByDate.containsKey(dateKey)) {
                        eventCountsByDate.put(dateKey, eventCountsByDate.get(dateKey) + 1);
                    } else {
                        eventCountsByDate.put(dateKey, 1);
                    }

                    currentDate = currentDate.addDays(1);
                }
            }

            // Process ResourceAbsences and count them per day
            for (ResourceAbsence ra : resourceAbsences) {
                // ResourceAbsences are timed events, use date() to get the local date
                Date startDate = ra.Start.date();
                Date endDate = ra.End.date();

                // Add ResourceAbsence to all days it spans
                Date currentDate = startDate;
                while (currentDate <= endDate) {
                    // Format as YYYY-MM-DD
                    String dateKey = String.valueOf(currentDate.year()) + '-' +
                                   String.valueOf(currentDate.month()).leftPad(2, '0') + '-' +
                                   String.valueOf(currentDate.day()).leftPad(2, '0');

                    // Increment count for this date
                    if (eventCountsByDate.containsKey(dateKey)) {
                        eventCountsByDate.put(dateKey, eventCountsByDate.get(dateKey) + 1);
                    } else {
                        eventCountsByDate.put(dateKey, 1);
                    }

                    currentDate = currentDate.addDays(1);
                }
            }

            // Process completed PD Service Appointments and count them per day
            for (ServiceAppointment sa : completedSAs) {
                // Service Appointments use datetime fields, use date() to get the local date
                Date startDate = sa.SchedStartTime.date();
                Date endDate = sa.SchedEndTime.date();

                // Add Service Appointment to all days it spans
                Date currentDate = startDate;
                while (currentDate <= endDate) {
                    // Format as YYYY-MM-DD
                    String dateKey = String.valueOf(currentDate.year()) + '-' +
                                   String.valueOf(currentDate.month()).leftPad(2, '0') + '-' +
                                   String.valueOf(currentDate.day()).leftPad(2, '0');

                    // Increment count for this date
                    if (eventCountsByDate.containsKey(dateKey)) {
                        eventCountsByDate.put(dateKey, eventCountsByDate.get(dateKey) + 1);
                    } else {
                        eventCountsByDate.put(dateKey, 1);
                    }

                    currentDate = currentDate.addDays(1);
                }
            }

            return eventCountsByDate;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching event indicators: ' + e.getMessage());
        }
    }

    /**
     * Helper method to deduplicate events
     * ServiceAppointments: deduplicate by WhatId only (one event per SA)
     * Other objects: deduplicate by WhatId + CreatedDate (multiple events per record allowed)
     * Events without WhatId: always unique
     * When duplicates found: keep the event with most recent LastModifiedDate
     */
    private static List<Event> deduplicateEvents(List<Event> events) {
        Map<String, Event> uniqueEventsByGroupKey = new Map<String, Event>();
        List<Event> deduplicatedEvents = new List<Event>();

        for (Event evt : events) {
            if (evt.WhatId == null) {
                // Events without WhatId are always unique
                deduplicatedEvents.add(evt);
            } else if (evt.What != null) {
                // For ServiceAppointments, use WhatId only to ensure one event per SA
                // For other objects, include CreatedDate to allow multiple events per record
                String objectType = evt.What.Type;
                String groupKey;

                if (objectType == OBJECT_TYPE_SERVICE_APPOINTMENT) {
                    // ServiceAppointments: deduplicate by WhatId only
                    groupKey = String.valueOf(evt.WhatId);
                } else {
                    // Other objects: deduplicate by WhatId + CreatedDate
                    groupKey = String.valueOf(evt.WhatId) + '_' +
                               String.valueOf(evt.CreatedDate.getTime());
                }

                // Check if we've seen this group before
                if (uniqueEventsByGroupKey.containsKey(groupKey)) {
                    Event existing = uniqueEventsByGroupKey.get(groupKey);

                    // Compare LastModifiedDate - keep the more recent one
                    if (evt.LastModifiedDate > existing.LastModifiedDate) {
                        uniqueEventsByGroupKey.put(groupKey, evt);
                    }
                    // If existing has newer or same LastModifiedDate, keep existing (do nothing)
                } else {
                    // First time seeing this group key
                    uniqueEventsByGroupKey.put(groupKey, evt);
                }
            }
        }

        // Add all unique events with WhatId
        deduplicatedEvents.addAll(uniqueEventsByGroupKey.values());
        return deduplicatedEvents;
    }

    // Wrapper class to include custom field data
    public class EventWrapper {
        @AuraEnabled public String Id { get; set; }
        @AuraEnabled public String Subject { get; set; }
        @AuraEnabled public DateTime StartDateTime { get; set; }
        @AuraEnabled public DateTime EndDateTime { get; set; }
        @AuraEnabled public Boolean IsAllDayEvent { get; set; }
        @AuraEnabled public String Description { get; set; }
        @AuraEnabled public String Location { get; set; }
        @AuraEnabled public String WhatId { get; set; }
        @AuraEnabled public String WhatType { get; set; }
        @AuraEnabled public String UserTutorType { get; set; }
        @AuraEnabled public String ServiceType { get; set; }
        @AuraEnabled public String TrainingType { get; set; }
        @AuraEnabled public String AbsenceType { get; set; }

        // Additional ServiceAppointment fields for PD type
        @AuraEnabled public String AppointmentNumber { get; set; }
        @AuraEnabled public String TrainingProductDelivered { get; set; }
        @AuraEnabled public String SAStatus { get; set; }
        @AuraEnabled public String SASubject { get; set; }
        @AuraEnabled public String ScheduledCustomerStart { get; set; }
        @AuraEnabled public Decimal Duration { get; set; }
        @AuraEnabled public Decimal NumberOfAttendees { get; set; }
        @AuraEnabled public String TypeOfAttendees { get; set; }
        @AuraEnabled public Boolean PTRCompleted { get; set; }
        @AuraEnabled public String AccountName { get; set; }

        // Additional ResourceAbsence fields
        @AuraEnabled public String AbsenceNumber { get; set; }
        @AuraEnabled public String ResourceUserId { get; set; }
        @AuraEnabled public String ResourceName { get; set; }
        @AuraEnabled public Decimal DurationInMinutes { get; set; }
    }
}