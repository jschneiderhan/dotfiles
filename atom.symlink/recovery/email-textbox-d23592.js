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
      let emails = this.get('emails');
      this.set('emails', null);

      if (!emails.match(/^\s+$/)) {
        // Regex taken from http://snipplr.com/view/26466/
        emails = emails.match(/([a-zA-Z0-9._-+]@[a-zA-Z0-9._+-]+\.[a-zA-Z0-9._-]+)/gi);

        this.get('stageEmails')(emails);
      }
    }
  }
});
