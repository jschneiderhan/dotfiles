import { test } from 'qunit';
import moduleForAcceptance from 'snap/tests/helpers/module-for-acceptance';

moduleForAcceptance('Acceptance | contract | eligibility | email | index');

test('Initial state of UI elements', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  signIn();

  visit(`/contracts/${contract.id}/eligibility/email`);

  andThen(function() {
    assert.equal(find(".EligibilityUserList__Staged .EligibilityUserList__title").text().trim(), "Paste or type a list above to see the preview.", "there are instructions and no list");
    assert.equal(find(".Button--submit-btn").text().trim(), "Add to the list", "the submit button is initially disabled");
    assert.equal(find(".EmailList .h2").text(), "Add to the list of employees who can enroll", "the page renders");
    assert.equal(find(".Button--submit-btn").prop('disabled'), true, "the submit button is initially disabled");
    assert.equal(find(".EligibilityUserList__Error--invalid").is(":visible"), false, "Invalid Emails error box is initially hidden");
    assert.equal(find(".EligibilityUserList__Error--duplicate").is(":visible"), false, "Duplicate Emails error box is initially hidden");
  });
});

test('The screen title is different whether the user is on the managing flow or onboarding flow', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  signIn();

  visit(`/contracts/${contract.id}/eligibility/email`);

  andThen(function() {
    assert.equal(find(".EmailList .h2").text(), "Add to the list of employees who can enroll", "the correct screen title for the managing flow");
  });

  visit(`/contracts/${contract.id}/eligibility/email?onboarding=true`);

  andThen(function() {
    assert.equal(find(".EmailList .h2").text(), "Create a list of employees who can enroll", "the correct screen title for the onboarding flow");
  });
});

test('Users have the ability to create an email list based on email addresses', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  signIn();

  visit(`/contracts/${contract.id}/eligibility/email`);

  fillIn('textarea.EmailList__textbox', 'joan.dee@blackmirror.org');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    assert.equal(find(".EligibilityUserList__Staged .EligibilityUserListColumn--name").text().trim(),
                 "joan.dee@blackmirror.org",
                 "entering an email and pressing <ENTER> adds the email to the list");
    assert.equal(find(".EligibilityUserList__Staged .EligibilityUserList__title").text().trim(),
                 "You're making 1 person eligible.",
                 "the email count in the message is accurate");
    assert.equal(find("textarea.EmailList__textbox").text().trim(), "", "after the email is added the text area is cleared");
    assert.equal(find(".Button--submit-btn").text().trim(), "Add 1 to the list", "the submit button is enabled after adding an email");
    assert.equal(find(".Button--submit-btn").prop('disabled'), false, "the submit button is enabled after adding an email");
  });
});

test('Multiple email addresses can be entered', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  signIn();

  visit(`/contracts/${contract.id}/eligibility/email`);

  fillIn('textarea.EmailList__textbox', 'joan.dee@blackmirror.org');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    assert.equal(find(".EligibilityUserList__Staged .EligibilityUserListColumn--name").text().trim(),
                 "joan.dee@blackmirror.org",
                 "entering an email and pressing <ENTER> adds the email to the list");
    assert.equal(find(".EligibilityUserList__Staged .EligibilityUserList__title").text().trim(),
                 "You're making 1 person eligible.",
                 "the email count in the message is accurate");
    assert.equal(find("textarea.EmailList__textbox").text().trim(), "", "after the email is added the text area is cleared");
    assert.equal(find(".Button--submit-btn").text().trim(), "Add 1 to the list", "the submit button is enabled after adding an email");
    assert.equal(find(".Button--submit-btn").prop('disabled'), false, "the submit button is enabled after adding an email");

    andThen(function() {
      fillIn('textarea.EmailList__textbox', 'lphovercraft@blackmirror.org\ngrantchester@meadows.gb');
      keyEvent('textarea.EmailList__textbox', 'keyup', 13);

      andThen(function() {
        assert.deepEqual(find(".EligibilityUserList__Staged .EligibilityUserListColumn--name").text().replace(/\n/g, '').trim().replace(/\s+/g, ',').split(','),
                     ["grantchester@meadows.gb", "lphovercraft@blackmirror.org", "joan.dee@blackmirror.org"],
                     "adding a second user succeeds");
        assert.equal(find(".EligibilityUserList__Staged .EligibilityUserList__title").text().trim(),
                     "You're making 3 people eligible.",
                     "the email count in the message is accurate");
      });
    });
  });
});

test('Multiple email addresses will be parsed from arbitrary text', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  signIn();

  visit(`/contracts/${contract.id}/eligibility/email`);

  fillIn('textarea.EmailList__textbox', '\t\nUser1 <user1@example.com>, \tuser2@example.com,\n\nUser the Third <user3@example.com>\n\r\tnot_an_email address,,user4+googleish@example.com');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    assert.deepEqual(find(".EligibilityUserList__Staged .EligibilityUserListColumn--name").text().replace(/\n/g, '').trim().replace(/\s+/g, ',').split(','),
                 ["user4+googleish@example.com", "user3@example.com", "user2@example.com", "user1@example.com"],
                 "adding a second user succeeds");
    assert.equal(find(".EligibilityUserList__Staged .EligibilityUserList__title").text().trim(),
                 "You're making 3 people eligible.",
                 "the email count in the message is accurate");
  });
});

test('Invalid emails are caught', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  signIn();

  visit(`/contracts/${contract.id}/eligibility/email`);

  andThen(function() {
    // Sad path invalid email
    fillIn('textarea.EmailList__textbox', 'joan.dee@notanemail');
    keyEvent('textarea.EmailList__textbox', 'keyup', 13);

    andThen(function() {
      assert.equal(find(".EligibilityUserList__Error--invalid .EligibilityUserListColumn--name").text().trim(),
                   "joan.dee@notanemail",
                   "entering an invalid email and pressing <ENTER> adds the email to the invalid list");
      assert.equal(find(".EligibilityUserList__Error--invalid .EligibilityUserList__title").text().trim(),
                   "These don't look like email addresses",
                   "the invalid email list has the correct title");
      assert.equal(find("textarea.EmailList__textbox").text().trim(), "", "after the email is added the text area is cleared");

      // Dismissing the message
      click(".EligibilityUserList__Error--invalid .EligibilityUserList__close-btn");

      andThen(function() {
        assert.equal(find(".EligibilityUserList__Error--invalid").is(":visible"), false, "after being dismissed the invalid error box is hidden");
      });
    });
  });
});

test('Duplicate emails are caught', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  signIn();

  visit(`/contracts/${contract.id}/eligibility/email`);

  fillIn('textarea.EmailList__textbox', 'joan.dee@blackmirror.org');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    // Sad path duplicate email
    fillIn('textarea.EmailList__textbox', 'joan.dee@blackmirror.org');
    keyEvent('textarea.EmailList__textbox', 'keyup', 13);

    andThen(function() {
      assert.equal(find(".EligibilityUserList__Error--duplicate .EligibilityUserListColumn--name").text().trim(),
                   "joan.dee@blackmirror.org",
                   "entering a duplicate email and pressing <ENTER> adds the email to the duplicate list");
      assert.equal(find(".EligibilityUserList__Error--duplicate .EligibilityUserList__title").text().trim(),
                   "These are already on your list",
                   "the duplicate email list has the correct title");
      assert.equal(find("textarea.EmailList__textbox").text().trim(), "", "after the email is added the text area is cleared");
      assert.ok(find(".Button--submit-btn").is(':disabled'), "the submit button is disabled while there are errors");

      // Dismissing the message
      click(".EligibilityUserList__Error--duplicate .EligibilityUserList__close-btn");

      andThen(function() {
        assert.equal(find(".EligibilityUserList__Error--duplicate").is(":visible"), false, "after being dismissed the duplicate error box is hidden");
      });
    });
  });
});

test('Emails are checked for duplicates case-insensitively', function(assert) {
    const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  signIn();

  visit(`/contracts/${contract.id}/eligibility/email`);

  fillIn('textarea.EmailList__textbox', 'joan.dee@blackmirror.org');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    fillIn('textarea.EmailList__textbox', 'JOAN.DEE@blackmirror.org');
    keyEvent('textarea.EmailList__textbox', 'keyup', 13);

    andThen(function() {
      assert.equal(find(".EligibilityUserList__Error--duplicate .EligibilityUserListColumn--name").text().trim(),
                   "JOAN.DEE@blackmirror.org",
                   "entering a duplicate email and pressing <ENTER> adds the email to the duplicate list");
      assert.equal(find(".EligibilityUserList__Error--duplicate .EligibilityUserList__title").text().trim(),
                   "These are already on your list",
                   "the duplicate email list has the correct title");
      assert.equal(find("textarea.EmailList__textbox").text().trim(), "", "after the email is added the text area is cleared");
      assert.ok(find(".Button--submit-btn").is(':disabled'), "the submit button is disabled while there are errors");
    });
  });
});

test('The email list can be submitted', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  signIn();

  visit(`/contracts/${contract.id}/eligibility/email`);

  fillIn('textarea.EmailList__textbox', 'joan.dee@blackmirror.org\ngrantchester@meadows.gb.uk');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    click('.Button--submit-btn');

    andThen(function() {
      assert.deepEqual(server.db.emailEligibilities.mapBy('email'), ["grantchester@meadows.gb.uk", "joan.dee@blackmirror.org"]);
      assert.deepEqual(server.db.emailEligibilities.mapBy('contractId'), [contract.id, contract.id]);

      assert.equal(find('.notification-messages-wrapper').length, 1);
      assert.equal(find('.notification-messages-wrapper').text().trim(), '2 employees have been added to the list.');

      assert.equal(currentURL(), `/contracts/${contract.id}/eligibility/email/manage`, 'after successfully submitting email list transition to manage eligibility screen');
    });
  });
});

test('For the onboarding flow the email list can be submitted', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  const currentUser = server.create('user', { email: "admin@example.com" });
  contract.createEmailEligibility({ email: currentUser.email });

  signIn(currentUser);

  visit(`/contracts/${contract.id}/eligibility/email?onboarding=true`);

  fillIn('textarea.EmailList__textbox', 'joan.dee@blackmirror.org\ngrantchester@meadows.gb.uk');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    click('.Button--submit-btn');

    andThen(function() {
      assert.deepEqual(server.db.emailEligibilities.mapBy('email'), ["admin@example.com", "grantchester@meadows.gb.uk", "joan.dee@blackmirror.org"]);
      assert.deepEqual(server.db.emailEligibilities.mapBy('contractId'), [contract.id, contract.id, contract.id]);

      assert.equal(find('.notification-messages-wrapper').length, 1);
      assert.equal(find('.notification-messages-wrapper').text().trim(), '2 employees have been added to the list.');

      assert.equal(currentURL(), `/contracts/${contract.id}/eligibility/email/eligibility?onboarding=true`, 'after successfully submitting email list transition to eligibilities listing screen');
    });
  });
});

test('Let the user know the number of employees already in the list when adding more staff during the onboarding flow', function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  const currentUser = server.create('user', { email: "admin@example.com" });

  signIn(currentUser);

  visit(`/contracts/${contract.id}/eligibility/email?onboarding=true`);

  andThen(function() {
    assert.equal(find(".EmailList .h2").text(), "Create a list of employees who can enroll", "the correct screen title for the onboarding flow");
    assert.equal(find(".eligibility-msg:eq(0)").text(), "This is where you tell us who should be allowed to take part in your wellness program.");
  });

  fillIn('textarea.EmailList__textbox', 'joan.dee@blackmirror.org');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  fillIn('textarea.EmailList__textbox', 'admin@example.com');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    click('.Button--submit-btn');

    andThen(function() {
      assert.equal(find('.notification-messages-wrapper').text().trim(), '2 employees have been added to the list.');

      andThen(function() {
        // This represents the user hitting the browser back button
        visit(`/contracts/${contract.id}/eligibility/email?onboarding=true`);

        andThen(function() {
          assert.equal(find(".EmailList .h2").text(), "Add to your list of 2 employees", "the correct screen title for the onboarding flow when the list of employees is not empty");
          assert.equal(find(".eligibility-msg:eq(0)").text(), "We currently have a list of 2 people who can enroll in your wellness program. You can add more below.");
        });
      });
    });
  });
});

test(`For the onboarding flow the admin's email address will not be added to the eligibility list if it's already there`, function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  const currentUser = server.create('user', { email: "admin@example.com" });

  // Preemptively add the user's email to the eligibility list
  contract.createEmailEligibility({ email: currentUser.email });

  signIn(currentUser);

  visit(`/contracts/${contract.id}/eligibility/email?onboarding=true`);

  fillIn('textarea.EmailList__textbox', 'john@example.com');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    assert.equal(find(".EligibilityUserList__Staged .EligibilityUserList__title").text().trim(), "You're making 1 person eligible.", "the email count in the message is accurate");

    click('.Button--submit-btn');

    andThen(function() {
      assert.deepEqual(server.db.emailEligibilities.mapBy('email').sort(), ["john@example.com", "admin@example.com"].sort());

      assert.equal(find('.notification-messages-wrapper').length, 1);
      assert.equal(find('.notification-messages-wrapper').text().trim(), '1 employee has been added to the list.', 'notification displays the correct number of eligible people');
    });
  });
});

test(`For the onboarding flow the admin's email address will not be added to the eligibility list if the user added themselves`, function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  const currentUser = server.create('user', { email: "admin@example.com" });

  signIn(currentUser);

  visit(`/contracts/${contract.id}/eligibility/email?onboarding=true`);

  fillIn('textarea.EmailList__textbox', 'admin@example.com');
  keyEvent('textarea.EmailList__textbox', 'keyup', 13);

  andThen(function() {
    assert.equal(find(".EligibilityUserList__Staged .EligibilityUserList__title").text().trim(), "You're making 1 person eligible.", "the email count in the message is accurate");

    fillIn('textarea.EmailList__textbox', 'john@example.com');
    keyEvent('textarea.EmailList__textbox', 'keyup', 13);

    andThen(function() {
      assert.equal(find(".EligibilityUserList__Staged .EligibilityUserList__title").text().trim(), "You're making 2 people eligible.", "the email count in the message is accurate");

      click('.Button--submit-btn');

      andThen(function() {
        assert.deepEqual(server.db.emailEligibilities.mapBy('email').sort(), ["john@example.com", "admin@example.com"].sort());

        assert.equal(find('.notification-messages-wrapper').length, 1);
        assert.equal(find('.notification-messages-wrapper').text().trim(), '2 employees have been added to the list.', 'notification displays the correct number of eligible people');
      });
    });
  });
});

test(`For the onboarding flow the admin's email address will added the eligibility list automatically`, function(assert) {
  const saasImplementation = server.create('saasImplementation', { status: 'active', eligibilityType: 'email', onboardingNextStep: 'review-eligibility' });
  saasImplementation.contract.update({ eligibilityType: 'email' });
  const contract = saasImplementation.contract;

  const currentUser = server.create('user', { email: "admin@example.com" });

  signIn(currentUser);

  visit(`/contracts/${contract.id}/eligibility/email?onboarding=true`);

  andThen(function() {
    // Happy path #1
    fillIn('textarea.EmailList__textbox', 'john@example.com');
    keyEvent('textarea.EmailList__textbox', 'keyup', 13);

    andThen(function() {
      assert.equal(find(".EligibilityUserList__Staged .EligibilityUserList__title").text().trim(), "You're making 1 person eligible.", "the email count in the message is accurate");

      click('.Button--submit-btn');

      andThen(function() {
        assert.deepEqual(server.db.emailEligibilities.mapBy('email'), ["john@example.com", "admin@example.com"]);

        assert.equal(find('.notification-messages-wrapper').length, 2);
        assert.equal(find('.notification-messages-wrapper:eq(0)').text().trim(), "We didn't see your email address on the list, so we've added it for you.", 'notification displays that the admin email was added to the list');
        assert.equal(find('.notification-messages-wrapper:eq(1)').text().trim(), '2 employees have been added to the list.', 'notification displays the correct number of eligible people');
      });
    });
  });
});
