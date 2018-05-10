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

      const user1LastName = user1.get('lastName');
      const user2LastName = user2.get('lastName');

      if (!user1LastName) {
        return -1;
      }

      if (!user2LastName) {
        return 1;
      }

      const user1LastNameUpper = user1LastName.toUpperCase();
      const user2LastNameUpper = user2LastName.toUpperCase();

      if (user1LastNameUpper > user2LastNameUpper) {
        return 1;
      } else if (user1LastNameUpper < user2LastNameUpper) {
        return -1;
      }

      const user1FirstName = user1.get('firstName');
      const user2FirstName = user2.get('firstName');

      if (!user1FirstName) {
        return -1;
      }

      if (!user2FirstName) {
        return 1;
      }

      const user1FirstNameUpper = user1FirstName.toUpperCase();
      const user2FirstNameUpper = user2FirstName.toUpperCase();

      if (user1FirstNameUpper == user2FirstNameUpper) {
        return 0;
      } else if (user1FirstNameUpper > user2FirstNameUpper) {
        return 1;
      } else {
        return -1;
      }
    }
    sortCaseInsensitive(user1, user2) {

      const user1LastName = user1.get('lastName');
      const user2LastName = user2.get('lastName');

      if (!user1LastName) {
        return -1;
      }

      if (!user2LastName) {
        return 1;
      }

      const user1LastNameUpper = user1LastName.toUpperCase();
      const user2LastNameUpper = user2LastName.toUpperCase();

      if (user1LastNameUpper > user2LastNameUpper) {
        return 1;
      } else if (user1LastNameUpper < user2LastNameUpper) {
        return -1;
      }

      const user1FirstName = user1.get('firstName');
      const user2FirstName = user2.get('firstName');

      if (!user1FirstName) {
        return -1;
      }

      if (!user2FirstName) {
        return 1;
      }

      const user1FirstNameUpper = user1FirstName.toUpperCase();
      const user2FirstNameUpper = user2FirstName.toUpperCase();

      if (user1FirstNameUpper == user2FirstNameUpper) {
        return 0;
      } else if (user1FirstNameUpper > user2FirstNameUpper) {
        return 1;
      } else {
        return -1;
      }
    }
  }
});
