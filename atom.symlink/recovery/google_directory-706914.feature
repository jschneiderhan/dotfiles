Feature: Enrolling in a Google Directory-eligible sponsor
  In order to enroll in a particular sponsorship
  As a registered user
  I want to determine my sponsor eligibility via Google authentication

  Background:
    Given there is a contract that uses Google authentication for eligibility

  Scenario: Enrolling before I have an account
    When I try to enroll in the sponsorship before registering an account
    Then I should be able to register an account
    And I should have to read the sponsor's consent before continuing

  Scenario: Enrolling after I have an account
    Given I am part of the G Suite account
    When I try to enroll in the sponsorship
    Then I should have to read the sponsor's consent before continuing

  Scenario: Trying to enroll when I use an ineligible Google account for authorization
    Given I am using a different Google account
    When I try to enroll in the sponsorship
    Then I should be told to use the G Suite account to verify eligibility

  Scenario Outline: Trying to enroll when the token is invalid
    Given I am trying to hack the eligibility check by <hack>
    When I try to enroll in the sponsorship
    Then I should be told that the token is invalid

    Examples:
      | hack                                          |
      | manipulating the audience of the issued token |
      | supplying an invalid token                    |

  Scenario Outline: Google returns an error code
    Given I am part of the G Suite account
    When I try to enroll in the sponsorship

    Examples:
      | code                                          | message |
      |  |         |
      | supplying an invalid token                    |         |
