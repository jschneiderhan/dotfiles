Feature: Challenge Admin Logins
  In order to get into the admin system
  As a challenge system admin
  I want to be able to sign in and be sent to where I was going

  Background:
    Given challenges exist

  Scenario: I can sign in to the admin area with a username and password
    Given I am signed in to the admin as a "Challenge Admin"
      When I go to the admin welcome page
      Then I should be on the admin welcome page
      Then I should see "Daily Challenge Administration - MeYou Health"

  Scenario: If I am signed into DC and then visit the admin login page I should be taken to the admin welcome page after I sign in to the admin area (as opposed to redirecting back to the login back after a successful login).
    Given I am signed in to the admin as a "Challenge Admin"
    When I go to the admin login page
    Then I should be on the admin login page
    When I sign in to the admin
    Then I should be on the admin welcome page

  Scenario: If I try to go somewhere specific while signed out I should be taken to the login page and then redirected back to that page after I sign in
    Given a challenge_template exists with title: "Test Challenge.", description: "test description", wellbeing_element_id: 1
    When I go to edit challenge template "Test Challenge."
    Then I should be on the admin login page
      And I should see "You must be signed in to access this page."
    Given I am signed in to the admin
    Then I should be on edit challenge template "Test Challenge."

  Scenario: If I am signed into DC I should have to login a second time before seeing admin pages
    Given I have registered and signed in
    When I go to the admin welcome page
    Then I should be on the admin login page
      And I should see "You must be signed in to access this page."
