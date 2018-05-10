import Component from '@ember/component';
import { inject as service } from '@ember/service';
import { filterBy } from '@ember/object/computed';

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

      const user1LastNameUpper = user1.get('lastName') ? user1.get('lastName').toUpperCase() : undefined;
      const user2LastNameUpper = user2.get('lastName') ? user2.get('lastName').toUpperCase() : undefined;

      if (user1LastNameUpper > user2LastNameUpper) {
        return 1;
      } else if (user1LastNameUpper < user2LastNameUpper) {
        return -1;
      }

      const user1FirstNameUpper = user1.get('firstName') ? user1.get('firstName').toUpperCase() : undefined;
      const user2FirstNameUpper = user2.get('firstName') ? user2.get('firstName').toUpperCase() : undefined;

      if (user1FirstNameUpper > user2FirstNameUpper) {
        return 1;
      } else if (user1FirstNameUpper < user2FirstNameUpper) {
        return -1;
      }

      return 0;
    }
  }
});
