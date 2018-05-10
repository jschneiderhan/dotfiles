const emailRegex = /([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+)/gi;

export default function parseEmailAddresses(text) {
  return text.match(emailRegex);
  //return ['a@a.com']
}
