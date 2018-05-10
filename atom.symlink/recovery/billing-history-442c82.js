import { gt } from '@ember/object/computed';
import Controller from '@ember/controller';

export default Controller.extend({
  billingPeriodsAvailable: gt('model.billingPeriods.length', 0)
});
