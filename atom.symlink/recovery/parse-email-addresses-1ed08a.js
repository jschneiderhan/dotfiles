import { isEmpty, isPresent } from '@ember/utils';

// Regex grabbed from http://snipplr.com/view/26466/
const emailRegex = /([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+)/gi;

export default function parseEmailAddresses(text) {
  const validEmails = [];
  const invalidEmails = [];
  const chunks = text.split(/[,\t\n;]/);

  chunks.forEach((chunk) => {
    chunk = chunk.trim();
    if (isEmpty(chunk)) {
      return;
    }
    const emails = chunk.match(/([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+)/gi);
    if (isPresent(emails)) {
      emails.forEach((email) => {
        validEmails.push(email);
      });
    } else {
      invalidEmails.push(chunk);
    }
  });

  return { validEmails: validEmails, invalidEmails: invalidEmails };
}
