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
        emails = emails.match(/([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+)/gi);

        this.get('stageEmails')(emails);
      }
    }
  }
});
