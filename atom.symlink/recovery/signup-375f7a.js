import Controller from '@ember/controller';
import { isBlank } from '@ember/utils';
import { computed } from '@ember/object';
import { or } from '@ember/object/computed';
import { inject as service } from '@ember/service';
import { later } from '@ember/runloop';
import { resolve, reject } from 'rsvp';
import ENV from '../config/environment';
import moment from 'moment';
import $ from 'jquery';

export default Controller.extend({
  session: service(),
  router: service(),
  notifications: service(),
  stripe: service('stripev3'),
  ajax: service(),

  queryParams: { planId: 'plan' },
  planId: '1',

  trialLengthInDays: ENV.APP.signupTrialLengthInDays,

  accountUrl: ENV.APP.accountUrl,

  // eslint-disable-next-line ember/avoid-leaking-state-in-ember-objects
  stripeOptions: {
    style: {
      base: {
        color: '#3f3f3f',
        fontFamily: '"Armitage Light", "Helvetica Neue", Arial, Helvetica, sans-serif',
        fontSmoothing: 'antialiased',
        fontSize: '14px',
        '::placeholder': {
          color: 'rgba(63, 63, 63, 0.5)'
        }
      },
      invalid: {
        color: '#ff3939',
        iconColor: '#ff3939',
        '::placeholder': {
          color: 'rgba(255, 57, 57, 0.5)'
        }
      }
    }
  },
  stripeElement: null,
  stripeComplete: false,
  companyName: null,
  isLoading: false,
  creationSuccessful: false,
  modalOpen: false,
  userSessionPassword: null,

  trialEndDate: computed(function() {
    return moment().add(this.get('trialLengthInDays'), 'days');
  }).volatile(),

  plan: computed('model.plans.@each.id', 'planId', function() {
    return this.get('model.plans').findBy('id', this.get('planId'));
  }),

  createInvalid: computed('model.wbidUser.{firstName,lastName,email,password,terms}', 'companyName', 'stripeComplete', function() {
    const wbidUserAttributesNotAllPresent = ['firstName', 'lastName', 'email', 'password'].any((attr) => {
      return isBlank(this.get(`model.wbidUser.${attr}`));
    });

    return wbidUserAttributesNotAllPresent || !this.get('model.wbidUser.terms') || !this.get('companyName') || !this.get('stripeComplete');
  }),

  loginInvalid: computed('model.wbidUser.{email,terms}', 'companyName', 'stripeComplete', 'userSessionPassword', function() {
    return isBlank(this.get('userSessionPassword')) || isBlank(this.get('model.wbidUser.email')) || !this.get('model.wbidUser.terms') || !this.get('companyName') || !this.get('stripeComplete');
  }),

  createNotSubmitable: or('createInvalid', 'isLoading'),
  loginNotSubmitable: or('loginInvalid', 'isLoading'),

  singleWbidError: computed('model.wbidUser.errors.[]', function() {
    return this.get('model.wbidUser.errors.length') === 1;
  }),

  maybeCreateWbidUser() {
    if (this.get('model.wbidUser.isNew')) {
      return this.get('model.wbidUser').save().catch((e) => {
        // TODO: Creation might ahve returned a `403` for another reason, which we should determine.
        // Right now, we assume any `403` response means the user has an active session.
        if (e.errors && e.errors.isAny('status', '403')) {
          return resolve();
        } else {
          return reject(e);
        }
      });
    } else {
      return resolve();
    }
  },

  actions: {
    create() {
      if (this.get('isInvalid')) { return; }

      this.get('notifications').clear();
      this.set('isLoading', true);

      this.maybeCreateWbidUser().then(() => {
        return this._createImplementation().then(() => {
          this._flashSuccessAndTransition();
        });
      }).catch((e) => {
        this.set('isLoading', false);

        const wbidErrors = this.get('model.wbidUser.errors');

        if (wbidErrors.get('email') && wbidErrors.get('email').isAny('message', 'has already been taken')) {
          this.send('openModal');

          wbidErrors.remove('email');
          wbidErrors.remove('password');
        } else if (wbidErrors.get('length') === 0) {
          // we already handle wbidUser creation validation errors
          this.get('notifications').error('Sorry, something went wrong! Please try creating your account again. If you aren’t able to, contact help@meyouhealth.com.');
          window.scrollTo(0, 0);

          throw e;
        }
      });
    },

    login() {
      this.set('isLoading', true);

      const data = {
        email: this.get('model.wbidUser.email'),
        password: this.get('userSessionPassword'),
        opt_out_of_sponsorship: true
      };

      return this.get('ajax').request(`${ENV.APP.accountUrl}/api/user/session`, {
        method: 'POST',
        headers: { 'X-Requested-With': 'XMLHttpRequest', 'X-API-Version': '1' },
        data: { user_session: data },
        xhrFields: { withCredentials: true },
        crossDomain: true
      }).then(() => {
        return this._createImplementation().then(() => {
          $('.ui.LoginModal.modal').modal('hide');

          this._flashSuccessAndTransition();
        }).catch((e) => {
          this.setProperties({ isLoading: false, loginError: true });

          // creating the implementation failed, so throw.
          throw e;
        });
      }).catch(() => {
        // signing in failed, so assume it's because of invalid credentials.

        // TODO: Login might have failed because the account is locked, which we should handle.
        // It could also fail because of an intermittent network issue, or some other reason.
        // Right now, those would all appear as an error shake as if the credentials are wrong.
        $('.ui.LoginModal.modal').addClass('error_shake');

        later(() => {
          this.set('isLoading', false);
          $('.ui.LoginModal.modal').removeClass('error_shake');
        }, 700 + 100); // shake animation is 0.7s long, plus 100 for buffer
      });
    },

    openModal() {
      $('.ui.LoginModal.modal').modal('show');

      this.setProperties({ loginError: false, modalOpen: true });
    },

    onModalClose() {
      this.set('modalOpen', false);

      return true;
    },

    updateStripe(stripeElement, data) {
      this.setProperties({ stripeElement: stripeElement, stripeComplete: data.complete });
    }
  },

  _createImplementation() {
    const existingSaasImplementations = this.get('store').query('saasImplementation', { filter: { user_id: 16} });
    debugger;
    return this.get('stripe').createToken(this.get('stripeElement')).then(({ token }) => {
      const saasImplementation = this.get('store').createRecord('saas-implementation', { companyName: this.get('companyName'), billingPlan: this.get('plan'), timeZone: moment.tz.guess(), cardToken: token.id });

      return saasImplementation.save().then(() => {
        saasImplementation.setProperties({ cardToken: undefined, timeZone: undefined });
      }).catch((e) => {
        saasImplementation.unloadRecord();

        return reject(e);
      });
    }).then(() => {
      // re-authenticate
      return this.get('session').load();
    });
  },

  _flashSuccessAndTransition() {
    this.set('creationSuccessful', true);

    later(() => {
      this.set('creationSuccessful', false);

      later(() => {
        this.send('redirectToNextStepInSaasOnboardingFlow');
      }, 300); // wait for the success popup disappearance transition to finish
    }, 2500); // show the success popup before transitioning
  },
});
