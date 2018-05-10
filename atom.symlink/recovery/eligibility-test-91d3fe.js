import { test } from 'qunit';
import moduleForAcceptance from 'snap/tests/helpers/module-for-acceptance';

moduleForAcceptance('Acceptance | contract | eligibility | google directory | eligibility');

test('contracts with google directory eligibility display a list of eligible users', function(assert) {
  const contract = server.create("contract", { eligibilityType: "google_directory" });
  server.create("googleDirectoryUser", { contractId: contract.id, name: { full_name: 'Alice Edwards', given_name: 'Alice', family_name: 'Edwards' }, excluded: false });
  server.create("googleDirectoryUser", { contractId: contract.id, name: { full_name: 'Alice Darwin', given_name: 'Alice', family_name: 'Darwin' }, excluded: false });
  server.create("googleDirectoryUser", { contractId: contract.id, name: { full_name: 'Alice Fells', given_name: 'Alice', family_name: 'Fells' }, excluded: false });
  server.create("googleDirectoryUser", { contractId: contract.id, name: { full_name: 'John Smith', given_name: 'John', family_name: 'Smith' }, excluded: true });

  signIn();

  visit(`/contracts/${contract.id}/eligibility/google-directory/eligibility`);

  andThen(function() {
    assert.equal(find(`.EligibilityUserList__row:nth-child(1):contains('John Doe')`).find(".EligibilityUserListColumn--checkbox input:checked").length, 1);
    assert.equal(find(`.EligibilityUserList__row:nth-child(2):contains('John Smith')`).find(".EligibilityUserListColumn--checkbox input:not(:checked)").length, 1);
    assert.equal(find(".EligibilityUserList__title:contains('1 eligible')").length, 1, "unable to find '1 eligible'");
    assert.equal(find(".EligibilityUserList__title:contains('1 excluded')").length, 1, "unable to find '1 excluded'");
    assert.equal(find(".eligibility-msg:contains('We found 2 people in your directory.')").length, 1, "unable to find 'We found 2 people in your directory.'");
  });
});

test('contracts with google directory eligibility can toggle exclusion of a particular user', function(assert) {
  const contract = server.create("contract", { eligibilityType: "google_directory" });
  const excludedUser = server.create("googleDirectoryUser", { contractId: contract.id, name: { family_name: "Kuhlman", full_name: "Dusty Kuhlman", given_name: "Dusty" } });

  signIn();

  visit(`/contracts/${contract.id}/eligibility/google-directory/eligibility`);

  click(`.EligibilityUserList .EligibilityUserListColumn--name:contains('${excludedUser.name.full_name}') label`);

  andThen(function() {
    assert.equal(find(`.EligibilityUserList__row:nth-child(1):contains('${excludedUser.name.full_name}')`).find(".EligibilityUserListColumn--checkbox input:not(:checked)").length, 1);
    assert.equal(find(".EligibilityUserList__title:contains('1 excluded')").length, 1, "unable to find '1 excluded'");
    assert.equal(server.db.googleDirectoryUsers[0].excluded, true);
    assert.equal(find('.notification-messages-wrapper').length, 1, 'notification is displayed');
    assert.equal(find('.notification-messages-wrapper:last').text().trim(), 'Dusty Kuhlman has been removed from your wellness program.', 'notification displays when we exclude a user');

    click(`.EligibilityUserList__list .EligibilityUserListColumn--name:contains('${excludedUser.name.full_name}') label`);

    andThen(function() {
      assert.equal(find(`.EligibilityUserList__row:nth-child(1):contains('${excludedUser.name.full_name}')`).find(".EligibilityUserListColumn--checkbox input:checked").length, 1);
      assert.equal(find(".EligibilityUserList__title:contains('0 excluded')").length, 1, "unable to find '0 excluded'");
      assert.equal(server.db.googleDirectoryUsers[0].excluded, false);
      assert.equal(find('.notification-messages-wrapper').length, 2, 'second notification is displayed');
      assert.equal(find('.notification-messages-wrapper:last').text().trim(), 'Dusty Kuhlman has been added to your wellness program.', 'notification displays when we include a user');
    });
  });
});

test('contracts without google directory eligibility send the user to the show contract page', function(assert) {
  const contract = server.create("contract", { eligibilityType: "code" });

  signIn();

  visit(`/contracts/${contract.id}/eligibility/google-directory/eligibility`);

  andThen(function() {
    assert.equal(currentURL(), `/contracts/${contract.id}`);
  });
});

test('during onboarding the CTA takes the user to the complete page', function(assert) {
  const contract = server.create("contract", { eligibilityType: "google_directory" });
  server.createList('googleDirectoryUser', 8, { contract: contract, excluded: false });
  server.createList('googleDirectoryUser', 2, { contract: contract, excluded: true });

  signIn();
  visit(`/contracts/${contract.id}/eligibility/google-directory/eligibility?onboarding=true`);
  click(".Button");

  andThen(function() {
    assert.equal(find('.notification-messages-wrapper').length, 1, 'notifications are displayed');
    assert.equal(find('.notification-messages-wrapper').text().trim(), '8 people have been added to the list', 'notification displays the correct number of eligible people');
    assert.equal(currentURL(), `/contracts/${contract.id}/eligibility/google-directory/complete?onboarding=true`);
  });
});
