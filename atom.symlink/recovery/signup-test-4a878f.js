import { test } from 'qunit';
import moduleForAcceptance from 'snap/tests/helpers/module-for-acceptance';
import { run } from '@ember/runloop';
import { resolve, reject } from 'rsvp';
import moment from 'moment';
import errorStateWorkaround from 'snap/tests/helpers/error-state-workaround';
import Response from 'ember-cli-mirage/response';

moduleForAcceptance('Acceptance | signup', {
  beforeEach: function() {
    const expectedErrors = ["Stripe error", "Snap error"];

    errorStateWorkaround.setup(err => {
      return err.errors && expectedErrors.includes(err.errors[0]);
    });
  },

  afterEach: function() {
    errorStateWorkaround.teardown();
  }
});

test('signup will not work if you have not filled in the form', function(assert) {
  server.create('billingPlan');

  visit('/signup');

  andThen(() => {
    const trialEndDate = moment().add(30, 'days').format('MMMM D, YYYY');

    assert.equal(find('p.SignupForm__notice').text().trim(), `We won’t bill you until your 30-day trial ends on ${trialEndDate}. You’ll be billed each month thereafter.`);
    assert.equal(find('button.SignupForm__btn').prop('disabled'), true);
  });
});

test('signup creates a WBID user and a Snap user', function(assert) {
  server.create('billingPlan');

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => resolve({ token: 'stripe-token-value' });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { user: { key: 'asdf1234' } }, 201);
      server.post('/saas_implementations', server.create('saasImplementation', { status: 'pending', onboardingNextStep: 'welcome' }), 201);
      server.get('/users/me', server.create('user', { firstName: 'John', role: 'saas' }));

      click('button.SignupForm__btn');

      andThen(() => {
        assert.equal(currentURL(), '/onboarding/welcome');
        assert.equal(find('.Welcome h1').text().trim(), 'Welcome to Snap, John!');
        assert.equal(find('.Welcome button.Welcome__btn').text().trim(), 'Start program setup');
        assert.equal(find('.NavBar .UserDropdown').length, 0);
      });
    });
  });
});

test('WBID errors are pluralized correctly', function(assert) {
  server.create('billingPlan');

  visit('/signup');
  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  click("input[type='checkbox']");

  // bad data
  fillIn("input[placeholder='Email address']", 'bad-email@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'tooeasy');

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { errors: { email: ['is invalid'], password: ['is too easy'] } }, 422);

      click('button.SignupForm__btn');

      andThen(() => {
        assert.equal(currentURL(), '/signup');

        let errorLanguage = find('.FormError__title').text().trim();

        assert.equal(errorLanguage, "Oops! A few things went wrong.");
        assert.equal(find('.SignupFormField.error').length, 2);

        // slightly better data
        fillIn("input[placeholder='Email address']", 'validemail@example.com');

        andThen(() => {
          assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

          server.post('http://account.myhdev.com:3400/api/user/user', { errors: { password: ['is too easy'] } }, 422);

          click('button.SignupForm__btn');

          andThen(() => {
            assert.equal(currentURL(), '/signup');

            errorLanguage = find('.FormError__title').text().trim();

            assert.equal(errorLanguage, "Oops! Something went wrong.");
            assert.equal(find('.SignupFormField.error').length, 1);
          });
        });
      });
    });
  });
});

test('WBID user creation fails', function(assert) {
  server.create('billingPlan');

  visit('/signup');
  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  click("input[type='checkbox']");

  // bad data
  fillIn("input[placeholder='Email address']", 'john@example');
  fillIn(".SignupForm input[placeholder='Password']", 'tooeasy');

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { errors: { email: ['is invalid'], password: ['is too easy'] } }, 422);

      click('button.SignupForm__btn');

      andThen(() => {
        assert.equal(currentURL(), '/signup');

        const errors = find('.FormError ul').text().trim().split("\n").map((e) => e.trim());

        assert.deepEqual(errors, ['Email is invalid.', 'Password is too easy.']);
        assert.equal(find('.SignupFormField.error').length, 2);
      });
    });
  });
});

test('there is already a WBID user session', function(assert) {
  server.create('billingPlan');

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => resolve({ token: 'stripe-token-value' });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', function() {
        return new Response(403, { 'Content-Type': 'application/json' });
      });
      server.post('/saas_implementations', server.create('saasImplementation', { status: 'pending', onboardingNextStep: 'welcome' }), 201);
      server.get('/users/me', server.create('user', { firstName: 'John', role: 'saas' }));

      click('button.SignupForm__btn');

      andThen(() => {
        assert.equal(currentURL(), '/onboarding/welcome');
        assert.equal(find('.Welcome h1').text().trim(), 'Welcome to Snap, John!');
        assert.equal(find('.Welcome button.Welcome__btn').text().trim(), 'Start program setup');
        assert.equal(find('.NavBar .UserDropdown').length, 0);
      });
    });
  });
});

test('Stripe credit card submission fails', function(assert) {
  server.create('billingPlan');

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => reject({ errors: ['Stripe error'] });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { user: { key: 'asdf1234' } }, 201);

      click('button.SignupForm__btn');

      andThen(() => {
        assert.equal(currentURL(), '/signup');
        assert.equal(find('.notification-messages-wrapper').length, 1);
        assert.equal(find('.notification-messages-wrapper').text().trim(), 'Sorry, something went wrong! Please try creating your account again. If you aren’t able to, contact help@meyouhealth.com.');
      });
    });
  });
});

test('We do not make repeated WBID user create calls if user creation succeeds', function(assert) {
  server.create('billingPlan');

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => reject({ errors: ['Stripe error'] });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { user: { key: 'asdf1234' } }, 201);

      click('button.SignupForm__btn');

      andThen(() => {
        assert.equal(currentURL(), '/signup');
        assert.equal(find('.notification-messages-wrapper').length, 1);
        assert.equal(find('.notification-messages-wrapper').text().trim(), 'Sorry, something went wrong! Please try creating your account again. If you aren’t able to, contact help@meyouhealth.com.');

        assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

        // this would block the stripe and snap calls if this API call was made again
        server.post('http://account.myhdev.com:3400/api/user/user', { errors: { email: ['is invalid'] } }, 422);
        server.post('/saas_implementations', server.create('saasImplementation', { status: 'pending', onboardingNextStep: 'welcome' }), 201);
        server.get('/users/me', server.create('user', { firstName: 'John', role: 'saas' }));

        // re stub the stripe call to succeed
        run(() => {
          const controller = this.application.__container__.lookup('controller:signup');

          controller.get('stripe').createToken = () => resolve({ token: 'stripe-token-value' });
        });

        click('button.SignupForm__btn');

        andThen(() => {
          assert.equal(currentURL(), '/onboarding/welcome');
          assert.equal(find('.Welcome h1').text().trim(), 'Welcome to Snap, John!');
          assert.equal(find('.Welcome button.Welcome__btn').text().trim(), 'Start program setup');
          assert.equal(find('.NavBar .UserDropdown').length, 0);
        });
      });
    });
  });
});

test('SaaS implementation creation fails and then succeeds', function(assert) {
  server.create('billingPlan');

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => resolve({ token: 'stripe-token-value' });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { user: { key: 'asdf1234' } }, 201);
      server.post('/saas_implementations', { errors: ['Snap error'] }, 400);

      click('button.SignupForm__btn');

      andThen(() => {
        assert.equal(currentURL(), '/signup');
        assert.equal(find('.notification-messages-wrapper').length, 1);
        assert.equal(find('.notification-messages-wrapper').text().trim(), 'Sorry, something went wrong! Please try creating your account again. If you aren’t able to, contact help@meyouhealth.com.');

        server.post('/saas_implementations', server.create('saasImplementation', { status: 'pending', onboardingNextStep: 'welcome' }), 201);
        server.get('/users/me', server.create('user', { firstName: 'John', role: 'saas' }));

        click('button.SignupForm__btn');

        andThen(() => {
          assert.equal(currentURL(), '/onboarding/welcome');
          assert.equal(find('.Welcome h1').text().trim(), 'Welcome to Snap, John!');
          assert.equal(find('.Welcome button.Welcome__btn').text().trim(), 'Start program setup');
          assert.equal(find('.NavBar .UserDropdown').length, 0);
        });
      });
    });
  });
});

test('I am shown a login modal if I attempt to create an account for a user that already has one', function(assert) {
  const done = assert.async();

  server.create('billingPlan');
  server.create('user', { 'email': 'john@example.com' });

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => resolve({ token: 'stripe-token-value' });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('.LoginModal').length, 1);
      assert.equal(find('.LoginModal.active.visible').length, 0);
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);
      assert.equal(find('.SignupForm__error').length, 0, 'No errors are displayed');
      assert.equal(find("input[placeholder='Email address']").hasClass('error'), false, 'Email field does not show an "already exists" error');

      server.post('http://account.myhdev.com:3400/api/user/user', { errors: { email: ['has already been taken'] } }, 422);

      click('button.SignupForm__btn');

      andThen(() => {
        setTimeout(() => {
          assert.equal(find('.LoginModal').hasClass("visible"), true, "expected the modal to have become visible");
          assert.equal(find('.LoginModal__header').text().trim(), "Welcome back!");
          assert.equal(find('.LoginModal__help').text().trim(), 'Forgot your password? You can reset it.');

          done();
        }, 1000);
      });
    });
  });
});

test('From the login modal if I enter the wrong password I can change it and retry', function(assert) {
  const done = assert.async();

  server.create('billingPlan');
  server.create('user', { 'email': 'john@example.com' });

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => resolve({ token: 'stripe-token-value' });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('.LoginModal').length, 1);
      assert.equal(find('.LoginModal.active.visible').length, 0);
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { errors: { email: ['has already been taken'] } }, 422);

      click('button.SignupForm__btn');

      andThen(() => {
        setTimeout(() => {
          assert.equal(find('.LoginModal').hasClass("visible"), true, "expected the modal to have become visible");

          server.post('http://account.myhdev.com:3400/api/user/session', { errors: { data: ["Invalid email or password"] } }, 422);

          fillIn(".LoginModal__password input[placeholder='Password']", 'p*7123s1234');

          andThen(() => {
            assert.equal(find('button.LoginModal__btn').prop('disabled'), false);

            click('button.LoginModal__btn');

            andThen(() => {
              assert.equal(find('button.LoginModal__btn').prop('disabled'), false);

              fillIn(".LoginModal__password input[placeholder='Password']", 'anotherp4ssword');

              done();
            });
          });
        }, 1000);
      });
    });
  });
});

test('From the login modal if the stripe or saasImplementation calls fails I see an error encouraging me to retry', function(assert) {
  const done = assert.async();

  server.create('billingPlan');
  server.create('user', { 'email': 'john@example.com' });

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => resolve({ token: 'stripe-token-value' });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('.LoginModal').length, 1);
      assert.equal(find('.LoginModal.active.visible').length, 0);
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { errors: { email: ['has already been taken'] } }, 422);

      click('button.SignupForm__btn');

      andThen(() => {
        setTimeout(() => {
          assert.equal(find('.LoginModal').hasClass("visible"), true, "expected the modal to have become visible");

          server.post('http://account.myhdev.com:3400/api/user/session', { user_session: { id: 1 } }, 201);

          fillIn(".LoginModal__password input[placeholder='Password']", 'p*7123s1234');

          andThen(() => {
            assert.equal(find('button.LoginModal__btn').prop('disabled'), false);

            server.post('/saas_implementations', { errors: ['Snap error'] }, 400);

            click('button.LoginModal__btn');

            andThen(() => {
              assert.equal(find('.LoginModal__error').length, 1);
              assert.equal(find('.LoginModal__error').text().trim(), 'Sorry, something went wrong! Please try again.');

              done();
            });
          });
        }, 1000);
      });
    });
  });
});

test('From the login modal if I enter the correct password I can complete the flow', function(assert) {
  const done = assert.async();

  server.create('billingPlan');
  const john = server.create('user', { 'firstName': 'John', 'email': 'john@example.com', role: 'saas' } );

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => resolve({ token: 'stripe-token-value' });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('.LoginModal').length, 1);
      assert.equal(find('.LoginModal.active.visible').length, 0);
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { errors: { email: ['has already been taken'] } }, 422);

      click('button.SignupForm__btn');

      andThen(() => {
        setTimeout(() => {
          assert.equal(find('.LoginModal').hasClass("visible"), true, "expected the modal to have become visible");

          server.post('http://account.myhdev.com:3400/api/user/session', { user_session: { id: 1 } }, 201);

          fillIn(".LoginModal__password input[placeholder='Password']", 'p*7123s1234');

          andThen(() => {
            assert.equal(find('button.LoginModal__btn').prop('disabled'), false);

            server.post('/saas_implementations', server.create('saasImplementation', { status: 'pending', onboardingNextStep: 'welcome' }), 201);
            server.get('/users/me', john);

            click('button.LoginModal__btn');

            andThen(() => {
              assert.equal(currentURL(), '/onboarding/welcome');
              assert.equal(find('.Welcome h1').text().trim(), 'Welcome to Snap, John!');
              assert.equal(find('.Welcome button.Welcome__btn').text().trim(), 'Start program setup');
              assert.equal(find('.NavBar .UserDropdown').length, 0);
              assert.equal(find('.ui.dimmer').length, 0, 'ui dimmer is destroyed upon navigation');

              done();
            });
          });
        }, 1000);
      });
    });
  });
});

test('I pick up where I left off if I already have a saasImplementation', function(assert) {
  const done = assert.async();

  server.create('billingPlan');
  const john = server.create('user', { 'firstName': 'John', 'email': 'john@example.com', role: 'saas' } );
  const implementation = server.create('saasImplementation', { status: 'active' });
  implementation.update({ onboardingNextStep: 'select-eligibility' });

  visit('/signup');

  fillIn("input[placeholder='First name']", 'John');
  fillIn("input[placeholder='Last name']", 'Doe');
  fillIn("input[placeholder='Company name']", 'Foo Bar Corporation');
  fillIn("input[placeholder='Email address']", 'john@example.com');
  fillIn(".SignupForm input[placeholder='Password']", 'password');
  click("input[type='checkbox']");

  andThen(() => {
    // we mock Stripe in test, requiring us to dive into the controller instance
    run(() => {
      const controller = this.application.__container__.lookup('controller:signup');

      controller.get('stripe').createToken = () => resolve({ token: 'stripe-token-value' });
      controller.send('updateStripe', {}, { complete: true });
    });

    andThen(() => {
      assert.equal(find('.LoginModal').length, 1);
      assert.equal(find('.LoginModal.active.visible').length, 0);
      assert.equal(find('button.SignupForm__btn').prop('disabled'), false);

      server.post('http://account.myhdev.com:3400/api/user/user', { errors: { email: ['has already been taken'] } }, 422);

      click('button.SignupForm__btn');

      andThen(() => {
        setTimeout(() => {
          assert.equal(find('.LoginModal').hasClass("visible"), true, "expected the modal to have become visible");

          server.post('http://account.myhdev.com:3400/api/user/session', { user_session: { id: 1 } }, 201);

          fillIn(".LoginModal__password input[placeholder='Password']", 'p*7123s1234');

          andThen(() => {
            assert.equal(find('button.LoginModal__btn').prop('disabled'), false);

            server.get('/saas_implementations', server.create('saasImplementation', { status: 'pending', onboardingNextStep: 'setup-program' }), 200);
            server.get('/users/me', john);

            click('button.LoginModal__btn');

            andThen(() => {
              assert.equal(currentURL(), '/implementation/setup');
              assert.equal(find('.SaasSetup h1').text().trim(), 'Welcome to Snap, John!');
              assert.equal(find('.Welcome button.Welcome__btn').text().trim(), 'Start program setup');
              assert.equal(find('.NavBar .UserDropdown').length, 0);
              assert.equal(find('.ui.dimmer').length, 0, 'ui dimmer is destroyed upon navigation');

              done();
            });
          });
        }, 1000);
      });
    });
  });
});

// test('I am told to unlock my account from my email if I enter an incorrect password too many times', function(assert) {
// TODO - inform users that they've locked themselves out
// });
