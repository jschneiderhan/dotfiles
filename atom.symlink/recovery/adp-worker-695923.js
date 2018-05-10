import DS from 'ember-data';
import { computed } from '@ember/object';
import { not } from '@ember/object/computed';

export default DS.Model.extend({
  contract: DS.belongsTo(),
  firstName: DS.attr(),
  lastName: DS.attr(),
  postalCode: DS.attr(),
  excluded: DS.attr(),

  isIncluded: not('excluded'),

  fullName: computed('firstName', 'lastName', function() {
    const parts = [];

    if (this.get('firstName')) {
      parts.push(this.get('firstName'));
    }

    if (this.get('lastName')) {
      parts.push(this.get('lastName'));
    }
    return parts.join(' ');
  })
});
