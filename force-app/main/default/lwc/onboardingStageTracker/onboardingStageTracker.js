import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import NAME from '@salesforce/schema/Onboarding__c.Name';
import STAGE from '@salesforce/schema/Onboarding__c.Stage__c';
import TARGET_GO_LIVE from '@salesforce/schema/Onboarding__c.Target_Go_Live__c';
import KICKOFF_FIRST from '@salesforce/schema/Onboarding__c.Kickoff_First_At__c';
import GATHERING_FIRST from '@salesforce/schema/Onboarding__c.Gathering_Info_First_At__c';
import IMPLEMENTATION_FIRST from '@salesforce/schema/Onboarding__c.Implementation_First_At__c';
import QA_FIRST from '@salesforce/schema/Onboarding__c.QA_Review_First_At__c';
import GO_LIVE_FIRST from '@salesforce/schema/Onboarding__c.Go_Live_First_At__c';
import REVIEW_FIRST from '@salesforce/schema/Onboarding__c.Post_Launch_Review_First_At__c';

// Keep these names in sync with Onboarding__c.Stage__c's restricted picklist.
const STAGES = [
    { name: 'Kickoff Scheduled', shortName: 'Kickoff', firstField: KICKOFF_FIRST },
    { name: 'Gathering Info', shortName: 'Gathering Info', firstField: GATHERING_FIRST },
    { name: 'Implementation', shortName: 'Implementation', firstField: IMPLEMENTATION_FIRST },
    { name: 'QA / Review', shortName: 'QA / Review', firstField: QA_FIRST },
    { name: 'Go Live', shortName: 'Go Live', firstField: GO_LIVE_FIRST },
    { name: 'Post-Launch Review', shortName: 'Post-Launch Review', firstField: REVIEW_FIRST }
];

const HINTS = {
    'Kickoff Scheduled': 'Next: Gather customer information after kickoff.',
    'Gathering Info': 'Gathering Notes are required before Implementation.',
    'Implementation': 'Implementation Notes are required before QA / Review.',
    'QA / Review': 'Advance to Go Live after approval, or return to Implementation with a QA failure reason.',
    'Go Live': 'Next: Complete the Post-Launch Review.',
    'Post-Launch Review': 'Onboarding has reached its final stage.'
};

export default class OnboardingStageTracker extends LightningElement {
    @api recordId;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [NAME, STAGE],
        // Missing field-level read permissions won't break the entire tracker.
        optionalFields: [
            TARGET_GO_LIVE, KICKOFF_FIRST, GATHERING_FIRST,
            IMPLEMENTATION_FIRST, QA_FIRST, GO_LIVE_FIRST, REVIEW_FIRST
        ]
    })
    onboarding;

    get hasError() {
        return Boolean(this.onboarding && this.onboarding.error);
    }

    get isLoaded() {
        return Boolean(this.onboarding && this.onboarding.data);
    }

    get data() {
        return this.isLoaded ? this.onboarding.data : null;
    }

    get onboardingName() {
        return this.data ? getFieldValue(this.data, NAME) : '';
    }

    get currentStage() {
        return this.data ? getFieldValue(this.data, STAGE) : '';
    }

    get targetGoLive() {
        return this.data ? getFieldValue(this.data, TARGET_GO_LIVE) : null;
    }

    get hasTargetGoLive() {
        return Boolean(this.targetGoLive);
    }

    get stageIndex() {
        return STAGES.findIndex((stage) => stage.name === this.currentStage);
    }

    get isKnownStage() {
        return this.stageIndex !== -1;
    }

    get isFinalStage() {
        return this.stageIndex === STAGES.length - 1;
    }

    get progressPercent() {
        return this.isKnownStage
            ? Math.round(((this.stageIndex + 1) / STAGES.length) * 100)
            : 0;
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%;`;
    }

    get progressText() {
        return this.isKnownStage
            ? `Stage ${this.stageIndex + 1} of ${STAGES.length}`
            : 'Stage not recognized';
    }

    get statusText() {
        return this.isFinalStage ? 'Final stage reached' : 'In progress';
    }

    get statusClass() {
        return this.isFinalStage ? 'status status--complete' : 'status';
    }

    get nextAction() {
        return HINTS[this.currentStage] || 'Review the current onboarding stage.';
    }

    get steps() {
        if (!this.data) return [];
        return STAGES.map((stage, index) => {
            const firstReachedAt = getFieldValue(this.data, stage.firstField);
            const isCurrent = index === this.stageIndex;
            const isPast = index < this.stageIndex;
            const wasVisitedBefore = index > this.stageIndex && Boolean(firstReachedAt);
            const state = isCurrent ? 'current'
                : isPast ? 'complete'
                    : wasVisitedBefore ? 'revisited' : 'upcoming';
            const text = isCurrent ? 'Current stage'
                : isPast ? 'Passed'
                    : wasVisitedBefore ? 'Visited previously' : 'Not started';
            return {
                key: stage.name,
                name: stage.name,
                shortName: stage.shortName,
                number: index + 1,
                firstReachedAt,
                hasTimestamp: Boolean(firstReachedAt),
                isPast,
                isCurrent,
                stateText: text,
                rowClass: `stage-row stage-row--${state}`,
                markerClass: `stage-marker stage-marker--${state}`,
                ariaCurrent: isCurrent ? 'step' : null
            };
        });
    }
}
