const emailRegex = /([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+)/gi;

export default function parseEmailAddresses(text) {
  debugger;
  const validEmails = [];
  const invalidEmails = [];
  //const chunks = text.split(/[,\t\n;]/gi)
  const chunks = text.split(/(?!\B"[^<]*)[,\t\n;](?![^>]*"\B)/)

  chunks.forEach((chunk) => {
    chunk = chunk.trim();
    const emails = chunk.match(/([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+)/gi);
    if (emails) {
      emails.forEach((email) => {
        validEmails.push(email);
      });
    } else {
      invalidEmails.push(chunk);
    }
  });

  return { validEmails: validEmails, invalidEmails: invalidEmails };
}
