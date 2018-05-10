import DS from 'ember-data';
import { computed } from '@ember/object';

export default DS.Model.extend({
  billingPlan: DS.belongsTo(),
  contract: DS.belongsTo(),
  organization: DS.belongsTo(),
  segment: DS.belongsTo(),
  billingPeriods: DS.hasMany(),

  status: DS.attr(),
  companyName: DS.attr(),
  code: DS.attr(),
  logo: DS.attr(),
  eligibilityType: DS.attr(),
  cardDetails: DS.attr(),
  trialEndsAt: DS.attr('date'),
  cycleDay: DS.attr(),
  onboardingLatestStepCompleted: DS.attr(),
  onboardingNextStep: DS.attr(),
  onboarded: DS.attr('boolean'),

  nonZeroBillingPeriods: computed.filterBy

  friendlyEligibilityType: computed('eligibilityType', function() {
    switch (this.get('eligibilityType')) {
      case 'google_directory':
        return 'G Suite';
      case 'adp':
        return 'ADP Workforce Now';
      case 'email':
        return 'Email list';
      default:
        return this.get('eligibilityType');
    }
  }),

  eligibleUsers: computed('eligibilityType', 'contract.{googleDirectoryUsers,adpWorkers,emailEligibilities}.@each.isIncluded', function() {
    return DS.PromiseManyArray.create({
      promise: this.get('contract').then((contract) => {
        let contractRelationship;

        switch (this.get('eligibilityType')) {
          case 'google_directory':
            contractRelationship = 'googleDirectoryUsers';
            break;
          case 'adp':
            contractRelationship = 'adpWorkers';
            break;
          case 'email':
            contractRelationship = 'emailEligibilities';
            break;
        }

        return contract.get(contractRelationship).then(users => users.filterBy('isIncluded'));
      })
    });
  })
});
