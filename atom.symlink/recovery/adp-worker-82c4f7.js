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
    return `${this.get('firstName')} ${this.get('lastName')}`;
  })
});
