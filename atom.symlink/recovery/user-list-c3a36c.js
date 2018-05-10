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
      if !user1.get('lastName') {
        return -1;
      }

      if !user2.get('lastName') {
        return 1;
      }

      let firstNameUpper =
    }
  }
});
