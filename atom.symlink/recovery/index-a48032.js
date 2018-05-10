import { computed } from '@ember/object';
import { allSettled, resolve } from 'rsvp';
import { isEmpty, isPresent } from '@ember/utils';
import { notEmpty, union, alias, reads } from '@ember/object/computed';
import { inject as service } from '@ember/service';
import { inject as controller } from '@ember/controller';
import Controller from '@ember/controller';

export default Controller.extend({
  session: service(),
  notifications: service(),
  eligibilityController: controller('contract.eligibility'),

  isOnboarding: reads('eligibilityController.isOnboarding'),

  isLoading: false,

  currentUserEmailAddress: alias('session.user.email'),
  hasEmails: notEmpty('validEmails'),
  validEmails: union('stagedEmails', 'savedEmails'),
  unsaveableEmails: union('duplicateEmails', 'invalidEmails'),
  hasEligibleStaff: notEmpty('contract.emailEligibilities'),
  eligibleCount: alias('contract.emailEligibilities.length'),

  disableSubmit: computed('isLoading', 'validEmails.[]', 'unsaveableEmails.[]', function() {
    return this.get('isLoading') || isEmpty(this.get('validEmails')) || isPresent(this.get('unsaveableEmails'));
  }),

  _ensureSelfIsIncluded() {
    if (!this.get('isOnboarding')) { return resolve(); }

    return this.get('store').query('email-eligibility', { contractId: this.get('contract.id'), filter: { email: this.get('currentUserEmailAddress') } }).then((results) => {
      if (isPresent(results.get('firstObject'))) { return resolve(); }

      const adminEmailEligibilityRecord = this.get('store').createRecord('email-eligibility', {
        contract: this.get('contract'),
        email: this.get('currentUserEmailAddress')
      });

      return adminEmailEligibilityRecord.save().then(() => {
        this.get('savedEmails').unshiftObject(this.get('currentUserEmailAddress'));
        this.get('notifications').success("We didn't see your email address on the list, so we've added it for you.", { clearDuration: 6400 });
      }).catch((e) => {
        adminEmailEligibilityRecord.unloadRecord();

        throw e;
      });
    });
  },

  actions: {
    stageEmails(emails) {
      emails.forEach((email) => {
        if (this.get('validEmails').map(e => e.toUpperCase()).includes(email.toUpperCase())) {
          this.get('duplicateEmails').unshiftObject(email);
        } else if (email.match(/^([^\s@]+)@([\w-]+\.)+([\w]{2,})$/i)) {
          this.get('stagedEmails').unshiftObject(email);
        } else {
          this.get('invalidEmails').unshiftObject(email);
        }
      });
    },

    removeEmail(email) {
      this.get('stagedEmails').removeObject(email);
    },

    saveEmails() {
      this.set('isLoading', true);

      const eligibilities = this.get('stagedEmails').map((email) => {
        return this.get('store').createRecord('email-eligibility', {
          contract: this.get('contract'),
          email: email
        });
      });

      allSettled( eligibilities.map(eligibility => eligibility.save()) ).then((results) => {
        results.forEach((result, index) => {
          if (result.state === 'fulfilled') {
            this.get('savedEmails').unshiftObject(result.value.get('email'));
            this.get('stagedEmails').removeObject(result.value.get('email'));
          } else {
            const errors = result.reason.errors;
            const failure = eligibilities[index];

            errors.forEach((error) => {
              if (error.detail.match(/Email has already been taken/)) {
                this.get('duplicateEmails').pushObject( failure.get('email') );
              } else if (error.detail.match(/Email is invalid/)) {
                this.get('invalidEmails').pushObject( failure.get('email') );
              }
            });

            this.get('stagedEmails').removeObject(failure.get('email'));
            failure.rollbackAttributes();
          }
        });
      }).finally(() => {
        if (isEmpty(this.get('unsaveableEmails'))) {
          this._ensureSelfIsIncluded().then(() => {
            const count = this.get('savedEmails.length');
            const employeeString = count == 1 ? 'employee has' : 'employees have';

            this.get('notifications').success(`${count} ${employeeString} been added to the list.`);

            if (this.get('isOnboarding')) {
              this.transitionToRoute('contract.eligibility.email.eligibility', this.get('contract.id'));
            } else {
              this.transitionToRoute('contract.eligibility.email.manage', this.get('contract.id'));
            }
          });
        } else {
          this.set('isLoading', false);

          this.get('notifications').warning('Uh oh - seems like there’s a problem. Please take a look below.');
        }
      });
    }
  }
});
