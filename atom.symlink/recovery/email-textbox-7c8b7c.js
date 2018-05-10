import Component from '@ember/component';
import { later } from '@ember/runloop';

export default Component.extend({
  emails: null,

  paste() {
    later(() => {
      this.send('parse');
    }, 100);
  },

  actions: {
    parse() {
      let emailText = this.get('emails');
      this.set('emails', null);

      if (!emailText.match(/^\s+$/)) {
        debugger
        // Regex taken from http://snipplr.com/view/26466/
        emails = emailText.match(/([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+)/gi);

        this.get('stageEmails')(emails + invalidEmails);
      }
    }
  }
});
