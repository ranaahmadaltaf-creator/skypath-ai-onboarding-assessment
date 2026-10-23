// Portable, ID-free setup. The service safely creates/reuses the unique GLOBAL lock.
OnboardingAssignmentService.acquireLock();
System.debug(LoggingLevel.INFO, 'SkyPath assignment lock initialized.');
