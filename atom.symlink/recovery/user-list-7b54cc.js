import Component from '@ember/component';
import { inject as service } from '@ember/service';
import { filterBy } from '@ember/object/computed';
import { isPresent } from '@ember/utils';

export default Component.extend({
  notifications: service(),

  classNames: ['EligibilityUserList'],

  includedUsers: filterBy('users', 'excluded', false),
  excludedUsers: filterBy('users', 'excluded', true),

  actions: {
    toggleExclusion(user) {
      user.toggleProperty('excluded');

      user.save().then(() => {
        let action;

        if (user.get('excluded')) {
          action = 'removed from';
        } else {
          action = 'added to';
        }

        this.get('notifications').success(`${user.get('fullName')} has been ${action} your wellness program.`);
      }).catch((e) => {
        user.rollbackAttributes();

        throw e;
      });
    },

    sortCaseInsensitive(user1, user2) {

      
    },

    OLDsortCaseInsensitive(user1, user2) {

      const user1LastNameUpper = isPresent(user1.get('lastName')) ? user1.get('lastName').toUpperCase() : null;
      const user2LastNameUpper = isPresent(user2.get('lastName')) ? user2.get('lastName').toUpperCase() : null;

      if (user1LastNameUpper > user2LastNameUpper) {
        return 1;
      } else if (user1LastNameUpper < user2LastNameUpper) {
        return -1;
      }

      const user1FirstNameUpper = isPresent(user1.get('firstName')) ? user1.get('firstName').toUpperCase() : null;
      const user2FirstNameUpper = isPresent(user2.get('firstName')) ? user2.get('firstName').toUpperCase() : null;

      if (user1FirstNameUpper > user2FirstNameUpper) {
        return 1;
      } else if (user1FirstNameUpper < user2FirstNameUpper) {
        return -1;
      }

      return 0;
    }
  }
});
