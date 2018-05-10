import parseEmailAddresses from 'snap/utils/parse-email-addresses';
import { module, test } from 'qunit';

module('Unit | Utility | parse-email-addresses');

// Replace this with your real tests.
test('it works', function(assert) {

  // Invididual entries
  assert.deepEqual(parseEmailAddresses('jon@example.com'), {
    validEmails: ['jon@example.com'],
    invalidEmails: []
  });

  assert.deepEqual(parseEmailAddresses('Jon Smith <jon@example.com>'), {
    validEmails: ['jon@example.com'],
    invalidEmails: []
  });

  assert.deepEqual(parseEmailAddresses('sue+google-like-suffix@example.com>'), {
    validEmails: ['sue+google-like-suffix@example.com'],
    invalidEmails: []
  });

  assert.deepEqual(parseEmailAddresses('jon@example'), {
    validEmails: [],
    invalidEmails: ['jon@example']
  });

  assert.deepEqual(parseEmailAddresses('Jon Smith'), {
    validEmails: [],
    invalidEmails: ['Jon Smith']
  });

  // Multiple comma separated entries
  assert.deepEqual(parseEmailAddresses('jon@example.com, Jane Smith <jane@example.com>, Jeff Jones - jeff@example.com, no email in this text, jon+google-like-suffix@example.com'), {
    validEmails: ['jon@example.com', 'jane@example.com', 'jeff@example.com', 'jon+google-like-suffix@example.com'],
    invalidEmails: ['no email in this text']
  });

  // Multiple colon separated entries
  assert.deepEqual(parseEmailAddresses('jon@example.com; Jane Smith <jane@example.com>; Jeff Jones - jeff@example.com; no email in this text, jon+google-like-suffix@example.com'), {
    validEmails: ['jon@example.com', 'jane@example.com', 'jeff@example.com', 'jon+google-like-suffix@example.com'],
    invalidEmails: ['no email in this text']
  });

  // Multiple newline separated entries
  assert.deepEqual(parseEmailAddresses('jon@example.com\n Jane Smith <jane@example.com>\n Jeff Jones - jeff@example.com\n no email in this text, jon+google-like-suffix@example.com'), {
    validEmails: ['jon@example.com', 'jane@example.com', 'jeff@example.com', 'jon+google-like-suffix@example.com'],
    invalidEmails: ['no email in this text']
  });

  // Multiple tab separated entries
  assert.deepEqual(parseEmailAddresses('jon@example.com\t Jane Smith <jane@example.com>\t Jeff Jones - jeff@example.com\t no email in this text, jon+google-like-suffix@example.com'), {
    validEmails: ['jon@example.com', 'jane@example.com', 'jeff@example.com', 'jon+google-like-suffix@example.com'],
    invalidEmails: ['no email in this text']
  });
});
