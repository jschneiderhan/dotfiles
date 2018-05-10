import parseEmailAddresses from 'snap/utils/parse-email-addresses';
import { module, test } from 'qunit';

module('Unit | Utility | parse-email-addresses');

// Replace this with your real tests.
test('it works', function(assert) {
  assert.deepEqual(parseEmailAddresses('jon@example.com'), {
    validEmails: ['jon@example.com'],
    invalidEmails: ['no email in this text']
  });

  assert.deepEqual(parseEmailAddresses('jon@example'), {
    validEmails: null,
    invalidEmails: ['jon@example']
  });

  assert.deepEqual(parseEmailAddresses('Jon Smith <jon@example.com>'), {
    validEmails: 'jon@example.com',
    invalidEmails: null
  });

  assert.deepEqual(parseEmailAddresses('Jon Smith'), {
    validEmails: null,
    invalidEmails: ['Jon Smith']
  });

  // comma separated
  assert.deepEqual(parseEmailAddresses('jon@example.com, Jane Smith <jane@example.com>, Jeff Jones - jeff@example.com, no email in this text'), {
    validEmails: ['jon@example.com', 'jane@example.com', 'jeff@example.com'],
    invalidEmails: ['no email in this text']
  });

  // colon separated
  assert.deepEqual(parseEmailAddresses('jon@example.com; Jane Smith <jane@example.com>; Jeff Jones - jeff@example.com; no email in this text'), {
    validEmails: ['jon@example.com', 'jane@example.com', 'jeff@example.com'],
    invalidEmails: ['no email in this text']
  });

  // newline separated
  assert.deepEqual(parseEmailAddresses('jon@example.com\n Jane Smith <jane@example.com>\n Jeff Jones - jeff@example.com\n no email in this text'), {
    validEmails: ['jon@example.com', 'jane@example.com', 'jeff@example.com'],
    invalidEmails: ['no email in this text']
  });

  // tab separated
  assert.deepEqual(parseEmailAddresses('jon@example.com\t Jane Smith <jane@example.com>\t Jeff Jones - jeff@example.com\t no email in this text'), {
    validEmails: ['jon@example.com', 'jane@example.com', 'jeff@example.com'],
    invalidEmails: ['no email in this text']
  });
});
